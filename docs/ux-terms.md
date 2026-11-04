# UX terms

Status: Active

This is the canonical vocabulary for approved v1 navigation and diary work. An **exact label** is approved user-facing text; a **concept term** names a thing consistently in designs and code but does not approve its final on-screen copy. Use the mapped code-facing name when that thing is represented in code.

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
| Metadata | metadata | Bottom detail section containing Audio replay and read-only recording details. |
| Audio replay | audioReplay | Playback inside Metadata, with play/pause, seek, elapsed time, and total time. |
| Diary editor | diaryEditor | Body-only editing destination; it does not edit Title. |
| Pending recording | pendingRecording | Retained recording waiting for method readiness, processing, destination access, or save. |
| Failed recording | failedRecording | Retained recording whose attempt failed or whose interrupted audio is unplayable. |
| Incomplete Diary Snippet | incompleteDiarySnippet | Flagged Markdown/audio pair with no repair copy, whose surviving content opens read-only. |
| Conflict pair | conflictPair | Two versions shown in separate tabs when iCloud modification times are equal or missing. Each tab scrolls vertically. |
| Main notice bar | mainNoticeBar | One-line bar at the top of Main for queued recordings, in-app transcription, and recovery attention. |
| Cancelling | cancelling | Visible state after confirmed removal of an in-flight recording, until its work stops and removal completes. |

## Naming rules and open copy

- Use **Diary Snippet** for finished v1 content, **recording** for queued audio, and **diary body** for editable text. There is no second retained transcript document.
- Use **Pending Recordings** and **Failed Recordings** for distinct destinations. A waiting job is pending even when its model or folder is unavailable; an unsuccessful attempt is failed.
- Use **active folder** for Main's collection scope and **recording destination** for an individual recording's save target. Switching the active folder does not move existing work.
- Use **Incomplete Diary Snippets** and **Conflicting Versions** for two separate All recovery destinations. Main's notice bar can call attention to them without listing their items; tapping a recovery message opens the relevant recovery screen.
- Main notice presentation, rotation, and routing follow [UX GUI](ux-gui.md#planned-owner-approved-behavior).
- The exact v1 empty-state messages are: Benefits — “Benefits are coming later.”; Calendar — “Calendar is coming later.”; Plugins — “Plugins are coming later.”
- Follow the [P1-M5 interface contract](phase-1/milestone-05-decisions-architecture.md#context-and-interface-contract) for custom bitmap icons, headings, accessibility, and queue/recovery copy. No Main Toolbar is specified; unapproved copy or artwork remains open.
