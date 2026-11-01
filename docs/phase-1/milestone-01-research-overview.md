# P1-M1: Research overview

Status: Active

Research Qwen-based AI audio transcription for diary recordings and document findings that can inform software architecture.

## Scope

- Investigate Qwen-based transcription options for recorded audio, including support for Korean and English and compatibility with the app's recording format.
- Document deployment and integration options, quality evaluation, privacy, costs, licensing, and relevant constraints, with sources and unresolved questions.
- Research the following items derived from the [owner’s initial ideas](../research/initial-ideas-from-owner.md), treating them as proposed requirements to reconcile with the current product and UX docs:
  - Apple on-device speech recognition for en-US and ko-KR, including iOS availability, offline capability, permissions, quality, and how it compares with Qwen and service-provider/model/prompt combinations.
  - Configuring transcription choices as provider, model, and optional prompt: what users can select, what must be stored with each asset, and the credential, privacy, and fallback implications of service-based options.
  - iPhone recording and playback of `.m4a`: codec and format choices, microphone permissions, interruptions, level metering, duration, the en-US/ko-KR recording language choice, and compatibility with each transcription option.
  - A transcription queue for recorded audio: background execution constraints, persistence, ordering, retries, connectivity, failure recovery, and creating a diary snippet after transcription.
  - Turning a transcript into diary snippet text: whether it is copied or transformed, how title and language are determined, what happens when transcription or text creation fails, and how users review or edit the result.
  - Diary snippet assets: paired Markdown and audio files, the owner’s example under `tmp/assets/example-on-2026-11-01`, UTC directory and file naming (including `.assets` audio directories) versus local display, the Markdown front-matter schema (including required and optional fields), title and preview extraction, edits and `updated_at`, and keeping audio and transcription provenance associated with the text.
  - User-selected local or iCloud folders: iOS document access, permissions, persistence, synchronization, conflicts, and changing the asset location without losing data.
  - Optional weather and location metadata: Apple Weather and location APIs, permissions, availability, accuracy, costs or service limits, and behavior when data is unavailable.
  - Target-device and development feasibility: iPhone 17 Pro Max and stated iOS/Xcode versions, suitable simulator fallback, and options for automatically generating an Xcode project; distinguish verified availability from the owner’s proposed versions.
  - UI feasibility and accessibility for the proposed five-tab navigation (including empty v1.0.0 tabs), date-grouped newest-first asset list, asset detail and text editing, recording controls, audio replay, folder settings, automatic light/dark appearance, and bitmap icons; reconcile terminology and behavior with the existing UX documents.

## Out of scope

- Selecting or implementing a transcription provider or model.
- Implementing the app or changing dependencies and build tools.

## Completion checklist

- [x] Document Qwen-based audio transcription options and their suitability for diary recordings, with sources: [research findings](../research/p1-m1-qwen-transcription.md).
- [x] Record integration, language and audio-format support, privacy, cost, licensing, and evaluation considerations, including unknowns: [research findings](../research/p1-m1-qwen-transcription.md).
- [x] Summarize findings and questions for P1-M2 without treating a recommendation as an approved decision: [research findings](../research/p1-m1-qwen-transcription.md).
- [x] Document sourced findings and unresolved questions for the owner-derived research items above, including feasibility and constraints, with links to evidence: [open-decision inventory](../research/p1-m1-open-decisions.md).
- [x] Compare iPhone recording codec, sample rate, channel, and bitrate choices with Qwen input requirements; document a provisional quality/cost recommendation: [audio-format research](../research/p1-m1-audio-format.md).
- [x] Compare relevant Qwen ASR models, capabilities, language support, and Singapore/Beijing list prices with a sourced provisional recommendation: [Qwen research](../research/p1-m1-qwen-transcription.md).
- [x] Update affected documentation and milestone status with acceptance evidence: the [Phase 1 plan](phase-1.md) marks P1-M1 Done, the [documentation index](../README.md) links the completed research, and the [Phase 1 changelog](changelog.md) records the handoff to P1-M2.
- [x] Apply the owner's exemption from all P1-M1 build, lint, and test gates; see the [Phase 1 changelog](changelog.md). Earlier exploratory checks do not affect completion.
