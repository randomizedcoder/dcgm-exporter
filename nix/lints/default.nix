# Lint registry. flake.nix imports this once per system; we return
# `apps = { ... }` ready for splicing into the flake outputs.
#
# Each per-tool file under this directory returns a
# `pkgs.writeShellApplication` whose `name` is `lint-<tool>`. We
# expose every one as a flake app, plus a composite `lint-extreme`
# that fans over all of them and tallies pass/fail at the end.
#
# These apps are intentionally NOT wired into `flake.nix#checks` —
# they're manual-only until the surfaced findings are triaged.
# Promote into nix/checks.nix when consistently green.

{ pkgs, lib }:

let
  mkAllApp = import ../lib/mk-all-app.nix { inherit pkgs lib; };

  perTool = lib.mapAttrs (_n: path: import path { inherit pkgs lib; }) {
    lint-shellcheck = ./shellcheck.nix;
    lint-shfmt = ./shfmt.nix;
    lint-deadnix = ./deadnix.nix;
    lint-statix = ./statix.nix;
    lint-gitleaks = ./gitleaks.nix;
    lint-markdown = ./markdown.nix;
    lint-typos = ./typos.nix;
    lint-cspell = ./cspell.nix;
    lint-nil = ./nil.nix;
    lint-golangci = ./golangci.nix;
    lint-hadolint = ./hadolint.nix;
  };

  lintExtreme = mkAllApp {
    name = "lint-extreme";
    subs = lib.mapAttrsToList (n: drv: {
      inherit drv;
      binName = n;
    }) perTool;
    description = "Run every manual lint sequentially; tally pass/fail.";
  };

  everything = import ./everything.nix { inherit pkgs; };

  allLints = perTool // {
    lint-extreme = lintExtreme;
    inherit everything;
  };

  drvsToApps = lib.mapAttrs (
    name: drv: {
      type = "app";
      program = "${drv}/bin/${name}";
      meta = drv.meta or { };
    }
  );
in
{
  apps = drvsToApps allLints;
  drvs = allLints;
}
