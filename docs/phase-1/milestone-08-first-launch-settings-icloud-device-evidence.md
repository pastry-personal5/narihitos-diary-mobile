# P1-M8: iCloud destination device evidence

Status: Active

The owner reported on 2026-11-02 that the M8 by-human test run was done and passed. This is an overall owner attestation; the scenario-level redacted evidence fields required below have not yet been supplied, so individual rows remain open for evidence entry.

## Evidence rules

Use only synthetic data and controlled nonpersonal accounts. Record device model, OS build, app revision, scenario ID, candidate class, directory/link/ubiquity Boolean availability, iCloud-identity presence and opaque equality, bookmark stale state, scope/coordination success, typed app outcome, and whether the previous destination remained unchanged. Never record a path, folder name, account identifier, token or bookmark bytes, or folder contents.

## Scenario matrix

| ID | Scenario | Status | Evidence needed to close row |
|---|---|---|---|
| M8-D01 | Select an existing iCloud Drive folder | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D02 | Create and select a folder in Files | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D03 | Reject On My iPhone and installed third-party providers | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D04 | Relaunch and restart with the accepted bookmark | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D05 | Rename and move the selected iCloud folder | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D06 | Revoke and restore Files and Folders access | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D07 | Delete the folder and create a same-named replacement | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D08 | Enter airplane mode and restore connectivity | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D09 | Sign out and back into the original controlled account | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D10 | Change to a second controlled iCloud account | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |
| M8-D11 | Verify the inactive/background app-switcher privacy cover | Owner-reported PASS; unverified | Redacted scenario observations and device/app metadata. |

Do not change this document to Active or complete a row from simulator observations. If the positive-iCloud predicate fails to distinguish any available non-iCloud provider, stop and request owner review instead of weakening admission.
