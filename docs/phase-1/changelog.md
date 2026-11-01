# Phase 1 changelog

Status: Active

This log records owner decisions and significant plan changes for Phase 1. Research implications and remaining questions are in the [open-decision inventory](../research/p1-m1-open-decisions.md).

## Entries

- 2026-11-01 — Owner decision — keep milestone and research documents in active directories until their phase is complete, including completed P1-M1 documents while Phase 1 remains active.
- 2026-11-01 — Research completion — P1-M1 checklist is complete: [Qwen transcription](../research/p1-m1-qwen-transcription.md), [recording format](../research/p1-m1-audio-format.md), and the active [open-decision inventory](../research/p1-m1-open-decisions.md) provide the P1-M2 handoff. The research did not approve a specific Qwen model or recording codec; unresolved product details remain open.
- 2026-11-01 — Owner decision — exempted P1-M1 and P1-M2 from all build, lint, and test completion gates. Their checklists and documentation remain required; the standard gate resumes at P1-M3.
- 2026-11-01 — Owner interview — allowed private local staging for offline recordings; bound each recording to its original iCloud folder while using the transcription method and Qwen settings current when processing starts. An unavailable destination keeps the result pending; completion into a former active folder names that folder.
- 2026-11-01 — Owner interview — confirmed v1 [product behavior](../product-behavior.md#confirmed-v1-behavior) and [planned GUI behavior](../ux-gui.md#planned-owner-approved-behavior), including foreground-only oldest-first transcription, iCloud-only active-folder storage, optional metadata, and retry rules; diary text transformation remains undecided.
- 2026-11-01 — Owner interview — chose XcodeGen for automatic project generation in P1-M3. No project or dependency was changed in this research milestone.
- 2026-11-01 — Owner interview — v1 recording must work offline; transcription may wait for connectivity.
- 2026-11-01 — Owner interview — users must be able to choose any iCloud folder for assets and create an iCloud folder.
- 2026-11-01 — Owner interview — accept a user-provided en-US or ko-KR recording language hint where possible and carry it to transcription when supported.
- 2026-11-01 — Owner interview — transcript versus polished diary text remains undecided.
