# P1-M11: Apple on-device transcription device evidence

Status: Active

This record captures redacted target-iPhone evidence for Apple Speech readiness, system-asset installation, English/Korean prerecorded transcription, cancellation, and local-only behavior. It contains no recording, transcript, path, Apple account data, raw error, or locale-reservation identifier.

## Required environment

- Target: iPhone 17 Pro Max running iOS 27.0.1 or later.
- App revision: record commit or working-tree identifier without embedding signing/account data.
- Xcode/SDK revision: record public version/build only.
- Fixtures: synthetic English and Korean short clips plus near-five-minute clips in the production M9 mono AAC `.m4a` shape. Keep fixture audio and expected text outside Git if they contain a real voice.
- Network controls: normal network for installation; airplane mode for offline inference; a controlled observation path for distinguishing installation traffic from later inference.
- Evidence fields: typed state, locale category, duration class, elapsed time, peak-memory/thermal observation, cancellation settlement time, and pass/fail. Do not paste output text or raw logs.

## Environment record

| Field | Redacted value |
|---|---|
| Device model | Not recorded |
| iOS version/build | Not recorded |
| App revision | Not recorded |
| Xcode/SDK | Not recorded |
| `maximumReservedLocales` capacity class | Not recorded |
| English fixture durations | Not recorded |
| Korean fixture durations | Not recorded |
| Network observation method | Not recorded |
| Download-size source and units / storage preflight method | Not recorded |

## Scenario results

| ID | Scenario and observable pass condition | Result | Evidence note |
|---|---|---|---|
| M11-D01 | Fresh launch reports live `SpeechTranscriber` device support and resolves the approved English and Korean hints independently. Unsupported or transient states remain not ready and no legacy speech authorization prompt appears. | Not run | — |
| M11-D02 | Record reservation capacity, reserve both resolved locales without releasing another locale, and relaunch. Both reservations/readiness states are truthful; capacity below two is reported as a blocker. | Not run | — |
| M11-D03 | From an absent/not-installed English asset, Download Model shows a documented size and passes the approved free-space preflight before installation, shows bounded progress, settles, and a fresh status becomes ready. Airplane mode before completion cannot fabricate readiness. | Not run | — |
| M11-D04 | Repeat installation/readiness for Korean. Switching Settings/lifecycle during installation cannot let a stale callback overwrite the final state. | Not run | — |
| M11-D05 | With assets installed and airplane mode enabled, a short production-shape English `.m4a` yields bounded usable final text, stages one candidate, and reaches `resultReady` with the expected method/locale/runtime/conversion provenance. | Not run | — |
| M11-D06 | Repeat offline short transcription for Korean, including Hangul acceptance and no volatile-result duplication. | Not run | — |
| M11-D07 | Near-five-minute English and Korean production-shape files each finish through end of input within the ten-minute limit. Record elapsed time, peak memory, and thermal state; verify expected beginning/middle/end sentinel phrases without recording them here. | Not run | — |
| M11-D08 | Cancel an active attempt and exercise a shortened test deadline through the production teardown path. Analyzer/input/result work and audio access acknowledge relinquishment before the next synthetic ready job starts; late output creates no candidate. | Not run | — |
| M11-D09 | Relaunch after claim, during analysis, after candidate write, and after `resultReady`. Reconciliation produces no duplicate attempt/text, preserves audio, and accepts only a verified current-generation candidate. | Not run | — |
| M11-D10 | Separate installation from inference network observation. Installed-model inference succeeds in airplane mode; with observation enabled, no app audio or transcript leaves for inference/telemetry. Diagnostics, accessibility, and app-switcher snapshots disclose no content or raw platform state. | Not run | — |

## Evidence rules

- Mark Pass only from an observed target-phone run satisfying every clause in that row. A simulator or mocked status cannot substitute.
- A model already installed by another app is valid readiness evidence but does not prove this app's download-progress flow. Use a controllable absent-asset state when the system permits it; otherwise record the installation scenario as blocked.
- A failed or cancelled app-side installation attempt does not prove the system stopped its own later download retries; record subsequent live status separately.
- `downloading` means not ready until a fresh module-status check reports installed. An installation request returning nil also requires a fresh ready check.
- For M11-D07, record only whether private expected start/middle/end sentinels were present. This is a completeness smoke test, not WER/CER or a transcript artifact.
- For M11-D08, using an injected shorter deadline is acceptable only if it reaches the same adapter cancellation and acknowledgment implementation as the production ten-minute cutoff. Record the injected duration, not content.
- Network evidence distinguishes Apple system-asset download endpoints from inference after installation. Do not claim that airplane mode alone proves the absence of every telemetry path; pair it with the controlled observation when available.

## Current blockers

- The M11 implementation is in progress; no M11 target-phone run has been recorded.
- The installed iOS 27.2 Speech interface exposes progress but no explicit pre-download byte count or required-space estimate. Verify any public documented alternative on device; if unavailable, the approved size disclosure and storage preflight remain blocked pending owner direction.
- System asset removal may not be controllable on the target device. If a clean English or Korean download cannot be induced safely, record M11-D03 or M11-D04 as blocked rather than treating an already-installed asset as download-flow proof.
- The reservation capacity and actual English/Korean support remain runtime facts until measured on the target iPhone/OS revision.
