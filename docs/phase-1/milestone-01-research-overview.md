# P1-M1: Research overview

Status: Active

Research Qwen-based AI audio transcription for diary recordings and document findings that can inform software architecture.

## Scope

- Investigate Qwen-based transcription options for recorded audio, including support for Korean and English and compatibility with the app's recording format.
- Document deployment and integration options, quality evaluation, privacy, costs, licensing, and relevant constraints, with sources and unresolved questions.
- Research the following items derived from the [owner’s initial ideas](../research/initial-ideas-from-owner.md), treating them as proposed requirements to reconcile with the current product and UX docs:
  - Apple on-device speech recognition for en-US and ko-KR, including iOS availability, offline capability, permissions, quality, and how it compares with Qwen and service-provider/model/prompt combinations.
  - iPhone recording and playback of `.m4a`: codec and format choices, microphone permissions, interruptions, level metering, duration, and compatibility with each transcription option.
  - A transcription queue for recorded audio: background execution constraints, persistence, ordering, retries, connectivity, failure recovery, and creating a diary snippet after transcription.
  - Diary snippet assets: paired Markdown and audio files, the owner’s example under `tmp/assets/example-on-2026-11-01`, UTC naming versus local display, front-matter metadata, edits, and preservation of transcription model and prompt provenance.
  - User-selected local or iCloud folders: iOS document access, permissions, persistence, synchronization, conflicts, and changing the asset location without losing data.
  - Optional weather and location metadata: Apple Weather and location APIs, permissions, availability, accuracy, costs or service limits, and behavior when data is unavailable.
  - Target-device and development feasibility: iPhone 17 Pro Max and stated iOS/Xcode versions, suitable simulator fallback, and options for automatically generating an Xcode project; distinguish verified availability from the owner’s proposed versions.
  - UI feasibility and accessibility for the proposed navigation, asset list and detail, recording controls, audio replay, settings, automatic light/dark appearance, and bitmap icons; reconcile terminology and behavior with the existing UX documents.

## Out of scope

- Selecting or implementing a transcription provider or model.
- Implementing the app or changing dependencies and build tools.

## Completion checklist

- [x] Document Qwen-based audio transcription options and their suitability for diary recordings, with sources: [research findings](../research/p1-m1-qwen-transcription.md).
- [x] Record integration, language and audio-format support, privacy, cost, licensing, and evaluation considerations, including unknowns: [research findings](../research/p1-m1-qwen-transcription.md).
- [x] Summarize findings and questions for P1-M2 without treating a recommendation as an approved decision: [research findings](../research/p1-m1-qwen-transcription.md).
- [ ] Document sourced findings and unresolved questions for the owner-derived research items above, including feasibility and constraints, with links to evidence.
- [ ] Update affected documentation and milestone status with acceptance evidence; milestone remains active until its expanded research and gate are complete.
- [x] Run `swift-format lint --strict --recursive .` — passed on 2026-11-01.
- [ ] Run `swiftlint lint --strict` — blocked on 2026-11-01: no lintable Swift files exist.
- [ ] Run `TBD: xcodebuild test with the generated project, scheme, and simulator` — blocked on 2026-11-01: no Xcode project or scheme exists; simulator services were also unavailable.
