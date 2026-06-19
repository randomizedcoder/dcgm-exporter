# OCI image bundling the dcgm-exporter binary with cacert + tzdata
# and the default counter CSV the binary loads at startup.
#
# The image is INTENTIONALLY thin: it ships only the exporter and
# minimal runtime support. At runtime the host must inject
# libdcgm.so / libnvidia-ml.so.1 via nvidia-container-toolkit
# (`docker run --gpus all ...` / Kubernetes nvidia-device-plugin) —
# same model as the official `nvcr.io/nvidia/dcgm-exporter` image.

{
  pkgs,
  src,
  dcgm-exporter,
}:

pkgs.dockerTools.buildLayeredImage {
  name = "dcgm-exporter-nix";
  tag = "latest";

  contents = [
    dcgm-exporter
    pkgs.cacert
    pkgs.tzdata
    pkgs.dockerTools.usrBinEnv
    pkgs.dockerTools.binSh
    pkgs.dockerTools.caCertificates
  ];

  extraCommands = ''
    mkdir -p tmp && chmod 1777 tmp
    mkdir -p var/run var/log etc/dcgm-exporter
    cp ${src}/etc/default-counters.csv etc/dcgm-exporter/default-counters.csv
    cp ${src}/etc/dcp-metrics-included.csv etc/dcgm-exporter/dcp-metrics-included.csv
    cp ${src}/etc/1.x-compatibility-metrics.csv etc/dcgm-exporter/1.x-compatibility-metrics.csv
  '';

  config = {
    Entrypoint = [ "/bin/dcgm-exporter" ];
    Env = [
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "TZ=UTC"
      "PATH=/bin:/usr/bin"
    ];
    WorkingDir = "/";
    Labels = {
      "org.opencontainers.image.title" = "dcgm-exporter";
      "org.opencontainers.image.description" =
        "NVIDIA DCGM Prometheus exporter (Nix-built; expects nvidia-container-toolkit at runtime).";
      "org.opencontainers.image.source" = "https://github.com/NVIDIA/dcgm-exporter";
      "org.opencontainers.image.licenses" = "Apache-2.0";
    };
  };

  meta.description = "OCI image bundling the dcgm-exporter binary. Requires nvidia-container-toolkit at runtime to inject NVIDIA driver / DCGM libraries.";
}
