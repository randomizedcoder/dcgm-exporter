# `lint-cspell` — dictionary-based spell checker.
#
# Complements `lint-typos`: typos catches high-confidence misspellings
# from a curated typo list, cspell catches anything not in its
# dictionary (useful for prose drift in docs and comments). Splits
# camelCase/snake_case automatically.
#
# Suppress noise via the project word-list in `cspell.json` at the
# repo root. Add domain terms there rather than pre-fixing every
# false positive.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-cspell";
  description = "Run cspell against tracked files using cspell.json.";
  runtimeInputs = [
    pkgs.cspell
    pkgs.git
  ];
  header = "cspell";
  globs = [ "*" ];
  emptyMessage = "(no tracked files)";
  command = ''cspell --no-progress --no-summary "''${files[@]}"'';
}
