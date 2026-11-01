# P1-M9: Recording and capture recovery overview

Status: Planned

Implement private iPhone audio capture, immediate durable settlement, and recovery of interrupted or abandoned capture. This milestone must prove on the target phone that capture continues through lock and backgrounding and that a recording ending while locked is finalized and recorded durably without waiting for unlock.

## Entry condition

- Follow Phase 1 order: implementation starts when P1-M8 is Done or the owner explicitly authorizes a reorder. Planning M9 does not close M8's open simulator and physical-device evidence.
- Use the approved [P1-M5 recording, queue, and privacy contract](milestone-05-decisions-architecture.md#recording-queue-and-privacy-contract), [product behavior](../product-behavior.md), [UX GUI](../ux-gui.md), and [security review](../security-review.md). M7 supplies the private-workspace foundation; M8 supplies live permission and destination prerequisites.
- No dependency or build-tool change is planned. Ask the owner before one is needed or before a device finding would change the approved capture outcome.

## Scope

- Add inward-owned capture and capture-settlement contracts. The application coordinator checks current microphone authorization, a previously accepted iCloud destination reference, the selected `en-US` or `ko-KR` language hint, and the 100 MiB free-space reserve before starting. Temporary provider/network unavailability does not block offline capture to a previously validated folder; an absent, invalid, known revoked, or known wrong-account reference cannot be treated as valid. Durably bind the destination's independent access record and the recording-start instant before accepting audio; a later active-folder change cannot retarget or erase that recording's original destination.
- Record mono AAC `.m4a` targeting 44.1 kHz and about 64 kb/s in a unique private workspace. Inspect actual output format, size, duration, and playability rather than assuming requested encoder settings succeeded. Refuse an unsafe or oversized output; retain recoverable bytes and a reason.
- Keep recording across screen lock and app backgrounding, subject to the approved Stop & Transcribe control, audio interruption, and five-minute maximum. Settle stop and interruption callbacks once, including races among timer, interruption, scene changes, and a late user action.
- Finalize playable audio and atomically persist a minimal capture receipt before reporting it queued. A receipt contains stable job/workspace identity, start/order, captured language and destination reference, actual audio metadata, and a pending or failed capture outcome. It is the M9 durable handoff that M10 expands into the processing queue; no transcription worker is started here.
- On relaunch, reconcile a capture receipt and private audio before exposing pending or failed state. Recover a playable partial after crash or force quit; retain an unplayable partial as failed with `This recording can’t be read.` and an entry-level reason. Prove the chosen `.m4a` recording mechanism can leave a playable partial under representative abrupt termination; do not infer this from normal `stop()` behavior. Never delete an orphaned private audio file merely because its receipt is missing.
- Choose and verify production Data Protection for the open recording, its finalization path, receipt and replacement files, and closed sensitive files. Preserve M7's backup exclusion on all pending audio and receipt/recovery artifacts. Protected-file inaccessibility while locked must not be interpreted as deletion.
- Add a capture screen with elapsed time, level indication, and only Stop & Transcribe as a user control. Show the approved low-storage message and actions. Route settled pending/failed capture to the corresponding All destination or a truthful interim state until M10/M17 owns those screens.
- Add deterministic state, fault, concurrency, audio-validation, storage, and presentation tests, plus the physical-device evidence matrix in the approach.

## Out of scope

- Full queue scheduling, effective transcription settings, readiness, retry, removal, installation identity, and restored-job quarantine belong to P1-M10 and later milestones. M9's receipt must be adoptable without changing the recorded start, language, destination, or audio bytes.
- Apple or Cohere transcription, model downloads, diary draft/title creation, and iCloud publication belong to P1-M11 through P1-M14. Stop & Transcribe means the clip is queued for the later automatic foreground processing pipeline; M9 must not claim that text was produced.
- Location/weather acquisition belongs to P1-M18. M9 exposes a recording-start event for that future adapter but does not invent context data.
- The full Main collection, notice rotation, finished-asset playback, and final bitmap icon set belong to P1-M15/P1-M16. General pending/failed recovery actions and confirmed removal belong to P1-M17.
- No background transcription, unlimited recording duration, pause/resume, discard, silent method switching, or direct recording into iCloud.

## Completion checklist

- [ ] The start gate rechecks live microphone authorization and destination identity/record validity, accepts only the approved language hints, reserves at least 100 MiB, and starts no audio/session/workspace mutation when a prerequisite fails. A previously validated folder permits offline capture during temporary provider/network unavailability; missing, invalid, known revoked, or known wrong-account references do not. Low storage shows `Not enough storage to start recording.` with Review Pending Recordings and OK.
- [ ] Tests show the recording-start instant, stable ID, language hint, and independent durable destination reference are captured once and survive stop, active-folder replacement, retryable settlement, and relaunch without becoming file paths or provider tokens in core values. A failed destination snapshot prevents capture.
- [ ] Synthetic and device clips verify actual mono AAC `.m4a` output, requested sample-rate/bitrate behavior on the target phone, bounded size at 64 MiB, measured duration at or below five minutes plus documented encoder/finalization tolerance, and playable decode before a pending receipt is reported. Unsupported actual output is retained as failed, not misrepresented as valid.
- [ ] State and race tests cover Stop & Transcribe, five-minute timeout, audio interruption, lock/background changes, simultaneous stop causes, late callbacks, start failure, and failed finalization. Exactly one settlement result is durable; no duplicate receipt or asset identity is minted.
- [ ] A playable interruption/crash partial becomes pending automatically after durable reconciliation. Physical crash/force-quit trials establish whether the selected `.m4a` writer yields a playable partial; any unplayable or unreadable partial remains private and appears as failed with the approved sanitized reason. An orphaned file is kept for review rather than deleted.
- [ ] Every successful stop or automatic end verifies the finalized file and durable receipt before UI reports queued; injected file, attribute, receipt-write, atomic-replace, storage-exhaustion, and relaunch failures preserve recoverable audio and never report false progress. A queue-store failure reports paused local work, not a fabricated failed recording.
- [ ] The chosen Data Protection classes and attribute application are documented with physical-device observations for open capture, locked finalization, receipt settlement, closed files, scratch/replacement files, and before/after-unlock reconciliation. Locked inaccessibility is distinguished from missing data, with no silent protection downgrade.
- [ ] Pending audio and related private capture artifacts remain in nonpurgeable Application Support, are excluded from backup on creation and replacement, and retain confinement against malformed identities and symlink/resource substitution.
- [ ] The capture UI has only Stop & Transcribe as its action during recording, accessible elapsed/level feedback, and truthful pending/failed or interim completion states. Main/All containment and the neutral nonforeground privacy cover remain intact; sensitive paths, audio, folder secrets, and raw errors are absent from diagnostics and accessibility.
- [ ] Target-phone scenarios M9-D01–M9-D10 in the approach have redacted results, including lock/background settlement, locked five-minute timeout, interruption, crash recovery, offline capture, free-space failure, and actual file/protection attributes. Unavailable device controls remain unchecked and are reported as blockers.
- [ ] Tests and source inspection prove the Domain/Application capture policy does not import AVFoundation, SwiftUI, UIKit, file URLs, or concrete workspace/destination adapters. No new dependency or build tool was added; affected docs record the M10/M17/M18 handoffs.
- [ ] `swift-format lint --strict --recursive .` passes.
- [ ] `swiftlint lint --strict` passes.
- [ ] The generated project builds and all tests pass through `scripts/validate.sh` on an available iPhone simulator.

## Acceptance evidence

Check items only with focused tests, source/attribute inspection, a successful validation command, or a redacted target-phone trial record. Simulator tests establish state transitions and injected failure behavior; they cannot establish locked audio continuity, iOS audio-session behavior, actual Data Protection access while locked, or background execution. Record requested versus observed audio parameters and any device-specific variance before accepting the encoder path.
