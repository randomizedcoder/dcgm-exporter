# Gated derivations consumed by `nix flake check`. CI gates on these.
#
# Tools that are too noisy or too churn-prone for the gate live as
# manual-only apps under `nix/lints/`. The promotion path is one-way:
# once a `lint-<tool>` is consistently green across the tree, copy
# its invocation into a new check here and remove it from
# `nix/lints/default.nix`. The two halves are intentionally not
# unified — the file split encodes the workflow.

{
  pkgs,
  src,
  goPackage,
  goEnv,
  vendorHash,
}:

let
  # Shared module sources for all Go-driven checks. Hash is centralized
  # in nix/lib.nix; replace lib.fakeHash there on first run.
  inherit
    (pkgs.buildGo126Module {
      pname = "dcgm-exporter-modules";
      version = "0.0.0";
      inherit src vendorHash;
      proxyVendor = true;
      doCheck = false;
      buildPhase = "true";
      installPhase = "mkdir -p $out";
    })
    goModules
    ;

  setupGoSrc = ''
    cp -r ${src}/. ./
    chmod -R u+w .
    ${goEnv}
    export GOPROXY=file://${goModules}
  '';

  mkCheckBase =
    {
      name,
      nativeBuildInputs ? [ ],
      preamble,
      script,
    }:
    pkgs.runCommand name { inherit nativeBuildInputs; } ''
      set -euo pipefail
      workdir=$(mktemp -d)
      cd "$workdir"
      ${preamble}
      ${script}
      touch $out
    '';

  mkGoCheck =
    {
      name,
      buildInputs ? [ ],
      script,
    }:
    mkCheckBase {
      inherit name script;
      # Go checks need a C compiler — every Go file that imports a cgo
      # package (go-dcgm, go-nvml, internal/pkg/stdout) won't type-check
      # without gcc. pkg-config is harmless extra; glibc.dev provides
      # the system headers for the one inline cgo file (stdio.h).
      nativeBuildInputs = [
        goPackage
        pkgs.gcc
        pkgs.pkg-config
      ]
      ++ buildInputs;
      preamble = setupGoSrc;
    };

  mkPlainCheck =
    {
      name,
      buildInputs ? [ ],
      script,
    }:
    mkCheckBase {
      inherit name script;
      nativeBuildInputs = buildInputs;
      preamble = ''
        cp -r ${src}/. ./
        chmod -R u+w .
      '';
    };

in
{
  # ────────────────────────────────────────────────────────────────
  # Go static analysis (PR gate, sandboxed)
  # ────────────────────────────────────────────────────────────────

  golangci-lint = mkGoCheck {
    name = "golangci-lint";
    buildInputs = [ pkgs.golangci-lint ];
    script = ''
      golangci-lint run --config .golangci.yml --timeout 10m ./...
    '';
  };

  go-vet = mkGoCheck {
    name = "go-vet";
    script = "go vet ./...";
  };

  staticcheck = mkGoCheck {
    name = "staticcheck";
    buildInputs = [ pkgs.go-tools ];
    # staticcheck.conf at the repo root sets checks = ["all", "-ST1005"].
    script = "staticcheck ./...";
  };

  govulncheck = mkGoCheck {
    name = "govulncheck";
    buildInputs = [ pkgs.govulncheck ];
    script = ''
      govulncheck ./...
    '';
  };

  gosec = mkGoCheck {
    name = "gosec";
    buildInputs = [ pkgs.gosec ];
    script = ''
      # No .gosec.json in this repo yet; use defaults. Add an exclusions
      # file at the repo root and switch to `-conf .gosec.json` once
      # false positives are triaged.
      gosec -fmt=text ./...
    '';
  };

  go-test-short = mkGoCheck {
    name = "go-test-short";
    script = ''
      # Skip GPU-dependent packages (need real libdcgm / libnvidia-ml at
      # runtime) and end-to-end suites. Mirrors Makefile:unit-test-coverage.
      pkgs=$(go list ./... | grep -v -E "(tests/e2e|integration_test|nvmlprovider|dcgmprovider)")
      go test -short -timeout 60s $pkgs
    '';
  };

  gofmt-check = mkGoCheck {
    name = "gofmt-check";
    script = ''
      out=$(gofmt -l -s pkg cmd internal 2>&1 || true)
      if [ -n "$out" ]; then
        echo "gofmt drift in:"
        echo "$out"
        exit 1
      fi
    '';
  };

  goimports-check = mkGoCheck {
    name = "goimports-check";
    buildInputs = [ pkgs.gotools ];
    script = ''
      out=$(goimports -l -local github.com/NVIDIA/dcgm-exporter pkg cmd internal 2>&1 || true)
      if [ -n "$out" ]; then
        echo "goimports drift in:"
        echo "$out"
        exit 1
      fi
    '';
  };

  go-mod-tidy-check = mkGoCheck {
    name = "go-mod-tidy-check";
    script = ''
      cp go.mod go.mod.orig
      cp go.sum go.sum.orig
      GOFLAGS="-mod=mod" go mod tidy -e -v 2>&1 || true
      if ! diff -q go.mod go.mod.orig >/dev/null 2>&1; then
        echo "go mod tidy would change go.mod"
        diff go.mod.orig go.mod || true
        exit 1
      fi
    '';
  };

  # ────────────────────────────────────────────────────────────────
  # Nix-side checks (gating via nix flake check)
  # ────────────────────────────────────────────────────────────────

  nixfmt-check = mkPlainCheck {
    name = "nixfmt-check";
    buildInputs = [ pkgs.nixfmt-rfc-style ];
    script = ''
      find . -name '*.nix' \
        -not -path './.git/*' \
        -not -path './result*' \
        -exec nixfmt --check {} +
    '';
  };

  deadnix = mkPlainCheck {
    name = "deadnix";
    buildInputs = [
      pkgs.deadnix
      pkgs.findutils
    ];
    script = ''
      find . -name '*.nix' \
        -not -path './.git/*' \
        -not -path './result*' \
        -exec deadnix --fail {} +
    '';
  };

  statix = mkPlainCheck {
    name = "statix";
    buildInputs = [ pkgs.statix ];
    script = ''
      statix check .
    '';
  };

  nil = mkPlainCheck {
    name = "nil";
    buildInputs = [
      pkgs.nil
      pkgs.findutils
    ];
    script = ''
      failed=0
      while IFS= read -r f; do
        diag=$(nil diagnostics "$f" 2>&1) || failed=1
        if [ -n "$diag" ]; then
          printf '=== %s ===\n%s\n' "$f" "$diag"
          failed=1
        fi
      done < <(find . -name '*.nix' \
        -not -path './.git/*' \
        -not -path './result*')
      if [ "$failed" -ne 0 ]; then
        exit 1
      fi
    '';
  };

  gitleaks = mkPlainCheck {
    name = "gitleaks";
    buildInputs = [ pkgs.gitleaks ];
    # Sandbox can't read .git; --no-git scans the source tree as it
    # appears at the current revision. Deeper history scan stays in
    # `nix run .#lint-gitleaks`.
    script = ''
      gitleaks detect --no-git --source=. --no-banner --redact
    '';
  };

  # ────────────────────────────────────────────────────────────────
  # Shell + Dockerfile checks
  # ────────────────────────────────────────────────────────────────

  shellcheck = mkPlainCheck {
    name = "shellcheck";
    buildInputs = [ pkgs.shellcheck ];
    script = ''
      shopt -s nullglob globstar
      shfiles=( docker/*.sh hack/*.sh tests/**/*.sh )
      if [ ''${#shfiles[@]} -eq 0 ]; then
        echo "no shell scripts found, skipping"
        exit 0
      fi
      shellcheck "''${shfiles[@]}"
    '';
  };

  hadolint = mkPlainCheck {
    name = "hadolint";
    buildInputs = [ pkgs.hadolint ];
    script = ''
      shopt -s nullglob
      dfs=( docker/Dockerfile* .devcontainer/Dockerfile* )
      if [ ''${#dfs[@]} -eq 0 ]; then
        echo "no Dockerfiles found, skipping"
        exit 0
      fi
      hadolint --config .hadolint.yaml "''${dfs[@]}"
    '';
  };
}
