# `lint-shellcheck` — runs shellcheck against tracked shell scripts.
# Embedded shell inside writeShellApplication is already linted at
# build time; this app catches hand-written `*.sh` / `*.bash` files.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-shellcheck";
  description = "Run shellcheck against tracked .sh / .bash files.";
  runtimeInputs = [
    pkgs.shellcheck
    pkgs.git
  ];
  header = "shellcheck";
  globs = [
    "*.sh"
    "*.bash"
  ];
  emptyMessage = "(no .sh / .bash files tracked)";
  command = ''
    printf '    %s\n' "''${files[@]}"
    shellcheck -x "''${files[@]}"
  '';
}
