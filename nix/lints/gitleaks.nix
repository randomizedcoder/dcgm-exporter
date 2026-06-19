# `lint-gitleaks` — scan git history + working tree for committed
# secrets (API keys, ssh private keys, vault patterns, …). `--redact`
# masks the secret value in output so the report can be shared
# without re-leaking; `--no-banner` drops the ASCII art.

{ pkgs, lib }:

import ../lib/mk-lint.nix { inherit pkgs lib; } {
  name = "lint-gitleaks";
  description = "Run gitleaks against the repo for committed secrets.";
  runtimeInputs = [
    pkgs.gitleaks
    pkgs.git
  ];
  header = "gitleaks detect";
  command = "gitleaks detect --source=. --no-banner --redact --verbose";
}
