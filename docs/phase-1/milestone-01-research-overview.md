# P1-M1: Research overview

Status: Active

Research transcription options for diary recordings and document findings that can inform software architecture.

## Scope

- Investigate Qwen-based transcription options for recorded audio, including support for Korean and English and compatibility with the app's recording format.
- Investigate whisper.cpp on iPhone 17 Pro Max and current whisper.cpp-compatible local models for English and Korean diary recordings, including runtime feasibility, quality evidence, model size, licensing, and input conversion.
- Investigate on-device Qwen3-ASR 0.6B and 1.7B inference on iPhone 17 Pro Max, including viable iOS runtimes and conversions, English/Korean accuracy, five-minute recording performance, peak memory, storage, battery and thermal behavior, licensing, and audio input conversion. Distinguish target-device measurements from estimates and results on other hardware.
- Investigate Qwen3-ForcedAligner-0.6B for English and Korean word timing on up-to-five-minute recordings, including its input transcript contract, iOS runtime and model availability, accuracy, latency, memory, licensing, and whether the current product needs alignment.
- Investigate the WhisperKit and FluidAudio Swift SDKs for local speech transcription on the target iPhone: supported models and languages, five-minute recording handling, input conversion, word timing, installation and offline behavior, licensing, and measured device performance.
- Investigate on-device Cohere Transcribe **ASR only** for en-US and ko-KR on iPhone 17 Pro Max, comparing Core ML, GGUF/Metal, and Swift/MLX paths, model sizes and licenses, five-minute input limits, measured quality and performance, and efficient loading, compute-unit, chunking, and failure handling. Distinguish phone measurements from Mac benchmarks and feasibility claims.
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
- [x] Record the original research completion with acceptance evidence: the [Phase 1 plan](phase-1.md) marked P1-M1 Done before reopening, the [documentation index](../README.md) links the research, and the [Phase 1 changelog](changelog.md) records the P1-M2 handoff.
- [x] Apply the owner's exemption from all P1-M1 build, lint, and test gates; see the [Phase 1 changelog](changelog.md). Earlier exploratory checks do not affect completion.
- [x] Document sourced whisper.cpp iOS integration and target-phone feasibility, distinguishing device measurements from estimates: [research findings](../research/p1-m1-whisper-cpp-iphone.md).
- [x] Compare current whisper.cpp-compatible local model candidates for en-US and ko-KR, including accuracy evidence, size, speed, licensing, and audio input needs: [research findings](../research/p1-m1-whisper-cpp-iphone.md).
- [x] Update the [open-decision inventory](../research/p1-m1-open-decisions.md) and [documentation index](../README.md) with the whisper.cpp findings, leaving P1-M1 Active for owner review.
- [x] Document sourced on-device feasibility for Qwen3-ASR 0.6B and 1.7B on iPhone 17 Pro Max, including the iOS runtime/model path and any compatibility or licensing blockers: [research findings](../research/p1-m1-qwen3-asr-iphone.md).
- [x] Compare both sizes on the same English and Korean diary-like recordings, or clearly record the absence of target-phone measurements, for transcription accuracy, five-minute latency, peak memory, storage, battery, and thermal behavior; identify what a physical-device test must measure: [research findings](../research/p1-m1-qwen3-asr-iphone.md) document the available partial benchmarks and missing target-phone comparison.
- [x] Document sourced Qwen3-ForcedAligner-0.6B capabilities, English/Korean limits, iOS feasibility, and measured versus unmeasured device costs; state where word timing would affect the current product: [research findings](../research/p1-m1-qwen3-forced-aligner-iphone.md).
- [x] Compare WhisperKit and FluidAudio Swift SDK integration, model/language coverage, licensing, input and long-form handling, offline behavior, and available iPhone 17 Pro Max performance evidence: [research findings](../research/p1-m1-swift-speech-sdks.md).
- [x] Update the [research index](../README.md) and [open-decision inventory](../research/p1-m1-open-decisions.md) with these findings while leaving unapproved runtime, model, and alignment choices open.
- [x] Document Cohere Transcribe variants and viable on-device iOS runtimes for en-US and ko-KR, including conversion sizes, licenses, input limits, and five-minute behavior: [research findings](../research/p1-m1-cohere-transcribe-iphone.md).
- [x] Record published language quality, latency, memory, battery, and thermal evidence separately by device and runtime; identify missing iPhone 17 Pro Max measurements and an efficient physical-device evaluation path: [research findings](../research/p1-m1-cohere-transcribe-iphone.md).
- [x] Update the [research index](../README.md) and [open decisions](../research/p1-m1-open-decisions.md) with the Cohere findings, keeping model and runtime choices open.
- [x] Extend the Cohere research to ASR-only iPhone deployment evidence, Swift/MLX feasibility and memory costs, compact GGUF English/Korean quality, and a practical physical-phone efficiency comparison: [research findings](../research/p1-m1-cohere-transcribe-iphone.md).
- [x] Add independent ASR app evidence for iPhone Cohere deployment and Mac Core ML working-memory cost, with clear limits on transferring either result to iPhone 17 Pro Max: [research findings](../research/p1-m1-cohere-transcribe-iphone.md).
- [ ] Owner reviews the added research and decides when to close the reopened milestone.
