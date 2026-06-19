{
  pkgs,
  lib,
  isLinux,
  src,
  dcgm-exporter,
}:

lib.optionalAttrs isLinux {
  dcgm-exporter = import ./dcgm-exporter.nix { inherit pkgs src dcgm-exporter; };
}
