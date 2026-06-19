# Test coverage apps. These run outside the nix sandbox (so tests that
# reach the filesystem or expect the host's Go module cache work) and
# write artefacts under ./coverage/ at the repo root.
#
# Two apps are exposed:
#   - test-coverage      — `go test -cover` (CGO=1, no race detector)
#   - test-race-coverage — `go test -race -cover` (CGO=1, ~3-5x slower)
#
# Both apps skip GPU-dependent packages (need real libdcgm /
# libnvidia-ml at runtime); the skip list mirrors
# Makefile:unit-test-coverage.
#
# Both pass through any user-supplied `./...` selector, so e.g.
# `nix run .#test-race-coverage -- ./pkg/...` scopes the run.

{ pkgs, lib }:

let
  goPkg = pkgs.go_1_26;

  summarizeAwk = ''
    awk '
      BEGIN {
        zero = 0; partial = 0; total_line = "";
      }
      /^total:/ { total_line = $0; next }
      {
        n = split($NF, p, "%");
        pct = p[1] + 0;
        if (pct == 0.0)      zero++;
        else if (pct < 100)  partial++;
      }
      END {
        print "";
        printf "  zero-coverage funcs:    %d\n", zero;
        printf "  partial-coverage funcs: %d\n", partial;
        if (total_line != "") {
          print "  " total_line;
        }
      }
    '
  '';

  perPackageAwk = ''
    awk '
      BEGIN { OFS = "\t" }
      /^total:/ { next }
      {
        n = split($1, parts, "/");
        file = parts[n];
        sub("/" file, "", $1);
        pkg = $1;

        m = split($NF, p, "%");
        pct = p[1] + 0;
        sum[pkg] += pct;
        count[pkg]++;
      }
      END {
        for (pkg in count) {
          avg = sum[pkg] / count[pkg];
          flag = (avg == 0.0) ? "  ⚠ no coverage" : "";
          printf "  %-60s %6.1f%%%s\n", pkg, avg, flag;
        }
      }
    ' | sort
  '';

  mkCoverageApp =
    {
      name,
      description,
      goTestArgs,
      profileFile,
      htmlFile,
      logFile,
      banner,
    }:
    {
      type = "app";
      meta.description = description;
      program = "${
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            goPkg
            pkgs.git
            pkgs.gnumake
            pkgs.gawk
            pkgs.coreutils
            # cgo packages (go-dcgm, go-nvml, internal/pkg/stdout) all
            # need a C compiler. Race detector additionally needs gcc.
            pkgs.gcc
            pkgs.binutils
            pkgs.pkg-config
          ];
          text = ''
            set -euo pipefail

            repo_root="$(git rev-parse --show-toplevel)"
            cd "$repo_root"
            mkdir -p coverage

            export CGO_ENABLED=1

            # Skip GPU-dependent packages — they dlopen NVIDIA libs at
            # runtime that aren't available without a real GPU + driver.
            # Mirrors Makefile:unit-test-coverage.
            pkgs_to_test=$(go list ./... | grep -v -E "(tests/e2e|integration_test|nvmlprovider|dcgmprovider)")

            # Allow the user to override the package set via positional args.
            if [ "$#" -eq 0 ]; then
              # shellcheck disable=SC2086
              set -- $pkgs_to_test
            fi

            ${banner}

            test_status=0
            go test \
              ${goTestArgs} \
              -coverprofile=coverage/${profileFile} \
              -covermode=atomic \
              -coverpkg=./... \
              -short \
              "$@" \
              2>&1 | tee coverage/${logFile} \
              || test_status=$?

            if [ ! -s coverage/${profileFile} ]; then
              echo
              echo "  (no coverage profile written; skipping analysis)"
              exit "$test_status"
            fi

            echo
            echo "=== per-function coverage (go tool cover -func) ==="
            go tool cover -func=coverage/${profileFile}

            echo
            echo "=== per-package summary ==="
            go tool cover -func=coverage/${profileFile} | ${perPackageAwk}

            echo
            echo "=== totals ==="
            go tool cover -func=coverage/${profileFile} | ${summarizeAwk}

            go tool cover -html=coverage/${profileFile} -o coverage/${htmlFile}
            echo
            echo "  HTML report: $(pwd)/coverage/${htmlFile}"
            echo "  Raw profile: $(pwd)/coverage/${profileFile}"
            echo "  Log:         $(pwd)/coverage/${logFile}"

            if [ "$test_status" -ne 0 ]; then
              echo
              echo "  NOTE: $test_status non-zero exit from go test — coverage above is from passing tests only."
              echo "        See coverage/${logFile} for failing test output."
            fi
            exit "$test_status"
          '';
        }
      }/bin/${name}";
    };

  # lib is included in inputs to keep the interface consistent across the
  # tree; this module currently doesn't reach for any lib helpers.
  _ = lib;
in
{
  apps = {
    test-coverage = mkCoverageApp {
      name = "test-coverage";
      description = "Run go test -cover across non-GPU packages; print per-function / per-package coverage and write an HTML report.";
      goTestArgs = "-timeout 5m";
      profileFile = "coverage.out";
      htmlFile = "coverage.html";
      logFile = "test.log";
      banner = ''
        echo "=== test-coverage (CGO=1, no race detector) ==="
      '';
    };

    test-race-coverage = mkCoverageApp {
      name = "test-race-coverage";
      description = "Run go test -race -cover; reveals which code is exercised under the race detector.";
      goTestArgs = "-race -timeout 10m";
      profileFile = "race-coverage.out";
      htmlFile = "race-coverage.html";
      logFile = "race-test.log";
      banner = ''
        echo "=== test-race-coverage (CGO=1, -race) ==="
        echo "Note: the race detector needs CGO and a C toolchain; build is ~3-5x slower."
      '';
    };
  };
}
