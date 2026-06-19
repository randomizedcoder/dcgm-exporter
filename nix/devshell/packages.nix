# Package list for the dev shell. Kept separate so the shell entrypoint
# stays focused on the shellHook and meta.description.

{ pkgs, exporterLib }:

[
  exporterLib.goPackage
  pkgs.gopls
  pkgs.gotools
  pkgs.delve

  pkgs.golangci-lint
  pkgs.go-tools
  pkgs.govulncheck
  pkgs.gosec
  pkgs.gofumpt
  pkgs.gotestsum

  # cgo support — go-dcgm / go-nvml + internal/pkg/stdout need a C
  # compiler. NVIDIA libs are NOT here; they're dlopened at runtime.
  pkgs.gcc
  pkgs.pkg-config
  pkgs.glibc.dev
  pkgs.gnumake

  pkgs.nixfmt-rfc-style
  pkgs.deadnix
  pkgs.statix
  pkgs.nil

  pkgs.shellcheck
  pkgs.shfmt

  pkgs.hadolint

  pkgs.gitleaks
  pkgs.typos
  pkgs.cspell
  pkgs.markdownlint-cli2

  pkgs.skopeo

  pkgs.jq
  pkgs.yq-go
  pkgs.ripgrep
  pkgs.git
]
