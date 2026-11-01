# Phase 1

Status: Active

Phase 1 is organized into the following milestones.

## Milestones

### P1-M1: Research

Status: Active
Goal: Research transcription and optional word-alignment options for diary recordings, including hosted Qwen, on-device Qwen3-ASR, whisper.cpp, WhisperKit, FluidAudio, Cohere Transcribe, and Qwen3-ForcedAligner on the target iPhone.
Plan: [overview](milestone-01-research-overview.md), [approach](milestone-01-research-architecture.md)
Validation: The owner exempted this milestone from all build, lint, and test gates; see the [changelog](changelog.md).

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

The following milestone themes are provisional while P1-M1 remains active. Their detailed plans and completion checklists will be written before implementation.

### P1-M5: Resolve V1 Product, Data, and Security Decisions

Status: Planned

### P1-M6: Validate the Cohere iPhone Runtime and Model Distribution

Status: Planned

### P1-M7: Establish Asset Schema and Private Storage

Status: Planned

### P1-M8: Build First Launch, Settings, and iCloud Folder Selection

Status: Planned

### P1-M9: Implement Recording and Capture Recovery

Status: Planned

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
