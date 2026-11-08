# P1-M21: Catalog benchmark record

Status: Active

Record the baseline, frozen acceptance budgets and subsequent prototype comparison for Tasks 10–14. Measurements below cover synthetic local files; production retention and the full device/provider matrix remain open. The [overview](milestone-21-architecture-gui-enhancement-overview.md#task-10-persistent-sqlite-catalog-foundation) owns completion.

## Baseline, 2026-11-04

Source: `6f62fd1` plus the optional aggregate diagnostics and opt-in benchmark harness. SHA-256 over the catalog/lifecycle sources (`AssetCatalog`, `CatalogAssetRegistry`, `FileCatalogWorker`, `DiaryCatalogHandler`, `CatalogAudioInspector`, `CatalogModel`, `AppModel`): `e1719203d4c268508258b1b71246d3d0a646d00b140ac957310371253f253cb3`. No SQLite prototype code was present during these measurements.

`CatalogBenchmarkTests` exercises fresh file workers and `CatalogModelBenchmarkTests` includes the existing presentation scheduling between discovery slices. Use Release with `ENABLE_TESTABILITY=YES`, code coverage off, test parallelism off and `NDM_CATALOG_BENCHMARK=1` in the test-runner environment. Testability is needed by the existing `@testable` suite; optimization remains Release. Each corpus/count has five repetitions; report median and maximum, with no percentile claim. Worker samples check `P_TRACED` through `sysctl`; all 40 final phone worker samples report no debugger attached.

Fixtures are deterministic: metadata files contain `Synthetic` under `notes/<number>.note`, with numeric timestamps and IDs. Current-schema diaries use sequential UUIDs, the same `2026-01-02T03:04:05Z` instant, a synthetic body and copied 100 ms AAC silence. Fixture creation precedes timing and owned test-directory cleanup follows it. A fresh worker/model is created for each repetition in the same process with locally present files; these are **not process-cold launch or evicted-provider measurements**. First-batch timing ends when the worker returns or the model exposes at least 10 rows (all available rows for smaller fixtures). The old implementation can return 50 rows in that batch.

### Target iPhone

Device `iPhone18,2`, iOS 27.0.1; `NarihitosDiary` project/scheme. All four selected tests passed, zero failed/skipped. System SQLite module/link access succeeds without a package or project dependency change; the phone reports SQLite 3.54.0.

| Corpus | Entries | Samples | Median first batch, ms | Maximum, ms | Rows in batch |
|---|---:|---:|---:|---:|---:|
| Metadata worker | 0 | 5 | 8.213 | 189.133 | 0 |
| Metadata worker | 10 | 5 | 84.157 | 101.565 | 10 |
| Metadata worker | 11 | 5 | 14.754 | 74.191 | 11 |
| Metadata worker | 100 | 5 | 33.705 | 40.712 | 50 |
| Metadata worker | 1,000 | 5 | 260.800 | 271.183 | 50 |
| Metadata worker | 10,000 | 5 | 2,191.858 | 2,373.840 | 50 |
| Metadata model | 100 | 5 | 131.055 | 136.868 | 50 |
| Metadata model | 1,000 | 5 | 1,008.631 | 1,037.381 | 50 |
| Metadata model | 10,000 | 5 | 9,886.496 | 9,995.631 | 50 |
| 100 ms AAC diaries | 10 | 5 | 133.320 | 137.317 | 10 |
| 100 ms AAC diaries | 100 | 5 | 741.721 | 744.825 | 50 |

The 10,000-entry fixture visits 10,005 enumeration entries before the first rows and validates 50 candidates. The 100-diary first batch validates 50 diaries, hashes 2,868,600 audio bytes and reads 56,400 Markdown bytes. The model result includes its 30 ms yields between progress-only slices. These observations support removing the startup discovery barrier and oversized first batch; they do not attribute all app launch delay to the catalog.

Artifacts retained locally: `test_device_2026-11-04T09-45-26-054Z_pid27471_76693e1b.xcresult` and `test_device_2026-11-04T09-45-26-053Z_pid27471_2bf5e763.log`. The earlier attempt waited on a locked phone, then ended with two unfinished test runners and one passed test. Its samples are excluded; the cause of those early exits is unestablished. The successful rerun began after the owner unlocked the phone.

### Simulator

iPhone 18 Pro / iOS 27.0, Release with the same test settings. The three worker/preflight tests passed (40 samples); a second focused run passed the model benchmark plus nine existing file-worker/diary-handler regressions (15 model samples). Median/maximum milliseconds: metadata worker 10,000 = 588.310/660.441; metadata model 10,000 = 7,623.045/7,955.553; AAC 10 = 74.279/123.019; AAC 100 = 395.720/416.578. These are simulator measurements, not iPhone or provider substitutes.

Artifacts: `test_sim_2026-11-04T09-39-56-852Z_pid17401_61bfbbbb.xcresult`, `test_sim_2026-11-04T09-44-14-834Z_pid17401_708281e2.xcresult`.

## Frozen prototype budgets

Frozen after the baseline and before SQLite prototype implementation, 2026-11-04. These are acceptance limits, not measured prototype results. Changes require a dated reason before rerunning a comparison; do not loosen limits to fit results. Reuse the same fixtures and five repetitions, reporting every timeout/failure and median/maximum; additional device/provider states use the same count. No p95 is inferred from five samples.

| Area | Required limit |
|---|---|
| Warm remembered Main, up to 10,000 stored resources | First remembered 10 including scope/barrier/open/query admission: median ≤ 500 ms, maximum ≤ 1,000 ms. Zero historical body/audio reads may gate that remembered page. Current and remembered freshness guarantees remain distinct in reports. |
| SQLite query, same corpus | Query a bounded 10-row keyset page: median ≤ 25 ms, maximum ≤ 50 ms; indexed query plan and no temporary full-result sort or offset paging. |
| Fresh/cold page, action, next page and empty/rebuilt cache | Median and maximum ≤ 1.20 × the corresponding baseline plus 50 ms on comparable available local fixtures. Record a matching action/next-page baseline before comparing those paths. No provider wait is subtracted from end-to-end results. |
| Correctness and work | Exact settled strict-oracle equivalence; ≤ 50 combined discovery/classification candidate visits per request, separately bounded enumeration and nested sibling slices, one unsettled provider accessor, no-scroll demand stops at 10, and every entry stays reachable. |
| UI and other use cases | No catalog SQL/open/rebuild or moved blocking I/O on the main actor. Main-thread blocking interval ≤ 50 ms in traces. Recording/transcription/save/edit/replay/delete latency regressions ≤ 20% plus 50 ms against matching baseline runs; no starvation or lost automatic progress. |
| Memory | Incremental catalog footprint ≤ 64 MiB at 10,000 resources; SQLite page cache ≤ 4 MiB; transient inspection proofs ≤ 16 MiB and 512 entries, evicted before metadata. This bounds the projection, not the number of browsable diaries. |
| Disk | Normal database family ≤ 64 MiB and combined old/new/rebuild/journal artifacts ≤ 128 MiB. Exceeding a safe bound disables/rebuilds only the disposable projection; no diary eviction. Short transaction batches ≤ 50 resource updates. |
| Contention and hints | SQLite busy timeout ≤ 250 ms; coalesced hint queue ≤ 256 entries, overflow dirties the scope for metadata reconciliation. No provider await or decode inside an SQL transaction. |
| Reconciliation | Active-session metadata sweep interval 30 s, ≤ 50 enumeration visits per slice, retry backoff 1/2/5/15/30 s. Quiescent local 10,000-resource metadata coverage converges within 30 s from sweep admission; no eager historical audio decode. Protection/provider waits remain typed and suspend this available-source deadline. |
| Rebuild/fallback | At most one corruption/incompatible-schema reset per activation. Access/permission/full-disk errors remain retryable. Fallback preserves file operations, scope/privacy and fresh actions; pre-purge epochs cannot be served on restart. |

## Foundation verification, 2026-11-04

All 11 `SQLiteCatalogIndexTests`/`CatalogSQLiteRecoveryTests` pass in Release on the same target phone, zero failed/skipped, using the real Complete Protection policy. They exercise differential Swift/SQL ordering, indexed keysets, session/revision fencing, nonunique claims, missing scope metadata, retryable summary retention, protected-access refusal, safe-path rejection, busy/full rollback, atomic metadata registration and reopening a stable database/journal image captured after uncommitted page spill. The last case exercises SQLite hot-journal recovery without claiming physical process-loss evidence. Database and journal backup exclusion/protection are verified before sensitive writes.

Artifact: `test_device_2026-11-04T10-13-57-338Z_pid40894_0248d091.xcresult`. A preceding seven-test run waited on a locked phone and exited before establishing its test connection; no physical pass is claimed for that attempt. The current full simulator generation/lint/build/test gate also passes on iPhone 18 Pro / iOS 27.0. Main is still on the strict file catalog; no remembered-first performance comparison is available yet.

Documentation validation at the foundation checkpoint resolves 448 local links/fragments across the affected plans, architecture and UX records, including incoming M21 links, with zero errors. `git diff --check` passes. Task 10 remains partially complete; subsequent implementation and full acceptance remain tracked below and in the overview.

## Reconciliation and maintenance progress, 2026-11-04

The unwired indexed adapter now implements current-scope admission, remembered-first query, ordered bounded discovery, strict demanded-content inspection, resumable legacy siblings, scan coverage/checked-absence retirement, metadata sweeps, retries, coalesced hints and serialized provider access. Schema v2 adds scan presence and global invalidation revisions; it resets the disposable v1 prototype rather than migrating authoritative data. No decoded body/audio or reusable inspection-proof cache is retained. One in-progress sibling cursor and the current returned action proof remain transient; resource metadata, current summaries and live version observations are measured separately in Task 14. Pending provider admission is capped at 256, user work has priority after actual settlement, and internal reset/memory teardown preserve source files.

The existing purge journal now retains a completed cache generation. Both purge scopes reject old cached epochs even when cache removal is deliberately omitted in tests. Existing purge confirmations, interrupted-source recovery and source allowlists remain in force. Main still uses the strict file catalog; no integrated first-frame or remembered-row performance win is claimed.

Release simulator evidence: 21 controller/worker/legacy/SQLite checks pass in `test_sim_2026-11-04T11-24-20-177Z_pid17401_18b02c44.xcresult`; 26 purge/controller/race checks pass in `test_sim_2026-11-04T11-33-09-531Z_pid17401_2042555a.xcresult`; 20 subsequent reset/reopen, hint, access-priority/bounds and worker checks pass in `test_sim_2026-11-04T11-37-15-657Z_pid17401_ff673436.xcresult`. These runs overlap and are not additive sample counts. A prior build caught a missing explicit actor-isolation annotation in a new test; it ran no tests and was corrected before the passing runs. The subsequent full required generation/lint/build/test gate passes on iPhone 18 Pro / iOS 27.0, including metadata-only recovery fairness after visible demand is satisfied. The current documentation check resolves 450 local links/fragments with zero errors; `git diff --check` passes. No v2/controller/purge physical-device acceptance is claimed by the earlier v1 phone evidence.

## Evidence still required

- [ ] Prototype versus baseline results and final strict-oracle/adversarial matrix.
- [ ] Real process-cold launch, first frame, warm app return, relaunch, lock/unlock and empty/rebuilt store measurements.
- [ ] Real-iCloud locally present, evicted and offline cases, long legacy audio, multi-day and recovery/duplicate corpora.
- [ ] Matched first-action/next-page/edit-reopen baselines, main-thread traces, peak memory and database/sidecar/rebuild growth.
- [ ] Activation/recovery/model-verification attribution with empty/pending/completed history and zero/one/both installed variants; production settings/models were not inventoried by the synthetic catalog tests.
- [ ] Physical accessibility, recording/transcription contention and mutation/save/recovery responsiveness.
- [ ] Owner production-retention decision after comparison; earlier milestones' phone/provider evidence remains open.
