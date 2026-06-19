# `lint-shfmt` — runs shfmt in diff mode against tracked shell scripts.
# Reports formatting drift as a unified diff; non-zero exit if any
# file would change. We do not auto-write — this is a lint, not a
# formatter run.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-shfmt";
  description = "Check tracked shell scripts for shfmt-formatting drift.";
  runtimeInputs = [
    pkgs.shfmt
    pkgs.git
  ];
  header = "shfmt -d -i 2 -ci -bn";
  globs = [
    "*.sh"
    "*.bash"
  ];
  emptyMessage = "(no .sh / .bash files tracked)";
  command = ''shfmt -d -i 2 -ci -bn "''${files[@]}"'';
}
