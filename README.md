# Narihito's Diary Mobile

An iPhone app that creates personal data assets from other multimodal data.

V1 plans offline transcription with Apple on-device speech and an on-device Cohere Transcribe model. The selected Cohere integration direction uses the pinned Q4_K_M model with `transcribe.cpp` and Metal; production integration remains in progress. Hosted Qwen transcription is planned for future work.

The first-time experience requests microphone access for recording and optional When In Use location access. Other parts of the app remain available if either is denied. Before recording, the user selects an iCloud Drive folder; the current boundary fails closed unless the folder passes iCloud metadata and account-identity checks, with target-device provider verification still in progress.

Each recording becomes a Markdown diary entry paired with its audio. Transcription initializes the diary text, and later edits replace that text; the app does not keep a separate original transcript. A read-only title summarizes the diary on device when Apple's model is available, with a shortened first-sentence fallback.

## Development

The app uses a flat journal icon; its editable vector source is in `assets/app-icon/`.

The SwiftUI app currently includes the five-root navigation shell, first-launch permission flow, Settings foundation, persistent iCloud-folder selection boundary, recording and local recovery, and a durable foreground processing queue. Main has separate blue `en` and purple `ko` recording buttons at the bottom right. Each starts capture in its indicated language; Stop & Transcribe stores a pending local recording. Pending work is bound to the current installation, and restored work requires explicit Resume or Remove. Settings supports explicit Apple method selection and system-model installation progress. Cohere model installation, readiness, explicit selection, and local transcription are being integrated; their simulator and target-iPhone validation remains open. Verified transcription now becomes a protected local diary draft; the iCloud save path is being completed and retains private staging while per-file upload proof is missing. A verified save to a folder that is no longer active shows a dismissible six-second completion banner. Removing a pending recording also cleans its identified private conflict copies. Diary browsing and full incomplete/conflict recovery screens remain later work. Target-iPhone lock, background, interruption, file-protection, and backup/restore trials remain open. With Xcode 27.2 or later and XcodeGen installed, run `make generate` to create the Xcode project, `make build` to generate and build it for the iOS Simulator, or `make open` to generate and open it in Xcode. Generation selects the first development team available in Xcode without committing its Team ID. Use `TEST_DESTINATION='platform=iOS Simulator,name=<available iPhone>' scripts/validate.sh` for concise generation, lint, build, and test results. The app requires iOS 27.0.1 or later.

## License

Licensed under the Apache-2.0 license. See [LICENSE](LICENSE).

## Contributing

Contributors and AI agents: see [AGENTS.md](AGENTS.md) and [docs/contribution-guide.md](docs/contribution-guide.md).
