# UX information architecture

Status: Active

The Standard Layout is the approved conceptual containment and navigation model for v1. It identifies where content and recovery paths live; [UX GUI](ux-gui.md) records behavior, while [UX terms](ux-terms.md) distinguishes exact labels from concept names. M21 Tasks 10–14 additions below are explicitly marked **Planned — M21**; the root layout does not imply that those additions are implemented.

## Root and destinations

```text
Root tabs (ordered)
├─ Main
│  ├─ One-line notice bar (top: queued, processing, or recovery state)
│  ├─ Active-folder Diary Snippet collection (paged, local-date groups)
│  │  └─ Diary Snippet detail
│  │     ├─ Title + Favorite
│  │     ├─ Diary body
│  │     ├─ Edit Diary (full width) → Diary editor
│  │     ├─ Delete Diary Snippet (full width) → inline confirmation
│  │     ├─ Audio replay (recorded snippets)
│  │     └─ Metadata (recorded snippets, bottom) → read-only details
│  ├─ Write Diary Snippet → creation editor (compact top-right Cancel/Save)
│  └─ Floating Record → recording path → Stop & Transcribe
├─ Benefits → “Benefits are coming later.”
├─ Calendar → “Calendar is coming later.”
├─ Plugins → “Plugins are coming later.”
└─ All (no Diary Snippet collection)
   ├─ Pending Diary Snippets → submitted manual text awaiting save/review
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

## Manual writing destination

Main → Write Diary Snippet opens a creation editor sheet. Compact custom bitmap Cancel and Save actions are grouped at the top right. Save acknowledges an independent durable submission; All → Pending Diary Snippets owns manual save waits and review reasons, with Retry. This destination is separate from Pending/Failed Recordings. Missing destination setup uses the existing folder picker/disclosure; temporarily closing for selection retains the editor buffer in memory. Manual detail shares the diary title/body/edit/Favorite/delete structure and omits recording-only Audio/Metadata. The [manual product contract](product-behavior.md#manual-diary-snippets) owns lifecycle and persistence semantics.

## Collection and item boundaries

- Main lists the full collection in the **active folder** with on-demand paging and infinite scroll. Group entries by the recording-start instant in the user's local calendar. Completion into a former active folder triggers a notice naming that folder; the new item does not appear in Main until that folder becomes active.
- All is a utility and recovery hub in v1. It has no Diary Snippet snippets or duplicate collection. A top-right icon-only `Settings` button opens Settings; the former bottom Settings menu item is not present. Pending Recordings, Failed Recordings, Incomplete Diary Snippets, and Conflicting Versions are separate destinations reached from All. Main's one-line notice bar sits above its collection and can report queued recordings, transcription running while the app is open, or recovery items. It shows one message at a time, rotating every 10 seconds in the order processing, queued, recovery. Rotation pauses for VoiceOver or Reduce Motion. A queued or processing notice opens Pending Recordings; a recovery message opens its relevant recovery screen. The pending and recovery items remain in their All destinations.
- A **recording** remains pending or failed until its complete Diary Snippet bundle is verified. A pending item can contain a locally prepared draft while its destination is unavailable. A failed item retains audio and an entry-level reason. These entries are not saved Diary Snippets.
- Recording removal confirmation belongs inside the selected Pending/Failed Recordings entry: its context, confirmation question, Remove Recording, and Cancel remain in the list screen. It does not open an overlay dialog or a new destination.
- Normal Diary Snippet detail puts Title and Diary body before bottom Metadata. Favorite sits beside Title. Full-width Edit Diary and Delete Diary Snippet actions follow the body, in that order; Audio replay follows the actions. Metadata appears below Audio and contains read-only recording start date/time, duration, recording language, and available place and weather. Omit unavailable place and weather rather than showing empty fields. The editor changes only Diary body; saving regenerates Title. Legacy pairs open read-only without file changes.
- An incomplete Diary Snippet without a repair copy appears in Incomplete Diary Snippets with surviving text or playable audio read-only, a missing-file explanation, and confirmed removal. A conflict pair appears in Conflicting Versions with one version per tab. Both tabs scroll vertically; after the user chooses one, confirmation is required before removing the other version.

## Planned M21: Collection access and recovery boundaries

**Planned — M21 Main integration.** Task 10's storage foundation exists; remembered-first navigation is not connected yet. It changes how Main obtains its initial list within the existing root hierarchy and introduces no tab, destination, checking screen or cache-management Settings item. [UX GUI](ux-gui.md#planned-m21-remembered-first-main-collection) owns the planned loading/paging behavior; [M21](phase-1/milestone-21-architecture-gui-enhancement-overview.md#task-12-remembered-first-main-presentation) owns the acceptance checklist.

| Status | Starting point | Planned destination or outcome | Containment boundary |
|---|---|---|---|
| **Planned — M21** | Launch or return to Main | Same active-folder collection, initially up to 10 remembered summaries | Show titles only after current scope/access and protected-data checks. Keep local-date grouping and floating Record controls. |
| **Planned — M21** | Scroll or accessible continuation | Further increments of 10 in the same collection | Partial results fill existing demand; repeated footer/viewport events cannot request unlimited history. No separate page screen. |
| **Planned — M21** | Tap a remembered entry | Fresh validation, then existing Diary Snippet detail or typed unavailable/recovery outcome | The remembered summary is a navigation hint. Detail and actions require a fresh current resource binding; no cached action or confirmation survives. |
| **Planned — M21** | Background reconciliation finds invalid, incomplete, duplicate or conflicting content | Existing unavailable outcome or All recovery destination according to current observation | Main notices retain existing routes. Do not create a second recovery collection or treat cached counts as complete current evidence. |
| **Planned — M21** | Account/folder change, access loss or protection loss | Existing privacy/unavailable/restore behavior | Clear disallowed remembered titles before another scope can appear. Scene departure retains the existing privacy cover. |
| **Planned — M21** | Empty/rebuilt local catalog or projection failure | Existing cold-loading path or strict file-catalog fallback in Main | An empty projection does not mean an empty source folder. Internal reset/rebuild has no new user-facing destination. |
| **Planned — M21** | Confirmed Danger Zone purge or interrupted purge restart | Existing Danger Zone maintenance/retry flow, then fresh collection discovery | Discard old remembered data under the durable maintenance barrier. Staging purge preserves committed iCloud diaries, which may reappear after fresh discovery; folder purge cannot reuse old rows. |

**Planned — M21:** remembered-versus-current status is internal presentation state, not a new asset kind, saved state, destination or visible badge. Pending/Failed Recordings continue to own unfinished recording work; an outdated remembered row is not a pending recording. Main keeps the full active-folder collection with silent warm updates, while All retains Settings and its four recovery destinations. The prototype does not change which folder owns an in-flight recording or move a former-folder save into the current list.

## Cross-cutting flows

| Starting point | Destination or outcome | Approved boundary |
|---|---|---|
| First launch | Permission explanations and requests | Microphone denial leaves non-recording areas usable; location is optional. |
| Main Record | Recording path | Capture requires microphone permission and a selected iCloud destination. Stop & Transcribe is the only user control during capture. Using it, reaching the five-minute limit, or an interruption sends playable audio to Pending Recordings; unplayable partial audio appears in Failed Recordings. |
| All → Pending Recordings | Recording state and available recovery | Method choice, installation, destination restoration or explicit replacement are contextual actions; a waiting item does not block later ready work. |
| All → Failed Recordings | Reason, manual retry, or confirmed removal | Retry uses current Settings while audio remains. Confirmed removal includes private audio and invalidates in-flight work; an in-flight item shows Cancelling until work stops and removal completes. |
| All → Incomplete Diary Snippets | Inspect surviving content or confirm removal | Text or playable audio opens read-only; explain the missing file. |
| All → Conflicting Versions | Inspect vertically scrollable version tabs and choose one | Do not silently choose when iCloud times are equal or missing. Confirm before removing the unchosen version. |
| Main → Diary Snippet detail | Read, edit body, Favorite, replay | Title is read-only. Edit Diary and Delete Diary Snippet precede Audio; Metadata follows Audio. |
| All → Settings | Method readiness and selection, model installation, location control, Danger Zone | No hosted Qwen controls in v1. |
| Settings → Danger Zone | Separately confirmed folder-content or internal-staging purge | Require idle app work; folder purge also requires staging to finish (completed queue history is allowed). Preserve each scope's exclusions. An interrupted purge pauses processing until an explicit retry. |

## P1-M5 decisions

P1-M5 approved the non-tab headings, semantic bitmap-icon brief, accessibility names and values, completion banner, and recovery placement without changing this containment model. Detailed visual styling and bitmap production belong to the implementing UI milestones. No Main Toolbar is specified. See the [approved decision contracts](phase-1/milestone-05-decisions-architecture.md#context-and-interface-contract).
