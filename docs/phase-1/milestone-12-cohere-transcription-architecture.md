# P1-M12: Cohere transcription approach

Status: Planned

This plan connects one app-approved Cohere GGUF installation and the bundled `transcribe.cpp` Metal runtime to the existing queue and protected result handoff. It defines fail-closed installation, long-audio seam handling, production provenance, and evidence boundaries without claiming that the integration has been built or tested.

## Boundaries and interface fit

| Area | Owns | Must not own |
|---|---|---|
| Domain/Application | Stable method ID, typed readiness/outcomes, attempt snapshot, required provenance shape, result bounds, candidate-before-transition rule | URLs, file paths, native handles, `URLSession`, Metal, GGUF parsing |
| Model manager adapter | Trusted descriptor, capacity preflight, download/redirect policy, verification, installed identity, atomic replacement, leases, backup exclusion | Queue ordering, method selection, audio or diary access |
| Cohere inference adapter | Verified audio/model leases, conversion, chunk plan, native sessions, Metal/backend attestation, seam assembly, cancellation acknowledgment | Queue persistence, SwiftUI, destination access, remote inference |
| Private candidate store | Method-specific provenance validation, bounded atomic candidate, attempt/source/revision binding, recovery inventory | Model download, title/body semantics, iCloud publication |
| Presentation | Explicit install/select intents, bounded progress, accessible sanitized readiness | Durable authority, raw native/network errors, automatic selection |

Reuse the final M11 verified audio source, queue fences, candidate publication, and launch reconciliation where their contracts are method-neutral. The current M11 candidate already carries runtime, conversion, source digest, locale, OS, attempt, model-identity, and effective-settings fields, but its method-specific validator is Apple-only. M12 must add a known Cohere method identifier and a closed required provenance schema rather than treating any non-Apple record as valid. Preserve old verified Apple candidates and reject unknown methods or missing Cohere fields; version or migrate the private record only if compatibility tests prove reopen behavior.

The queue never receives a model URL or path. A Cohere request carries the job/attempt identity, original `en-US` or `ko-KR` hint, current settings revision, selected method, and descriptor/installation identity captured by a generation-fenced preclaim. M13 receives the same bounded managed-body candidate as Apple, not another transcript sidecar. It serializes only the approved Diary Snippet provenance fields, while richer internal digest and build evidence remains in the private candidate/descriptor rather than inventing front-matter keys.

## Approved artifact baseline and provenance

The selected runtime baseline is `transcribe.cpp` v0.2.4 at commit `4807eda`; the release's `TranscribeCpp.xcframework.zip` is 8,399,649 bytes with SHA-256 `243e96ea569583245c9732de3955111210d986c03a34b81424dacde169f9de6a`. The selected model baseline is `handy-computer/cohere-transcribe-03-2026-gguf` revision `7353b6040bdc1be9e5a3823d99d5fe12afe88264`, file `cohere-transcribe-03-2026-Q4_K_M.gguf`, 1,558,162,944 bytes, SHA-256 `0ea56826d8bd5d74b7143a4a04e022dc1bb75452cfae49d98b6acb0c1d16a1fb`. Reverify all values during the separately approved dependency integration. If the selected bytes, notices, compatible iOS/Metal slice, or necessary immutable distribution values are unavailable, stop and report the blocker.

Keep two related but distinct trust records:

- Build provenance binds runtime ID/version/commit, source and exact versioned release URL, XCFramework archive byte count/digest, included architectures, app build revision, and bundled MIT/third-party notices. Native runtime code ships inside the signed app and is never downloaded by the model installer.
- The signed-app-bundled model descriptor binds descriptor schema/revision, stable model ID, quantization, repository and immutable revision, exact filename/URL, exact bytes, SHA-256, approved languages, allowed HTTPS redirect hosts, runtime compatibility range or exact identity, conversion/chunking revision, and Apache-2.0 `LICENSE`/`NOTICE` references. The descriptor is covered by app code signing; no checksum fetched beside the GGUF grants trust.

The installed identity is derived from the descriptor revision and verified artifact digest, not a path, filename, HTTP ETag, mutable repository branch, or server-reported length. Candidate provenance must identify the effective model ID plus immutable version/revision, `transcribe.cpp` runtime identity, conversion/chunking identity, original language hint, effective `en`/`ko`, settings revision, and OS/app build context needed for reconciliation. Empty, `unknown`, or inconsistent required values fail before candidate publication.

## Installation, replacement, and readiness

The model manager has no audio, transcript, diary, or destination capability. Its state is derived from the bundled descriptor, one confined installation record, the installed regular file, and any bounded staging operation; a persisted `ready` Boolean is never authority.

1. On refresh, validate the bundled descriptor and current app approval. Resolve only app-owned constant components, reject links/aliases/unexpected files, and verify the installed file's identity, exact size, digest when new/changed, backup exclusion, and compatibility record. A revoked or descriptor-mismatched installation is not ready even if its file remains present.
2. Installation begins only from explicit user intent. Show 1,558,162,944 bytes in localized units backed by the exact byte value. Before traffic, conservatively calculate peak required capacity for the full staging file, atomic publication, any prior verified copy that must survive, and bounded scratch/metadata; require available capacity to satisfy that calculation and to be at least the approved 1 GiB. Unknown or insufficient capacity fails without changing readiness.
3. Use an ephemeral, noncredentialed HTTPS session and the immutable descriptor URL. Evaluate every redirect before following it, allow at most three, require every hop and final URL to use HTTPS and an explicitly listed host, and never log URLs or query strings. Stream to an exclusively created confined file with an exact byte ceiling; reject early EOF, extra bytes, a declared length that conflicts with the descriptor, content-range inconsistencies, or unsupported content encoding. A missing length header is not trust evidence and is safe only when the transfer remains bounded and the final byte count and digest match. The selected production artifact is a raw GGUF: do not extract or execute downloaded content.
4. Close and synchronize the staged file, then verify it as a plain regular file with the exact length and SHA-256. Validate bounded GGUF identity/metadata and runtime compatibility without accepting values that conflict with the descriptor. Apply and recheck backup exclusion on staging, final publication, and replacements.
5. Atomically publish an immutable versioned installation on the same volume, reopen and reverify it, then commit the small active-installation record. Only a fresh post-publication refresh may report ready. A crash at any step leaves either the former verified install active or no ready install; it never creates a partially ready state.
6. Coalesce repeated taps behind one installation generation. A newer descriptor/app activation invalidates stale presentation callbacks. Leaving Settings may detach progress but does not fabricate success. Relaunch removes only positively identified abandoned staging files and reconciles publication before accepting another install.

The model file and download scratch are redownloadable, backup-excluded app-owned data. Do not delete or replace an installed version while an inference lease holds its exact identity. An app update may approve or revoke a descriptor, but never silently uses a formerly installed unapproved artifact or automatically downloads a replacement. Preserve an older still-approved verified install until a replacement is fully verified; if the current app revokes it, mark it not ready and perform only lease-aware confined cleanup. M12 adds no user-facing uninstall action without separate product direction.

Readiness refreshes at Settings entry, app activation, installation settlement, descriptor/app revision change, and immediately before claim. Async refresh and install results are generation-fenced against lifecycle, descriptor, selected method, and queue revision. Missing, corrupt, revoked, incompatible, protected-data-inaccessible, or contended state is typed and sanitized. A missing or invalid approved installation projects `Cohere model isn’t installed.` with Install Model/Choose Method. Installation completion never selects Cohere, selection persists globally as M11 defines, and a waiting Cohere job does not prevent another ready job from being considered.

## Conversion and chunk plan

Open M9 audio only through the finalized M11 source-validation and read-lease boundary. Stream conversion to 16 kHz mono Float32 with explicit source format, end-of-input, converter draining, bounded buffers, checked arithmetic, and a no-progress guard. Account for every emitted frame and bound the converted duration to the approved recording maximum. Cancellation closes converter/scratch resources without treating protected-data unavailability as missing input.

Represent chunking as a versioned plan created before native inference:

- Primary spans are ordered, nonempty half-open sample intervals whose union is the full converted interval and whose intersections are empty. This ledger proves no sample was silently skipped or assigned twice.
- Prefer a versioned bounded search for a low-energy boundary before each primary hard limit. Thresholds, search window, minimum chunk, padding, and tie-breaking are constants in the conversion/chunking identity and have unit fixtures; do not adapt them from transcript content.
- Every actual runtime input, including context overlap, is at most 45 seconds. Silence cuts may use disjoint runtime windows. When a no-silence hard cut could split speech, bounded audio context may overlap adjacent primary spans, but the plan records the overlap and keeps primary ownership unambiguous.
- Because this Cohere runtime exposes no word timestamps, overlapping text must use a deterministic, Unicode-preserving seam rule with a unique exact alignment under its documented normalization. Do not use fuzzy similarity or delete a repeated word merely because adjacent chunks resemble each other. If an overlap has no unique safe alignment, or a fixture shows a lost/duplicated word, fail the attempt and keep the audio rather than guessing.
- Joining nonoverlapping silence cuts still needs deterministic whitespace and punctuation handling for English and Korean. Preserve original chunk Unicode, normalize only the seam representation needed by the versioned rule, and enforce the 1 MiB UTF-8 bound incrementally.

The fixture matrix covers zero/very short audio, exact and just-over boundaries, tail fragments, long silence, low-volume speech, no-silence speech across hard cuts, punctuation and Hangul near cuts, repeated phrases at seams, ambiguous overlap, converter stalls, and near-five-minute primary coverage. Silence-only chunks may return no text without failing an otherwise usable recording, but all-silence/noise input must not become a successful invented diary. The final combined text is trimmed only at its outer boundary and must contain a Unicode alphanumeric scalar.

## Metal inference and complete-output contract

Map only `en-US` to `en` and `ko-KR` to `ko`; absence or any unsupported hint is not language detection. Acquire one verified installation lease and one verified audio lease for the attempt. Select an enumerated Metal device explicitly through the v0.2.4 API and capture a bounded typed backend attestation. An unavailable or rejected Metal device fails the attempt; automatic device selection or CPU fallback is not acceptable evidence.

Load the leased model under the selected Metal device and keep shared immutable model state only if the runtime contract and tests prove it safe. Each chunk gets an independent session or a proven complete reset so abort/truncation/text state cannot bleed into the next chunk. For every attempted chunk require the native return status to be success, `was_aborted == false`, `was_truncated == false`, the selected backend to remain Metal, and the session to settle. Do not treat those flags alone as long-input completeness evidence: the 45-second policy and reference seam matrix remain required because upstream issue [`transcribe.cpp` #128](https://github.com/handy-computer/transcribe.cpp/issues/128) demonstrates successful but incomplete longer Cohere output.

An empty successful silence chunk may contribute no text. Any runtime error, abort, truncation, backend mismatch, unattempted/duplicate chunk, unsafe seam, missing provenance, oversized aggregate, or unusable final aggregate fails with audio retained and no partial candidate. Model loading, conversion, and inference have no network or diary-destination collaborator. Diagnostics allow only operation, typed code, duration/sample/chunk counts, elapsed/resource classes, backend class, and opaque identifiers—never audio, text, URLs, paths, digests, native logs, or raw errors.

## Queue handoff, cancellation, and recovery

Preclaim readiness snapshots the exact descriptor/installed identity, then the queue persists the claim, attempt ID/generation, current settings revision, method, model identity, conversion/chunking identity, destination revision, and body revision before work starts. The adapter binds the result to a digest of the actual opened confined audio bytes. The candidate store validates Cohere's closed required provenance set, atomically publishes and reopens the candidate, rechecks current claim/source/revisions, and only then allows `resultReady`. Candidate or queue-store failure follows M11: pause durable progress rather than report recognition failure or rerun while the process remains alive.

Cancellation is one idempotent structured teardown path for user removal, deadline, lifecycle invalidation, and tests:

1. Invalidate the durable attempt generation/barrier so no new callback can publish.
2. Stop scheduling chunks, cancel conversion/download-independent scratch work, and set the native abort signal for any model load or active session that supports it.
3. Await conversion, every native call/callback/session, seam work, and candidate publication attempt; discard uncommitted text and positively identified attempt scratch.
4. Close the audio and exact model leases, then send one terminal acknowledgment meaning the adapter has relinquished all work.

The ten-minute cutoff and confirmed removal use this path. If native model load or inference does not settle, the worker remains occupied and the condition is a blocker; it is never permission to start a second native attempt. App inactivity starts no new work. Relaunch reconciliation first handles removal tombstones/quarantine, then applies the M11 candidate matrix: a fully verified current candidate may promote an interrupted claim; an absent interrupted candidate fails with audio retained; protected data defers; invalid/stale candidates isolate only that job; removed/quarantined work is never adopted.

## Verification sequence

1. Obtain dependency approval. Reverify the immutable runtime/model artifacts, exact hashes/bytes, allowed redirect chain, iOS/Metal slices, licenses/notices, and security posture. Record the chosen integration mechanism without changing the approved runtime direction.
2. Inspect the completed M11 interfaces. Add the Cohere method and a closed method-specific candidate/provenance validator with Apple regression tests before native inference is registered.
3. Implement the model manager behind fake capacity, network, filesystem, descriptor, hashing, lifecycle, and lease ports. Inject failures at each download/verification/publication record boundary and every concurrent install/inference ordering.
4. Implement streaming conversion and the versioned chunk plan independently of the native runtime. Prove primary coverage and seam behavior with English/Korean reference fixtures, including explicit ambiguous-seam failure.
5. Integrate the bundled runtime and Metal adapter behind a thin native seam. Test status/abort/truncation/backend mappings, session isolation, provenance, timeout/removal acknowledgment, late callbacks, and absence of network capability.
6. Run affected tests while iterating, then the full lint and simulator validation gate once. Record failures and unavailable prerequisites without checking them off.
7. Run M12-D01–M12-D08 on the target iPhone using synthetic references. Keep audio, transcript, raw logs, paths, account data, URLs, and identifiers out of Git. Record app/runtime/model revisions, device/iOS/Xcode versions, fixture duration classes, observation method, pass/fail, timing, peak-memory method/value class, thermal state, and cancellation settlement time in the [redacted evidence record](milestone-12-cohere-transcription-device-evidence.md).

## Target-iPhone evidence

| ID | Required observable evidence | Status |
|---|---|---|
| M12-D01 | Fresh install shows the exact pinned size, satisfies the calculated peak-space need and minimum 1 GiB preflight, follows only the approved redirect chain, verifies the pinned bytes/digest, excludes the final file from backup, relaunches ready, and does not select Cohere automatically. | Not run |
| M12-D02 | Interruptions at download/verify/publication, insufficient space, corrupt/extra bytes, concurrent taps, app relaunch, and app-manifest revocation remain not ready or preserve the prior approved verified install; an active inference lease prevents replacement/cleanup. | Not run |
| M12-D03 | Short production-format English and Korean recordings transcribe in airplane mode with explicit hints, actual Metal selection, successful nontruncated chunk status, usable bounded text, and a verified candidate whose provenance matches the runtime/model/install identity. | Not run |
| M12-D04 | Near-five-minute English reference input covers beginning, middle, end, every silence seam, speech across a hard boundary, and a repeated phrase near overlap. Private reference checks find no missing or duplicated sentinel; completion is within the ten-minute cutoff without jetsam. | Not run |
| M12-D05 | Repeat the near-five-minute completeness and hard-seam matrix for Korean, including Hangul/spacing/punctuation boundaries and ambiguous alignment rejection. Record timing, peak memory, and thermal state without transcript text. | Not run |
| M12-D06 | Cancellation during conversion, model load, and active early/late chunk inference, plus a shortened deadline through the production path, acknowledges complete settlement before another ready job starts. Removal and late callbacks cannot publish; record settlement times. | Not run |
| M12-D07 | Background/relaunch, installation contention, damaged/revoked model, unavailable Metal, protected-data unavailability, all-silence/noise, and queue/candidate-store failure produce truthful recovery without CPU/method fallback, false diary creation, or audio loss; unrelated ready work advances after settlement. | Not run |
| M12-D08 | Controlled observation separates installation traffic from inference. Offline inference works and no audio/text is sent for inference or telemetry; diagnostics, accessibility, progress, license notices, and app-switcher privacy expose no private content, raw errors, URLs, paths, or digests. | Not run |

M12 establishes integrity, completeness, cancellation, and resource viability only for the tested production path and fixtures. It does not establish general WER/CER, subjective diary quality, comparative method ranking, energy impact, or all-condition thermal behavior; P1-M19 retains the complete-experience evidence.
