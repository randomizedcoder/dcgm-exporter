# `mk-lint` — single helper used by every `nix/lints/<tool>.nix`.
#
# Before this helper, each lint app repeated the same boilerplate:
# `cd $(git rev-parse --show-toplevel)`, optional `git ls-files` +
# `mapfile` + emptiness check, then the tool invocation. The helper
# absorbs the boilerplate; the per-tool files become a single attrset.
#
# Two modes, selected by whether `globs` is provided:
#
#   - **Tree-walk mode** (`globs` omitted or null): the tool walks the
#     working tree itself (e.g. `statix check .`, `typos`, `gitleaks
#     detect`). The body just runs `command` from the repo root.
#
#   - **File-list mode** (`globs` is a list): the helper builds
#     `files=( $(git ls-files <patterns>) )`, exits 0 cleanly when the
#     list is empty, and the per-tool `command` references
#     `"${files[@]}"`.
#
# Inside `command`, escape `$` for shell expansion as `''$` (Nix
# multi-line string convention) — see `mk-all-app.nix` for the same
# pattern.

{ pkgs, lib }:

{
  # `lint-<tool>` — the binary name and flake-app key.
  name,
  # `meta.description` — surfaced by `nix flake show`.
  description,
  # Tools the shell script needs at runtime (always include `pkgs.git`
  # since we always `cd $(git rev-parse --show-toplevel)`).
  runtimeInputs,
  # Banner line printed before the tool runs. Defaults to `name`.
  header ? name,
  # File-list mode: list of `git ls-files` patterns. `null` → tree-walk.
  globs ? null,
  # Friendly message printed when `globs` matches no tracked files.
  emptyMessage ? "(no matching files tracked)",
  # Bash command to run. In file-list mode, `"${files[@]}"` is in scope.
  command,
}:

let
  cdRoot = ''cd "$(git rev-parse --show-toplevel)"'';
  banner = ''echo "==> ${header}"'';
  fileList =
    if globs == null then
      ""
    else
      ''
        mapfile -t files < <(git ls-files ${lib.concatStringsSep " " (map (g: "'${g}'") globs)})
        if [ "''${#files[@]}" -eq 0 ]; then
          echo "    ${emptyMessage}"
          exit 0
        fi
      '';
in
pkgs.writeShellApplication {
  inherit name runtimeInputs;
  text = ''
    ${cdRoot}
    ${banner}
    ${fileList}
    ${command}
  '';
  meta.description = description;
}
