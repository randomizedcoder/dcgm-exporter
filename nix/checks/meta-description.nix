# `checks.meta-description` — assert every flake `apps.<name>` exposes
# a non-empty `meta.description`. Surfaces in `nix flake show`; missing
# descriptions print a confusing `app:` line instead of `app: <text>`.
#
# The assertion fires at evaluation time. If any app is missing a
# description, `nix flake check` (and any command that touches the
# checks output, like `nix flake show`) bails with a clear message
# naming the offenders.

{
  pkgs,
  lib,
  appsForCheck,
}:

let
  hasDesc = app: ((app.meta or { }).description or "") != "";
  missing = lib.filter (n: !hasDesc appsForCheck.${n}) (lib.attrNames appsForCheck);
in
assert lib.assertMsg (missing == [ ]) "flake apps missing meta.description: ${toString missing}";

pkgs.runCommand "check-meta-description"
  {
    meta.description = "Assert every flake app has a non-empty meta.description.";
  }
  ''
    echo "All ${toString (lib.length (lib.attrNames appsForCheck))} apps have meta.description."
    touch $out
  ''
