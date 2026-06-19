# `lint-hadolint` — hadolint pass against every tracked Dockerfile.
# Uses repo `.hadolint.yaml` for rule configuration.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-hadolint";
  description = "Run hadolint against tracked Dockerfiles.";
  runtimeInputs = [
    pkgs.hadolint
    pkgs.git
  ];
  header = "hadolint";
  globs = [
    "Dockerfile*"
    "*/Dockerfile*"
    "**/Dockerfile*"
  ];
  emptyMessage = "(no Dockerfiles tracked)";
  command = ''hadolint --config .hadolint.yaml "''${files[@]}"'';
}
