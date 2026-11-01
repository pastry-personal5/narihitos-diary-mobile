# P1-M8: iCloud destination device evidence

Status: Blocked

This record is reserved for redacted target-iPhone evidence for P1-M8. No scenario is complete: the current implementation session has no controlled physical iPhone, controlled iCloud accounts, installed third-party File Provider, or permission to change device account and Files access state.

## Evidence rules

Use only synthetic data and controlled nonpersonal accounts. Record device model, OS build, app revision, scenario ID, candidate class, directory/link/ubiquity Boolean availability, iCloud-identity presence and opaque equality, bookmark stale state, scope/coordination success, typed app outcome, and whether the previous destination remained unchanged. Never record a path, folder name, account identifier, token or bookmark bytes, or folder contents.

## Scenario matrix

| ID | Scenario | Status | Current blocker |
|---|---|---|---|
| M8-D01 | Select an existing iCloud Drive folder | Not run | Controlled target iPhone and iCloud account unavailable. |
| M8-D02 | Create and select a folder in Files | Not run | Controlled target iPhone and iCloud account unavailable. |
| M8-D03 | Reject On My iPhone and installed third-party providers | Not run | Target iPhone and third-party File Provider unavailable. |
| M8-D04 | Relaunch and restart with the accepted bookmark | Not run | Target iPhone and accepted synthetic destination unavailable. |
| M8-D05 | Rename and move the selected iCloud folder | Not run | Target iPhone and accepted synthetic destination unavailable. |
| M8-D06 | Revoke and restore Files and Folders access | Not run | Required physical-device system control unavailable. |
| M8-D07 | Delete the folder and create a same-named replacement | Not run | Target iPhone and accepted synthetic destination unavailable. |
| M8-D08 | Enter airplane mode and restore connectivity | Not run | Target iPhone unavailable. |
| M8-D09 | Sign out and back into the original controlled account | Not run | Target iPhone and controlled account unavailable. |
| M8-D10 | Change to a second controlled iCloud account | Not run | Target iPhone and second controlled account unavailable. |
| M8-D11 | Verify the inactive/background app-switcher privacy cover | Not run | Target iPhone unavailable. |

Do not change this document to Active or complete a row from simulator observations. If the positive-iCloud predicate fails to distinguish any available non-iCloud provider, stop and request owner review instead of weakening admission.
