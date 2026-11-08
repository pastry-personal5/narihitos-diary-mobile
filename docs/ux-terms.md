# UX terms

Status: Active

This is the canonical vocabulary for approved v1 navigation and diary work. An **exact label** is approved user-facing text; a **concept term** names a thing consistently in designs and code but does not approve its final on-screen copy. Use the mapped code-facing name when that thing is represented in code. M21 catalog additions below are marked **Planned — M21** and introduce concept vocabulary only. The separate manual-writing labels describe Task 15’s creation flow.

## Exact labels

| Exact label | Code-facing name | Meaning |
|---|---|---|
| Main | main | Root tab containing the active-folder Diary Snippet collection and Record. |
| Benefits | benefits | Root tab with an explanatory empty state in v1. |
| Calendar | calendar | Root tab with an explanatory empty state in v1. |
| Plugins | plugins | Root tab with an explanatory empty state in v1. |
| All | all | Root tab containing utility and recovery entries, with no Diary Snippet list in v1. |
| Record | record | Floating Main control that opens the recording path after required permissions and folder selection. |
| Stop & Transcribe | stopAndTranscribe | Sole user control during capture; ends capture and queues playable audio. |
| Settings | settings | Destination opened by All's top-right icon-only button; method readiness, selection, model installation, and location access. |
| Pending Recordings | pendingRecordings | Separate All destination for recordings awaiting processing or save. |
| Failed Recordings | failedRecordings | Separate All destination for recordings requiring attention or manual retry. |
| Incomplete Diary Snippets | incompleteDiarySnippets | Separate All recovery destination for flagged Markdown/audio pairs without a repair copy. |
| Conflicting Versions | conflictingVersions | Separate All recovery destination for equal-time or missing-time iCloud conflicts. |
| Favorite | favorite | On/off action beside a Diary Snippet title where editing is allowed. |

The five root tab labels retain the order Main, Benefits, Calendar, Plugins, All. Other exact labels name destinations or controls, not additional tabs.

## Manual writing labels

- `Write Diary Snippet`: Main creation entry and editor heading.
- `Save` / `Cancel`: accessible names of the compact custom bitmap actions together at the editor top right.
- `Pending Diary Snippets`: All destination for accepted manual text awaiting saving or review, distinct from recording queues.
- `Keep Writing` / `Discard Changes`: inline protection for changed editor text.

## Content and workflow concepts

| Concept term | Code-facing name | Meaning |
|---|---|---|
| Diary Snippet | diarySnippet | Only approved v1 asset kind: a managed Markdown diary body with referenced audio. Use *asset* for type-neutral architecture. |
| Diary Snippet collection | diarySnippetCollection | Main's full, paged list from the active iCloud folder. A list item is a **Diary Snippet entry**. |
| Active folder | activeFolder | Currently selected iCloud folder whose Diary Snippets Main lists. |
| Recording destination | recordingDestination | Folder bound when capture begins, retained even if the active folder changes. |
| Recording | recording | Captured audio and its durable queue entry before a complete Diary Snippet is saved. |
| Diary Snippet detail | diarySnippetDetail | Screen opening a saved entry, with title and body before metadata. |
| Diary body | diaryBody | Single managed text body, initialized from transcription and replaced by user edits. |
| Title | title | Generated, read-only Diary Snippet heading; regenerated on body save. |
| Metadata | metadata | Bottom detail section below Audio containing read-only recording details. |
| Audio replay | audioReplay | Playback above Metadata, with play/pause, seek, elapsed time, and total time. |
| Diary editor | diaryEditor | Body-only editing destination; it does not edit Title. |
| Pending recording | pendingRecording | Retained recording waiting for method readiness, processing, destination access, or save. |
| Failed recording | failedRecording | Retained recording whose attempt failed or whose interrupted audio is unplayable. |
| Incomplete Diary Snippet | incompleteDiarySnippet | Flagged Markdown/audio pair with no repair copy, whose surviving content opens read-only. |
| Conflict pair | conflictPair | Two versions shown in separate tabs when iCloud modification times are equal or missing. Each tab scrolls vertically. |
| Main notice bar | mainNoticeBar | One-line bar at the top of Main for queued recordings, in-app transcription, and recovery attention. |
| Cancelling | cancelling | Visible state after confirmed removal of an in-flight recording, until its work stops and removal completes. |

## Planned M21 concepts

**Planned — M21 Main integration.** Task 10's storage foundation exists; these terms still describe interface behavior awaiting integration. Code-facing names below are vocabulary rather than declarations of types or ports. Their behavior is owned by [UX GUI](ux-gui.md#planned-m21-remembered-first-main-collection) and their containment by [UX information architecture](ux-information-architecture.md#planned-m21-collection-access-and-recovery-boundaries).

| Status | Concept term | Planned code-facing name | Meaning |
|---|---|---|---|
| **Planned — M21** | Remembered summary | rememberedSummary | Previously validated title/date/Favorite projection for the verified active-folder scope. It may be outdated and grants no current detail or action authority. It is not a pending recording. |
| **Planned — M21** | Current validated summary | currentValidatedSummary | Summary observed through current strict file validation. This observation alone does not replace action-specific checks or prove that every newer or duplicate resource has been discovered. |
| **Planned — M21** | Silent reconciliation | silentReconciliation | Active-session updates that converge the remembered list with current files without normal-progress banners, stale badges, progress titles or replacement empty spinners. Existing actionable notices and tap failures remain visible. |
| **Planned — M21** | Fresh row validation | freshRowValidation | Demand-priority check of the exact scoped resource before opening detail. Editing, Favorite, replay and deletion retain their existing additional checks. |
| **Planned — M21** | Requested collection range | requestedCollectionRange | Visible demand beginning at up to 10 summaries and increasing by 10 on continuation. Partial eligible results fill the same demand; the range is not a collection cap or proof of completed discovery. |
| **Planned — M21** | Catalog rebuild | catalogRebuild | Internal recreation of disposable remembered data from authoritative files. It is not a diary restore, retranscription, source deletion or new Settings action. |

**Planned — M21:** keep Main, Diary Snippet, Favorite and all existing destination/action labels. “Remembered”, “current validated”, “reconciling”, “SQLite” and “cache” do not become new user-facing labels, badges or screen titles through this plan. Use existing loading, unavailable and typed recovery vocabulary when user action needs an outcome. Do not describe a remembered row as verified saved/upload completion or label an empty local catalog as an empty iCloud folder.

## Naming rules and open copy

- Use **Diary Snippet** for finished v1 content, **recording** for queued audio, and **diary body** for editable text. There is no second retained transcript document.
- Use **Pending Recordings** and **Failed Recordings** for distinct destinations. A waiting job is pending even when its model or folder is unavailable; an unsuccessful attempt is failed.
- Use **active folder** for Main's collection scope and **recording destination** for an individual recording's save target. Switching the active folder does not move existing work.
- Use **Incomplete Diary Snippets** and **Conflicting Versions** for two separate All recovery destinations. Main's notice bar can call attention to them without listing their items; tapping a recovery message opens the relevant recovery screen.
- Main notice presentation, rotation, and routing follow [UX GUI](ux-gui.md#planned-owner-approved-behavior).
- The exact v1 empty-state messages are: Benefits — “Benefits are coming later.”; Calendar — “Calendar is coming later.”; Plugins — “Plugins are coming later.”
- Follow the [P1-M5 interface contract](phase-1/milestone-05-decisions-architecture.md#context-and-interface-contract) for custom bitmap icons, headings, accessibility, and queue/recovery copy. No Main Toolbar is specified; unapproved copy or artwork remains open.
