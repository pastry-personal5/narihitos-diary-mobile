# P1-M13: Diary drafts and titles overview

Status: Done (owner decision; target-iPhone evidence pending)

Turn a verified Apple or Cohere transcription candidate into one protected, backup-excluded Diary Snippet Markdown draft. Generate its read-only title with the approved bounded on-device policy, retain the original recording and draft for M14 publication, and remove the intermediate transcription candidate only after the draft is verified.

## Entry and locked inputs

- The owner requested implementation ahead of P1-M12 completion on 2026-11-02. This does not close M8–M12 device evidence, M11's Apple-installation work, or M12's unchecked gates.
- Use the [P1-M5 title and schema contract](milestone-05-decisions-architecture.md), [M7 codec and workspace](milestone-07-asset-storage-architecture.md), [M10 queue](milestone-10-durable-processing-queue-architecture.md), and [M11/M12 candidate handoff](milestone-11-apple-on-device-transcription-architecture.md). A mechanism that changes an approved outcome remains an owner decision.
- Write the recording's explicit `en-US` or `ko-KR` hint into both front-matter `language` and `transcription_language_hint`. Title generation independently uses the body's current language, which may differ from that hint.
- M13 creates no iCloud files. M14 owns pair publication, upload verification, save retry, and final private staging deletion. M16 owns title regeneration after user body edits; M18 owns optional location and weather capture.

## Scope

- Add a method-neutral draft builder that accepts only a current, verified `resultReady` candidate. Bind the draft to job, attempt, source-audio digest, destination revision, body revision, and effective transcription provenance; reject stale, removed, quarantined, or mismatched work.
- Adopt the candidate text exactly as the initial managed `DiaryBody`, with no enduring original-transcript field or sidecar. Allocate a stable random asset ID before the first draft write and keep the job-to-asset mapping through M14 completion. Set `created_at` from recording start, freeze the initial `updated_at` when the managed draft is created, and set `favorite: false`; M14 must not advance `updated_at` for upload or synchronization alone.
- Use the M7 v1 codec and canonical UTC layout to make a complete, bounded Markdown draft with validated recording metadata, audio filename, language, title origin, and method-specific effective provenance. Keep the audio in its existing private workspace; a draft reference is not evidence that an iCloud audio pair exists.
- Prefer Apple's available on-device title model. Apply `title-v1` to the whole body in the body's current language with the approved token, chunk, pass, output, confidence, grapheme, and 30-second limits. Failure, unavailable model, uncertain or wrong language, incomplete body coverage, or unusable output takes the native first-sentence fallback. An empty body uses `Untitled` when later editing invokes the same policy; an unusable transcription still fails before M13.
- Publish the protected, backup-excluded draft and a bounded private binding record, reopen and verify both, then transition the queue to a draft-ready state. Reconcile crash orderings by inspecting a verified draft before treating a missing candidate as transcription failure. Discard only the identified intermediate after verified draft ownership is durable.
- Keep a draft ready for M14 even when its destination is temporarily unavailable. Queue/store or protected-data unavailability pauses or defers local work; title-model failure alone never blocks draft creation. Confirmed removal invalidates M13 work and confines cleanup after the worker relinquishes access.

## Out of scope

Recording, transcription, model installation, iCloud mutation and upload proof, catalog/detail UI, body editing, Favorite, audio replay, optional context acquisition, and full recovery screens remain with their assigned milestones. M13 does not add a manual title editor, automatic title replacement when a model later becomes ready, or a new AI provider.

## Completion checklist

- [x] The validation gate diagnoses unavailable CoreSimulator access before building, selects a unique booted iPhone when no destination is supplied, rejects missing or ambiguous destinations, and preserves failure logs. Its build and test steps use the same selected simulator.
- [x] Review hardening: post-transition candidate cleanup preserves the intermediate whenever the draft is missing, invalid, or inaccessible; focused tests cover recovery after the draft is lost.
- [x] The queue has a durable, generation-fenced draft transition and stable asset-ID mapping with compatible migration of existing jobs. A `resultReady` job can be adopted once; removal, restore quarantine, stale attempts/revisions, and duplicate callbacks cannot create a draft. Reconciliation checks a verified draft before requiring its discarded candidate.
- [x] Apple and Cohere candidates produce the exact same managed-body path. The builder validates source binding and method-specific provenance, derives codec/rate/channels/bitrate from verified audio evidence, writes the verified recording hint to both approved language fields, emits a codec-valid Markdown draft, and retains no permanent separate transcript.
- [x] Title policy tests cover available/unavailable models, English and Korean current-body language, confidence below 0.8, wrong-language and unsafe output, long-body full coverage, all work limits, 30-grapheme Unicode boundaries, native sentence fallback, and `Untitled` for an empty edited body. AI provenance records `title-v1`, iOS version, and model ID only when exposed.
- [x] Fault tests cover every candidate-read, ID allocation, binding-record/draft-write and verification, queue-transition, and intermediate-discard boundary; relaunch converges on one verified draft without rerunning transcription or losing audio. A stale or replaced draft cannot be accepted by ID or filename alone. Protected data and queue-store failure pause/defer without fabricating a transcription failure.
- [ ] A destination outage leaves the verified draft ready for M14; cancellation/removal fences title callbacks and draft publication. Backup exclusion, protection, confinement, privacy-safe diagnostics, and no remote title inference are verified.
- [ ] The [target-iPhone evidence record](milestone-13-diary-drafts-titles-device-evidence.md) has redacted pass evidence for M13-D01–M13-D05, including actual Apple model availability/fallback, long English/Korean bodies, lifecycle recovery, privacy, and draft retention during a destination outage.
- [x] Affected docs describe the implemented handoff and evidence. `make lint` and `TEST_DESTINATION=… scripts/validate.sh` pass with the destination recorded; unavailable gates remain unchecked with the blocker reported.

## M13 implementation review, 2026-11-02

Startup cleanup previously discarded a `readyToSave` transcription candidate without checking its draft. That could remove the only valid recovery copy after draft loss or corruption. Cleanup now requires a verified draft before identity-checked candidate discard. The focused M13 adoption suite passed 17/17 tests on the iPhone 18 Pro simulator (`993AECCC-055E-4C46-8F3B-D2913A5C1082`), including missing, invalid, and protected-data-unavailable draft cases. On 2026-11-02, `make lint` and the full `scripts/validate.sh` gate passed with that simulator ID, including generation, build, and all tests. The earlier SwiftUI macro error did not recur. CoreSimulator fails to connect from the restricted shell but works when simulator service access is granted; the gate now reports this before building. Target-iPhone evidence remains open.
