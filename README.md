# Narihito's Diary Mobile

Status: Active

An iPhone app that turns recordings into personal Markdown diaries paired with their audio in a user-selected iCloud Drive folder. It uses Swift and SwiftUI and requires iOS 27.0.1 or later.

## Using the app

First launch requests microphone access and optional location access. Denial leaves non-recording features usable. Before recording, select an iCloud folder, tap Open, then confirm Use Folder in the Readable Files notice.

Main shows the active folder's diary collection. Its English and Korean recording buttons start capture with the corresponding language hint; Stop & Transcribe queues the audio for automatic processing while the app is open. Capture also stops automatically at five minutes.

All → Settings → Transcription offers None, Apple Local, Cohere Q4, and Cohere Q5. Transcription runs locally after the selected method is ready; the app never switches methods automatically. Q4 and Q5 have separate pinned installations. Q5 inference currently waits for device certification; see the [M20 Q5 evidence](docs/phase-1/milestone-20-enhancements-fixes-refactoring-overview.md#task-12-cohere-q5-installation-terminates-near-completion). Hosted Qwen is future work.

Transcription initializes one diary body and a read-only title, using Apple's on-device model when available or a shortened first sentence. Supported diaries offer body editing with title regeneration, Favorite, and audio replay inside Metadata. Legacy text stays read-only, with replay for safely validated audio.

Pending and Failed Recordings are separate destinations in All. Retry uses current Settings; Remove opens inline Remove Recording/Cancel confirmation. Diary detail has a separate Delete Diary Snippet action below Metadata for permanently deleting its verified text/audio pair after confirmation.

Settings → Danger Zone separately confirms purging all active-folder contents, including non-app files, or internal staging, including pending audio and unsaved drafts. Purges require idle app work; folder purge also requires staging to finish or be purged separately. An interrupted purge pauses recording and processing until explicitly retried. See the [purge contract](docs/product-behavior.md#confirmed-v1-behavior) for scope and exclusions.

## Implementation and known issues

The app is under active development. Full incomplete/conflict recovery flows and recording-time context/reminders remain planned; physical-device and iCloud evidence remains open across several milestones. The [Phase 1 plan](docs/phase-1/phase-1.md) tracks implementation status, and the [human-test tracker](docs/phase-1/by-human-test-required.md) tracks outstanding device scenarios.

Repair details and validation evidence live in the [M20 task checklists](docs/phase-1/milestone-20-enhancements-fixes-refactoring-overview.md). For a retained Cohere Q4 recording blocked by a local-storage message, reopen the updated app, keep Q4 selected, and use Retry in Failed Recordings; see [Task 20](docs/phase-1/milestone-20-enhancements-fixes-refactoring-overview.md#task-20-installed-cohere-q4-blocked-by-local-storage-pause). Editing, Favorite, and replay evidence is recorded in [M16](docs/phase-1/milestone-16-diary-editing-favorite-audio-replay-device-evidence.md).

## Development

Start with the [contribution guide](docs/contribution-guide.md) for prerequisites, build commands, simulator validation, and real-iPhone testing. Contributors and AI agents must follow [AGENTS.md](AGENTS.md). The [documentation index](docs/README.md) links product, architecture, interface, and milestone documents. The editable app-icon source is in `assets/app-icon/`.

## License

Licensed under [Apache-2.0](LICENSE).
