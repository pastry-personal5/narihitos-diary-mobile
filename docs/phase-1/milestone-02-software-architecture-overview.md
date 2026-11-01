# P1-M2: Software architecture overview

Status: Planned

Define a reviewable software architecture for the confirmed iPhone app behavior. Keep unresolved product choices visible so later implementation does not silently settle them.

## Goal

Describe the app's responsibilities, data flow, persistence boundaries, failure recovery, and integration points well enough to guide scaffolding and feature work.

## Scope

- Map confirmed product and UX behavior to Clean Architecture layers with inward source dependencies, use-case-owned ports, and outer adapters.
- Define type-neutral asset discovery and registered, type-specific creation/storage so additional asset kinds do not inherit Diary Snippet's file bundle.
- Define a transcription-method registry and normalized transcript port so adding another approved local or hosted method does not change queue and diary rules.
- Define conceptual recording, processing, and asset lifecycles, including offline staging, foreground queue processing, provenance, and iCloud folder ownership.
- Describe how the app preserves recordings and the original transcript through retries, destination failures, app closure, and partial writes.
- Identify test seams and observable evidence for critical flows.
- Enumerate decisions that must be resolved before the corresponding behavior is implemented. Recommendations may be recorded as proposals, not owner-approved product decisions.
- Publish a standalone [software architecture](../architecture.md) that remains useful outside this milestone.

## Out of scope

- App code, project generation, dependency or build-tool changes, and provider calls.
- Selecting exact Qwen models, recording encoding, remaining asset schema, title-length rules, conflict timestamp tie handling, or the remaining screen interactions.
- Resolving the open product and platform questions without the owner's decision or device evidence.

## Completion checklist

- [x] Publish the standalone [software architecture](../architecture.md) with Clean Architecture dependencies, extension contracts for asset kinds and transcription methods, lifecycle diagrams, persistence, error handling, privacy, and test seams.
- [x] Keep confirmed behavior distinct from proposals and enumerate the open decisions that block implementation of specific paths: [decisions required](../architecture.md#decisions-required-before-dependent-implementation).
- [x] Document the architecture work sequence and affected interfaces in the [approach](milestone-02-software-architecture-architecture.md).
- [x] Link the new documents from the [phase plan](phase-1.md) and [documentation index](../README.md), and record the plan change in the [changelog](changelog.md).
- [x] Apply the owner's P1-M2 exemption from build, lint, and test gates. Documentation review found no missing local links or phase/milestone references in the standalone architecture.
- [ ] Review the proposal with the owner and record any approved architectural decisions before marking this milestone Done.
