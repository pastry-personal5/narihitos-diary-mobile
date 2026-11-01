# P1-M1 decision inventory

Status: Closed for P1-M5

This inventory began as the evidence and question list from P1-M1. P1-M5 resolved every non-M6 owner decision; the authoritative implementation details are in the [approved P1-M5 contracts](../phase-1/milestone-05-decisions-architecture.md), while later milestones still owe the physical and adversarial evidence listed below.

## Resolved decisions

| Area | Owner outcome | Handoff |
|---|---|---|
| Title and diary text | One managed body; no retained transcript sidecar. Apple AI title when usable, otherwise first-sentence fallback. Count 30 Swift grapheme clusters. Use the approved prompt, chunk/pass/token/time/language limits and store available provenance. | P1-M13, P1-M16 |
| Asset schema | Random lowercase canonical UUID v4; RFC 3339 UTC whole seconds with `Z`; existing UTC path layout; exact strict flat-scalar fields, stable values, limits, optional groups, unknown-key preservation, unsupported recovery, and read-only legacy behavior. | P1-M7, P1-M15–P1-M17 |
| Recording and lock | Mono 44.1 kHz AAC `.m4a` around 64 kb/s. Continue while locked/backgrounded and finalize/queue immediately if capture ends locked. Playable crash/interruption partials queue; unreadable partials fail with audio retained. | P1-M9 |
| Backup and restore | Exclude pending audio and unsaved drafts from backup. Detect another-install restoration with a random `ThisDeviceOnly` Keychain ID; quarantine in Pending Recordings for Resume-current-Settings or Remove. | P1-M9, P1-M10, P1-M17 |
| Queue and reminders | Refresh readiness at approved points; prerequisites wait and attempts fail. Apply the ten-minute cutoff, exact sanitized reasons/actions, generic next-day reminder, DST/current-timezone recomputation, cancellation when work clears, and nonrepeating permission recovery. | P1-M10, P1-M11, P1-M18 |
| iCloud and conflicts | Positively verify iCloud Drive. Transient errors wait; user-confirmed removal/revocation permits per-job retargeting. Retain staging until local pair and two upload reports verify. Keep protected conflict pairs until the chosen pair is published and verified. | P1-M8, P1-M14, P1-M17 |
| Optional context | Context is recording start. Location: five minutes and 500 m; keep/display coordinates after geocoding failure. Weather: 60 minutes, Celsius storage, locale display, attribution, no late backfill. | P1-M18 |
| Privacy and hostile input | Neutral snapshot cover; generic notifications; diagnostics allowlist; inert Markdown; no biometric lock or app encryption; strict parser/audio/catalog/storage limits; ordinary readable finished assets and one-time folder disclosure. | P1-M7, P1-M15–P1-M19 |
| Model trust | App-bundled URL/version/length/digest approval; HTTPS; at most three allowlisted redirects; expanded-size and 1 GiB free-space preflight; app-update approval/revocation; no fixed installed-size cap. | P1-M12, P1-M19 |
| UI and accessibility | Six-second former-folder banner, approved semantic bitmap icon brief, exact playback/conflict/headings labels, polite notice behavior, unsupported/ambiguous recovery placement, and no word-linked replay. | P1-M15–P1-M18 |
| Dependency policy | Project-owned code remains Apache-2.0. Dependency license compatibility is not a gate; owner approval for dependency/build-tool changes remains required. | All implementation milestones |

## P1-M6 result

P1-M6 is Done. The owner selected the runtime-publisher `cohere-transcribe-03-2026-Q4_K_M.gguf` with `transcribe.cpp` and Metal as the P1-M12 implementation direction after short English/Korean runs on an iPhone 17 Pro Max. Q4 was faster and used less peak memory than Q5 on the observed clips; the English output matched, while the differing Korean outputs were not reference-scored. See the [sanitized results](../phase-1/milestone-06-cohere-runtime-trial-results.md).

The owner closed the unperformed five-minute, true-cold, cancellation, profiler, energy, and WER/CER work without claiming it as evidence. P1-M12 must pin trusted artifact/runtime provenance, use explicit language, reject incomplete output, use silence-aware chunks no longer than 45 seconds until long input is proven complete, and verify production seam and cancellation behavior. A different runtime, quantization, backend, or host requires a new owner decision.

Hosted Qwen, local Qwen ASR, whisper.cpp, and word alignment remain outside v1. Their research documents are retained as future evidence, not open P1-M5 decisions.

## Remaining evidence, not owner decisions

1. P1-M8 verifies arbitrary iCloud Drive folder selection/creation, provider identity, and bookmark behavior.
2. P1-M9 verifies locked/background capture, finalization, crash recovery, and Data Protection mechanics on a physical phone.
3. P1-M14 verifies coordinated pair writes, per-file upload observation, staging retention, conflicts, and cleanup.
4. P1-M17 verifies restored, unsupported, malformed, legacy-ambiguous, incomplete, and conflict recovery presentation.
5. P1-M19 executes the [security review matrix](../security-review.md#adversarial-verification-matrix).
