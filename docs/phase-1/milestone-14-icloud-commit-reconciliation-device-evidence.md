# P1-M14: iCloud commit and reconciliation device evidence

Status: Planned

Record redacted target-iPhone observations for the production coordinated-pair path in a user-picked iCloud Drive folder. Use synthetic Diary Snippets; do not commit content, filenames, paths, bookmarks, account identifiers, file digests, raw provider logs, or stable device identifiers.

| ID | Required observable evidence | Status |
|---|---|---|
| M14-D01 | In a positively verified user-picked iCloud folder, the original capture destination receives one canonical audio-then-Markdown pair; coordinated reopen validates both expected files and their reference. Changing Settings' active folder before save does not redirect it. | Not run |
| M14-D02 | Separate upload-success observations refer to the exact verified Markdown and audio versions. Withhold either report and show waiting while private staging remains; restore the report and durably complete, then remove owned staging. Record the observation API and method without provider tokens. | Not run |
| M14-D03 | Airplane mode, ordinary provider outage, and access revocation keep the verified private draft/audio and truthful waiting state; restored access retries the same job and asset ID without retranscription or automatic retargeting. | Not run |
| M14-D04 | Terminate after commit intent, audio write, Markdown write, pair verification, each upload report, completion persistence, and staging cleanup. Relaunch repairs only owned expected partials and converges on one complete asset or explicit recovery without premature deletion. | Not run |
| M14-D05 | Complete conflict pairs with later comparable modification time choose the later whole pair; equal/missing times retain two separate snapshots for user choice. A changed, shared, or unsafe external resource blocks overwrite and deletion; chosen-pair proof precedes cleanup. | Not run |
| M14-D06 | Confirm removal before mutation, during coordinated work, and after durable completion; exercise a destination-revision change and delayed callbacks. No stale save/repair publishes, `Cancelling` persists until relinquishment, and a completed asset is reported saved. | Not run |
| M14-D07 | A former-folder save emits the approved completion event; diagnostics, status, privacy cover, and recovery surfaces expose no synthetic diary content, audio, full path, bookmark, or provider token. A waiting save does not block newer ready work. | Not run |

For each run, record device/iOS/app revision, synthetic fixture class, destination/provider class, operation/version class, timing class, observed state, and evidence collection method. Mark Pass only after every clause in its row is observed on the production path. Simulator and fake-provider results support implementation tests but do not close these device rows. An upload report establishes the approved local completion threshold, not receipt on another device. If a user-picked iCloud folder exposes no reliable per-file success signal, leave M14-D02 and the milestone checklist open for owner review.
