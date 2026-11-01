# UX GUI

Status: Active

This document defines the current interface and records owner-approved GUI behavior separately under a planned heading. Product scope is in [product-behavior.md](product-behavior.md); [UX information architecture](ux-information-architecture.md) defines containment, and [UX terms](ux-terms.md) distinguishes exact labels from concept names.

## Current interface

Only the P1-M3 launch-policy scaffold screen is implemented; the planned v1 interface below has not been built.

## Planned owner-approved behavior

- The root navigation shows five tabs, labeled exactly Main, Benefits, Calendar, Plugins, and All. Their v1 empty states read “Benefits are coming later.”, “Calendar is coming later.”, and “Plugins are coming later.” respectively.
- Main shows the full active-folder diary collection with on-demand loading and infinite scroll. A one-line notice bar at its top reports queued recordings, in-app transcription activity, or recovery attention. With multiple states, it rotates one message every 10 seconds in the order processing, queued, recovery; rotation pauses for VoiceOver or Reduce Motion. Tapping a queued or processing message opens Pending Recordings; tapping a recovery message opens the relevant recovery screen. All shows no diary snippets for now; it contains the only Settings entry plus entries to separate Pending Recordings, Failed Recordings, Incomplete Diary Snippets, and Conflicting Versions screens. A floating Record control appears on Main. The pending and recovery items themselves stay in their All destinations.
- Tab and control icons are custom bitmap images. They need accessible names and variants suitable for different sizes and system appearances. No Main Toolbar is specified.
- The Diary Snippet collection groups entries by the recording-start instant in the user's local calendar and shows an automatically generated, read-only title.
- A completed Diary Snippet saves automatically with an Apple on-device AI title summarizing the whole diary body when available, or an ellipsized first-sentence title if the model is unavailable or returns an empty or failed result. Both have a strict maximum of 30 displayed characters, including the ellipsis. AI title failure does not delay saving. Its managed diary body starts as the transcription output. There is no pre-save review step or separate original-transcript view.
- An AI title follows the current diary body's language, which can differ from the recording language after editing. A wrong-language result uses the fallback. Long bodies are summarized in parts; an AI title over 30 displayed characters is truncated locally with an ellipsis. A saved fallback title stays until the next body save, even if the model becomes ready meanwhile.
- The Settings screen offers Apple on-device and local Cohere Transcribe, shows readiness for each, and lets the user install the Cohere model. The last selected transcription method is reused for the next recording; if it is not ready, show why and offer installation or explicit method selection. Hosted Qwen controls are future work and do not appear in v1.
- If Apple on-device transcription is unavailable for a queued recording, explain why and ask the user to choose an available approved method. Do not switch methods automatically.
- While the app is open, queued recordings transcribe from oldest ready to newest ready; a waiting item does not block newer ready work. Pending and failed recordings have visible states, and a failed item offers manual retry. Both screens let the user remove an entry and its private audio after confirmation. Removing an in-flight item shows Cancelling until its work stops and removal completes.
- Pending recordings and failed recordings have separate screens, opened from All.
- A Failed Recordings entry shows the reason when transcription produced no usable words and offers manual retry; no Diary Snippet is created for that result.
- Manual transcription retry uses the method and settings current at retry time and has no fixed count limit while the recording remains.
- Stop & Transcribe is the only user control during capture; it stops and queues playable audio for automatic processing while the app is open. Recording also stops and queues automatically at five minutes. A playable partial recording queues automatically after an interruption; show the resulting pending item. An unplayable partial appears in Failed Recordings with its reason. Pause/resume and discard controls are outside v1.
- V1 requests notification permission for a local reminder on the next local day at the same local time the user left if transcription remains pending. The reminder cannot be treated as guaranteed delivery.
- If a pending recording is saved into a former active folder, show a completion notice naming that folder. If its destination is unavailable, show that the result is pending and ask the user to restore access.
- Require an iCloud folder choice before the first recording. If the original destination becomes permanently inaccessible, let the user explicitly choose a replacement for the affected pending recording.
- First launch explains and requests microphone permission for recording. If denied, the rest of the app remains usable, and Record shows a route to system Settings instead of starting capture. First launch also asks for optional location permission, and Settings offers a control for later location permission changes; location denial does not block recording.
- Recorded-audio replay offers play/pause, seeking, and elapsed and total time.
- Diary Snippet detail presents the Title and Diary body first, with Favorite beside the Title. Metadata is at the bottom and contains Audio replay plus read-only recording start date/time, duration, recording language, and available place and weather. Omit unavailable place and weather fields. Title provenance remains hidden.
- Keep title-generation origin and version details in Markdown front matter without displaying them in Diary Snippet detail. Incomplete Diary Snippets opens a flagged iCloud pair with no local repair copy, shows surviving text or playable audio read-only, explains the missing file, and offers confirmed removal. Conflicting Versions presents one version per tab when iCloud modification times are equal or missing; each tab scrolls vertically. After the user selects a version, confirm before removing the other.
- The editor changes only the diary body. Saving regenerates the title using the same AI-or-fallback policy; the title has no direct edit control. Favorite has an on/off toggle.

Remaining interaction details are in the [decision inventory](research/p1-m1-open-decisions.md). The [initial ideas](research/initial-ideas-from-owner.md) contain additional proposals that have not all been approved.

## P1-M4 design review boundaries

- Main owns the active-folder Diary Snippet collection; All owns Settings, two recording-status destinations, and two recovery destinations. A recording awaiting save or retry is distinct from a completed Diary Snippet.
- The structure in [UX information architecture](ux-information-architecture.md) does not decide the visual style of navigation. Icon art, accessibility names, and completion notice presentation need review before implementation.

