# Human device tests requiring evidence

Status: Active

This tracker lists physical-device scenarios that still need human observations. Record redacted results in the linked milestone evidence records.

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
