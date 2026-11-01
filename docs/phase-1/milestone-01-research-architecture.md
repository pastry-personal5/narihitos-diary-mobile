# P1-M1: Research approach

Status: Active

This plan describes how to gather evidence for the research milestone; it does not decide the app's architecture.

## Approach

1. Identify hosted Qwen, on-device Qwen3-ASR 0.6B/1.7B, Qwen3-ForcedAligner-0.6B, whisper.cpp-compatible local audio transcription, WhisperKit, FluidAudio, and Cohere Transcribe options and their authoritative documentation.
2. Examine language and audio-format support, deployment and integration requirements, privacy, cost, licensing, and constraints relevant to diary recordings. For local options, compare device runtime and model-conversion paths, storage, peak memory, latency, battery, and thermal behavior; separate target-phone measurements from hardware estimates and public dataset scores. Record unknowns when evidence is unavailable.
3. Describe a practical way to evaluate transcription quality and, if useful, word timing for Korean and English recordings, without assuming access to private diary data.
4. Investigate the owner-derived items in the [overview](milestone-01-research-overview.md), using the example asset where available and distinguishing proposals from existing decisions. Record platform/version availability, tradeoffs, constraints, and unanswered questions without selecting dependencies or implementing features.
5. Record sourced findings and open questions in research documents, index them, and summarize implications for P1-M2.

## Affected interfaces

No app modules or interfaces are introduced in this milestone. Findings may inform the transcription interface planned in P1-M2.
