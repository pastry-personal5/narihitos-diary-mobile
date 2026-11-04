# P1-M2: Software architecture overview

Status: Done

Define a reviewable software architecture for the confirmed iPhone app behavior. Keep unresolved product choices visible so later implementation does not silently settle them.

## Goal

Describe the app's responsibilities, data flow, persistence boundaries, failure recovery, and integration points well enough to guide scaffolding and feature work.

## Scope

- Map confirmed product and UX behavior to Clean Architecture layers with inward source dependencies, use-case-owned ports, and outer adapters.
- Define type-neutral asset discovery and registered, type-specific creation/storage so additional asset kinds do not inherit Diary Snippet's file bundle.
- Define a transcription-method registry and normalized text port for Apple and on-device Cohere in v1, while keeping future hosted methods from changing queue and diary rules.
- Define conceptual recording, processing, and asset lifecycles, including offline staging, foreground queue processing, provenance, and iCloud folder ownership.
- Describe how the app preserves recording audio and one managed Markdown draft through retries, destination failures, app closure, and partial writes.
- Identify test seams and observable evidence for critical flows.
- Review security boundaries and document prioritized design findings, proposed controls, and adversarial acceptance scenarios in the [security review](../security-review.md).
- Enumerate decisions that must be resolved before the corresponding behavior is implemented. Recommendations may be recorded as proposals, not owner-approved product decisions.
- Publish a standalone [software architecture](../architecture.md) that remains useful outside this milestone.

## Out of scope

- App code, project generation, dependency or build-tool changes, and provider calls.
- Selecting the Cohere iOS runtime or conversion, exact future Qwen models, recording encoding, remaining asset schema, title-generation details, conflict timestamp tie handling, or the remaining screen interactions.
- Resolving the open product and platform questions without the owner's decision or device evidence.

## Completion checklist

- [x] Complete the requested security review: the [review record](../security-review.md) identifies eight prioritized findings, and the [architecture](../architecture.md#security-privacy-and-operating-limits) defines trust boundaries and source-backed controls for files, private data, local inference, model installation, and recovery.
- [x] Define twelve [adversarial verification scenarios](../security-review.md#adversarial-verification-matrix) and carry unresolved security choices into the [decision inventory](../research/p1-m1-open-decisions.md). Delegated documentation validation found no broken local links/fragments or whitespace errors; runtime security verification remains pending.
- [x] Replace preserved-transcript and text-creation stages with one managed diary text file in the [architecture](../architecture.md) and affected product, UX, process, and decision docs. The documentation check found no whitespace errors or broken local links; only dated changelog entries retain the superseded design.
- [x] Review the architecture against confirmed behavior and close gaps in local capture recovery, attempt snapshots, iCloud bundle publication, catalog refresh, and edit durability; keep unresolved choices explicit in the [architecture proposal](../architecture.md). The documentation check found no whitespace errors or broken local links and fragments.
- [x] Define fail-open processing and queue recovery so one recording's wait, failure, or malformed state cannot prevent other ready recordings from advancing; document the data-safety limit and verification scenarios in the [architecture](../architecture.md).
- [x] Publish the standalone [software architecture](../architecture.md) with Clean Architecture dependencies, extension contracts for asset kinds and transcription methods, lifecycle diagrams, persistence, error handling, privacy, and test seams.
- [x] Keep confirmed behavior distinct from proposals and enumerate the open decisions that block implementation of specific paths. Those decisions are now closed in the [decision inventory](../research/p1-m1-open-decisions.md); [implementation evidence](../architecture.md#remaining-implementation-evidence) remains tracked separately.
- [x] Document the architecture work sequence and affected interfaces in the [approach](milestone-02-software-architecture-architecture.md).
- [x] Link the new documents from the [phase plan](phase-1.md) and [documentation index](../README.md), and record the plan change in the [changelog](changelog.md).
- [x] Apply the owner's P1-M2 exemption from build, lint, and test gates. Documentation review found no missing local links or phase/milestone references in the standalone architecture.
- [x] Complete the owner review. No additional architectural decisions were approved; the proposal continues to distinguish confirmed behavior from implementation-dependent open decisions.
