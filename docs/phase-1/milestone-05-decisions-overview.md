# P1-M5: V1 product, data, and security decisions overview

Status: Done

This milestone closes the remaining owner-dependent v1 product, data, privacy, and interface contracts. Physical-device behavior remains verification work for the implementing milestones; it does not reopen the decisions recorded here.

## Outcome

- The title algorithm, Diary Snippet schema, recording and queue behavior, iCloud commit and recovery rules, optional context, security limits, privacy presentation, icons, and accessibility contracts are approved.
- P1-M6 is deliberately limited to running each viable Cohere candidate once on each available English and Korean recording, applying the ten-minute nonsettling cutoff, and privately showing the returned text or failure. Its detailed plan lives only in its separate worktree.
- P1-M5 is exempt from lint, build, and test exit gates. Its evidence is the owner interview, the reconciled documents, and explicit downstream verification assignments.

## Completion checklist

- [x] P1-M1 research is closed and its unresolved implementation evidence is assigned to later milestones.
- [x] The title contract defines grapheme counting, bounded whole-body summarization, language validation, prompt/version provenance, truncation, and fallback.
- [x] The schema contract defines canonical identity and timestamps, paths, exact fields and stable values, serialization, optional groups, limits, validation, unknown fields, unsupported files, and legacy handling.
- [x] Recording format, locked/background capture, immediate locked finalization, pending-data protection policy, backup exclusion, restored-job quarantine, and crash recovery outcomes are approved.
- [x] Queue readiness, wait/fail classification, exact recovery copy, ten-minute settlement, reminder behavior, removal races, and readiness refresh are approved.
- [x] iCloud-only selection, transient versus confirmed permanent access loss, per-job retargeting, coordinated conflict packaging, upload proof, and staging cleanup are approved.
- [x] Parser, audio, catalog, storage, diagnostic, privacy-cover, download, artifact-integrity, and dependency-policy limits are approved.
- [x] Location and weather timing, completion banner, semantic icon brief, accessibility labels/actions, and recovery-screen placement are approved.
- [x] P1-M8, P1-M9, P1-M14, P1-M17, and P1-M19 own the remaining device and adversarial evidence without blocking this decision milestone.
- [x] Product behavior, architecture, security review, UX, contributor rules, decision inventory, changelog, and Phase 1 status agree with the owner decisions.
- [x] The owner reviewed the resulting contract and directed P1-M5 to be marked Done once all non-M6 decisions were resolved.

## Downstream verification

- P1-M8 verifies iCloud-only folder selection/creation, bookmarks, and provider identity.
- P1-M9 verifies capture, finalization, crash recovery, and Data Protection behavior while locked or backgrounded.
- P1-M14 verifies coordinated writes, paired local validation, per-file upload observation, staging retention, and conflict cleanup.
- P1-M17 verifies quarantine, incomplete/unsupported/legacy recovery, and conflict-selection interfaces.
- P1-M19 runs the complete security and privacy verification matrix.

## Validation exemption

Do not use Swift formatting, lint, build, or test commands as a P1-M5 exit gate. Documentation links, decision consistency, and owner review remain required.
