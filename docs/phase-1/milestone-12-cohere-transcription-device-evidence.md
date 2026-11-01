# P1-M12: Cohere transcription device evidence

Status: Planned

This record will capture redacted target-iPhone evidence for trusted Cohere model installation, local Metal transcription, bounded long-audio seams, cancellation, recovery, resource viability, and network/privacy behavior. It must contain no recording, transcript, path, request URL, digest, raw native log, account data, or stable device identifier.

## Required environment

- Target: iPhone 17 Pro Max running iOS 27.0.1 or later.
- App revision: record commit or working-tree identifier without signing/account data.
- Runtime: record public `transcribe.cpp` version/commit and whether the app build independently matched the approved archive digest; do not paste the digest into device logs.
- Model: record the approved stable model ID, immutable repository revision, Q4_K_M quantization, and whether installed bytes matched the trusted descriptor; do not record a downloaded path or digest in this file.
- Fixtures: synthetic English and Korean short clips plus near-five-minute production-shape mono AAC `.m4a` inputs with private expected start/middle/end and seam sentinels. Include silence-boundary, no-silence hard-boundary, repeated-phrase, ambiguous-seam, low-volume, silence-only, and noise cases. Keep audio, expected text, and transcripts outside Git.
- Network controls: normal network for installation, airplane mode for offline inference, and a controlled observation path that distinguishes installation traffic from later inference.
- Evidence fields: typed state, duration/chunk classes, backend class, elapsed time, peak-memory observation method/value class, thermal state, cancellation settlement time, and pass/fail. Do not paste output text or raw logs.

## Environment record

| Field | Redacted value |
|---|---|
| Device model | Not recorded |
| iOS version/build | Not recorded |
| App revision | Not recorded |
| Xcode/SDK | Not recorded |
| Runtime version/commit verified | Not recorded |
| Approved model revision/quantization verified | Not recorded |
| English fixture duration/chunk classes | Not recorded |
| Korean fixture duration/chunk classes | Not recorded |
| Network observation method | Not recorded |
| Peak-memory observation method | Not recorded |
| Capacity/preflight observation method | Not recorded |

## Scenario results

| ID | Scenario and observable pass condition | Result | Evidence note |
|---|---|---|---|
| M12-D01 | Fresh explicit installation shows the exact trusted size, satisfies the calculated peak-space need and minimum approved 1 GiB preflight, follows only approved HTTPS redirects, verifies and atomically publishes the selected model, excludes it from backup, relaunches ready, and leaves method selection unchanged. | Not run | — |
| M12-D02 | Interrupt download, verification, publication, and active-install record persistence; exercise low space, corrupt/extra bytes, concurrent taps, relaunch, descriptor revocation, and install-versus-inference contention. No invalid state becomes ready, a prior approved verified install survives replacement failure, and a leased model is not replaced or removed. | Not run | — |
| M12-D03 | In airplane mode, short production-shape English and Korean inputs use explicit `en`/`ko`, select an actual Metal device with no CPU fallback, settle successful/nontruncated chunk status, and create one verified bounded candidate with matching effective provenance. | Not run | — |
| M12-D04 | A near-five-minute English fixture completes within the ten-minute limit and covers private beginning/middle/end and every planned seam, including speech at a hard boundary and a repeated phrase in overlap, with no missing or duplicated expected sentinel. The app remains responsive and is not terminated for memory pressure. | Not run | — |
| M12-D05 | Repeat near-five-minute completeness for Korean, including Hangul/spacing/punctuation seams. A deliberately ambiguous overlap is rejected without a partial candidate. Record elapsed time, peak memory, and thermal state without content. | Not run | — |
| M12-D06 | Cancel during conversion, model load, and active early/late chunk inference; also use a shortened deadline through the production teardown path. Conversion, native sessions/callbacks, scratch, audio, and model leases acknowledge settlement before another ready job starts; late results and removal publish nothing. | Not run | — |
| M12-D07 | Background/relaunch, damaged/revoked model, unavailable Metal, protected-data unavailability, all-silence/noise, queue-store failure, and candidate-store failure retain audio and produce truthful isolated recovery without CPU/method fallback or a false diary. Other ready work advances after the adapter settles. | Not run | — |
| M12-D08 | Controlled network observation separates model installation from inference. Installed-model inference succeeds in airplane mode and sends no audio/text for inference or telemetry. Accessible progress/status, notices, diagnostics, and app-switcher privacy disclose no transcript, raw native/network error, URL, path, or digest. | Not run | — |

## Evidence rules

- Mark Pass only from an observed target-phone run satisfying every clause in that row. Simulator, fake backend, or the P1-M6 trial cannot substitute for the production path.
- M12-D01 must begin from no approved installation. M12-D02 may use controlled fault injection only when it reaches the same production filesystem, descriptor, lease, and settlement code.
- Actual Metal evidence needs a bounded runtime/backend attestation from the selected device path plus successful inference. Merely compiling Metal code, registering a Metal device, or observing a CPU device too is insufficient.
- Long-fixture completeness is a private sentinel/seam smoke test, not WER/CER. Record only presence/absence, seam outcome, chunk counts/classes, and timing/resource observations.
- The ambiguous-seam fixture must reach the production seam assembler and fail closed. It cannot be counted as pass by choosing a convenient expected transcript after observing output.
- A shortened test deadline is acceptable only when it reaches the same cancellation and acknowledgment path as the production ten-minute cutoff. Record the injected duration class, not content.
- Airplane mode establishes offline viability but not the absence of every telemetry path. Pair it with controlled network observation when available and distinguish approved installation traffic from inference.
- Memory and thermal observations are viability evidence for these runs, not universal performance or energy claims. Record the measurement method and whether the app remained responsive and free of jetsam.

## Current blockers

- M12 implementation has not started and the production runtime dependency/build integration still requires owner approval.
- P1-M11 is not Done, so its final method-selection, candidate, audio-source, and reconciliation interfaces are not yet a stable implementation entry.
- The exact production redirect chain/host allowlist and runtime iOS/Metal binary compatibility must be reverified during approved integration; planning metadata is not shipped evidence.
