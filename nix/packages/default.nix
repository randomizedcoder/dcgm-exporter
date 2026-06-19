# dcgm-exporter binary, built via buildGoModule. Two variants:
#   - dcgm-exporter       — prod (stripped, smaller)
#   - dcgm-exporter-debug — keeps symbols for delve / pprof
#
# Both build the same Go module with CGO_ENABLED=1. The cgo deps
# (go-dcgm, go-nvml) dlopen their NVIDIA shared libraries at runtime,
# so no NVIDIA SDK / headers are required at build time. The single
# in-tree cgo file (internal/pkg/stdout/capture_test_wrapper.go) just
# uses stdio.h, satisfied by glibc.dev via gcc.
#
# Runtime requires libdcgm.so + libnvidia-ml.so.1 on the host
# (provided by NVIDIA drivers and DCGM packaging, same as the
# Makefile-built binary).

{
  lib,
  src,
  rev,
  goPackage,
  buildGoModule,
  ldflagsFor,
  vendorHash,
  dcgmVersion,
  exporterVersion,
}:

let
  mkExporter =
    {
      variant,
      extraTags ? [ ],
      strip,
    }:
    buildGoModule {
      pname = "dcgm-exporter${if variant == "prod" then "" else "-${variant}"}";
      version = "${exporterVersion}+${rev}";
      inherit src vendorHash;
      proxyVendor = true;

      subPackages = [ "cmd/dcgm-exporter" ];

      env.CGO_ENABLED = "1";

      ldflags = ldflagsFor { inherit rev strip; };

      tags = extraTags;

      doCheck = false;

      passthru = {
        go = goPackage;
        inherit rev dcgmVersion exporterVersion;
      };

      meta = {
        description = "NVIDIA DCGM Prometheus exporter (${variant})";
        homepage = "https://github.com/NVIDIA/dcgm-exporter";
        license = lib.licenses.asl20;
        mainProgram = "dcgm-exporter";
        platforms = lib.platforms.unix;
      };
    };
in
{
  dcgm-exporter = mkExporter {
    variant = "prod";
    strip = true;
  };
  dcgm-exporter-debug = mkExporter {
    variant = "debug";
    extraTags = [ "debug" ];
    strip = false;
  };
}
