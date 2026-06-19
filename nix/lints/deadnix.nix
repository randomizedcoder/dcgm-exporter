# `lint-deadnix` — flag dead Nix code: unused `let` bindings, unused
# function arguments, dead attribute fields. `--fail` makes it exit
# non-zero if anything is found.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-deadnix";
  description = "Run deadnix against tracked .nix files.";
  runtimeInputs = [
    pkgs.deadnix
    pkgs.git
  ];
  header = "deadnix --fail";
  globs = [ "*.nix" ];
  emptyMessage = "(no .nix files tracked)";
  command = ''deadnix --fail "''${files[@]}"'';
}
