# `lint-golangci` — manual full golangci-lint pass against the working
# tree, outside the nix sandbox (so it can hit GOPROXY for any module
# fetches the in-sandbox checks have to pre-vendor). Use this when
# iterating on lint config; the sandboxed gating version lives in
# nix/checks.nix.
#
# CGO_ENABLED=1 mirrors the Makefile `lint` target: dcgm-exporter
# uses cgo bindings via go-dcgm / go-nvml, so the linter needs a C
# compiler in PATH to type-check those packages.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-golangci";
  description = "Run golangci-lint against the tree (host machine, not sandboxed).";
  runtimeInputs = [
    pkgs.golangci-lint
    pkgs.git
    pkgs.go_1_26
    pkgs.gcc
    pkgs.pkg-config
  ];
  header = "golangci-lint run --config .golangci.yml";
  command = ''
    export CGO_ENABLED=1
    golangci-lint run --config .golangci.yml --timeout 10m ./...
  '';
}
