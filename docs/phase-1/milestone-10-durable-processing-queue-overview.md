# P1-M10: Durable processing queue overview

Status: Done (owner decision; human device tests pending)

Adopt P1-M9's settled capture receipts into one durable, foreground-only processing queue. Prove ordering, crash recovery, restored-work quarantine, bounded attempt ownership, and per-job failure isolation with injected methods before production transcription adapters arrive.

## Entry condition

- Follow [Phase 1 order](phase-1.md): implementation starts after P1-M9 is Done or the owner explicitly authorizes a reorder. Planning M10 does not close P1-M8's provider evidence or P1-M9's target-phone capture evidence.
- Use the approved [queue lifecycle](../architecture.md#processing-and-queue-lifecycle), [P1-M5 recording and privacy contract](milestone-05-decisions-architecture.md#recording-queue-and-privacy-contract), [product behavior](../product-behavior.md), and [UX terms](../ux-terms.md). M9 supplies the immutable capture identity, verified audio, independent destination snapshot, and receipt.
- No dependency or build-tool change is planned. Ask the owner before one is needed or before a device finding would change an approved outcome.

## Scope

- Add an inward-owned, versioned queue record and repository that adopt each valid M9 pending receipt exactly once by its stable recording ID, without copying its only audio or changing start time, language, measured audio metadata, or destination reference. Capture failures and unresolved orphans stay reviewable and never become ready work.
- Create a random Keychain installation identity with `ThisDeviceOnly` accessibility. Bind new capture markers and receipts to it before audio starts and carry that binding into queue records without a Keychain read during locked settlement. Quarantine unbound legacy receipts and jobs with a missing or different binding; require a user-initiated Resume or confirmed Remove before transcription or iCloud mutation. Distinguish a temporarily unavailable Keychain from a missing installation identity: pause without reclassifying jobs until identity can be checked. Resume uses a new attempt and current Settings.
- Register approved transcription methods through descriptors and adapters. Resolve the selected method and effective settings immediately before each claim, refresh readiness on Settings entry, app activation, and claim, and persist the method, model/conversion identity, settings snapshot, and attempt generation before inference. A missing, unknown, or unready method waits with a sanitized reason; never switch methods automatically. Manual retry uses current Settings without a fixed retry count.
- Schedule the oldest ready recording by persisted recording start/order, using stable ID to break ties, while the app is active. Keep one transcription attempt at a time. A waiting, failed, destination-blocked, malformed, or cancelling job does not prevent another ready recording from being selected, except while an adapter still owns the single inference worker. Stop claiming work when the app leaves the active state; in-flight work settles or is reconciled after relaunch. Recheck waiting prerequisites on relevant readiness and Settings changes without creating a retry loop for failed attempts.
- Apply a ten-minute hard cutoff to nonsettling local inference. Invalidate the attempt at timeout or cancellation, retain its audio and an entry-level reason, and advance only after the adapter has relinquished underlying work. Late callbacks cannot change a newer attempt, removed job, destination revision, or body revision.
- Persist transitions atomically and reconcile each job independently against its receipt and private files on launch. Quarantine malformed, unsafe, or restored records without deleting audio. Distinguish temporarily inaccessible protected data from missing or corrupt data. A queue-wide durable-write failure pauses claims and reports paused local work; it never presents a fabricated success or loops on the failed job.
- Define the per-job mutation barrier and durable removal tombstone consumed by later save work. Confirmed removal invalidates in-flight work, shows Cancelling until it relinquishes access, and cleans only positively identified app-owned files. If a complete asset won the barrier and was verified before confirmation, preserve it and report completion. M10 implements the core contract and a minimal recovery route; P1-M17 owns the full Pending/Failed screens and actions.
- Expose method-neutral queue projections for Pending/Failed state and future Main notices. Keep production processing idle until M11/M12 register ready adapters; synthetic adapters exercise scheduling and result handoff without claiming that a diary or iCloud asset was created.

## Out of scope

- Apple Speech readiness, download, conversion, and transcription belong to P1-M11; Cohere installation, pinned model provenance, chunking, runtime cancellation, and transcription belong to P1-M12. Their device tests must prove the adapter-specific cancellation contract.
- Managed diary draft and title creation belong to P1-M13. Coordinated iCloud pair publication, upload proof, save recovery, and destination replacement belong to P1-M14/P1-M17. M10 provides state and barriers for these stages but does not mark a recording completed without their verified artifacts.
- Full recovery screens, collection notices, optional context, and pending-work reminders belong to P1-M15/P1-M17/P1-M18. No hosted Qwen controls, network retries, background inference, or automatic method fallback are introduced.

## Completion checklist

- [ ] Review existing-job installation checks and durable removal ordering; add regression evidence for any fixes.
- [ ] A bounded, versioned queue record and confined repository adopt one verified M9 receipt once; tests cover duplicate callback/relaunch, receipt replacement, active-folder change, immutable capture fields, backup exclusion, protection attributes, and audio remaining in place.
- [ ] Installation identity is stored in Keychain with `ThisDeviceOnly` accessibility and bound to new capture markers and receipts before audio starts. Unbound M9-era receipts and jobs with a different or absent binding are quarantined before any method or destination call. Tests distinguish mismatch, absent identity, temporarily inaccessible Keychain, locked settlement without Keychain access, duplicate launch, Resume with current Settings, and confirmed removal. Redacted device evidence records an actual backup/restore outcome and exercises quarantine with a controlled prior-install fixture if excluded work does not appear in the restored backup.
- [ ] Method registry and synthetic second/third registrations prove selected-method routing, language and audio compatibility, readiness refresh at all three approved points and after a prerequisite changes state, durable effective-settings/model/conversion snapshot, no silent fallback, unknown-method recovery, and fresh unlimited manual retries without overlapping attempts.
- [x] Deterministic three-job tests show a waiting oldest job, a failed or timed-out next job, and a ready newest job: the newest is claimed, earlier audio and reasons remain, and no failed job spins. App-inactive state starts no new attempt.
- [x] Deadline, cancellation, and late-result tests show a ten-minute cutoff, invalidated attempt generation, retained audio, and no next claim until the adapter acknowledges relinquishment. M11/M12 retain physical runtime proof of this contract.
- [ ] Crash-point tests cover every durable transition and file dependency, including adoption, claim before adapter start, wait, failure, retry, cancellation, and removal. Reopening is idempotent; protected-data unavailability is deferred; malformed or unsafe records are isolated; a queue-store write failure pauses all claims without false progress or deletion.
- [ ] Per-job barrier tests cover removal before publication, completion verified before confirmation, removal during an unverified write, a stalled adapter/file operation, crash during tombstone cleanup, and stale attempt/destination/body revisions. Cleanup touches only positively identified files; Cancelling lasts until work relinquishes access and cleanup is durable.
- [x] Pending/Failed projections and minimal recovery navigation show truthful, sanitized state and reasons, including restored-work review and paused local work. No UI claims production transcription, diary creation, or iCloud save before their adapters exist; diagnostics and accessibility contain no private audio, text, destination, bookmark, or model output.
- [ ] Source inspection confirms Domain/Application do not import SwiftUI, AVFoundation, Security, provider URLs, or concrete persistence. A fake additional asset kind and transcription method exercise the extension boundary without changing Diary Snippet queue rules.
- [x] Affected docs record the M11–M14, M17, M18, and M19 handoffs; no dependency or build tool changed without approval.
- [x] `swift-format lint --strict --recursive .` passes.
- [x] `swiftlint lint --strict` passes.
- [ ] The generated project builds and all tests pass through `scripts/validate.sh` on an available iPhone simulator after the review fixes.

## Acceptance evidence

The owner marked implementation done except human tests on 2026-11-02. This status does not imply that unchecked evidence has been obtained: the post-review simulator gate and the remaining composite checklist items are still unverified.

Check an item only with focused tests, source or attribute inspection, a successful validation command, or a redacted physical-device observation. Simulator Keychain and injected restore outcomes do not prove real backup/restore behavior. Record what an actual device restore does with backup-excluded work; a controlled prior-install fixture on device can separately establish the quarantine path when the restore contains no pending work. Missing device access or a required command leaves its item unchecked and is reported as a blocker.

Implementation began by owner request on 2026-11-02 while the earlier physical-device gates remain open. Automated evidence currently lives in `ProcessingQueueTests`, `CapturePolicyTests`, and `CapturePrivateFilesTests`; the full gate passed on the iPhone 18 Pro iOS 27.0 simulator. The redacted physical restore record is tracked in the [M10 device evidence log](milestone-10-durable-processing-queue-device-evidence.md). Composite checklist items remain unchecked until every clause has evidence.

The review fixes require a fresh simulator test run; the current environment could not start CoreSimulatorService.
