# UX GUI

Status: Active

This document defines the current interface and records owner-approved GUI behavior separately under a planned heading. Product scope is in [product-behavior.md](product-behavior.md); component vocabulary is in [ux-terms.md](ux-terms.md).

## Current interface

No app interface has been implemented yet.

## Planned owner-approved behavior

- The root navigation shows five tabs, labeled exactly Main, Benefits, Calendar, Plugins, and All. Benefits, Calendar, and Plugins have explanatory empty states in v1.
- Main shows the full active-folder diary collection with on-demand loading and infinite scroll. All shows no diary snippets for now; it contains the only Settings entry plus entries to separate Pending Recordings and Failed Recordings screens. A floating Record control appears on Main.
- Tab and control icons are custom bitmap images. They need accessible names and variants suitable for different sizes and system appearances.
- The asset list groups snippets by the recording-start instant in the user's local calendar. The first line of diary text supplies an automatically generated, read-only title.
- A completed asset saves automatically with a locally shortened first-sentence title above an unchanged transcript copy. There is no pre-save review step. A diary-text creation failure stays pending with a manual retry action.
- The Settings screen contains transcription choices and an Apple on-device readiness check. The last selected transcription method is reused for the next recording.
- Settings lets the user revoke Qwen upload consent, remove the saved API key, and set a monthly Qwen budget. Key removal immediately fails pending Qwen jobs while preserving their recordings.
- The Qwen budget covers this app's estimated monthly usage; a request that would exceed the remaining budget waits for user action or the next budget period.
- If Apple on-device transcription is unavailable for a queued recording, explain why and ask the user to choose an available approved method. Do not switch methods automatically.
- While the app is open, queued recordings transcribe automatically from oldest to newest. Pending and failed recordings have visible states, and a failed item offers manual retry.
- Pending recordings and failed recordings have separate screens, opened from All.
- A Failed Recordings entry shows the reason when transcription produced no usable words and offers manual retry; no asset is created for that result.
- Manual transcription retry uses the method and settings current at retry time and has no fixed count limit while the recording remains.
- Recording stops and queues automatically at five minutes. A playable partial recording also queues automatically after an interruption; show the resulting pending item.
- V1 requests notification permission for a local reminder on the next local day at the same local time the user left if transcription remains pending. The reminder cannot be treated as guaranteed delivery.
- If a pending recording is saved into a former active folder, show a completion notice naming that folder. If its destination is unavailable, show that the result is pending and ask the user to restore access.
- Require an iCloud folder choice before the first recording. If the original destination becomes permanently inaccessible, let the user explicitly choose a replacement for the affected pending recording.
- First launch asks for optional location permission, and Settings offers a control for later permission changes. A denial does not block recording.
- Recorded-audio replay offers play/pause, seeking, and elapsed and total time.
- Asset detail presents the title and diary text first, with Favorite beside the title. Metadata is at the bottom and contains the audio replay entry; other metadata controls remain undecided.
- The editor changes only the diary body. Saving regenerates the title from the edited body's first sentence; the title has no direct edit control. Favorite has an on/off toggle.

Remaining interaction details, including other detail metadata controls and recording interruption controls, are in the [decision inventory](research/p1-m1-open-decisions.md). The [initial ideas](research/initial-ideas-from-owner.md) contain additional proposals that have not all been approved.

