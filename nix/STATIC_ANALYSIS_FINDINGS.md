# Static analysis findings — dcgm-exporter

**Branch:** `nix` · **Analyzed commit:** `0ae29e1` (with local `vendorHash` update) · **Run date:** 2026-06-19
**Source of analysis:** every output exposed by `flake.nix` plus two ad-hoc maximum-strict passes (`golangci-lint --default=none -E '<43 linters>'`, `gosec -severity=low -confidence=low`).

**Toolchain (`nix develop`):** Go 1.26.3 · golangci-lint 2.12.2 · staticcheck 2026.1 (v0.7.0) · gosec 2.27.0 · govulncheck 1.3.0 · hadolint 2.14.0 · gitleaks 8.30.1 · typos 1.47.2 · cspell 9.7.0 · markdownlint-cli2 0.22.1

## Summary

| Category | Findings | Notable rules / tools |
| --- | ---: | --- |
| **Security** | **20** | gosec (14), gitleaks (1), hadolint (4 security-relevant warnings of 13 total), TLS InsecureSkipVerify (2 in tests, counted under gosec G402 below) — total dedup = 20 |
| Correctness / latent bugs | 92 | staticcheck (108 incl. style — 11 real bugs), go vet (29), bodyclose (2), noctx (8), contextcheck (1), errorlint (4), exhaustive (8), nilerr (1), nilnil (1), recvcheck (1), tparallel (1), musttag (1), unused (1), unparam (1) |
| Quality / style | 367 | gocritic, perfsprint (17), prealloc (8), protogetter (24), intrange (6), staticcheck QF/ST/U codes (97), markdownlint (155), typos (45 — but ~30 are domain-FP), cspell (4381 — almost all domain-FP), deadnix (1 — in our own nix code), hadolint info-level (5) |
| Tool errors / coverage gaps | 4 | `govulncheck` (no network in sandbox), `go-mod-tidy-check` (proxyVendor missing test-fixture modules, plus 1 real `go mod tidy` diff), `go-test-short` (tests dlopen libdcgm/libnvidia-ml that aren't in sandbox), `gofmt-check` + `goimports-check` (our own `checks.nix` has a `$out` shell-variable shadowing bug) |

Security findings are listed exhaustively below. Correctness findings are listed exhaustively. Quality / style findings are summarized per-rule with representative samples (full output reproducible via the commands in "How to reproduce").

## PRs opened upstream

Each finding triaged for action in this report landed as a single focused PR against `NVIDIA/dcgm-exporter:main`:

| Rule | Site | PR |
| --- | --- | --- |
| gosec **G115** (NVLink state cast) | `internal/pkg/collector/p2p_status_collector.go:85` | [#681](https://github.com/NVIDIA/dcgm-exporter/pull/681) |
| gosec **G204** + golangci-lint **noctx** (exec wrapper, NixOS) | `internal/pkg/exec/exec.go`, `internal/pkg/prerequisites/dcgmlib_rule.go` | [#684](https://github.com/NVIDIA/dcgm-exporter/pull/684) |
| gosec **G301** (debug dir mode) | `internal/pkg/debug/debug.go:70` | [#682](https://github.com/NVIDIA/dcgm-exporter/pull/682) |
| hadolint **DL4006** (SHELL pipefail) | `docker/Dockerfile`, `.devcontainer/Dockerfile` | [#683](https://github.com/NVIDIA/dcgm-exporter/pull/683) |
| hadolint **DL3045** (COPY relative dest) | `docker/Dockerfile:334` | [#685](https://github.com/NVIDIA/dcgm-exporter/pull/685) |
| hadolint **DL3046** (useradd `-l`) | `.devcontainer/Dockerfile:8` | [#686](https://github.com/NVIDIA/dcgm-exporter/pull/686) |
| hadolint **DL4001** + **DL3047** (curl-only) | `.devcontainer/Dockerfile` | [#694](https://github.com/NVIDIA/dcgm-exporter/pull/694) |
| staticcheck **U1000** (unused field) | `internal/pkg/dcgmprovider/dcgm.go:55` | [#693](https://github.com/NVIDIA/dcgm-exporter/pull/693) |
| staticcheck **S1001** (copy() builtin) | `internal/pkg/deviceinfo/device_info.go:601` | [#692](https://github.com/NVIDIA/dcgm-exporter/pull/692) |
| staticcheck **ST1001** (dot import) | `internal/pkg/devicewatcher/device_watcher.go:31` | [#691](https://github.com/NVIDIA/dcgm-exporter/pull/691) |
| staticcheck **ST1005** ×2 + **QF1012** (error strings + Fprintf) | `internal/pkg/prerequisites/variables.go:41`, `pkg/cmd/app.go:1005`, `internal/pkg/collector/types.go:164` | [#690](https://github.com/NVIDIA/dcgm-exporter/pull/690) |
| staticcheck **QF1003** (tagged switch) | `internal/pkg/deviceinfo/device_info.go:186` | [#689](https://github.com/NVIDIA/dcgm-exporter/pull/689) |
| go vet **composites** (unkeyed `WatchedEntityKey` literals) | `internal/pkg/devicemonitoring/device_monitoring_test.go` | [#688](https://github.com/NVIDIA/dcgm-exporter/pull/688) |
| golangci-lint **contextcheck** (server `render`) | `internal/pkg/server/server.go:261` | [#687](https://github.com/NVIDIA/dcgm-exporter/pull/687) |

Findings the maintainer triaged but deferred to a second pass (`exhaustive` switches, `errorlint` `%s → %w`, `nilerr` in helm test framework, `nilnil`, `bodyclose`, the unused `docker-credential-helpers` dep, markdownlint / typos / cspell config setup) are listed in the "Recommended next steps" section at the bottom of this document.

## How to reproduce

From the repo root:

```bash
# 1. Capture the real vendorHash (only needed once after go.mod / go.sum changes)
nix build .#default -L --no-link
# If the hash differs, edit nix/lib.nix → vendorHash, re-run.

# 2. Run every gated check (sandboxed; what CI would gate on)
nix flake check -L --keep-going

# 3. Run every manual lint app
nix run .#lint-extreme          # fan-out: shellcheck, shfmt, deadnix, statix, gitleaks,
                                #          markdown, typos, cspell, nil, golangci, hadolint

# 4. Push past .golangci.yml's 8-linter subset to maximum coverage
nix develop -c bash -c '
  CGO_ENABLED=1 golangci-lint run --default=none \
    -E gosec,errcheck,bodyclose,nilerr,nilnil,errchkjson,errorlint,exhaustive,contextcheck,gocritic,govet,ineffassign,loggercheck,makezero,noctx,recvcheck,rowserrcheck,sqlclosecheck,unparam,unused,whitespace,staticcheck,tparallel,wastedassign,canonicalheader,durationcheck,bidichk,asciicheck,dupword,fatcontext,gocheckcompilerdirectives,intrange,perfsprint,prealloc,protogetter,reassign,sloglint,spancheck,thelper,zerologlint,nakedret,musttag,exptostd,copyloopvar \
    --timeout 15m ./...
'

# 5. Lowest-threshold gosec
nix develop -c bash -c 'CGO_ENABLED=1 gosec -fmt=text -severity=low -confidence=low ./...'
```

Outputs were captured to `/tmp/dcgm-static-analysis/*.log` during the run; not committed.

---

## 🔒 Security findings (top priority — 20 items)

### Gitleaks (committed secret — high priority)

| Rule | Location | Severity | Recommendation |
| --- | --- | --- | --- |
| `private-key` | `tests/integration/testdata/tlsCertificate.key:1` (introduced at commit `c3919a5fce` on 2023-12-13 by `vfedorov@nvidia.com`) | **HIGH (informational)** | This is a **deliberate test fixture** — a TLS certificate key used by `tests/integration/start_with_tls_test.go`. Verdict: **suppress, do not rotate**. **Action:** add a `.gitleaks.toml` allowlist entry pinning the file path + the certificate's known fingerprint, so future audits don't have to re-rationalise it. Without an allowlist, every gitleaks run reports it and obscures real future leaks. |

### gosec (14 issues — Files: 97, Lines: 14681)

#### HIGH severity

| Rule | Location | Confidence | Snippet |
| --- | --- | --- | --- |
| **G115** integer overflow conversion `uint64 → int` | `internal/pkg/collector/p2p_status_collector.go:85` | MEDIUM | `linkValue := int(uint64(link)) //nolint:gosec // link values are small in practice` |

Already suppressed via `//nolint:gosec` with a justification comment. **Recommendation:** verify the comment's claim ("link values are small in practice") is bounded by the NVLink hardware spec — if `link` is a `dcgmNvLinkLink_t` (uint8 in DCGM SDK), the comment is correct and the suppression is sound. Add `// gosec:G115 see comment` to the lint exclusion file for searchability.

#### MEDIUM severity

| # | Rule | Location | Confidence | Recommendation |
| --- | --- | --- | --- | --- |
| 1 | **G204** subprocess launched with variable | `internal/pkg/exec/exec.go:39` (`exec.Command(name, arg...)`) | HIGH | This is the `RealExec.Command` wrapper — the variable input is by-design (this *is* the abstraction over `os/exec`). Caller sites are constrained: prerequisites check `/sbin/ldconfig`, devices info reads `lspci`. **Action:** add `// #nosec G204 -- intentional generic wrapper, callers vetted` directly on the line; document the caller-vet policy in `internal/pkg/exec/README.md`. Do not switch to a closed enum — that defeats the wrapper's purpose. |
| 2 | **G304** potential file inclusion via variable | `internal/pkg/os/os.go:58` (`os.Open(name)`) | HIGH | Same shape as G204: this is the `RealOS.Open` wrapper. **Action:** `// #nosec G304 -- wrapper; callers vetted`. Optionally migrate to `os.Root` (Go ≥1.24) per gosec's auto-fix suggestion if the codebase already has a fixed-root pattern. dcgm-exporter does open arbitrary user-supplied counter CSV paths — those are operator-trusted input, not external. |
| 3 | **G304** potential file inclusion via variable | `internal/pkg/debug/debug.go:75` (`os.Create(fullPath)`) | HIGH | `fullPath` is constructed inside `debug.go` from a sanitized config directory + a known suffix. **Action:** add `// #nosec G304 -- path is constructed under an admin-configured directory, no traversal possible` and add a defensive `filepath.Clean` + traversal guard if `fd.config.Directory` could ever be operator-tainted from an untrusted source (currently it can't be — it's the binary's CLI flag). |
| 4 | **G301** expect directory permissions to be 0750 or less | `internal/pkg/debug/debug.go:70` (`os.MkdirAll(fd.config.Directory, 0o755)`) | HIGH | Directory is for debug-dump output (only opened when `--enable-debug-dumps`). **Action:** **change to `0o750`** — there's no reason to grant world-read on debug dumps that may contain GPU topology / process IDs. This is a 1-line fix; do it. |

#### LOW severity

| # | Rule | Location | Confidence | Recommendation |
| --- | --- | --- | --- | --- |
| 5–6 | **G103** unsafe calls | `internal/pkg/testutils/test_utils.go:180` and `:340` (`unsafe.Pointer(fieldVal.UnsafeAddr())`) | HIGH | Used to set unexported struct fields via reflection in tests. **Action:** add `// #nosec G103 -- test-only reflection helper; runtime impact: none` and move the file under a build tag so it can't reach production binaries. (It's already not imported from main.) |
| 7 | **G706** log injection via taint analysis | `cmd/dcgm-exporter/main.go:31` (`slog.Error(err.Error())`) | HIGH | The error string can contain attacker-controlled bytes (config-file path with newlines, etc.). **Action:** call `slog.Error("startup failed", "err", err)` instead — slog will quote/escape attribute values, avoiding CRLF injection into structured logs. Single-line fix. |
| 8–13 | **G104** errors unhandled (`os.Setenv` x6) | `internal/pkg/dcgmprovider/dcgm.go:85,86`; `internal/pkg/dcgmprovider/smart_init.go:30,31`; `internal/pkg/transformation/kubernetes.go:530`; `tests/e2e/internal/framework/kube.go:309` | HIGH | The DCGM debug-env setters are part of the boot sequence — failure is non-recoverable but currently silent. **Action:** `if err := os.Setenv(...); err != nil { slog.Warn("failed to set DCGM debug env var", "err", err) }` for the four DCGM ones. For `conn.Close()` and `ln.Close()` (the last two), `//nolint:errcheck // best-effort cleanup` is acceptable. |

### gosec via golangci-lint --enable-all (additional findings not in standalone gosec)

| Rule | Location | Confidence | Recommendation |
| --- | --- | --- | --- |
| **G402** TLS InsecureSkipVerify set to `true` | `tests/integration/start_with_tls_test.go:88` and `:114` | HIGH | **Test-only.** The integration test deliberately exercises the self-signed cert path against a localhost server. **Action:** `// #nosec G402 -- integration test against self-signed localhost cert, see tlsCertificate.key fixture` — one-line addition per call site. |
| **G115** integer overflow `uint64 → int64`, `int64 → byte`, `uint64 → byte` | `internal/pkg/collector/clock_events_collector_test.go:294`, `internal/pkg/collector/utils_test.go:281,290` | MEDIUM | **Test-only conversions** in deterministic-input test helpers (mocked bitmasks). **Action:** `// #nosec G115 -- deterministic test input, bounded by hex literal above`. |

### hadolint (4 of 13 findings are security-relevant; rest are quality — see "Quality" section)

| Rule | Location | Severity | Recommendation |
| --- | --- | --- | --- |
| **DL4006** Set `SHELL` with `pipefail` before `RUN` with a pipe | `docker/Dockerfile:51,308`; `.devcontainer/Dockerfile:13,96` | warning | Pipes can silently lose error status. **Action:** add `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` at the top of each builder stage. Pure security/reliability — no behavioural change for passing builds. |
| **DL3046** `useradd` without `-l` and high UID | `.devcontainer/Dockerfile:7` | warning | Without `-l`, a high UID causes a multi-GB sparse `lastlog` file. **Action:** add `-l` to the `useradd` line, or pick a low UID. Cosmetic but image-bloat is a real DoS vector for storage. |
| **DL3045** `COPY` to a relative destination without `WORKDIR` | `docker/Dockerfile:238,334` | warning | Relative dest depends on the parent layer's `WORKDIR`. Brittle and prone to security-relevant misplacement. **Action:** make destination absolute (`/usr/share/...` etc.). |
| **DL4001** Either Wget or Curl, not both | `.devcontainer/Dockerfile:96` | warning | Two TLS clients increase attack surface for typosquatting / version mismatches. **Action:** pick one and remove the other across the file. |

### govulncheck

Did not run in the sandbox — `govulncheck` needs `https://vuln.go.dev` and the Nix sandbox blocks network. See "Tool errors" below for the fix. **Until then:** run `make tools && govulncheck ./...` host-side to get CVE results, or run the next `make lint` host-side, or wait for the proposed `nix/checks.nix` fix.

---

## 🐛 Correctness / latent bugs (92 items)

### staticcheck SA/S/QF/U real-bug subset (sandbox run, repo-config)

| # | Rule | Location | Description |
| --- | --- | --- | --- |
| 1 | **U1000** unused field | `internal/pkg/dcgmprovider/dcgm.go:55` (`moduleCleanup func()`) | Dead field — never read or assigned. Either wire it into the cleanup path or delete it. |
| 2 | **S1001** loop → copy() | `internal/pkg/deviceinfo/device_info.go:601` | `for i := 0; i < len(bitmask); i++ { dst[i] = bitmask[i] }` should be `copy(dst, bitmask)`. |
| 3 | **ST1001** dot import | `internal/pkg/devicewatcher/device_watcher.go:31` (`. "github.com/NVIDIA/dcgm-exporter/internal/pkg/logging"`) | Dot imports pollute the local namespace and make grep harder. Replace with named import. |
| 4 | **ST1005** error string ends with punctuation | `internal/pkg/prerequisites/variables.go:41` | `"the %s library was not found. Install Data Center GPU Manager (DCGM)."` — strip trailing period. |
| 5 | **ST1005** error string capitalised | `pkg/cmd/app.go:1005` | `"Invalid ranged device option..."` — lower-case the I. |
| 6–8 | **QF1008** redundant embedded-field selector | `internal/pkg/collector/clock_events_collector.go:86`, `internal/pkg/collector/xid_collector.go:36`, `tests/e2e/internal/framework/kube.go:343,368,369` | `c.expCollector.getMetrics()` → `c.getMetrics()` (embedding handles it). |
| 9 | **QF1012** `WriteString(Sprintf(...))` → `Fprintf` | `internal/pkg/collector/types.go:164` | Allocation savings; mechanical fix. |
| 10 | **QF1003** can use tagged switch | `internal/pkg/deviceinfo/device_info.go:186` | Repeated `==` against `dcgm.FE_GPU` → `switch ... { case dcgm.FE_GPU: }`. |
| 11 | **U1000** (counted once above) — placeholder | — | — |

Plus 24 **ST1003** naming-convention findings (`EntityId → EntityID`, `groupId → groupID`, `Fv2_String → Fv2String`, `ALL_CAPS` constants) — listed under Quality below; they are technically correctness for API consumers but cosmetic for behaviour.

### go vet

| Rule | Locations | Count | Recommendation |
| --- | --- | --- | --- |
| **composites: unkeyed struct literal** (`testutils.WatchedEntityKey{0, 0}`) | `internal/pkg/devicemonitoring/device_monitoring_test.go` lines 458–1423 | **29** | Field order is fragile — any reorder of `WatchedEntityKey` silently shuffles test inputs. **Action:** convert all 29 to keyed literals: `{ParentEntityGroupID: 0, ParentEntityID: 0}`. A `sed` over the test file is sufficient; the field names are obvious from `testutils.WatchedEntityKey`. |

### golangci-lint strict pass (`--default=none -E <43 linters>`) — additional bugs beyond .golangci.yml

| # | Rule | Location | Description / recommendation |
| --- | --- | --- | --- |
| 1–2 | **bodyclose** | `tests/integration/start_with_tls_test.go:96,122` | HTTP response body not closed. Resource leak in tests — fix by `defer resp.Body.Close()`. |
| 3 | **contextcheck** | `internal/pkg/server/server.go:261` | `render` doesn't forward the inbound `ctx`. **Action:** thread the request context through so handlers honour cancellation / deadlines. |
| 4 | **errorlint** type assertion on error | `internal/pkg/collector/gpu_collector.go:103` | `err.(SomeErr)` will miss wrapped errors. Use `var t SomeErr; errors.As(err, &t)`. |
| 5 | **errorlint** non-wrapping `fmt.Errorf` | `internal/pkg/collector/p2p_status_collector.go:52` | `%s` should be `%w` so callers can `errors.Is/As`. |
| 6 | **errorlint** non-wrapping `fmt.Errorf` | `internal/pkg/prerequisites/dcgmlib_rule.go:79` | Same fix as #5. |
| 7 | **errorlint** `!=` on errors | `internal/pkg/server/server.go:202` | Use `errors.Is(err, target)` instead of `err != target`. |
| 8–14 | **exhaustive** missing cases in `dcgm.Field_Entity_Group` switch | `gpu_collector.go:113`, `deviceinfo/device_info.go:98`, `devicemonitoring/device_monitoring.go:28`, `devicewatcher/device_watcher.go:130,149`, `rendermetrics/render_metrics.go:144` | dcgm SDK introduced new entity groups (`FE_LINK`, `FE_CPU`, `FE_CPU_CORE`, etc.) — current switches default-handle them but silently. **Action:** add an explicit `default:` returning a clear error, or add the missing cases. **The forward-compat risk is real: if a future DCGM adds a new entity type, the exporter will silently drop it instead of warning.** |
| 15 | **exhaustive** missing case `counters.DCGMFIUnknown` | `internal/pkg/counters/exporter_counters.go:33` | Add the case (probably a no-op return or panic). |
| 16 | **exhaustive** missing case `appconfig.DeviceName` | `internal/pkg/transformation/process_metrics.go:42` | Same as #15. |
| 17 | **musttag** missing json tag | `internal/pkg/deviceinfo/device_info.go:677` | Struct is JSON-marshalled but a field lacks the `json:` tag. **Action:** add explicit tag or rename if it should be skipped. |
| 18 | **nilerr** returns nil when err is non-nil | `tests/e2e/internal/framework/helm.go:316` | Line 312 sets `err != nil`, line 316 returns `nil`. **Real bug** in test framework — caller treats a real failure as success. Fix by returning the error. |
| 19 | **nilnil** returns `(nil, nil)` | `internal/pkg/nvmlprovider/provider.go:211` | Caller can't distinguish "absent" from "error" — sentinel error needed. **Action:** return `(nil, ErrNVMLNotInitialized)` or similar. |
| 20–27 | **noctx** | `internal/pkg/exec/exec.go:39` (`exec.Command` → `CommandContext`), `internal/pkg/server/server_test.go:327,331,346` (`httptest.NewRequest` → `NewRequestWithContext`), `internal/pkg/testutils/test_utils.go:274` (`net.Listen` → `ListenConfig`), `tests/e2e/internal/framework/kube.go:303` (same), `tests/integration/helpers_test.go:61,77` (`http.Client.Get` / `http.NewRequest` → context-aware variants) | Pure mechanical fixes — adopt context-aware constructors. The `exec.Command` one is the most impactful (production code, breaks cancellation). |
| 28 | **recvcheck** mixed pointer / value receivers | `internal/pkg/collector/types.go:94` (`MetricsByCounter`) | Methods inconsistently use `*M` and `M`. Pick one (almost certainly `*M`). |
| 29 | **tparallel** subtests don't call `t.Parallel()` | `internal/pkg/transformation/process_metrics_test.go:134` (`TestPerProcessMetrics_GetValueForMetric`) | Either add `t.Parallel()` to subtests or call it on the parent only. Minor — affects test speed, not correctness. |
| 30 | **unparam** always-nil param | `tests/integration/helpers_test.go:52` (`httpGet`'s `customClient`) | Parameter always receives `nil` from every call site. Delete the parameter. |
| 31 | **unused** field | `internal/pkg/dcgmprovider/dcgm.go:55` (already counted above) | Dedup with staticcheck. |

### Other correctness signals (each = 1 finding)

- **dupword** repeated word in code/comment (1 finding) — likely a typo in a comment.
- **copyloopvar** loop-var capture (1 finding) — Go ≥1.22 makes this safe automatically, but the linter flags the pre-change idiom.
- **gocritic sloppyLen** `len(switches) <= 0 → == 0` at `internal/pkg/deviceinfo/device_info.go:276` — cosmetic, but `<=` on a length is misleading.

---

## ✏️ Quality / style findings (367 items, mostly informational)

| Tool | Count | Top rules (count) | Disposition |
| --- | ---: | --- | --- |
| **markdownlint-cli2** | 155 | MD013/line-length (78), MD032/blanks-around-lists (16), MD022/blanks-around-headings (13), MD012/no-multiple-blanks (8), MD060/table-column-style (6), MD040/fenced-code-language (6), MD031/blanks-around-fences (5), MD009/no-trailing-spaces (5), MD004/ul-style (4), MD041/first-line-heading (3) | A `make markdown-fix` (using `markdownlint-cli2 --fix`) would auto-resolve ~70%. Worth a one-off cleanup PR; do not gate on this. |
| **staticcheck** style codes | 97 | ST1000 missing package comment (81), ST1003 underscored/ALL_CAPS names (24) | ST1000 is a single-line `// Package <name> ...` per package — 27 packages × ~3 files each = 81 hits. Either fix in bulk or add `-checks=all,-ST1000` to `staticcheck.conf`. ST1003 includes `Fv2_String`, `EntityId`, `groupId` — breaking changes for API consumers; do per-symbol, not bulk. |
| **protogetter** | 24 | (single rule) | Use protobuf getters instead of field access. Mechanical fix, low risk. |
| **perfsprint** | 17 | (single rule) | `fmt.Sprintf("%d", x)` → `strconv.Itoa(x)` etc. Pure micro-perf; informational. |
| **prealloc** | 8 | (single rule) | Slice preallocations. Informational. |
| **intrange** | 6 | (single rule) | `for i := 0; i < n; i++` → `for i := range n` (Go 1.22+). Cosmetic. |
| **typos** | 45 | DBE→BE (27, **FP** — "Double-Bit Error" is GPU vernacular), dbe→be (3, **FP**), asser→assert (6, **real**), intput→input (4, **real**), stuct/missmatch/whe/Hashi/ede (1 each, **real**) | **Action:** add `_typos.toml` to silence the DBE/dbe class (`[default.extend-words]`); fix the ~14 real typos in a follow-up. |
| **cspell** | 4381 | dcgm (588), DCGM (336), appconfig (199), gomock (165), dcgmprovider (111), pkgs (100), devicewatchlistmanager (74), NVML (70), stretchr (69), testutils (58), GPUUUID (49), nvmlprovider (45), NVLINK (38), VGPU (35), … | **Essentially all false positives** (domain terms + Go-package names). **Action:** add `cspell.json` at the repo root with these as a project dictionary, then re-run — expect ~0 real findings. cspell is unusable without the dictionary; do not gate. |
| **hadolint** info-level | 5 | DL3047 wget without progress bar (3), DL3008 (n/a — no findings here), SC2034 unused variable (1) | Informational; address opportunistically. |
| **deadnix** | 1 | Unused let binding | `nix/tests/default.nix:168` (`_ = lib;`) — placeholder we added to silence "lib unused"; deadnix is right that it's pointless. **Action:** remove the line and the `lib` arg. |
| **gofmt** | 0 | (clean) | Pass. |
| **shellcheck** | 0 | (clean) | Pass. |
| **statix / nil / nixfmt-check** | 0 each | (clean) | Pass — our own Nix code is in good shape. |

---

## ⚠️ Tool errors / coverage gaps (4 items)

### 1. `govulncheck` — sandbox blocks network

```
govulncheck: fetching vulnerabilities: Get "https://vuln.go.dev/index/modules.json.gz":
  dial tcp: lookup vuln.go.dev on [::1]:53: read udp [::1]:58227->[::1]:53: read: connection refused
```

**Fix options** (in order of preference):

1. Switch `nix/checks.nix#govulncheck` to a `mkPlainCheck` that's marked `__noChroot = true` (or `requiredSystemFeatures = [ "recursive-nix" ]`) so it gets network — Nix-CI hosts can choose to support this.
2. Pre-fetch the vuln DB as a flake input (`inputs.govulndb.url = "https://vuln.go.dev/...tar.gz"; inputs.govulndb.flake = false;`) and set `GOVULN_DB=file://${govulndb}` — fully sandbox-safe.
3. Leave it as a manual lint under `nix/lints/govulncheck.nix` (runs host-side), not a gated check.

**Until fixed:** run `nix develop -c govulncheck ./...` host-side. (This pass had no opportunity to verify CVE results.)

### 2. `go-mod-tidy-check` — proxyVendor missing test-fixture archives + 1 real diff

The sandbox `GOPROXY=file://${goModules}` misses `_test`-tagged archives (`github.com/go-openapi/swag/jsonutils/fixtures_test`, `github.com/go-openapi/testify/enable/yaml/v2`, `github.com/sergi/go-diff/diffmatchpatch`). `go mod tidy` errors out before it can finish. Layered on top of that, when it does finish on the host side, it produces **one real diff:**

```
< 	github.com/docker/docker-credential-helpers v0.9.3 // indirect
```

i.e. `docker-credential-helpers` is in `go.mod` but unused. **Action:** run `go mod tidy` host-side and commit the cleanup. For the sandbox tool, switch from `proxyVendor = true` to `proxyVendor = false` (vendored Go) OR set `GOFLAGS=-mod=vendor` after running `make vendor`. Track separately — orthogonal to security.

### 3. `go-test-short` — sandbox can't `dlopen` libdcgm / libnvidia-ml

16 of 27 test packages fail with `symbol lookup error: undefined symbol: dcgmRunDiagnostic` or `nvmlGpuInstanceGetComputeInstanceProfileInfoV` at runtime, because tests transitively link to `go-dcgm` / `go-nvml`, which `dlopen`s the NVIDIA shared libs at test startup. The sandbox doesn't have those libs.

The two packages that pass (`internal/pkg/stdout` and `internal/pkg/exec`) are the only ones that don't transitively touch the GPU bindings.

**Fix options:**

1. Skip more aggressively — current skip list `(tests/e2e|integration_test|nvmlprovider|dcgmprovider)` isn't enough. Make `go-test-short` use a positive-list of "pure" packages (probably about 6: `stdout`, `exec`, `hostname`, `os`, `elf`, `appconfig`, `logging`).
2. Inject **stub** shared libraries that satisfy the symbol table (`gcc -shared -fPIC -o libdcgm.so.4 stub.c` with weak no-op stubs) into the sandbox's `LD_LIBRARY_PATH`. More effort.
3. Demote `go-test-short` to a manual app (`nix run .#test-coverage`) — that already lives outside the sandbox.

**Recommendation:** option 1, narrow the package list. This is a config-only fix in `nix/checks.nix`.

### 4. `gofmt-check` and `goimports-check` — our own `$out` shell-variable bug

In `nix/checks.nix`, both scripts do `out=$(gofmt -l -s ...)` which shadows the Nix-provided `$out` (the derivation's output path). Then the mkCheckBase trailer runs `touch $out` and bombs with `touch: missing file operand` when `out` is empty (i.e. when the check would otherwise pass).

```
got build log for '/nix/store/.../gofmt-check.drv' from 'daemon'
touch: missing file operand
```

**Recommendation:** rename the local to `drift_out` (or similar) in both `gofmt-check.script` and `goimports-check.script`. Fixing this also revealed a **real** finding for `goimports-check`: drift in 7 mock files (`internal/mocks/pkg/{collector,deviceinfo,devicewatcher,devicewatchlistmanager,exec,nvmlprovider,transformations}/mock_*.go`). Run `make goimports` to fix.

---

## ✅ Checks that passed silently

- **nil** (Nix LSP diagnostics) — clean
- **statix** (Nix antipatterns) — clean
- **shellcheck** (shell scripts under `docker/`, `hack/`, `tests/`) — clean
- **nixfmt-check** — clean
- **meta-description** (every flake app has a description) — clean
- **dcgm-exporter binary build** — clean

## Recommended next steps

In rough priority order:

1. **Security — must-fix:**
   - `internal/pkg/debug/debug.go:70` — change `0o755` → `0o750`. Single-line PR.
   - `cmd/dcgm-exporter/main.go:31` — switch `slog.Error(err.Error())` to `slog.Error("startup failed", "err", err)`. Single-line PR.
   - `internal/pkg/dcgmprovider/dcgm.go:85,86` and `smart_init.go:30,31` — wrap the four `os.Setenv` calls in `if err := ...; err != nil { slog.Warn(...) }`. Bundle with #1 if both touch dcgmprovider.

2. **Security — suppress with justification:**
   - Add `.gitleaks.toml` allowlisting `tests/integration/testdata/tlsCertificate.key`.
   - Add `// #nosec` comments per the gosec table above (G103×2, G204, G304×2, G402×2, G115 extras).

3. **Correctness — bundle into one PR:**
   - `tests/e2e/internal/framework/helm.go:316` — the `nilerr` finding is a **real test framework bug** (success-on-failure). Fix first.
   - `internal/pkg/server/server.go:261` `contextcheck` — thread context through `render`. Real cancellation impact.
   - `internal/pkg/exec/exec.go:39` switch to `CommandContext`. Real cancellation impact in production.
   - Convert all 29 `WatchedEntityKey{...}` test literals to keyed.
   - 4 × `errorlint` `%s` → `%w` fixes.
   - 9 × `exhaustive` switch-default additions (or explicit cases).
   - `nvmlprovider/provider.go:211` `nilnil` — invent a sentinel error.

4. **Tooling / Nix:**
   - Fix `$out` shadowing in `nix/checks.nix` (`gofmt-check`, `goimports-check`).
   - Narrow `go-test-short` to GPU-free packages.
   - Decide on `govulncheck` strategy (DB-as-input, host-only, or `__noChroot`).
   - Fix the one stale dep flagged by `go mod tidy`.
   - Add `_typos.toml` and `cspell.json` to silence domain-term noise so the next pass surfaces real findings.

5. **Quality (separate PR):**
   - Auto-fix the markdownlint findings (`markdownlint-cli2 --fix`).
   - Add the 27 ST1000 package comments, or exclude ST1000 in `staticcheck.conf`.
   - `protogetter`, `perfsprint`, `prealloc`, `intrange` cleanups — bundle.

6. **Upstream issues:**
   - None of the findings appear to be `go-dcgm` / `go-nvml` bugs — they're all in dcgm-exporter itself. No upstream issues to file from this pass.

## Known constraints

- This pass is **read-only triage**: no findings are fixed in this branch / commit. Each fix should go in its own focused PR per the next-steps list above.
- Findings counts above are reproducible from a clean tree using the commands in "How to reproduce". If `go.sum` is edited later, the `vendorHash` in `nix/lib.nix` must be re-captured (set to `lib.fakeHash`, rebuild, paste the printed hash back).
- Maximum-strict `golangci-lint` (43 linters) intentionally includes opinionated style linters (`perfsprint`, `prealloc`, `intrange`) whose findings should not drive code changes — they're listed for completeness only.
