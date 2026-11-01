# Narihito's Diary Mobile

An iPhone app that creates personal data assets from other multimodal data.

V1 plans offline transcription with Apple on-device speech and an on-device Cohere Transcribe model. The Cohere iPhone runtime and model download are still under evaluation. Hosted Qwen transcription is planned for future work.

The first-time experience requests microphone access for recording. Other parts of the app remain available if access is denied.

Each recording becomes a Markdown diary entry paired with its audio. Transcription initializes the diary text, and later edits replace that text; the app does not keep a separate original transcript. A read-only title summarizes the diary on device when Apple's model is available, with a shortened first-sentence fallback.

## License

Licensed under the Apache-2.0 license. See [LICENSE](LICENSE).

## Contributing

Contributors and AI agents: see [AGENTS.md](AGENTS.md) and [docs/contribution-guide.md](docs/contribution-guide.md).
