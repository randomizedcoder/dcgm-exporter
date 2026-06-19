{
  description = "dcgm-exporter — NVIDIA DCGM Prometheus exporter (Go 1.26, cgo) with pedantic static analysis, test coverage, and OCI container builds";

  inputs = {
    # nixos-unstable currently ships Go 1.26.x under pkgs.go_1_26 (matches go.mod).
    # Bump deliberately when go.mod's toolchain directive moves.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          inherit (pkgs) lib;
          inherit (pkgs.stdenv.hostPlatform) isLinux;

          src = lib.cleanSourceWith {
            src = ./.;
            filter =
              path: _type:
              let
                baseName = baseNameOf (toString path);
              in
              baseName != "result"
              && baseName != ".direnv"
              && baseName != ".git"
              && baseName != "coverage"
              && baseName != ".go"
              && baseName != ".coverdata";
          };

          rev = self.shortRev or self.dirtyShortRev or "dirty";

          exporterLib = import ./nix/lib.nix { inherit pkgs lib; };

          packages = import ./nix/packages {
            inherit lib src rev;
            inherit (exporterLib)
              goPackage
              buildGoModule
              ldflagsFor
              vendorHash
              dcgmVersion
              exporterVersion
              ;
          };

          containers = import ./nix/containers {
            inherit
              pkgs
              lib
              isLinux
              src
              ;
            inherit (packages) dcgm-exporter;
          };

          checks = import ./nix/checks.nix {
            inherit pkgs src;
            inherit (exporterLib) goPackage goEnv vendorHash;
          };

          lints = import ./nix/lints { inherit pkgs lib; };

          tests = import ./nix/tests { inherit pkgs lib; };

          devShell = import ./nix/devshell { inherit pkgs exporterLib; };

          formatter = import ./nix/formatter.nix { inherit pkgs; };

          # Every flake `apps.<name>` must expose a meta.description so
          # `nix flake show` prints something useful. The assertion lives in
          # nix/checks/meta-description.nix and runs at evaluation time.
          appsForCheck =
            lints.apps
            // tests.apps
            // {
              default = {
                type = "app";
                program = "${packages.dcgm-exporter}/bin/dcgm-exporter";
                meta.description = "Run the dcgm-exporter binary (default app).";
              };
            };
          metaDescriptionCheck = import ./nix/checks/meta-description.nix {
            inherit pkgs lib appsForCheck;
          };
        in
        {
          packages = {
            default = packages.dcgm-exporter;
            inherit (packages) dcgm-exporter dcgm-exporter-debug;
          }
          // lib.optionalAttrs isLinux {
            container = containers.dcgm-exporter;
          };

          checks = checks // {
            inherit (packages) dcgm-exporter;
            meta-description = metaDescriptionCheck;
          };

          devShells.default = devShell;

          apps = {
            default = {
              type = "app";
              program = "${packages.dcgm-exporter}/bin/dcgm-exporter";
              meta.description = "Run the dcgm-exporter binary (default app).";
            };
          }
          // lints.apps
          // tests.apps;

          inherit formatter;
        }
      );
}
