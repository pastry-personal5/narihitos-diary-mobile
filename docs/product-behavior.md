# Product behavior

Status: Active

Product scope: the v1 behavior confirmed by the owner. Details still needing a decision are linked below.

## Confirmed v1 behavior

### Target and recording

- V1 targets iPhone 17 Pro Max running iOS 27.0.1 or later, without iPad support.
- A user can record up to five minutes of audio without a network connection.
- The app may keep the recording temporarily in private local storage while offline or while its iCloud destination is unavailable.
- A user provides an en-US or ko-KR recording language hint where possible. Store the user's hint with the recording, pass a corresponding value to a transcription method when supported, and save only this hint as the asset language value.

### Transcription

- V1 offers Apple on-device and Qwen transcription. Reuse the last selected method automatically; provide its settings on the Settings screen.
- The Settings screen lets a user preflight Apple on-device transcription, download a needed language model, wait for readiness, and see the reason when it is unavailable. Automatic fallback to Qwen has not been approved.
- A user supplies their own Qwen API key, chooses Beijing or Singapore, and chooses among supported models with optional ASR context and relevant controls. Ask for cloud-upload consent once when Qwen is enabled and remember the choice.
- A queued recording uses the transcription method and, for Qwen, the model, region, and context selected when processing starts. Respect the saved Qwen upload-consent choice. Record the settings actually used with the result.
- Transcription runs automatically, oldest recording first, only while the app is open. Recordings and queue state survive offline periods and app closure. Request notification permission to remind a user about pending transcription after leaving the app; show pending state in the app as well.
- After an initial transcription failure, retry up to three times. If those attempts fail, keep the audio in a failed queue state and offer manual retry. Do not create the diary Markdown file until transcription and diary-text creation succeed.

### Assets and metadata

- V1 stores assets in a user-selected iCloud folder. The user may select any iCloud folder or create one. Local and third-party folders are outside v1.
- Changing the selected folder leaves existing assets in the old folder. The app lists only assets in the active folder.
- A recording keeps the iCloud destination folder selected when recording began, even if the active folder changes before processing finishes. If that destination is unavailable, keep the result pending and ask the user to restore access. When a result is saved into a former active folder, show a completion notice naming that folder.
- Preserve the original machine transcript separately from editable diary text. A third sidecar file is allowed. Use the first line of diary text as its editable title.
- Group assets in the list by the user's local calendar date at creation. File and directory names remain UTC as required by [AGENTS.md](../AGENTS.md).
- Location and weather are optional, permission-based metadata describing the time of recording. If either is unavailable, create the asset without it.
- For conflicting iCloud edits, make the latest edit current automatically and discard the older conflicting version. The rule for determining “latest” still needs an architecture decision.

The initial diary text's relationship to the transcript remains undecided. Detailed schema, provider, and failure rules are tracked in the [P1-M1 decision inventory](research/p1-m1-open-decisions.md). Planned screen behavior is in [UX GUI](ux-gui.md).
