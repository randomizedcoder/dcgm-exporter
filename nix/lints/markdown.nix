# `lint-markdown` — run markdownlint-cli2 against tracked .md files.
# Catches broken anchors, mismatched heading levels, trailing
# whitespace, missing fenced-code language tags, etc.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-markdown";
  description = "Run markdownlint-cli2 against tracked .md files.";
  runtimeInputs = [
    pkgs.markdownlint-cli2
    pkgs.git
  ];
  header = "markdownlint-cli2";
  globs = [ "*.md" ];
  emptyMessage = "(no .md files tracked)";
  command = ''markdownlint-cli2 "''${files[@]}"'';
}
