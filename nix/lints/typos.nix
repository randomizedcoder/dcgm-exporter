# `lint-typos` — find typos in source, comments, and docs.
#
# Walks the working tree using its built-in default rules. False
# positives can be silenced via `_typos.toml` at the repo root.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-typos";
  description = "Run typos against the working tree.";
  runtimeInputs = [
    pkgs.typos
    pkgs.git
  ];
  header = "typos";
  command = "typos";
}
