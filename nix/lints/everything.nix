# `everything` — single entry point that runs the full static-analysis
# pipeline: every gated derivation under `nix flake check`, then every
# manual lint via `lint-extreme`. Use this as the "run it all" command;
# the two halves remain available individually for narrower runs.
#
# Why both halves: `nix flake check` runs sandboxed derivations (the Go
# linters that need a hermetic GOPROXY, plus the nix-side gates) and is
# what CI gates on. `lint-extreme` runs the host-side manual lints
# (cspell, typos, gitleaks-history, markdown, golangci against the
# real working tree). They cover different ground — together they're
# everything.

{ pkgs }:

pkgs.writeShellApplication {
  name = "everything";
  runtimeInputs = [
    pkgs.nix
    pkgs.git
  ];
  text = ''
    cd "$(git rev-parse --show-toplevel)"

    set -uo pipefail
    passes=0
    fails=0
    failed_names=""

    echo
    echo "============================================================"
    echo "==> nix flake check (gated derivations)"
    echo "============================================================"
    if nix --extra-experimental-features 'nix-command flakes' flake check --print-build-logs; then
      passes=$((passes + 1))
    else
      fails=$((fails + 1))
      failed_names="$failed_names nix-flake-check"
    fi

    echo
    echo "============================================================"
    echo "==> lint-extreme (manual lints)"
    echo "============================================================"
    if nix --extra-experimental-features 'nix-command flakes' run .#lint-extreme; then
      passes=$((passes + 1))
    else
      fails=$((fails + 1))
      failed_names="$failed_names lint-extreme"
    fi

    echo
    echo "============================================================"
    echo "Overall: $passes passed, $fails failed"
    if [ "$fails" -gt 0 ]; then
      echo "Failed:$failed_names"
    fi
    echo "============================================================"
    [ "$fails" -eq 0 ] || exit 1
  '';
  meta.description = "Run nix flake check + lint-extreme together; tally pass/fail.";
}
