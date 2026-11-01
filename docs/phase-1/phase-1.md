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

Status: Active
Goal: Implement resumable microphone/location onboarding, the Settings and Record prerequisite foundation, and a physically verified iCloud-only persistent folder boundary.
Plan: [overview](milestone-08-first-launch-settings-icloud-overview.md), [approach](milestone-08-first-launch-settings-icloud-architecture.md)
Notes: The owner explicitly requested implementation while P1-M7's environment-blocked full validation item remains open. Apple/Cohere readiness remains P1-M11/P1-M12, capture remains P1-M9, and coordinated asset publication/upload proof remains P1-M14.

### P1-M9: Implement Recording and Capture Recovery

Status: Planned
Goal: Capture private playable audio through lock and backgrounding, settle it durably on stop/interruption/five minutes, and recover playable partials after relaunch.
Plan: [overview](milestone-09-recording-capture-recovery-overview.md), [approach](milestone-09-recording-capture-recovery-architecture.md)
Notes: Implementation follows P1-M8 completion or an explicit owner reorder. P1-M9 provides the minimal durable capture receipt that P1-M10 adopts into the full processing queue; target-phone Data Protection and interruption evidence are required.

### P1-M10: Implement the Durable Processing Queue

Status: Planned

### P1-M11: Add Apple On-Device Transcription

Status: Planned

### P1-M12: Add Cohere Model Installation and On-Device Transcription

Status: Planned

### P1-M13: Create Diary Drafts and Generate Titles

Status: Planned

### P1-M14: Commit and Reconcile iCloud Diary Assets

Status: Planned

### P1-M15: Build the Main Collection and Diary Detail

Status: Planned

### P1-M16: Add Diary Editing, Favorite, and Audio Replay

Status: Planned

### P1-M17: Build Pending, Failed, Incomplete, and Conflict Recovery

Status: Planned

### P1-M18: Add Optional Context and Pending-Work Reminders

Status: Planned

### P1-M19: Validate the Complete V1 Experience

Status: Planned
