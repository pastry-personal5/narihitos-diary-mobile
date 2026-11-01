# UX GUI

Status: Active

This document defines the current interface and records owner-approved GUI behavior separately under a planned heading. Product scope is in [product-behavior.md](product-behavior.md); component vocabulary is in [ux-terms.md](ux-terms.md).

## Current interface

No app interface has been implemented yet.

## Planned owner-approved behavior

- The root navigation shows five tabs, labeled exactly Main, Benefits, Calendar, Plugins, and All. Benefits, Calendar, and Plugins have explanatory empty states in v1.
- Tab and control icons are custom bitmap images. They need accessible names and variants suitable for different sizes and system appearances.
- The asset list groups snippets by the user's local creation date. The first line of diary text supplies an editable title.
- The Settings screen contains transcription choices and an Apple on-device readiness check. The last selected transcription method is reused for the next recording.
- While the app is open, queued recordings transcribe automatically from oldest to newest. Pending and failed recordings have visible states, and a failed item offers manual retry.
- V1 requests notification permission for a local reminder about pending transcription after the user leaves the app. The reminder cannot be treated as guaranteed delivery.
- If a pending recording is saved into a former active folder, show a completion notice naming that folder. If its destination is unavailable, show that the result is pending and ask the user to restore access.

Remaining interaction details, including exact screen containment, recording interruption controls, replay controls, and metadata presentation, are in the [decision inventory](research/p1-m1-open-decisions.md). The [initial ideas](research/initial-ideas-from-owner.md) contain additional proposals that have not all been approved.

