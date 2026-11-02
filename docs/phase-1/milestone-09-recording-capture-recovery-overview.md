# P1-M9: Recording and capture recovery overview

Status: Done (owner decision; by-human test and evidence pending)

Implement private iPhone audio capture, immediate durable settlement, and recovery of interrupted or abandoned capture. This milestone must prove on the target phone that capture continues through lock and backgrounding and that a recording ending while locked is finalized and recorded durably without waiting for unlock.

## Entry condition

- Follow Phase 1 order: implementation starts when P1-M8 is Done or the owner explicitly authorizes a reorder. Planning M9 does not close M8's open simulator and physical-device evidence.
- The owner authorized starting M9 while M8 remains Active by requesting M9 implementation on 2026-11-02.
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

### Owner-requested app icon addendum

- [x] A flat, simple app icon is supplied as an editable source and a 1024 px opaque PNG in the app asset catalog; 120 px and 48 px previews remain recognizable.
- [x] The generated app target names the icon asset, and asset metadata and image dimensions pass inspection.

### Owner-requested recording language controls

- [x] Main has separate bottom-right `en` and `ko` recording buttons with distinct accessible names and at least 44 pt targets. Source inspection confirms two 56 pt controls in the trailing safe-area inset.
- [x] Each button carries its language through the existing microphone and destination gate into capture; the language selection dialog is removed. Source inspection confirms both routes and no remaining picker state or dialog.
- [x] The `en` and `ko` Record buttons have distinct, legible backgrounds; source inspection verifies their language-to-color mapping, and rendered iOS 27.1 simulator previews verify blue `en` and purple `ko` with legible white content in light and dark appearance.
- [x] Focused presentation tests and source inspection verify the new routing and layout. The accessibility tree exposes `Record in English` and `Record in Korean` as separate controls.

- [x] The start gate rechecks live microphone authorization and destination identity/record validity, accepts only the approved language hints, reserves at least 100 MiB, and starts no audio/session/workspace mutation when a prerequisite fails. A previously validated folder permits offline capture during temporary provider/network unavailability; missing, invalid, known revoked, or known wrong-account references do not. Low storage shows `Not enough storage to start recording.` with Review Pending Recordings and OK.
- [x] Tests show the recording-start instant, stable ID, language hint, and independent durable destination reference are captured once and survive stop, active-folder replacement, retryable settlement, and relaunch without becoming file paths or provider tokens in core values. A failed destination snapshot prevents capture.
- [x] Simulator tests write and decode synthetic mono AAC `.m4a`, inspect actual sample rate, channels, bytes, and duration, and verify a pending receipt only after playable validation. Boundary tests reject overlong, oversized, and unsupported output; unreadable audio remains failed with its private bytes retained.
- [ ] Target-phone clips verify requested versus actual sample rate and bit rate, the 64 MiB and five-minute bounds including encoder/finalization tolerance, and playable decode before Pending is shown.
- [x] Deterministic state and race tests cover Stop & Transcribe, exact five-minute timeout, interruption, duplicate/late stop causes, start failure, and failed finalization. Source inspection confirms scene changes do not call stop. One settlement result uses the original identity.
- [ ] Target-phone lock/background and simultaneous interruption/stop trials confirm one durable settlement and no duplicate identity under actual platform callbacks.
- [x] A synthetic playable partial becomes pending once after relaunch reconciliation. Synthetic unreadable audio is retained as Failed with the approved reason, while missing or substituted audio remains a review issue without a false receipt.
- [ ] Physical crash/force-quit trials establish whether the selected `.m4a` writer yields a playable partial; any unplayable partial stays private and reviewable.
- [x] Every successful stop or automatic end verifies the finalized file and durable receipt before UI reports queued; injected file, attribute, receipt-write, atomic-replace, storage-exhaustion, and relaunch failures preserve recoverable audio and never report false progress. A queue-store failure reports paused local work, not a fabricated failed recording.
- [ ] The chosen Data Protection classes and attribute application are documented with physical-device observations for open capture, locked finalization, receipt settlement, closed files, scratch/replacement files, and before/after-unlock reconciliation. Locked inaccessibility is distinguished from missing data, with no silent protection downgrade.
- [x] Pending audio and related private capture artifacts remain in nonpurgeable Application Support, are excluded from backup on creation and replacement, and retain confinement against malformed identities and symlink/resource substitution.
- [x] The capture UI has only Stop & Transcribe as its action during recording, accessible elapsed/level feedback, and truthful pending/failed or interim completion states. Main/All containment and the neutral nonforeground privacy cover remain intact; source inspection and focused presentation tests find no sensitive paths, audio, folder secrets, or raw errors in diagnostics and accessibility.
- [ ] Target-phone scenarios M9-D01–M9-D10 in the approach have redacted results, including lock/background settlement, locked five-minute timeout, interruption, crash recovery, offline capture, free-space failure, and actual file/protection attributes. Unavailable device controls remain unchecked and are reported as blockers.
- [x] Tests and source inspection prove the Domain/Application capture policy does not import AVFoundation, SwiftUI, UIKit, file URLs, or concrete workspace/destination adapters. No new dependency or build tool was added; affected docs record the M10/M17/M18 handoffs.
- [x] `swift-format lint --strict --recursive .` passes.
- [x] `swiftlint lint --strict` passes.
- [x] The generated project builds and all tests pass through `scripts/validate.sh` on an available iPhone simulator. The current review revision passed on a booted iPhone 18 Pro simulator running iOS 27.0.

## Acceptance evidence

The owner marked M9 implementation done on 2026-11-02, except for the by-human test and evidence. Target-phone capture, interruption, lock/background, and Data Protection evidence remain pending; any unavailable validation gate remains unchecked.

Check items only with focused tests, source/attribute inspection, a successful validation command, or a redacted target-phone trial record. Simulator tests establish state transitions and injected failure behavior; they cannot establish locked audio continuity, iOS audio-session behavior, actual Data Protection access while locked, or background execution. Record requested versus observed audio parameters and any device-specific variance before accepting the encoder path.

## Implementation evidence

- The owner-requested journal icon has an editable SVG and an opaque 1024 by 1024 PNG. Visual inspection at 120 and 48 px found the journal, spine, and recording dot legible. Asset JSON parsed, `git diff --check` passed, generation confirmed the `AppIcon` build setting, and direct `xcrun actool` compilation passed. The latest generic simulator build also passes.
- On 2026-11-02, M9 implementation began under the owner's explicit request while M8 remains Active. The application-owned capture coordinator checks live microphone state, typed destination access (including independently verified offline eligibility), and the 100 MiB reserve before creating capture artifacts. It binds a stable ID, start time, language, and independent opaque destination snapshot reference. Its monotonic deadline and size poll, single settlement owner, and receipt gate do not depend on the visible timer.
- The Apple adapter requests mono 44.1 kHz, 64 kb/s AAC, prepares and protects a private `.m4a` file, measures actual format, size, duration, and playback preparation, and retains unplayable data as failed. A private Application Support capture journal, snapshot, and receipt are written through backup-excluded verified files with atomic publication of each journal file. Relaunch reconciliation retains audio and writes one failed or pending receipt when protected data is available; malformed or incomplete work remains visible as a sanitized recovery issue. The UI shows language-specific Record controls, a capture screen with only Stop & Transcribe, and interim Pending/Failed destinations. The built app bundle includes the `audio` background mode.
- Reconciliation classifies only an inspected audio file as unreadable. Missing, inaccessible, or substituted audio remains a review issue without a fabricated failed receipt. A synthetic mono AAC test exercises decode, measured metadata, receipt publication, and idempotent reopen; source checks cover language-button routing and capture controls. Target-phone encoder and lock observations remain in the owner-run evidence sheet.
- The settlement path reopens and verifies its receipt against the capture marker and measured audio after writing it, including the nominal success path. A tampered-marker test confirms that retained audio and a recovery issue cannot be reported as queued.
- Receipt listing also requires the fixed private audio file for a Failed entry; if that file later goes missing, the entry remains a recovery issue instead of appearing as a recording with no audio.
- Review follow-up: closed-file protection and backup exclusion are applied before an empty or oversized recording is classified as unreadable. If attribute verification fails, settlement pauses with the audio retained instead of publishing a Failed receipt. Recorder start failure also deactivates the audio session. A focused fault test covers the empty-audio protection path.
- An iOS 27.1 iPhone Duo simulator rendered both Record controls in light and dark appearance; both colors and white labels were legible and distinct. The iOS 27.0 simulator cannot launch this app because the approved minimum is iOS 27.0.1.
- Focused automated tests cover start gates, offline/invalid destination snapshots, immutable capture data, duplicate stop causes, exact five-minute and size arbitration, invalid audio, start/receipt failure, relaunch reconciliation, retained partial audio, and backup exclusion. The current review revision passed generation, strict `swift-format`, strict `swiftlint`, build, and all simulator tests through `scripts/validate.sh` on a booted iPhone 18 Pro simulator running iOS 27.0, including the new empty-audio protection fault test. The [target-phone evidence sheet](milestone-09-recording-capture-recovery-device-evidence.md) remains entirely Not run. Those runs are needed to verify background/lock continuity, interruption and abrupt-termination behavior, actual encoder output, and protection attributes before the corresponding checklist items can be checked.
