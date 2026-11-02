# Phase 1

Status: Active

Phase 1 is organized into the following milestones.

## Milestones

### P1-M1: Research

Status: Done
Goal: Research transcription and optional word-alignment options for diary recordings, including hosted Qwen, on-device Qwen3-ASR, whisper.cpp, WhisperKit, FluidAudio, Cohere Transcribe, and Qwen3-ForcedAligner on the target iPhone.
Plan: [overview](milestone-01-research-overview.md), [approach](milestone-01-research-architecture.md)
Validation: The owner exempted this milestone from all build, lint, and test gates; see the [changelog](changelog.md).
Notes: P1-M1 recorded the research and evaluation plan; P1-M6 later completed the target-phone comparison and selected the P1-M12 runtime direction.

### P1-M2: Software Architecture

Status: Done
Goal: Define reviewable app boundaries, durable workflows, and decision gates for implementation.
Plan: [overview](milestone-02-software-architecture-overview.md), [approach](milestone-02-software-architecture-architecture.md), [software architecture](../architecture.md)
Validation: The owner exempted this milestone from all build, lint, and test gates; see the [changelog](changelog.md).

### P1-M3: Scaffolding

Status: Done
Goal: Generate a minimal iPhone SwiftUI app and test project with XcodeGen and quiet validation commands.
Plan: [overview](milestone-03-scaffolding-overview.md), [approach](milestone-03-scaffolding-architecture.md)

### P1-M4: Design Information Architecture and Define Canonical UX Terms

Status: Done
Goal: Define the v1 screen hierarchy and consistent names for approved destinations, content, and recovery flows.
Plan: [overview](milestone-04-ux-overview.md), [approach](milestone-04-ux-architecture.md), [information architecture](../ux-information-architecture.md), [terms](../ux-terms.md)
Validation: The owner exempted this milestone from build, lint, and test exit gates; see the [changelog](changelog.md).

P1-M5 is Done with owner-approved product, data, privacy, and interface contracts. Later milestone themes remain provisional; their detailed plans and completion checklists will be written before implementation.

### P1-M5: Resolve V1 Product, Data, and Security Decisions

Status: Done
Goal: Approve the remaining v1 product, data, privacy, and security contracts with evidence and explicit downstream handoffs.
Plan: [overview](milestone-05-decisions-overview.md), [approach](milestone-05-decisions-architecture.md)
Validation: No lint, build, or test exit gate; the completed checklist, reconciled decision documents, and owner review are the evidence.

### P1-M6: Validate the Cohere iPhone Runtime and Model Distribution

Status: Done
Goal: Build an isolated physical-iPhone Cohere trial, compare Q4/Q5 on available English/Korean clips, and select an implementation direction without overstating unperformed quality or long-form evidence.
Plan: [overview](milestone-06-cohere-runtime-trial-overview.md), [approach](milestone-06-cohere-runtime-trial-architecture.md), [device protocol](milestone-06-cohere-runtime-trial-protocol.md), [results](milestone-06-cohere-runtime-trial-results.md)
Notes: The owner selected Q4_K_M with `transcribe.cpp` Metal for P1-M12 after the available short English/Korean phone runs and explicitly closed the remaining trial matrix without claiming it as evidence.

### P1-M7: Establish Asset Schema and Private Storage

Status: Done
Goal: Implement the bounded Diary Snippet v1 codec and confined, backup-excluded private-workspace foundation used by later recording, queue, draft, and iCloud milestones.
Plan: [overview](milestone-07-asset-storage-overview.md), [approach](milestone-07-asset-storage-architecture.md)
Notes: The owner explicitly reordered implementation ahead of P1-M6 on 2026-11-01; lock-compatible Data Protection and restore behavior retain their assigned physical-device evidence in later milestones.

### P1-M8: Build First Launch, Settings, and iCloud Folder Selection

Status: Done (owner decision; by-human test and evidence pending)
Goal: Implement resumable microphone/location onboarding, the Settings and Record prerequisite foundation, and a physically verified iCloud-only persistent folder boundary.
Plan: [overview](milestone-08-first-launch-settings-icloud-overview.md), [approach](milestone-08-first-launch-settings-icloud-architecture.md)
Notes: The owner marked M8 implementation done on 2026-11-02, except for the by-human test and evidence. The environment-blocked validation item and physical provider/account evidence remain open. Apple/Cohere readiness remains P1-M11/P1-M12, capture remains P1-M9, and coordinated asset publication/upload proof remains P1-M14.

### P1-M9: Implement Recording and Capture Recovery

Status: Active
Goal: Capture private playable audio through lock and backgrounding, settle it durably on stop/interruption/five minutes, and recover playable partials after relaunch.
Plan: [overview](milestone-09-recording-capture-recovery-overview.md), [approach](milestone-09-recording-capture-recovery-architecture.md), [device evidence](milestone-09-recording-capture-recovery-device-evidence.md)
Notes: The owner marked M9 implementation done on 2026-11-02, except for the by-human test and evidence. P1-M9 provides the minimal durable capture receipt that P1-M10 adopts into the full processing queue; target-phone Data Protection and interruption evidence remain open.

### P1-M10: Implement the Durable Processing Queue

Status: Done (owner decision; human device tests pending)
Goal: Adopt verified capture receipts into a durable foreground queue with method readiness, fair failure isolation, restored-work quarantine, and bounded attempt ownership.
Plan: [overview](milestone-10-durable-processing-queue-overview.md), [approach](milestone-10-durable-processing-queue-architecture.md)
Notes: The owner marked implementation done except human tests on 2026-11-02. Physical restore evidence remains open in the [human test tracker](by-human-test-required.md#p1-m10); the post-review simulator gate and unchecked evidence in the overview also remain unverified. Production transcription adapters arrive in P1-M11/P1-M12, and diary drafts and iCloud publication follow in P1-M13/P1-M14.

### P1-M11: Add Apple On-Device Transcription

Status: Done (owner decision; by-human test and evidence pending)
Goal: Integrate Apple SpeechTranscriber for explicit English/Korean local transcription, truthful system-asset readiness and installation, durable result handoff, and acknowledged cancellation.
Plan: [overview](milestone-11-apple-on-device-transcription-overview.md), [approach](milestone-11-apple-on-device-transcription-architecture.md), [device evidence](milestone-11-apple-on-device-transcription-device-evidence.md)
Notes: The owner marked M11 implementation done on 2026-11-02, except for the by-human test and evidence. Apple installation remains blocked pending direction on the unavailable documented download-size and storage-preflight information. M11 stages a protected transcription-result candidate; P1-M13 adopts it as the managed Diary body, and P1-M12 adds the separately approved Cohere method.

### P1-M12: Add Cohere Model Installation and On-Device Transcription

Status: Done (owner decision; by-human test and evidence pending)
Goal: Install the verified approved Cohere model and integrate local Metal transcription with bounded chunking, durable handoff, and target-phone evidence.
Plan: [overview](milestone-12-cohere-transcription-overview.md), [approach](milestone-12-cohere-transcription-architecture.md), [device evidence](milestone-12-cohere-transcription-device-evidence.md)
Notes: The owner marked implementation done on 2026-11-02, except for the by-human test and evidence. The owner authorized implementation ahead of M11 completion and approved the pinned production `transcribe.cpp` dependency/build integration. Open M8–M11 device evidence, M12-D01–D08, and the M11 Apple-installation blocker remain open and are not waived; the unavailable full validation gate is also reported in the M12 overview.

### P1-M13: Create Diary Drafts and Generate Titles

Status: Done (owner decision; target-iPhone evidence pending)
Goal: Adopt a verified transcription candidate as one protected managed Diary draft and generate a bounded read-only title with an on-device AI or first-sentence fallback.
Plan: [overview](milestone-13-diary-drafts-titles-overview.md), [approach](milestone-13-diary-drafts-titles-architecture.md), [device evidence](milestone-13-diary-drafts-titles-device-evidence.md)
Notes: The owner requested M13 implementation on 2026-11-02, authorizing work ahead of M12 completion. The implementation and simulator test suite are complete; M13 retains the draft and audio for M14's iCloud pair publication. The full simulator gate passed on 2026-11-02 with CoreSimulator access; target-iPhone evidence remains open.

### P1-M14: Commit and Reconcile iCloud Diary Assets

Status: Implementation complete (target-iPhone evidence pending)
Goal: Publish the verified diary/audio pair to its capture-time iCloud folder, prove both uploads, and reconcile partial writes and conflicts safely.
Plan: [overview](milestone-14-icloud-commit-reconciliation-overview.md), [approach](milestone-14-icloud-commit-reconciliation-architecture.md), [device evidence](milestone-14-icloud-commit-reconciliation-device-evidence.md)
Notes: M14 has a live audio-first coordinated pair writer, per-file upload observations, durable file-version checkpoints, save retry and cleanup, original-destination loans, guarded partial repair, typed active-folder and capture-folder inspection, and protected conflict snapshots. The conflict path inspects provider versions, pairs them by explicit audio digest without sharing an audio version, durably claims the selected snapshot, replaces audio then Markdown against expected current versions, waits for separate upload reports, and checks the selected pair again before removing only recognized obsolete provider versions. Unknown historical versions block cleanup. Automatic later-pair cleanup follows proof; ambiguous choice needs M17 confirmation. After provider cleanup, the job is saved and protected snapshots and capture staging are removed. Random inode-bound markers support guarded adoption after interrupted version checkpoints where the provider retains them; otherwise collisions remain for read-only recovery. The full simulator gate passed on 2026-11-02 with `platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082`; target-iPhone provider and adversarial evidence remains open. An isolated synthetic-test build was installed on a paired iPhone running iOS 27.0.1, but launch was denied while the device was locked, so no M14 device scenario has passed.

### P1-M15: Build the Main Collection and Diary Detail

Status: Active
Goal: Page and validate the active-folder Diary Snippet collection, surface recovery attention, and present safe read-only Diary Snippet detail.
Plan: [overview](milestone-15-main-collection-diary-detail-overview.md), [approach](milestone-15-main-collection-diary-detail-architecture.md), [device evidence](milestone-15-main-collection-diary-detail-device-evidence.md)
Notes: The owner requested implementation on 2026-11-02 ahead of remaining M14 device evidence. M15 now has scoped catalog discovery/paging, exact-version read-only detail, evidenced legacy support, Main notices/All routing, and custom template artwork. Lint and the full simulator gate passed with `platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082`; target-iPhone M15-D01–D10 and the unchecked display/provider/visual checklist items remain open, so the milestone stays Active. M16 retains editing/Favorite mutation/replay; M17 retains complete recovery actions/screens; M18 retains context acquisition/reminders. Earlier device gates are unchanged.

### P1-M16: Add Diary Editing, Favorite, and Audio Replay

Status: Planned
Goal: Save version-checked body and Favorite edits durably and replay verified audio without compromising capture or legacy read-only behavior.
Plan: [overview](milestone-16-diary-editing-favorite-audio-replay-overview.md), [approach](milestone-16-diary-editing-favorite-audio-replay-architecture.md), [device evidence](milestone-16-diary-editing-favorite-audio-replay-device-evidence.md)
Notes: Planning only; implementation follows M15 unless the owner authorizes a reorder. Submitted edits need an independent committed-asset journal and destination capability, and replay needs shared audio-session ownership with capture. M17 retains recovery choice/removal screens; earlier provider, legacy, capture, and device evidence remains open.

### P1-M17: Build Pending, Failed, Incomplete, and Conflict Recovery

Status: Planned
Goal: Complete the four All recovery destinations with typed state, safe inspection, version-bound retry/replacement/removal, and verified conflict choice and cleanup.
Plan: [overview](milestone-17-recovery-overview.md), [approach](milestone-17-recovery-architecture.md), [device evidence](milestone-17-recovery-device-evidence.md)
Notes: Planning only; implementation follows M16 unless the owner authorizes a reorder. Recovery spans capture jobs, active-folder resources, and M16 submitted edits through owner-specific capabilities and journals. Confirmation never substitutes for fresh resource/version checks, cancellation settlement, or chosen-pair/upload proof. Earlier validation and target-phone evidence remain open.

### P1-M18: Add Optional Context and Pending-Work Reminders

Status: Planned
Goal: Bind optional location/weather to recording start and schedule a generic next-local-day reminder from durable pending work without blocking capture or saving.
Plan: [overview](milestone-18-context-reminders-overview.md), [approach](milestone-18-context-reminders-architecture.md), [device evidence](milestone-18-context-reminders-device-evidence.md)
Notes: Planning only; implementation follows M17 unless the owner authorizes a reorder. Context needs a protected recording-bound handoff into draft/publication and a verified WeatherKit capability/profile; reminders need authoritative pending state, genuine departure events, and calendar/permission reconciliation. Earlier implementation gates and target-phone evidence remain open.

### P1-M19: Validate the Complete V1 Experience

Status: Planned
