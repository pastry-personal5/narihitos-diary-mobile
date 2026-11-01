# P1-M4: UX design approach

Status: Done

Use confirmed product behavior as the boundary for the v1 information architecture, then assign names to destinations and objects without inventing screen interactions. The [overview](milestone-04-ux-overview.md) holds the completion checklist.

## Source and deliverables

1. Read [product behavior](../product-behavior.md), [UX GUI](../ux-gui.md), and the [open-decision inventory](../research/p1-m1-open-decisions.md). Keep the owner-approved five-tab root and Main/All responsibilities.
2. Express containment in [UX information architecture](../ux-information-architecture.md): root tabs, destinations, detail content order, and cross-cutting recording/recovery flows. Distinguish a saved Diary Snippet from a queued recording and an active folder from a recording's destination.
3. Express vocabulary in [UX terms](../ux-terms.md). Mark only approved exact labels as exact; make other names canonical for design discussion and identifiers while their final on-screen wording awaits review.
4. Keep [UX GUI](../ux-gui.md) focused on visible behavior and link it to the structure and terminology. Record unresolved interface choices instead of adding controls.

## Review criteria

- Every approved destination has one discoverable parent; Settings and both recovery screens are reached from All, and All does not duplicate Main's collection. Main's top one-line notice bar reports queued, processing, or recovery state without listing those items.
- A pending or failed recording is never presented as a completed Diary Snippet. Incomplete pairs and equal-time conflicts live in separate All recovery screens; each conflict version has a vertically scrollable tab, and the unchosen version is removed only after confirmation.
- Detail has Title and Diary body first, Favorite beside Title, and Audio replay inside bottom Metadata. Editor changes only Diary body.
- The exact-label list contains only owner-confirmed labels. Open copy and interaction decisions stay explicit.

The milestone is design-only. Build, lint, and test commands are exempt as an exit gate by the owner; documentation consistency and owner review remain required.
