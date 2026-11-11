# Human device tests requiring evidence

Status: Active

This tracker lists physical-device scenarios that still need human observations. Record redacted results in the linked milestone evidence records. As of 2026-11-11, [M19](milestone-19-complete-v1-validation-overview.md) schedules these scenarios as one prioritized pass; M9, M15 and M16 are closed pending this evidence.

## P1-M21

- [ ] Task 4: record a synthetic diary against the selected iCloud folder and confirm Pending verification completes automatically into Main without tapping Retry Verification. Repeat with initially unavailable uploads, app departure/return, and relaunch; confirm no duplicate pair or lost staging. Record only redacted state/timing and keep M14's exact-version upload evidence separate. See the [Task 4 checklist](milestone-21-architecture-gui-enhancement-overview.md#task-4-automatically-resume-icloud-upload-verification).

## P1-M16

The [M16 connected-iPhone record](milestone-16-diary-editing-favorite-audio-replay-device-evidence.md#connected-iphone-results) now contains passing synthetic storage/recovery/maintenance, native replay, and native Apple title checks. No complete M16-D01–D11 row is closed. Use disposable English/Korean fixtures and record the following remaining observations in that record:

- **M16-D01/D02/D10:** real editor input, Korean marked-text composition, empty/long/over-limit Save, failure/discard retention, Favorite interaction, keyboard/focus, VoiceOver, Reduce Motion, largest text and physical rotation. Hosted phone control lookup failed before actions; the VoiceOver diagnostic could not be run.
- **M16-D03/D05:** real iCloud publication and separate upload proof, offline restoration, folder/account changes, external replacement and actual provider conflicts. Current phone storage tests use synthetic destination/upload ports.
- **M16-D04/D11:** physical termination/relaunch at journal, publication, completion and purge boundaries; locked-data denial, backup/restore and prior-install review. Injected filesystem faults and unlocked protection attributes are partial evidence.
- **M16-D06/D07/D08:** large/boundary/corrupt media and storage pressure, real headphone loss/interruption/media reset, capture priority, background/lock/five-minute capture and playable-partial recovery. Native replay passed alone; combined-run audio-session rejection remains unexplained.
- **M16-D09/D10:** actual background/app-switcher snapshots, editor-buffer privacy, route/folder/account departure and stale callback settlement. Synthetic rendered covers and state tests do not establish snapshot timing.

## P1-M15

M15-D01–M15-D10 remain unrun in the [M15 device evidence record](milestone-15-main-collection-diary-detail-device-evidence.md). The implementation and simulator gate pass; human evidence must still establish user-picked-folder paging/downloads/refresh, selection/account changes, provider conflicts and stalls, stored-weather attribution, full layout/VoiceOver/Reduce Motion, and app-switcher privacy. Use controlled synthetic iCloud fixtures, not the personal files supplied to establish the legacy format. Record state/count/timing observations without content or paths; earlier device gates remain open.

## P1-M11

M11-D01–M11-D10 remain unrun. Record redacted results in the [M11 device evidence record](milestone-11-apple-on-device-transcription-device-evidence.md); installation scenarios depend on resolving the documented size and storage-preflight blocker. Simulator tests do not establish real model availability, file protection, offline inference, resource use, or network behavior.

## P1-M10

The owner marked M10 done except for human tests. Record an actual backup and restore and a controlled prior-install quarantine fixture in the [M10 device evidence record](milestone-10-durable-processing-queue-device-evidence.md). Both remain pending.

## P1-M8

The owner reported these P1-M8 scenarios as passed, but the redacted observations needed to verify each result have not been supplied. Record the evidence in the [M8 device evidence record](milestone-08-first-launch-settings-icloud-device-evidence.md) using the [scenario pass criteria](milestone-08-first-launch-settings-icloud-architecture.md#test-and-evidence-strategy).

| ID | Scenario | Status | Evidence needed to close row |
|---|---|---|---|
| M8-D03 | Reject On My iPhone and installed third-party providers | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D04 | Relaunch and restart with the accepted bookmark | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D05 | Rename and move the selected iCloud folder | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D06 | Revoke and restore Files and Folders access | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D07 | Delete the folder and create a same-named replacement | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D08 | Enter airplane mode and restore connectivity | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D09 | Sign out and back into the original controlled account | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D10 | Change to a second controlled iCloud account | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D11 | Verify the inactive/background app-switcher privacy cover | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |

Use synthetic data and controlled nonpersonal accounts. Record device model, OS build, app revision, scenario ID, candidate class, applicable directory/link/ubiquity availability, iCloud-identity presence and opaque equality, bookmark stale state, scope/coordination success, typed app outcome, and whether the previous destination remained unchanged. Do not record paths, folder names, account identifiers, token or bookmark bytes, or folder contents. Simulator observations do not close these rows.

## P1-M9

These target-iPhone scenarios have not been run. Record redacted observations in the [M9 device evidence record](milestone-09-recording-capture-recovery-device-evidence.md) against the [scenario pass criteria](milestone-09-recording-capture-recovery-architecture.md#tests-and-target-phone-scenarios).

| ID | Result | Redacted observation or blocker |
|---|---|---|
| M9-D03 | Not run | Background continuity. |
| M9-D04 | Not run | Locked five-minute cutoff. |
| M9-D05 | Not run | Locked interruption and relaunch. |
| M9-D06 | Not run | Abrupt termination and decodable partials. |
| M9-D07 | Not run | Locked close and journal attributes. |
| M9-D08 | Not run | Low-space start and write exhaustion. |
| M9-D09 | Not run | Before/after-unlock reconciliation and backup attributes. |
| M9-D10 | Not run | Previously accepted folder during provider outage. |
