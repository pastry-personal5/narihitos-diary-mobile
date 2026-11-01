# P1-M2: Software architecture approach

Status: Planned

This plan describes how the architecture deliverable is organized and how its unresolved choices are carried into later work. The standalone [software architecture](../architecture.md) is the technical reference.

## Affected modules and interfaces

No app modules or compiled interfaces are changed here. The architecture proposes inward domain/use-case dependencies and outward adapters for SwiftUI screens, recording and processing, a durable local queue, Apple and on-device Cohere transcription, managed Markdown creation, iCloud asset storage, model readiness, optional metadata, and reminders. It also defines generic asset discovery with kind-specific behavior and a registry of approved transcription methods. Names and exact Swift signatures remain implementation choices.

## Approach and sequence

1. Start from [confirmed product behavior](../product-behavior.md), [planned UX behavior](../ux-gui.md), and the [open-decision inventory](../research/p1-m1-open-decisions.md). Mark each architectural statement as confirmed behavior, a proposed design, or a pending decision where that distinction matters.
2. Trace a recording from permission and capture through durable local audio staging, oldest-ready foreground transcription, one managed Markdown draft, iCloud asset commit, and active-folder display. Specify state transitions and failure recovery at each durable boundary.
3. Apply the Clean Architecture dependency rule: domain and use cases own rules and ports; SwiftUI, Apple APIs, file formats, and providers stay in outward adapters assembled by a composition root.
4. Keep type-neutral asset discovery separate from Diary Snippet creation/storage, and select transcription methods through stable IDs and registered adapters returning normalized text for the managed diary body. Keep SwiftUI view state separate from the durable queue and user-selected document storage so app relaunch and external iCloud changes can be handled explicitly.
5. Describe security-scoped folder access, coordinated file I/O, local-model readiness, effective transcription-setting provenance, and optional metadata without fixing undecided schema or Cohere runtime details. Hosted consent and credential boundaries remain future extension seams.
6. Identify the tests and device prototypes that would validate the architecture, including extension-contract checks, then list the owner decisions needed before dependent implementation starts.
7. Index the deliverable, update the phase plan, and review the completion checklist. The owner exempted this milestone from build, lint, and test gates.

## Review criteria

The architecture is ready for review when a reader can identify the owner of every durable datum, the state left after each expected failure, the source of each user-visible asset, and which decisions remain open. A proposal must not be mistaken for an approved product rule.
