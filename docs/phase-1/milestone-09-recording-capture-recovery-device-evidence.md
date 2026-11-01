# P1-M9: Recording and capture recovery device evidence

Status: Active

This is the redacted record for the target-iPhone scenarios in the [M9 approach](milestone-09-recording-capture-recovery-architecture.md#tests-and-target-phone-scenarios). The owner performs the phone runs after the automated implementation gate. No scenario is marked as passed from simulator behavior or source inspection.

## Run metadata

| Field | Redacted observation |
|---|---|
| Device and iOS build | Not run |
| App revision | Not run |
| Controlled iCloud account and synthetic folder | Not run |
| Synthetic audio source and interruption control | Not run |
| Requested format | Mono AAC `.m4a`, 44.1 kHz, 64 kb/s |
| Protection candidates | Open audio: `completeUnlessOpen`; closed audio and journal: `completeUntilFirstUserAuthentication` |

## Scenarios

For every run, record requested and measured format, sample rate, channels, bit rate, bytes, duration, stop cause, lock/scene state, receipt outcome, backup exclusion, observed protection attributes, and relaunch result. Keep folder names, account identifiers, file paths, audio content, bookmarks, and raw logs out of this document. Mark a scenario Pass only after its required observation in the [approach matrix](milestone-09-recording-capture-recovery-architecture.md#tests-and-target-phone-scenarios) is demonstrated.

| ID | Result | Redacted observation or blocker |
|---|---|---|
| M9-D01 | Not run | Foreground stop and actual audio parameters. |
| M9-D02 | Not run | Lock during delayed settlement. |
| M9-D03 | Not run | Background continuity. |
| M9-D04 | Not run | Locked five-minute cutoff. |
| M9-D05 | Not run | Locked interruption and relaunch. |
| M9-D06 | Not run | Abrupt termination and decodable partials. |
| M9-D07 | Not run | Locked close and journal attributes. |
| M9-D08 | Not run | Low-space start and write exhaustion. |
| M9-D09 | Not run | Before/after-unlock reconciliation and backup attributes. |
| M9-D10 | Not run | Previously accepted folder during provider outage. |

## Decision gate

The protection policy and AAC writer remain candidates until these runs show that a locked recording can continue, settle immediately, and recover safely. If either mechanism fails the approved outcome, record the observation here and obtain owner review before changing it.
