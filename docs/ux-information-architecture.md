# UX information architecture

Status: Active

The Standard Layout is the approved conceptual containment and navigation model for v1. It identifies where content and recovery paths live; [UX GUI](ux-gui.md) records behavior, while [UX terms](ux-terms.md) distinguishes exact labels from concept names.

## Root and destinations

```text
Root tabs (ordered)
├─ Main
│  ├─ One-line notice bar (top: queued, processing, or recovery state)
│  ├─ Active-folder Diary Snippet collection (paged, local-date groups)
│  │  └─ Diary Snippet detail
│  │     ├─ Title + Favorite
│  │     ├─ Diary body → Diary editor
│  │     └─ Metadata (bottom) → Audio replay + read-only details
│  └─ Floating Record → recording path → Stop & Transcribe
├─ Benefits → “Benefits are coming later.”
├─ Calendar → “Calendar is coming later.”
├─ Plugins → “Plugins are coming later.”
└─ All (no Diary Snippet collection)
   ├─ Pending Recordings → pending recording entries and actions
   ├─ Failed Recordings → failed recording entries and actions
   ├─ Incomplete Diary Snippets → flagged pairs and confirmed removal
   ├─ Conflicting Versions → open both versions and choose one
   └─ Top-right Settings icon button
      ├─ Transcription → model selection, readiness and installation
      ├─ Active Folder and Location
      └─ Danger Zone
         ├─ Purge Active Folder Contents → separate inline confirmation
         └─ Purge Internal Staging → separate inline confirmation
```

Arrows indicate destinations or actions, not an approved navigation presentation or exact screen heading. First-launch permission and folder-selection steps are prerequisites to recording, not extra root tabs. Record must explain microphone denial and route to system Settings for recovery; folder selection is required before first capture.

## Collection and item boundaries

- Main lists the full collection in the **active folder** with on-demand paging and infinite scroll. Group entries by the recording-start instant in the user's local calendar. Completion into a former active folder triggers a notice naming that folder; the new item does not appear in Main until that folder becomes active.
- All is a utility and recovery hub in v1. It has no Diary Snippet snippets or duplicate collection. A top-right icon-only `Settings` button opens Settings; the former bottom Settings menu item is not present. Pending Recordings, Failed Recordings, Incomplete Diary Snippets, and Conflicting Versions are separate destinations reached from All. Main's one-line notice bar sits above its collection and can report queued recordings, transcription running while the app is open, or recovery items. It shows one message at a time, rotating every 10 seconds in the order processing, queued, recovery. Rotation pauses for VoiceOver or Reduce Motion. A queued or processing notice opens Pending Recordings; a recovery message opens its relevant recovery screen. The pending and recovery items remain in their All destinations.
- A **recording** remains pending or failed until its complete Diary Snippet bundle is verified. A pending item can contain a locally prepared draft while its destination is unavailable. A failed item retains audio and an entry-level reason. These entries are not saved Diary Snippets.
- Recording removal confirmation belongs inside the selected Pending/Failed Recordings entry: its context, confirmation question, Remove Recording, and Cancel remain in the list screen. It does not open an overlay dialog or a new destination.
- Normal Diary Snippet detail puts Title and Diary body before bottom Metadata. Favorite sits beside Title. Metadata contains Audio replay plus read-only recording start date/time, duration, recording language, and available place and weather. Omit unavailable place and weather rather than showing empty fields. The editor changes only Diary body; saving regenerates Title. Legacy pairs open read-only without file changes.
- An incomplete Diary Snippet without a repair copy appears in Incomplete Diary Snippets with surviving text or playable audio read-only, a missing-file explanation, and confirmed removal. A conflict pair appears in Conflicting Versions with one version per tab. Both tabs scroll vertically; after the user chooses one, confirmation is required before removing the other version.

## Cross-cutting flows

| Starting point | Destination or outcome | Approved boundary |
|---|---|---|
| First launch | Permission explanations and requests | Microphone denial leaves non-recording areas usable; location is optional. |
| Main Record | Recording path | Capture requires microphone permission and a selected iCloud destination. Stop & Transcribe is the only user control during capture. Using it, reaching the five-minute limit, or an interruption sends playable audio to Pending Recordings; unplayable partial audio appears in Failed Recordings. |
| All → Pending Recordings | Recording state and available recovery | Method choice, installation, destination restoration or explicit replacement are contextual actions; a waiting item does not block later ready work. |
| All → Failed Recordings | Reason, manual retry, or confirmed removal | Retry uses current Settings while audio remains. Confirmed removal includes private audio and invalidates in-flight work; an in-flight item shows Cancelling until work stops and removal completes. |
| All → Incomplete Diary Snippets | Inspect surviving content or confirm removal | Text or playable audio opens read-only; explain the missing file. |
| All → Conflicting Versions | Inspect vertically scrollable version tabs and choose one | Do not silently choose when iCloud times are equal or missing. Confirm before removing the unchosen version. |
| Main → Diary Snippet detail | Read, edit body, Favorite, replay | Title is read-only. Metadata is below the body. |
| All → Settings | Method readiness and selection, model installation, location control, Danger Zone | No hosted Qwen controls in v1. |
| Settings → Danger Zone | Separately confirmed folder-content or internal-staging purge | Require idle app work; folder purge also requires staging to finish (completed queue history is allowed). Preserve each scope's exclusions. An interrupted purge pauses processing until an explicit retry. |

## P1-M5 decisions

P1-M5 approved the non-tab headings, semantic bitmap-icon brief, accessibility names and values, completion banner, and recovery placement without changing this containment model. Detailed visual styling and bitmap production belong to the implementing UI milestones. No Main Toolbar is specified. See the [approved decision contracts](phase-1/milestone-05-decisions-architecture.md#context-and-interface-contract).
