# Development shell for the dcgm-exporter repo.
#
# Provides Go 1.26.x plus the static-analysis toolchain (every linter
# wired into `nix/lints/` and `nix/checks.nix`) so contributors can run
# the same checks CI gates on without installing anything system-wide.
#
# CGO_ENABLED=1 is set because go-dcgm / go-nvml are cgo bindings.

{ pkgs, exporterLib }:

let
  packages = import ./packages.nix { inherit pkgs exporterLib; };
in
pkgs.mkShell {
  inherit packages;
  meta.description = "dcgm-exporter dev shell (Go 1.26.x, cgo, golangci-lint, staticcheck, gosec, govulncheck, hadolint, nix lints).";

  shellHook = ''
    echo "dcgm-exporter dev shell"
    echo "  Go: ${exporterLib.goPackage.version}  (go.mod requires ${exporterLib.requiredGo})"
    echo
    echo "  nix flake check                # gating: Go static analysis + nix linters + secrets + hadolint"
    echo "  nix run .#lint-extreme         # fan out every manual lint, tally results"
    echo "  nix run .#lint-golangci        # full golangci-lint against working tree (uses .golangci.yml)"
    echo "  nix run .#lint-cspell          # spell check (dictionary)"
    echo "  nix run .#lint-typos           # spell check (typo list)"
    echo "  nix run .#lint-gitleaks        # secret scan over full git history"
    echo "  nix run .#lint-markdown        # markdownlint-cli2"
    echo "  nix run .#lint-nil             # nil (Nix LSP) diagnostics"
    echo "  nix run .#lint-hadolint        # hadolint on Dockerfiles"
    echo
    echo "  nix build .#default            # build dcgm-exporter binary (Go ${exporterLib.requiredGo}, CGO=1)"
    echo "  nix build .#container          # OCI image (linux only)"
    echo "  nix run .#test-coverage        # go test -cover (skips GPU packages)"
    echo "  nix run .#test-race-coverage   # go test -race -cover (skips GPU packages)"
    echo "  nix fmt                        # nixfmt every .nix file"
    echo
    echo "  Existing Makefile path is unchanged (make binary, make lint, make test-main, …)."

    export CGO_ENABLED=1
  '';
}
