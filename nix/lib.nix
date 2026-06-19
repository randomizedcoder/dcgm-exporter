# This file is the "lib namespace root" — small, eagerly-loaded helpers
# (Go version assertion, vendorHash, goEnv, ldflagsFor) that every part of
# the flake consumes via `let exporterLib = import ./nix/lib.nix …`.
#
# Specialized builders that aren't universally needed live as their own
# files under `nix/lib/<name>.nix` (e.g. `mk-all-app.nix`, `mk-lint.nix`)
# and are imported by their consumer. This is deliberate asymmetry, not
# an oversight — keep it.

{ pkgs, lib }:

let
  requiredGo = "1.26.2";

  goPackage =
    if lib.versionAtLeast pkgs.go_1_26.version requiredGo then
      pkgs.go_1_26
    else
      throw "Go ${pkgs.go_1_26.version} from nixpkgs is older than go.mod requires (${requiredGo}). Bump the nixpkgs input.";

  buildGoModule = pkgs.buildGo126Module or (pkgs.buildGoModule.override { go = goPackage; });

  # Single source of truth for the vendored Go module hash.
  # Update after any go.mod / go.sum change: run `nix build .#default`,
  # copy the printed `got:` hash here. lib.fakeHash on first run forces
  # the build to print the real hash.
  vendorHash = lib.fakeHash;

  # Versions sourced from hack/VERSION (Makefile reads the same file).
  # When hack/VERSION is bumped, update these two lines. Keeping them
  # in Nix rather than parsing the file avoids IFD / build-time reads.
  dcgmVersion = "4.5.3";
  exporterVersion = "4.8.2";

  # Per-derivation Go env. `goModules` (a proxyVendor=true output) is
  # spliced in by checks.nix via `GOPROXY=file://${goModules}` so the
  # sandbox has a fully-resolvable module graph without network access.
  #
  # CGO is required: github.com/NVIDIA/go-dcgm and go-nvml use cgo
  # bindings (they dlopen libdcgm.so / libnvidia-ml.so.1 at runtime,
  # so no NVIDIA headers are needed at build time — just a C compiler).
  goEnv = ''
    export HOME=$(mktemp -d)
    export GOCACHE=$HOME/.cache/go-build
    export GOPATH=$HOME/go
    export CGO_ENABLED=1
    export CC=${pkgs.gcc}/bin/gcc
    export GOFLAGS="-mod=mod"
    export GOSUMDB=off
  '';

  # ldflags matching the Makefile `binary` target:
  #   -X main.BuildVersion=${DCGM_VERSION}-${VERSION}
  # We append `-nix-${rev}` so Nix-built binaries are distinguishable
  # from Makefile builds at runtime.
  ldflagsFor =
    {
      rev,
      strip ? true,
    }:
    [
      "-X"
      "main.BuildVersion=${dcgmVersion}-${exporterVersion}-nix-${rev}"
    ]
    ++ lib.optionals strip [
      "-s"
      "-w"
    ];
in
{
  inherit
    goPackage
    buildGoModule
    goEnv
    ldflagsFor
    requiredGo
    vendorHash
    dcgmVersion
    exporterVersion
    ;
}
