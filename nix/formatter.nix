# `nix fmt` formatter — wraps RFC 166 nixfmt so a bare `nix fmt` walks
# every .nix file in the tree; explicit arguments (e.g. `nix fmt --
# --check flake.nix`) are forwarded unchanged.

{ pkgs }:

pkgs.writeShellApplication {
  name = "nixfmt-tree";
  runtimeInputs = [
    pkgs.nixfmt-rfc-style
    pkgs.findutils
  ];
  text = ''
    if [ "$#" -eq 0 ]; then
      find . -name '*.nix' \
        -not -path './.git/*' \
        -not -path './result*' \
        -exec nixfmt {} +
    else
      exec nixfmt "$@"
    fi
  '';
  meta.description = "Walk the tree and nixfmt every .nix file (used by `nix fmt`).";
}
