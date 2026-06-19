# Security & correctness fix plan — dcgm-exporter

## Why

- `dcgm-exporter` runs in production on thousands of machines.
- Many of those machines are internet-facing.
- This file is the maintainer-approved subset of `nix/STATIC_ANALYSIS_FINDINGS.md`.
- One branch per item. One PR per branch. All branches fork from `main`.

## How to use this document

- Each section below is one PR. Each section is self-contained.
- Branches are independent. You can implement them in any order, or in parallel.
- Open PRs upstream at `https://github.com/NVIDIA/dcgm-exporter`.
- DCO sign-off is required (`git commit -s`). See `CONTRIBUTING.md`.
- Each commit message follows this style:
  - First line: short imperative subject, lowercase, ≤60 characters.
  - Blank line.
  - Optional body: terse. No idioms. One file per line where possible.
- Each PR body follows this style:
  - `What:` one sentence.
  - `Why:` one sentence — security or correctness impact.
  - `How:` one sentence — what the new code does.
  - `Findings rule:` the rule code.
  - `Refs:` `nix/STATIC_ANALYSIS_FINDINGS.md`.

## Plain-language note on tests

Where possible each PR adds **table-driven tests** that cover four cases:

- **Positive** — the normal case that should pass.
- **Negative** — the case that must fail.
- **Boundary** — the exact edge value (e.g. `MaxInt32` or umask `022`).
- **Corner** — an unusual case that is easy to forget (e.g. cancelled context, empty input, existing directory).

For pure refactors or Dockerfile changes, the test plan is "the existing tests still pass" or "the build still produces the same image". This is called out explicitly per PR.

## PR index

| # | Branch | Title | Category | Rule |
| --- | --- | --- | --- | --- |
| 1 | `security/g115-p2p-link-bounds-check` | collector: bound NVLink state cast | Security | gosec G115 |
| 2 | `security/exec-context-timeout-and-nixos` | exec: context+timeout, find ldconfig via PATH | Security / NixOS / robustness | gosec G204, noctx |
| 3 | `security/debug-dir-mode-0750` | debug: dir mode 0o755 → 0o750 | Security | gosec G301 |
| 4 | `security/dockerfile-shell-pipefail` | docker: SHELL with pipefail | Security | hadolint DL4006 |
| 5 | `security/dockerfile-copy-absolute-paths` | docker: COPY absolute dest in distroless | Security | hadolint DL3045 |
| 6 | `security/devcontainer-useradd-l-flag` | devcontainer: useradd -l | Security | hadolint DL3046 |
| 7 | `security/devcontainer-curl-only` | devcontainer: use curl, drop wget | Security | hadolint DL4001, DL3047 |
| 8 | `cleanup/dcgmprovider-drop-unused-field` | dcgmprovider: drop unused moduleCleanup field | Cleanup | staticcheck U1000 |
| 9 | `cleanup/deviceinfo-use-copy-builtin` | deviceinfo: use copy() builtin | Cleanup | staticcheck S1001 |
| 10 | `cleanup/devicewatcher-qualify-logging` | devicewatcher: drop dot import, qualify logging refs | Cleanup | staticcheck ST1001 |
| 11 | `cleanup/error-strings-and-fprintf` | cleanup: error string style + Fprintf | Cleanup | staticcheck ST1005×2, QF1012 |
| 12 | `cleanup/deviceinfo-tagged-switch` | deviceinfo: tagged switch on EntityGroupId | Cleanup | staticcheck QF1003 |
| 13 | `cleanup/device-monitoring-keyed-literals` | devicemonitoring: keyed WatchedEntityKey literals | Cleanup | go vet composites |
| 14 | `correctness/server-thread-request-context` | server: thread r.Context() through render | Correctness | golangci-lint contextcheck |

---

## PR 1 — collector: bound NVLink state cast

**Branch:** `security/g115-p2p-link-bounds-check` (forks from `main`)
**Findings rule:** gosec G115

**Why this matters.** `link` has the Go type `dcgm.Link_State`, which is defined as `uint` in the DCGM SDK. The current code casts it to `int` with a `//nolint:gosec` comment that says "small in practice". The cast is safe today (Link_State is a small enum: 0…N), but the bound is not enforced in code. If a future DCGM SDK changes `Link_State` to a larger type, or returns a sentinel value, the silent cast can produce garbage metric values. We replace the `//nolint` annotation with an explicit bounds check that warns once and skips the bad sample.

**Files**

- `internal/pkg/collector/p2p_status_collector.go` — line 85.

**Change**

Before:
```go
linkValue := int(uint64(link)) //nolint:gosec // link values are small in practice
```

After:
```go
// dcgm.Link_State is a small enum; guard against future SDK changes.
if uint64(link) > math.MaxInt32 {
    slog.Warn("unexpected NVLink state value", slog.Uint64("value", uint64(link)))
    continue
}
linkValue := int(link)
```

Add `"math"` and `"log/slog"` to the import block if not present.

**Commit message**

```
collector: bound NVLink state cast (gosec G115)

internal/pkg/collector/p2p_status_collector.go:85
Reject Link_State values > MaxInt32 instead of silent cast.
Drops the //nolint:gosec annotation.
```

**PR title**

```
collector: bound NVLink state cast (gosec G115)
```

**PR body**

```
What: bounds-check the NVLink state cast in p2p_status_collector.
Why: gosec G115 is a false-positive today, but enforcing the bound makes the cast future-proof against DCGM SDK changes.
How: skip the metric and warn if Link_State > math.MaxInt32.

Findings rule: gosec G115
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

Add table-driven test in `internal/pkg/collector/p2p_status_collector_test.go` (create if absent). Test the bound-check logic in isolation by extracting it into a small helper, or by injecting `link` values via mock.

```go
func Test_linkValueBound(t *testing.T) {
    cases := []struct {
        name string
        link uint64
        want int
        drop bool
    }{
        {"positive: zero",              0,              0,              false},
        {"positive: small enum value",  6,              6,              false},
        {"boundary: MaxInt32",          math.MaxInt32,  math.MaxInt32,  false},
        {"corner: MaxInt32+1",          math.MaxInt32+1, 0,             true},
        {"negative: MaxUint64",         math.MaxUint64, 0,              true},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            got, dropped := boundLinkValue(tc.link)
            assert.Equal(t, tc.drop, dropped)
            if !tc.drop {
                assert.Equal(t, tc.want, got)
            }
        })
    }
}
```

**Maintainer review focus**

- Confirm the warning log is rate-limited or only fires on unexpected hardware — it must not spam at metric-collection cadence.

---

## PR 2 — exec: context+timeout, find ldconfig via PATH

**Branch:** `security/exec-context-timeout-and-nixos` (forks from `main`)
**Findings rule:** gosec G204; golangci-lint `noctx`

**Why this matters.** Three concerns are inseparable here because they touch the same files and the same interface:

1. **gosec G204** — `exec.Command(name, args...)` with a variable name. The `RealExec.Command` wrapper is generic by design (it is the abstraction). We suppress with a documented `// #nosec G204 -- generic wrapper, callers vetted` and add a short policy README so callers and reviewers know what to check.
2. **golangci-lint noctx** — the wrapper takes no `context.Context`. If the subprocess hangs, the daemon hangs. We replace `Command` with `CommandContext` so every call site must pass a context (and the call site is in a position to attach a sensible timeout).
3. **NixOS support** — the dcgm-library prerequisite check calls `/sbin/ldconfig`. NixOS does not ship `/sbin/ldconfig`; users currently work around this with `systemd.tmpfiles.rules`. We add `exec.LookPath("ldconfig")` as the first attempt; the existing `/sbin/ldconfig.real` → `/sbin/ldconfig` chain remains as fallback for Ubuntu / Debian / RHEL.

**Files**

- `internal/pkg/exec/exec.go` — interface + wrapper.
- `internal/pkg/exec/README.md` — new, ~10 lines, documents the policy.
- `internal/pkg/prerequisites/types.go` — `Validate()` interface gets `ctx`.
- `internal/pkg/prerequisites/validation.go` — any code that calls `Validate()`.
- `internal/pkg/prerequisites/dcgmlib_rule.go` — the one consumer of `exec.Exec`.
- `internal/pkg/prerequisites/dcgmlib_rule_test.go` — tests for the new logic.
- `internal/mocks/pkg/exec/` — regenerated mocks via `go generate`.

**Change**

Interface (`internal/pkg/exec/exec.go`):

```go
type Exec interface {
    CommandContext(ctx context.Context, name string, arg ...string) Cmd
}

type Cmd interface {
    Output() ([]byte, error)
}

func (r RealExec) CommandContext(ctx context.Context, name string, arg ...string) Cmd {
    // #nosec G204 -- generic wrapper; callers vetted, no shell, no user-supplied PATH
    return &RealCmd{cmd: exec.CommandContext(ctx, name, arg...)}
}
```

Caller (`internal/pkg/prerequisites/dcgmlib_rule.go`):

```go
func (c dcgmLibExistsRule) Validate(ctx context.Context) error {
    ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
    defer cancel()

    // PATH lookup works on NixOS where /sbin is not standard.
    ldconfigPath, lookErr := exec.LookPath(ldconfig)
    if lookErr != nil {
        // Ubuntu wraps ldconfig as ldconfig.real; try that next.
        ldconfigPath = "/sbin/" + ldconfig + ".real"
        if _, statErr := os.Stat(ldconfigPath); statErr != nil {
            ldconfigPath = "/sbin/" + ldconfig
        }
    }
    out, err := c.exec.CommandContext(ctx, ldconfigPath, ldconfigParam).Output()
    if err != nil {
        return err
    }
    // ... existing parse of `out`
}
```

The `Validate(ctx)` signature change must be applied to every implementation of the prereq rule interface. Find them with:

```
grep -rn 'Validate() error' internal/pkg/prerequisites/
```

New file (`internal/pkg/exec/README.md`):

```
# exec

Thin context-aware wrapper around os/exec. All command construction
goes through this package so call sites are easy to audit.

Policy:
- Callers MUST pass a context.Context with a timeout.
- Commands MUST be whitelisted at the call site, never user-input-derived.
- The G204 suppression on RealExec.CommandContext is intentional and reviewed.
```

Regenerate the mock:

```
go generate ./internal/pkg/exec/...
```

**Commit message**

```
exec: context+timeout, find ldconfig via PATH (gosec G204, NixOS)

- Exec interface: Command → CommandContext.
- Validate() takes context; ldconfig call gets 10s timeout.
- LookPath("ldconfig") first; fall back to /sbin/.
- Fixes NixOS where /sbin/ldconfig is absent.
- #nosec G204 on the wrapper (generic by design).

internal/pkg/exec/exec.go
internal/pkg/exec/README.md (new)
internal/pkg/prerequisites/dcgmlib_rule.go
internal/pkg/prerequisites/types.go
internal/pkg/prerequisites/validation.go
```

**PR title**

```
exec: context+timeout, find ldconfig via PATH (gosec G204, NixOS)
```

**PR body**

```
What: make the exec wrapper context-aware and find ldconfig via PATH.
Why: timeouts protect against hung subprocesses; PATH lookup makes the daemon run on NixOS without a /sbin/ldconfig shim.
How: Exec.Command → CommandContext; Validate(ctx); exec.LookPath fallback chain.

Findings rule: gosec G204, golangci-lint noctx
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

Table-driven test in `internal/pkg/prerequisites/dcgmlib_rule_test.go`:

```go
cases := []struct {
    name        string
    lookPathOK  bool
    statExists  map[string]bool // path → exists
    timeout     time.Duration
    cmdOutput   []byte
    cmdErr      error
    wantPath    string
    wantTimeout bool
    wantErr     bool
}{
    {"positive: LookPath finds it (NixOS-like)",         true,  nil,                                       time.Second, []byte("libdcgm.so.4"), nil, "<lookpath>", false, false},
    {"positive: ldconfig.real exists (Ubuntu)",          false, map[string]bool{"/sbin/ldconfig.real": true}, time.Second, []byte("libdcgm.so.4"), nil, "/sbin/ldconfig.real", false, false},
    {"positive: only /sbin/ldconfig (Debian)",           false, map[string]bool{"/sbin/ldconfig": true},   time.Second, []byte("libdcgm.so.4"), nil, "/sbin/ldconfig",      false, false},
    {"negative: no ldconfig anywhere",                   false, map[string]bool{},                          time.Second, nil,                    errors.New("not found"), "/sbin/ldconfig", false, true},
    {"corner: timeout exceeded",                         true,  nil,                                       time.Millisecond, nil,               context.DeadlineExceeded, "<lookpath>", true,  true},
    {"negative: library not present in ldconfig output", true,  nil,                                       time.Second, []byte("libfoo.so"),    nil, "<lookpath>", false, true},
}
```

Use a mock filesystem for `os.Stat` and the existing `exec.Exec` mock for `CommandContext`.

**Maintainer review focus**

- The `Validate(ctx)` signature change must be applied to **every** prereq rule. Verify with `grep -rn 'Validate() error' internal/pkg/prerequisites/` — that grep should return zero results after the change.

---

## PR 3 — debug: dir mode 0o755 → 0o750

**Branch:** `security/debug-dir-mode-0750` (forks from `main`)
**Findings rule:** gosec G301

**Why this matters.** Debug dumps may include GPU topology and process IDs. Other users on the same host should not be able to read those files. The cost of the fix is one digit.

**Files**

- `internal/pkg/debug/debug.go` — line 70.

**Change**

```go
// before
if err := os.MkdirAll(fd.config.Directory, 0o755); err != nil {

// after
if err := os.MkdirAll(fd.config.Directory, 0o750); err != nil {
```

**Commit message**

```
debug: dir mode 0o755 → 0o750 (gosec G301)

internal/pkg/debug/debug.go:70
Debug dumps may include GPU topology and PIDs.
No reason to grant world-read.
```

**PR title**

```
debug: dir mode 0o755 → 0o750 (gosec G301)
```

**PR body**

```
What: tighten debug-dump directory permissions.
Why: dumps may contain process IDs and GPU topology; world-read is unnecessary.
How: 0o755 → 0o750 on MkdirAll.

Findings rule: gosec G301
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

Table-driven test in `internal/pkg/debug/debug_test.go`. Verify via `os.Stat(dir).Mode().Perm()` after `MkdirAll`.

```go
cases := []struct {
    name     string
    umask    int
    wantMode os.FileMode
}{
    {"positive: default umask 022 → 0o750",     0o022, 0o750},
    {"boundary: strict umask 077 → 0o700",      0o077, 0o700},
    {"corner: loose umask 002 still 0o750",     0o002, 0o750},
    {"corner: existing dir, MkdirAll no-op",    -1,    0o777}, // pre-create with 0o777, verify unchanged
}
```

**Maintainer review focus**

- `MkdirAll` does **not** tighten permissions on a directory that already exists. If the dir was created earlier with `0o755`, this change does not retroactively fix it. Acceptable behaviour; flagged for the commit body.

---

## PR 4 — docker: SHELL with pipefail

**Branch:** `security/dockerfile-shell-pipefail` (forks from `main`)
**Findings rule:** hadolint DL4006

**Why this matters.** Without `pipefail`, a non-zero exit from any pipe segment **except the last one** is silently dropped. In the builder stage, this means a failed `wget` or a broken `sha256sum` can be hidden if the next command in the pipe (e.g. `awk`) succeeds. The fix is one line per stage.

**Files**

- `docker/Dockerfile` — two stages (`builder` at line 20, `runtime-distroless-helper` at line 288).
- `.devcontainer/Dockerfile` — single stage (line 1).

**Change**

In each affected stage, insert this line immediately after the `FROM ... AS <stage>` directive:

```
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
```

Stages that do not contain a piped `RUN` do not need the directive.

**Commit message**

```
docker: SHELL with pipefail (hadolint DL4006)

docker/Dockerfile: builder + runtime-distroless-helper stages.
.devcontainer/Dockerfile: single stage.
Catches silent failures inside piped RUN commands.
```

**PR title**

```
docker: SHELL with pipefail (hadolint DL4006)
```

**PR body**

```
What: add `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` to stages with piped RUN.
Why: without pipefail, errors before the last pipe segment are silently dropped — a bad checksum or a failed download becomes a green build.
How: one SHELL directive per stage that contains a pipe.

Findings rule: hadolint DL4006
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- `make ubuntu22.04`, `make distroless` build green.
- `nix run .#lint-hadolint` no longer reports DL4006 on these stages.

**Maintainer review focus**

- Both Ubuntu and the distroless-helper stage have `bash` available. Confirmed during exploration.

---

## PR 5 — docker: COPY absolute dest in distroless

**Branch:** `security/dockerfile-copy-absolute-paths` (forks from `main`)
**Findings rule:** hadolint DL3045

**Why this matters.** A relative `COPY` destination depends on whatever `WORKDIR` the base image happens to set. If the base image changes, the file lands in a different place. Absolute paths are unambiguous.

**Files**

- `docker/Dockerfile` — line 334, `runtime-distroless` stage.

**Change**

```
# before
COPY --chown=root:root --chmod=644 ./LICENSE ./licenses/LICENSE

# after
COPY --chown=root:root --chmod=644 ./LICENSE /licenses/LICENSE
```

**Commit message**

```
docker: COPY absolute dest in distroless (hadolint DL3045)

docker/Dockerfile:334
Relative dest without WORKDIR is brittle.
```

**PR title**

```
docker: COPY absolute dest in distroless (hadolint DL3045)
```

**PR body**

```
What: change a relative COPY destination to absolute in the runtime-distroless stage.
Why: hadolint DL3045 — relative destination without WORKDIR depends on the base image's internals.
How: ./licenses/LICENSE → /licenses/LICENSE.

Findings rule: hadolint DL3045
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- `make distroless` builds.
- `docker run --rm --entrypoint /bin/sh <image> -c 'ls /licenses/LICENSE'` shows the file present.

**Maintainer review focus**

- No behaviour change expected — the file was already landing at `/licenses/LICENSE` because the distroless base image's `WORKDIR` is `/`. Confirm by `docker inspect nvcr.io/nvidia/distroless/cc:v4.0.4` if in doubt.

---

## PR 6 — devcontainer: useradd -l

**Branch:** `security/devcontainer-useradd-l-flag` (forks from `main`)
**Findings rule:** hadolint DL3046

**Why this matters.** Without `-l`, `useradd` may create a multi-gigabyte sparse `/var/log/lastlog` for high UIDs. UID 1000 in this devcontainer is not high enough to trigger the bug today, but `-l` is the safe default and is essentially free.

**Files**

- `.devcontainer/Dockerfile` — line 8.

**Change**

```
# before
useradd -m -u $USER_GID -g $USERNAME -s /bin/bash $USERNAME

# after
useradd -m -l -u $USER_GID -g $USERNAME -s /bin/bash $USERNAME
```

**Commit message**

```
devcontainer: useradd -l (hadolint DL3046)

.devcontainer/Dockerfile:8
Avoids large sparse lastlog on high UIDs.
```

**PR title**

```
devcontainer: useradd -l (hadolint DL3046)
```

**PR body**

```
What: add `-l` to `useradd` in the devcontainer.
Why: hadolint DL3046 — without -l, useradd may create a multi-GB sparse /var/log/lastlog for high UIDs. UID 1000 is fine today but -l is the safe default.
How: add `-l` flag.

Findings rule: hadolint DL3046
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- `docker build -f .devcontainer/Dockerfile .` succeeds.
- `docker run --rm <image> id developer` shows the user is present.

**Maintainer review focus**

- `-l` skips `lastlog` and `faillog` entries — harmless for a devcontainer.

---

## PR 7 — devcontainer: use curl, drop wget

**Branch:** `security/devcontainer-curl-only` (forks from `main`)
**Findings rule:** hadolint DL4001, DL3047

**Why this matters.** Two TLS clients shipped in one image is two attack surfaces and two supply-chain risks. The repo already uses both `wget` and `curl` for various downloads. Standardising on `curl` removes the `wget` apt package and removes the related DL3047 findings (no progress bar) because curl shows progress by default on a TTY and is silent otherwise.

**Files**

- `.devcontainer/Dockerfile` — lines 25 (apt list), 29, 69, 72.

**Change**

- Line 25: remove `wget` from the apt-get install list.
- Line 29: `wget -O /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg`
  → `curl -fSL --retry 3 -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg`
- Line 69: `wget -O go.tgz "$url" --progress=dot:giga`
  → `curl -fSL --retry 3 -o go.tgz "$url"`
- Line 72: `wget -O go.sha256 "https://dl.google.com/go/${filename}.sha256"`
  → `curl -fSL --retry 3 -o go.sha256 "https://dl.google.com/go/${filename}.sha256"`

`curl` flag summary: `-f` fail on HTTP 4xx/5xx; `-S` show errors; `-L` follow redirects; `--retry 3` retry transient failures three times.

**Commit message**

```
devcontainer: use curl, drop wget (hadolint DL4001)

.devcontainer/Dockerfile
-fSL --retry 3 = fail on HTTP errors, follow redirects, retry on transient failure.
Removes wget from apt list.
```

**PR title**

```
devcontainer: use curl, drop wget (hadolint DL4001)
```

**PR body**

```
What: replace all wget calls in .devcontainer/Dockerfile with curl.
Why: hadolint DL4001 — two TLS clients increase attack surface and image bloat. DL3047 is subsumed because curl is silent off-TTY.
How: `wget -O X URL` → `curl -fSL --retry 3 -o X URL`; remove wget from apt-get list.

Findings rule: hadolint DL4001, DL3047
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- `docker build -f .devcontainer/Dockerfile .` succeeds.
- The existing SHA256 verification step (`sha256sum go.tgz | awk ...`) still runs and still fails the build on mismatch.

**Maintainer review focus**

- `curl -fSL` fails on HTTP 4xx/5xx (matches `wget -O`'s behaviour). `--retry 3` is a strict improvement over plain `wget -O`.

---

## PR 8 — dcgmprovider: drop unused moduleCleanup field

**Branch:** `cleanup/dcgmprovider-drop-unused-field` (forks from `main`)
**Findings rule:** staticcheck U1000

**Why this matters.** Dead code is a maintenance hazard. Removing it is risk-free.

**Files**

- `internal/pkg/dcgmprovider/dcgm.go` — line 55.

**Change**

Delete the line:

```go
moduleCleanup func()
```

Before deleting, confirm with `grep -rn 'moduleCleanup' internal/ pkg/ cmd/` that the field is not referenced anywhere else.

**Commit message**

```
dcgmprovider: drop unused moduleCleanup field (staticcheck U1000)

internal/pkg/dcgmprovider/dcgm.go:55
Field is never read or assigned.
```

**PR title**

```
dcgmprovider: drop unused moduleCleanup field (staticcheck U1000)
```

**PR body**

```
What: remove the unused moduleCleanup field on the dcgmprovider struct.
Why: dead code; staticcheck U1000.
How: delete the line.

Findings rule: staticcheck U1000
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- Existing `dcgmprovider` tests pass. No new tests needed for a deletion.

**Maintainer review focus**

- Confirm nothing uses reflection on this field name. The grep above is sufficient.

---

## PR 9 — deviceinfo: use copy() builtin

**Branch:** `cleanup/deviceinfo-use-copy-builtin` (forks from `main`)
**Findings rule:** staticcheck S1001

**Why this matters.** The Go `copy()` builtin is shorter, idiomatic, and uses `memmove` internally. Maintenance and review are easier when standard idioms are used.

**Files**

- `internal/pkg/deviceinfo/device_info.go` — line 601.

**Change**

Replace the explicit byte-copy loop with `copy(dst, bitmask)`. Confirm `len(dst) >= len(bitmask)` at the call site, or use `dst = dst[:len(bitmask)]` defensively.

**Commit message**

```
deviceinfo: use copy() builtin (staticcheck S1001)

internal/pkg/deviceinfo/device_info.go:601
Replace manual loop with builtin.
```

**PR title**

```
deviceinfo: use copy() builtin (staticcheck S1001)
```

**PR body**

```
What: replace a manual byte-copy loop with the copy() builtin.
Why: copy() is shorter and slightly faster (uses memmove).
How: for-loop → copy(dst, src).

Findings rule: staticcheck S1001
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- Existing `device_info` tests pass; behaviour preserved.

**Maintainer review focus**

- `copy` writes `min(len(dst), len(src))` bytes; the original loop wrote `len(bitmask)` unconditionally. If `dst` is shorter than `bitmask`, the loop would have panicked; `copy` will not. Confirm the call site invariant.

---

## PR 10 — devicewatcher: drop dot import, qualify logging refs

**Branch:** `cleanup/devicewatcher-qualify-logging` (forks from `main`)
**Findings rule:** staticcheck ST1001

**Why this matters (explained at length because it is non-obvious).**

A "dot import" is the import form `. "path/to/pkg"`. It pulls every exported identifier from `pkg` into the current package's namespace **without a qualifier**. So `ErrorKey` could be:

- A constant defined in this file.
- A constant defined elsewhere in this package.
- An exported identifier from `logging` brought in via the dot import.

A reader cannot tell from the use site which one it is. This makes code review harder, breaks `grep`-based navigation, and makes IDE go-to-definition unreliable. The Go standard library uses dot imports only in test files (and even then rarely).

The standard fix is to use a normal named import and qualify each use as `logging.ErrorKey`. There is no behaviour change.

**Files**

- `internal/pkg/devicewatcher/device_watcher.go` — line 31 (the import) plus six use sites in the file.

**Change**

Line 31:
```go
// before
. "github.com/NVIDIA/dcgm-exporter/internal/pkg/logging"

// after
"github.com/NVIDIA/dcgm-exporter/internal/pkg/logging"
```

Qualify the references to symbols **defined in the local `logging` package**:

- `ErrorKey` → `logging.ErrorKey` (4 occurrences: lines 63, 73, 104, 407)
- `GroupIDKey` → `logging.GroupIDKey` (2 occurrences: lines 83, 406)

**Do not change** `DCGM_ST_NOT_CONFIGURED` or `DCGM_ST_FIELD_NOT_WATCHED`. Those come from `github.com/NVIDIA/go-dcgm/pkg/dcgm`, not from the local `logging` package. They are imported separately. (Verified during exploration.)

**Commit message**

```
devicewatcher: drop dot import, qualify logging refs (staticcheck ST1001)

internal/pkg/devicewatcher/device_watcher.go
Replace `. "internal/pkg/logging"` with named import.
Qualify ErrorKey, GroupIDKey → logging.ErrorKey, logging.GroupIDKey.
```

**PR title**

```
devicewatcher: drop dot import, qualify logging refs (staticcheck ST1001)
```

**PR body**

```
What: replace the dot import of internal/pkg/logging with a named import.
Why: dot imports pollute the namespace — readers cannot tell whether an identifier is local or imported. staticcheck ST1001.
How: drop the leading `.`, qualify ErrorKey and GroupIDKey at the use sites.

Findings rule: staticcheck ST1001
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- No new tests; existing `devicewatcher` tests must pass.
- `go vet` and the gated `staticcheck` check both go green.

**Maintainer review focus**

- After the change, `grep -n '\bErrorKey\|\bGroupIDKey' internal/pkg/devicewatcher/device_watcher.go` should return zero unqualified hits.

---

## PR 11 — cleanup: error string style + Fprintf

**Branch:** `cleanup/error-strings-and-fprintf` (forks from `main`)
**Findings rule:** staticcheck ST1005 ×2, QF1012

**Why this matters.** The Go convention is that error strings start with a lowercase letter and do not end with punctuation. This is so callers can wrap them naturally: `fmt.Errorf("foo: %w", err)` produces `foo: the X library was not found` rather than `foo: The X library was not found.`. The `Fprintf` change avoids a temporary string allocation.

These three findings are bundled into one PR per the maintainer's explicit request.

**Files**

- `internal/pkg/prerequisites/variables.go` — line 41.
- `pkg/cmd/app.go` — line 1005.
- `internal/pkg/collector/types.go` — line 164.

**Change**

1. `internal/pkg/prerequisites/variables.go:41` — strip the trailing period:
   ```go
   // before
   errLibdcgmNotFound = fmt.Errorf("the %s library was not found. Install Data Center GPU Manager (DCGM).", libdcgmco)
   // after
   errLibdcgmNotFound = fmt.Errorf("the %s library was not found. Install Data Center GPU Manager (DCGM)", libdcgmco)
   ```
2. `pkg/cmd/app.go:1005` — lowercase the first letter:
   ```go
   // before
   return dOpt, fmt.Errorf("Invalid ranged device option '%s': there can only be one specified range", devices)
   // after
   return dOpt, fmt.Errorf("invalid ranged device option %q: there can only be one specified range", devices)
   ```
   (Also `'%s' → %q` while we are touching this line, which is the idiomatic Go quoting verb.)
3. `internal/pkg/collector/types.go:164` — `WriteString(Sprintf(...))` → `Fprintf`:
   ```go
   // before
   result.WriteString(fmt.Sprintf("%q: %#v", counter.FieldName, metrics))
   // after
   fmt.Fprintf(&result, "%q: %#v", counter.FieldName, metrics)
   ```
   If `result` is a `strings.Builder` (not a `*bytes.Buffer`), `&result` still satisfies `io.Writer` because `strings.Builder`'s `Write` method has a pointer receiver. Confirm at the call site.

**Commit message**

```
cleanup: error string style + Fprintf (staticcheck ST1005, QF1012)

prerequisites/variables.go:41 — drop trailing period in error message.
pkg/cmd/app.go:1005           — lowercase first letter of error message.
collector/types.go:164        — WriteString(Sprintf(...)) → Fprintf.
```

**PR title**

```
cleanup: error string style + Fprintf (staticcheck ST1005, QF1012)
```

**PR body**

```
What: three small staticcheck fixes bundled.
Why: error strings should start lowercase and not end with punctuation (Go convention); Fprintf avoids a temporary Sprintf allocation.
How: see the commit body.

Findings rule: staticcheck ST1005 ×2, QF1012
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- Existing tests for each touched package pass.
- If any test asserts on the literal error string, update the assertion in the same commit.

**Maintainer review focus**

- `grep -rn '"Invalid ranged"' .` should return zero hits after the change. Same for `"library was not found."`.

---

## PR 12 — deviceinfo: tagged switch on EntityGroupId

**Branch:** `cleanup/deviceinfo-tagged-switch` (forks from `main`)
**Findings rule:** staticcheck QF1003

**Why this matters.** A chain of `if x == foo { ... } else if x == bar { ... }` is harder to read and extend than a `switch x { case foo: ... case bar: ... }`. DCGM adds new entity group constants over time; a switch makes the next addition mechanical.

**Files**

- `internal/pkg/deviceinfo/device_info.go` — around line 186.

**Change**

Read the full if-chain in the file first. Convert:

```go
// before
if hierarchy.EntityList[i].Parent.EntityGroupId == dcgm.FE_GPU {
    ...
} else if hierarchy.EntityList[i].Parent.EntityGroupId == dcgm.FE_SWITCH {
    ...
}

// after
switch hierarchy.EntityList[i].Parent.EntityGroupId {
case dcgm.FE_GPU:
    ...
case dcgm.FE_SWITCH:
    ...
}
```

No `default` case needed if the original chain had no `else` branch.

**Commit message**

```
deviceinfo: tagged switch on EntityGroupId (staticcheck QF1003)

internal/pkg/deviceinfo/device_info.go:186
Replace if/else chain with switch — shorter, easier to extend.
```

**PR title**

```
deviceinfo: tagged switch on EntityGroupId (staticcheck QF1003)
```

**PR body**

```
What: convert an if/else chain on EntityGroupId to a tagged switch.
Why: shorter and easier to extend when DCGM adds a new entity group.
How: switch hierarchy.EntityList[i].Parent.EntityGroupId { case ...: }.

Findings rule: staticcheck QF1003
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- Existing `device_info` tests cover the branches; ensure each `case` is exercised. If coverage is missing, add a table-driven test scoped to the helper function:
  ```go
  cases := []struct {
      name      string
      group     dcgm.Field_Entity_Group
      wantSlice string
  }{
      {"positive: GPU",         dcgm.FE_GPU,    "gpus"},
      {"positive: SWITCH",      dcgm.FE_SWITCH, "switches"},
      {"corner: unknown group", dcgm.FE_NONE,   "<default>"},
  }
  ```

**Maintainer review focus**

- A Go `switch` evaluates cases in source order — the same ordering as the original if-chain. No behaviour change.

---

## PR 13 — devicemonitoring: keyed WatchedEntityKey literals

**Branch:** `cleanup/device-monitoring-keyed-literals` (forks from `main`)
**Findings rule:** go vet `composites`

**Why this matters.** `WatchedEntityKey` is `struct { ParentID uint; ChildID uint }`. Today the test file uses positional literals like `{0, 0}: true`. If anyone ever swaps the order of the fields in the struct, the tests **silently change meaning** — every literal `{a, b}` now refers to the opposite mapping. Keyed literals (`{ParentID: 0, ChildID: 0}: true`) are immune.

**Files**

- `internal/pkg/devicemonitoring/device_monitoring_test.go` — 29 sites, lines 458–1423.

**Change**

A `sed` does the bulk of the work:

```
sed -E -i 's/\{([0-9]+), ([0-9]+)\}: /{ParentID: \1, ChildID: \2}: /g' \
    internal/pkg/devicemonitoring/device_monitoring_test.go
```

After running the `sed`, eyeball the diff to confirm every site converted cleanly (no map keys with non-numeric components, no nested literals).

**Commit message**

```
devicemonitoring: keyed WatchedEntityKey literals (go vet composites)

internal/pkg/devicemonitoring/device_monitoring_test.go
Convert 29 unkeyed {a, b}: true literals to {ParentID: a, ChildID: b}: true.
Future field reorders won't silently shuffle test inputs.
```

**PR title**

```
devicemonitoring: keyed WatchedEntityKey literals (go vet composites)
```

**PR body**

```
What: convert 29 unkeyed WatchedEntityKey literals to keyed form in device_monitoring_test.go.
Why: go vet composites — if WatchedEntityKey ever swaps field order, current tests would silently change meaning. Keyed literals make field reordering safe.
How: sed + manual review of the diff.

Findings rule: go vet composites
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
```

**Test plan**

- Tests still pass — purely cosmetic.

**Maintainer review focus**

- The diff is large but every hunk has the same shape. Reading two or three hunks is enough.

---

## PR 14 — server: thread r.Context() through render

**Branch:** `correctness/server-thread-request-context` (forks from `main`)
**Findings rule:** golangci-lint `contextcheck`

**Why this matters.** Prometheus scrapers cancel the HTTP request when the scrape times out. Today the metrics handler discards the request (`func (s *MetricsServer) Metrics(w http.ResponseWriter, _ *http.Request)`) and `render` cannot honour cancellation. The daemon keeps rendering metrics after the scrape has given up. This is wasted CPU and adds shutdown latency. The fix also removes two `context.Background()` placeholders that the original author left in `slog.LogAttrs` calls.

**Files**

- `internal/pkg/server/server.go` — `Metrics` handler and `render` function.
- `internal/pkg/server/server_test.go` — new table-driven test.

**Change**

```go
// before
func (s *MetricsServer) Metrics(w http.ResponseWriter, _ *http.Request) {
    ...
    err = s.render(&buf, metricGroups)
}

func (s *MetricsServer) render(w io.Writer, metricGroups …) error {
    for group, metrics := range metricGroups {
        ...
        slog.LogAttrs(context.Background(), slog.LevelError, "Failed to apply transformations on metrics", ...)
        ...
    }
}

// after
func (s *MetricsServer) Metrics(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context()
    ...
    err = s.render(ctx, &buf, metricGroups)
}

func (s *MetricsServer) render(ctx context.Context, w io.Writer, metricGroups …) error {
    for group, metrics := range metricGroups {
        if err := ctx.Err(); err != nil {
            return err
        }
        ...
        slog.LogAttrs(ctx, slog.LevelError, "Failed to apply transformations on metrics", ...)
        ...
    }
}
```

The follow-up work — threading `ctx` into `transformation.Process` and `rendermetrics.RenderGroup` — needs interface changes outside this file and is **out of scope** for this PR. Flag it in the PR body as a follow-up.

**Commit message**

```
server: thread r.Context() through render (golangci-lint contextcheck)

internal/pkg/server/server.go
- Metrics handler uses r.Context() instead of discarding the request.
- render(ctx, ...) signature.
- Replace context.Background() in slog.LogAttrs with the real ctx.
- Early-return ctx.Err() between metric-group iterations so a
  cancelled scrape aborts within one group.
```

**PR title**

```
server: thread r.Context() through render (golangci-lint contextcheck)
```

**PR body**

```
What: pass the HTTP request context through render() and use it for logging + cancellation.
Why: Prometheus scrapers cancel on timeout; today the daemon keeps rendering after cancellation, wasting CPU and adding shutdown latency. Also fixes two slog.LogAttrs calls that currently use context.Background() as a placeholder.
How: Metrics(w, r) reads r.Context(); render(ctx, w, mg); ctx.Err() check between metric groups.

Findings rule: golangci-lint contextcheck
Refs: nix/STATIC_ANALYSIS_FINDINGS.md
Follow-up: thread ctx into transformation.Process and rendermetrics.RenderGroup (separate PR; needs interface changes upstream).
```

**Test plan**

Table-driven test in `internal/pkg/server/server_test.go`. Use `httptest.NewRequestWithContext` to inject a cancellable context.

```go
cases := []struct {
    name       string
    cancelAt   string // "never" | "before-render" | "mid-render"
    wantStatus int
    wantBodyHasPrefix string
}{
    {"positive: no cancel, happy path", "never",         200, "# HELP"},
    {"negative: client cancels before render starts", "before-render", 200, ""},
    {"corner: client cancels mid-render", "mid-render",  200, "# HELP"},
    {"boundary: context already cancelled at handler entry", "before-render", 200, ""},
}
```

(The HTTP status is 200 in all cases because the response header is written before render begins — only the body is truncated. A follow-up PR could make the handler write 499 / log the cancellation more visibly; out of scope here.)

**Maintainer review focus**

- This is the only PR in the series with a **runtime behaviour change**: a cancelled scrape now produces a truncated response body instead of a complete one. Some monitoring setups will treat truncation as an error (e.g. Prometheus will log a parse error). Acceptable trade-off — the scrape was going to fail anyway — but it should be called out in the release notes.

---

## Shared appendix

### Opening a PR upstream

After the branch is pushed to the user's fork (`origin`):

```
gh pr create \
    --repo NVIDIA/dcgm-exporter \
    --base main \
    --head randomizedcoder:<branch> \
    --title "<PR title from this document>" \
    --body-file <(echo "<PR body from this document>")
```

`gh` auto-detects the remote and prompts for the body if `--body-file` is omitted.

### DCO sign-off

`CONTRIBUTING.md` requires every commit to carry a `Signed-off-by:` trailer. Use `git commit -s` to add it automatically. The trailer must match `user.name` and `user.email` from `git config`.

### Reproducing a single finding locally

To re-verify any finding before fixing it, see `nix/STATIC_ANALYSIS_FINDINGS.md` § "How to reproduce". Each rule cite there includes the exact tool invocation.

### Out of scope (for follow-up)

The findings report calls out a much larger set of issues. The items below are **deliberately not in this PR series** but are worth a separate planning pass:

- The 8 `exhaustive` switches in `internal/pkg/{collector,deviceinfo,devicemonitoring,devicewatcher,rendermetrics,transformation}` (forward-compat risk when DCGM adds entity groups).
- The 4 `errorlint` `%s → %w` fixes (better error wrapping).
- The `nilerr` real bug in `tests/e2e/internal/framework/helm.go:316` (test framework returns nil after an error — silent test failures possible).
- The `nilnil` finding in `internal/pkg/nvmlprovider/provider.go:211` (sentinel error).
- The 7 `noctx` findings in test files plus `internal/pkg/exec/exec.go` (covered by PR 2 for the prod code; test files separate).
- `recvcheck` mixed pointer/value receivers in `internal/pkg/collector/types.go:94`.
- Dependency cleanup: `go mod tidy` says `github.com/docker/docker-credential-helpers v0.9.3` is unused.
- The two `bodyclose` and four `errorlint` issues in `tests/integration/start_with_tls_test.go`.
- Markdown / typos / cspell quality cleanup (configs missing — add `_typos.toml` and `cspell.json` first).

These are listed in `nix/STATIC_ANALYSIS_FINDINGS.md`. Pick them up in a second PR series after the current set has landed.
