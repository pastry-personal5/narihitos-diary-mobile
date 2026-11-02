# P1-M11: Apple on-device transcription approach

Status: Active

Adapt Apple's system-managed SpeechAnalyzer stack behind the method-neutral M10 queue contracts. Keep readiness and asset installation separate from inference, and durably stage a bounded result before handing the job to M13.

## Platform basis

The installed Xcode 27.2 SDK exposes `SpeechTranscriber.isAvailable`, asynchronous supported/installed locale lookup, `AssetInventory` status and locale reservations, `AssetInstallationRequest.downloadAndInstall()`, prerecorded-file analysis, explicit analyzer finalization, and `cancelAndFinishNow()`. Use those installed names (`reserve`/`release` and preset `.transcription`) rather than copying older beta/sample spellings.

Apple documents `SpeechTranscriber` as the general-purpose on-device transcriber and distinguishes supported locales from installed locales. [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory) manages system assets, reservations, installation requests, and status; its maximum reservations can vary by device storage. Apple's [SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/) shows file analysis, concurrent result consumption, finalization, and system-model download. Apple's [authorization guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) states that SpeechAnalyzer transcriber modules do not send voice audio to Apple servers; M11 therefore does not introduce the legacy server-recognizer authorization path.

These API statements do not prove that `en-US` and `ko-KR` are installed, downloadable, compatible with the app's AAC files, or performant on the target phone. The device matrix supplies that evidence.

## Boundaries

| Area | Owns | Excludes |
|---|---|---|
| Domain/Application | Stable method ID, supported app language hints, typed readiness/install projections, attempt snapshot, normalized result, staging-before-transition rule, cancellation acknowledgment | `Locale`, Speech/AVFoundation, file URLs, `Progress`, raw Apple errors |
| Apple readiness/installer adapter | Equivalent-locale resolution, device/asset status, reservations, installation request, progress, sanitized failure mapping | Queue ordering, method switching, result staging |
| Apple inference adapter | Verified audio lease, SpeechTranscriber/SpeechAnalyzer lifecycle, finalized result collection, normalization, provenance, teardown | Queue persistence, SwiftUI, destination access, title generation |
| Private result store | Bounded atomic candidate, protection/backup attributes, attempt/source binding, recovery inventory | Title/body semantics, iCloud publication, arbitrary cleanup paths |
| Presentation | Method selection, per-language status, progress, Download Model/Choose Method actions | Durable authority, locale guessing, raw platform state |

`TranscriptionRequest` continues to carry job and attempt identity, language hint, settings snapshot, and revision fences. It does not carry a URL. The Apple adapter receives an adapter-owned audio-source collaborator that resolves the fixed M9 file from the validated job ID, rechecks the receipt/audio identity, and holds a scoped read lease until inference or cancellation has fully relinquished it.

Replace string-only success with a bounded `TranscriptionPayload` containing normalized text and typed effective provenance. The coordinator writes that payload through an inward-owned result-store port and verifies it before persisting `resultReady`. The queue JSON stores only state and bounded provenance references, never transcript text. If candidate persistence fails, pause local work under the existing queue-store rule; do not report a failed recognition or automatically rerun inference while the process remains alive. Text that never reached durable storage cannot be recovered after process death; retain the audio and reconcile as an interrupted attempt, without claiming the text survived.

## Readiness and selection

Use one typed snapshot per approved language:

1. Map the app hint to `Locale(identifier: "en-US")` or `Locale(identifier: "ko-KR")` in the Apple adapter.
2. If `SpeechTranscriber.isAvailable` is false, project unavailable hardware.
3. Ask `supportedLocale(equivalentTo:)`. A nil result is unsupported; a nonnil locale is the only locale used to configure the module and the effective snapshot.
4. Create `SpeechTranscriber(locale:preset:.transcription)` and ask `AssetInventory.status(forModules:)`. Map `installed` to ready, `supported` to downloadable, `downloading` to downloading/not ready, and `unsupported` to unsupported. Cross-check installed locale state only as platform evidence; do not treat a cached set as stronger than current module status.
5. Generation-fence every async refresh. A Settings dismissal, app lifecycle change, completed install, or newer refresh invalidates an older result before it reaches UI or releases a waiting job.

An async preclaim refresh must not reserve the inference worker indefinitely or let a late response claim a stale job: serialize scheduler decisions, fence each response to the current app activation, job, selection and queue revision, then recheck oldest-ready ordering and worker availability before persisting the claim. Waiting jobs must not prevent checking later jobs; a readiness change schedules another pass without spinning on transient failures.

The settings repository persists the last explicitly selected stable method ID globally, not a separate choice per language or a readiness Boolean. Adapt M10’s language-parameterized settings port and migrate any existing persisted selection without silently choosing a method. A recovery choice must be ready for the affected recording language when selected; recheck at claim because readiness can change. With no prior choice, the queue waits and the user explicitly selects Apple in Settings or the future Choose Method flow. A selected Apple method remains selected when one language is not ready; that job waits, while jobs using a ready language may proceed. Never rewrite selection because readiness changes.

Installation is a user intent for one language. Resolve the locale again, reserve it, construct the module, request the installation, observe its `Progress` through a bounded presentation projection, await download/install, and refresh. A nil request is not automatically success: recheck module status. Multiple taps coalesce behind one language-specific install generation. Leaving Settings may detach presentation but cannot turn an uncertain system operation into success. Raw errors map to typed transient/capacity/unsupported outcomes. Apple documents that the system may retry a failed download later; do not equate the return or cancellation of this app’s task with cancellation of system work. Refresh on activation and relevant status changes, and only report installed after a fresh status check. Request creation may itself reserve locales, so it is performed only as part of the user-initiated installation flow, after the user requests installation.

The owner approved progress-only Apple system-asset installation. The installed Speech API exposes progress but no documented pre-download byte count or required-space estimate. Do not label `Progress.totalUnitCount` as bytes. Cohere retains its separate pinned-size and storage-preflight contract.

Do not automatically call `release(reservedLocale:)`. Releasing English to install Korean or the reverse would change future readiness without an approved policy. M11-D02 records `maximumReservedLocales` only as a numeric capacity class and proves whether both v1 locales can be retained on the target device. A capacity below two is an implementation blocker requiring owner direction, not permission to evict.

## File inference and result normalization

The first production path uses Apple's prerecorded-file convenience over `AVAudioFile`, matching Apple's file-transcription example. Open only after the M9 receipt and current file have passed containment, regular-file, byte, duration, codec/channel, playability, and protection checks. Record conversion identifier `ndm.apple-speech.av-audio-file-v1`; if target evidence proves this path cannot accept the approved `.m4a`, stop and revise the plan/provenance before adding an alternate converter.

For each attempt:

1. Preclaim refresh must still be ready for the request's language. Snapshot requested/resolved locale, settings revision `1`, `.transcription` preset, final-results-only policy, runtime `apple-speech-analyzer`, conversion identifier, and OS version. Apple model ID/version remain absent unless a public API exposes them.
2. Open and hold the verified audio lease. Create a new transcriber and analyzer for this attempt; do not share analyzer state or result sequences between jobs.
3. Start consuming `transcriber.results` before or concurrently with file analysis so backpressure cannot drop results. The preset does not request volatile results; nonetheless accept only results whose `isFinal` is true.
4. Call `analyzeSequence(from:)`. If it returns a last sample time, finalize through that time; if it has no input, cancel/finish and classify the output as unusable. Await the result sequence's normal completion.
5. Append final segments in delivery order. Strip attributes, not Unicode characters; use a documented, deterministic boundary rule that respects existing whitespace and punctuation, with English and Korean fixtures demonstrating that segment joins neither merge words nor introduce duplicate spaces; preserve each segment’s internal Unicode text. Enforce the UTF-8 byte bound incrementally.
6. Trim outer whitespace/newlines for the candidate. Require at least one Unicode alphanumeric scalar so English letters/digits and Korean Hangul are accepted while punctuation/control-only output is rejected. Do not language-correct, summarize, spell-check, or infer a different language.
7. Return the bounded payload. The coordinator atomically stages and reopens it, verifies all attempt/revision/source bindings again, transitions to `resultReady`, then releases the worker.

The result candidate schema contains a version, job ID, attempt UUID/generation, source audio byte count, duration, and a cryptographic digest of the verified audio bytes, recording language hint, method ID, requested/resolved locale, settings revision, runtime/conversion IDs, OS version, and UTF-8 text. It is confined to the job workspace, nonpurgeable, backup-excluded, and protected like an unsaved draft. It cannot nominate a path. On reopen, an invalid, stale, linked, oversized, or mismatched candidate is isolated without deleting audio or blocking unrelated jobs.

Bind the digest to the actual opened, confined regular file, not only its pathname or receipt metadata. Before accepting a candidate on reopen, recompute and compare the digest from a newly verified audio lease; size and duration alone cannot detect same-size substitution. Verify the file identity around opening and reading so a path swap cannot change the bytes being analyzed or validated. Digest mismatch isolates that job and retains the audio for review. Do not log the digest or treat it as proof of authenticity against an attacker able to rewrite both private records.

### Candidate commit and recovery

Persist the claim, attempt ID, generation, and revision fences before starting inference. After the adapter has relinquished inference, serialize candidate publication and queue mutation with removal/retry through the per-job barrier. Validate the current durable claim and source, write a protected temporary candidate, atomically publish it, reopen and verify it, then durably transition to `resultReady` while retaining the attempt identity needed for verification. Do not release the single worker until publication and transition settle. A store failure pauses claims; a removal or invalidation that wins the barrier prevents publication or removes only the identified uncommitted candidate.

On launch, first enforce installation quarantine and removal tombstones; never adopt a candidate from quarantined or removed work. Reconcile independently and idempotently:

| Durable state | Candidate | Recovery |
|---|---|---|
| `transcribing` with current claim | Fully verified, matching claim, fences and audio | Promote to `resultReady` without rerunning inference. |
| `transcribing` | Absent | Mark interrupted/failed with audio retained and manual retry. |
| `resultReady` | Fully verified and matching | Keep pending for M13 adoption. |
| `transcribing` or `resultReady` | Temporarily inaccessible protected data | Defer reconciliation until available; do not call it missing or start inference. |
| `transcribing` or `resultReady` | Invalid, stale, mismatched, unsafe, or absent for `resultReady` | Isolate the affected job with a sanitized recovery reason, preserve audio, and prevent adoption; other valid jobs continue. |
| No matching live claim, including invalidated/removing job | Any candidate | Never adopt; confine cleanup to positively identified app-owned candidate files after the relevant barrier. |

Test crashes before and after temporary write, atomic publication, verification, queue transition, and cleanup, including the failure of each durable operation and repeated relaunch. Test a restored candidate paired with quarantined work, same-size audio substitution, and cancellation racing publication. A successfully published candidate is recoverable; a crash before publication may require manual retranscription.

M13 must atomically adopt the exact candidate text as the initial managed body, bind the resulting draft to the same attempt/source provenance, and remove the intermediate after the draft is verified. Until then, `resultReady` remains pending local work. Retry invalidates and removes only a positively identified old candidate. Confirmed removal uses M10's tombstone/barrier and waits for Apple work and candidate access to relinquish before confined cleanup.

### Implementation handoffs

- M12 can register another method through the existing registry and asynchronous preflight contract; it must supply its own verified runtime, cancellation, and provenance. No readiness result changes the globally selected method automatically.
- M13 can call the candidate-store port's `readVerified` for a `resultReady` claim. The stored version-one record binds the exact text and effective provenance to the attempt, revisions, recording metadata, and source digest. M13 must create and verify the managed draft before discarding this intermediate; locked data must remain deferred.
- M17 must replace the minimal waiting-recording route with the complete ready-method and download recovery flow. Apple installation exposes progress and refreshes readiness after settlement.
- M19 must recheck full-experience privacy, scheduling, and adversarial behavior, including the target-device observations that simulator fakes cannot establish.

## Cancellation, lifecycle, and privacy

Wrap input, result collection, and analyzer lifetime in one attempt object. Its cancellation path is idempotent:

1. Mark the attempt cancelled locally so no new segment is accepted.
2. Cancel input/result tasks and call `SpeechAnalyzer.cancelAndFinishNow()` from structured async teardown.
3. Await both tasks and analyzer completion, discard any uncommitted text, remove attempt scratch, and close the verified audio lease.
4. Send exactly one terminal callback that explicitly means the adapter relinquished work.

Task cancellation alone is not acknowledgment. The M10 ten-minute timeout and confirmed Remove invalidate the durable generation before requesting teardown; the coordinator must not start the next inference until step 4. A callback after invalidation is ignored and cannot write a candidate. App inactive state starts no new attempt; an in-flight attempt follows M10's current settlement/reconciliation policy rather than being silently declared successful. Relaunch finds an interrupted transcribing state or a verified candidate and reconciles each independently.

Model installation traffic and inference traffic are observed separately. After assets are ready, short and five-minute fixtures must transcribe in airplane mode. A controlled network trace with networking available must show no app audio or transcript sent to an inference or telemetry endpoint; logs and evidence retain no content. Add a truthful `NSSpeechRecognitionUsageDescription` if the platform requires the key for Speech framework use, but never call the legacy authorization API or imply server recognition.

## Failure mapping

| Condition | Durable outcome | User action |
|---|---|---|
| Apple device/locale unsupported, asset absent/downloading, transient readiness failure | Pending/waiting with `Apple transcription isn’t ready for {language}.` | Download Model when actionable; Choose Method |
| Protected audio temporarily inaccessible | Pending/waiting; not missing | Retry on unlock/activation |
| Invalid/replaced/incompatible audio or decoder/analyzer/result failure | Failed with sanitized entry reason; audio retained | Retry/Remove |
| Empty or unusable result | Failed with `No usable diary text was found.` | Retry |
| Result exceeding the 1 MiB body limit | Failed with a sanitized entry reason; audio retained, no truncated candidate | Retry/Remove |
| Ten-minute cutoff | Failed with `Transcription stopped after 10 minutes.` with audio retained; worker remains occupied until teardown acknowledgment | Retry |
| Result-store durable write unavailable | Queue paused with approved local-storage message | Retry after storage recovers |
| Confirmed removal during Apple work | Cancelling until teardown and confined cleanup complete | None until settled |

Do not include raw `SFSpeechError`, `Locale` descriptions, result text, paths, reservation lists, or download endpoints in a reason or diagnostic. Allowlist typed operation, failure code, elapsed time, byte/duration class, and opaque correlation ID only.

## Verification sequence

1. Refine M10 ports for async readiness, explicit selection/install intents, payload/provenance, result staging, and relinquishment. Keep all existing synthetic method tests passing and add crash/fault tests before registering Apple.
2. Implement the Apple readiness/installer adapter behind fakes for module status, reservation, request/progress, and lifecycle generations. Add Settings projections and accessibility tests without requiring a real system download in unit tests.
3. Implement confined audio leasing, Apple inference, normalization, candidate persistence, and structured cancellation. Exercise synthetic AAC, corrupt input, result ordering, bounds, stale callbacks, timeout, removal, and relaunch.
4. Wire the production adapter and explicit selection. Run focused tests, then the full repository gate once. Do not check physical claims from simulator behavior.
5. Run M11-D01–M11-D10 on the target iPhone with synthetic fixtures. Record readiness/install capacity, short/five-minute English and Korean outcomes, latency/peak-memory/thermal observations, cancellation settlement, offline behavior, and sanitized network observations in the evidence record.

The physical trial does not need to establish WER/CER or compare Apple with Cohere; P1-M19 owns complete-experience evaluation. It must establish usable output, full-file settlement, model/input compatibility, local-only behavior, and bounded cancellation for both approved languages before M11 is Done.
