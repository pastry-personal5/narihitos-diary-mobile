# Product behavior

Status: Active

Product scope: the v1 behavior confirmed by the owner. Details still needing a decision are linked below.

## Confirmed v1 behavior

### Target and recording

- V1 targets iPhone 17 Pro Max running iOS 27.0.1 or later, without iPad support.
- A user can record up to five minutes of audio without a network connection.
- At five minutes, stop recording and queue the finalized audio automatically. If an audio interruption ends recording early, automatically queue a playable partial recording. If the partial file cannot be played, retain it in Failed Recordings and show the reason beside its entry.
- The app may keep the recording temporarily in private local storage while offline or while its iCloud destination is unavailable.
- A user provides an en-US or ko-KR recording language hint where possible. Store the user's hint with the recording, pass a corresponding value to a transcription method when supported, and save only this hint as the asset language value.

### Transcription

- V1 offers Apple on-device and Qwen transcription. Reuse the last selected method automatically; provide its settings on the Settings screen.
- The Settings screen lets a user preflight Apple on-device transcription, download a needed language model, wait for readiness, and see the reason when it is unavailable. If Apple transcription is unavailable for a queued recording, ask the user to choose among available approved methods; never switch automatically.
- A user supplies their own Qwen API key, stored securely in Keychain until removed, chooses Beijing or Singapore, and chooses among supported models with optional ASR context and relevant controls. Ask for cloud-upload consent when Qwen is enabled and remember the choice. The user can revoke consent in Settings; revocation deletes the saved key. Removing the key immediately fails pending Qwen jobs while retaining their recordings for manual recovery.
- The user sets a monthly Qwen budget for this app's estimated Qwen usage, resetting at the start of the user's local calendar month. Do not start a Qwen request if its estimated cost would exceed the remaining budget. This is an app-local estimate, not a guarantee about the provider's bill; the estimation details remain open.
- A queued recording uses the transcription method and, for Qwen, the model, region, and context selected when processing starts. Respect the saved Qwen upload-consent choice. Record the settings actually used with the result.
- Transcription runs automatically, oldest recording first, only while the app is open. Recordings and queue state survive offline periods and app closure. Request notification permission and schedule a local reminder for the next local day at the same local time the user left the app when pending work remains; show pending state in the app as well.
- After an initial transcription failure caused by a temporary network or server problem, retry up to three times. Other transcription failures do not use automatic retries. If eligible attempts fail, keep the audio in a failed queue state and offer manual retry. Do not create the diary Markdown file until transcription and diary-text creation succeed.
- A manual transcription retry uses the method and settings current when the user starts that retry. Manual retries have no fixed count limit while the recording remains; consent and budget checks still apply.
- If transcription yields no usable words, retain the audio as a failed recording, create no asset, and offer manual retry. Show the reason beside the entry in Failed Recordings.
- After transcription, shorten the transcript's first sentence locally to create a short title, then place an unchanged copy of the transcript below it as the initial diary text. Save the completed asset automatically without a pre-save review step. On later body edits, regenerate the title from the edited body's first sentence when saving. An emptied body may be saved with the read-only title "Untitled". If diary-text creation fails, keep the audio and original transcript pending for manual retry; do not create the diary Markdown file.

### Assets and metadata

- Diary Snippet is the only confirmed v1 asset type. The architecture allows other asset types later, but their behavior is not defined here.
- Show the existing Markdown/audio pairs that lack the new schema fields and transcript sidecar as read-only Diary Snippets; leave their files untouched.
- V1 stores assets in a user-selected iCloud folder. The user may select any iCloud folder or create one. Local and third-party folders are outside v1.
- Before the first recording, require the user to select or create an iCloud destination folder. If a pending recording's original folder becomes permanently inaccessible, allow the user to explicitly choose a replacement for that recording.
- Changing the selected folder leaves existing assets in the old folder. The app lists only assets in the active folder.
- Main shows the full active-folder diary collection with on-demand loading and infinite scroll. All shows no diary snippets for now. Settings opens only from All, and a floating Record control is on Main.
- Pending and failed recordings have separate screens opened from All. Asset detail shows its title and diary text first, with Favorite beside the title and the audio replay entry inside metadata at the bottom. Other metadata controls remain open.
- A recording keeps the iCloud destination folder selected when recording began, even if the active folder changes before processing finishes. If that destination is unavailable, keep the result pending and ask the user to restore access. When a result is saved into a former active folder, show a completion notice naming that folder.
- Preserve the original machine transcript as a plain UTF-8 sidecar file separate from editable diary text. Use the first line of diary text as its automatically generated, read-only title. The editor changes only the body; Favorite has a separate on/off toggle.
- Include a schema version and explicit audio and transcript filename references in the Markdown front matter. Record the effective transcription method and, where applicable, model, region, and context there as provenance.
- Set `created_at` to the instant recording started and group assets by that instant's date in the user's local calendar. Set `updated_at` when a saved text or metadata edit occurs; an iCloud sync or download alone does not change it. File and directory names remain UTC as required by [AGENTS.md](../AGENTS.md).
- Location and weather are optional, permission-based metadata describing the time of recording. Request location permission during first launch and provide a Settings control for later permission changes; denial does not block recording. When location is available, save exact latitude/longitude and a place name. If either location or recording-time weather is unavailable, create the asset and omit its unavailable front-matter fields. Do not backfill missing weather later.
- Recorded-audio replay offers play/pause, seeking, and elapsed and total time.
- For conflicting iCloud edits with comparable modification times, make the later version current automatically and discard the older version. Device clock differences can make timestamp order differ from actual edit order.
- If conflicting versions have equal or missing iCloud modification times, keep both and ask the user to resolve them. If an iCloud write leaves an incomplete Diary Snippet bundle, repair it from the retained local candidate when the app reopens.
- If saving a completed diary draft fails because iCloud access is unavailable, retain the local candidate and retry saving it automatically when access returns, without repeating transcription or text creation. Delete the private local recording and draft immediately after the complete iCloud bundle is verified.

Title-length behavior and the remaining schema, provider, and failure rules are tracked in the [P1-M1 decision inventory](research/p1-m1-open-decisions.md). Planned screen behavior is in [UX GUI](ux-gui.md).
