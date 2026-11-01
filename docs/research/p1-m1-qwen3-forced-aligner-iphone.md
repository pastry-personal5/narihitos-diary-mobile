# P1-M1: Qwen3-ForcedAligner-0.6B on iPhone

Status: Active

Research checked on 2026-11-01. Qwen3-ForcedAligner-0.6B can place supplied English or Korean text on an audio timeline, but the published accuracy scores are not iPhone performance measurements. The current diary flow has no approved word-synchronized feature, so this is an optional post-transcription capability rather than a transcription method.

## What the model does

- The [official model card](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B) lists Apache-2.0, 11 alignment languages including English and Korean, and a model labeled 0.6B whose repository reports **0.9B parameters**. It accepts audio **and an existing transcript** and returns word or character start/end times. It does not recognize speech, correct words, or replace the selected ASR provider.
- The [official Qwen3-ASR implementation](https://github.com/QwenLM/Qwen3-ASR) exposes a separate forced-aligner load and timestamp option after transcription. Its reference deployment is Python/Transformers or vLLM, not an iOS SDK. The transcript sidecar approved in [product behavior](../product-behavior.md) could supply the text after a successful job; timestamp output would need a separately decided schema and UI.
- The model card's accumulated average shift (AAS) is **timestamp error in milliseconds**, not processing time. On its MFA-labeled data, Qwen reports English 37.5 ms and Korean 37.2 ms for raw clips, and English 58.6 ms and Korean 42.2 ms for concatenated 300-second clips. These are reference-corpus accuracy figures; they do not establish diary accuracy or five-minute runtime on an iPhone. [Source](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B#evaluation)

## Native runtime evidence

| Path | Published state | Five-minute constraint |
|---|---|---|
| Official Qwen | Python package and vLLM examples; no official iOS runtime documented. [Source](https://github.com/QwenLM/Qwen3-ASR) | Qwen evaluates concatenated 300-second audio, but this does not verify a phone integration. |
| `speech-swift` MLX | Third-party Swift implementation exposes `Qwen3ForcedAligner.alignLong`; its 4-bit bundle is about 979 MB. It uses Korean word segmentation through Apple's `NLTokenizer`. [Source](https://github.com/soniqo/speech-swift/blob/main/docs/inference/forced-aligner.md) | The implementer observed timestamp collapse after about 270 seconds and added a trailing-section realignment path for long audio. Leading silence and language switches remain caveats. |
| `speech-swift` Core ML | Third-party `CoreMLForcedAligner` and fixed FP16/INT8 bundles are documented; INT8 is about 880 MB, FP16 about 1.7 GB. The earlier NaN conversion issue was [closed with fixed bundles](https://github.com/soniqo/speech-swift/issues/342). [Source](https://github.com/soniqo/speech-swift/blob/main/docs/inference/forced-aligner.md) | Its documented audio encoder is fixed to 30-second inputs. The shown Core ML API does not provide the MLX `alignLong` path, so a five-minute app path would need chunking, transcript splitting, and offset/stitch validation. |
| FluidAudio | Its [model catalog](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md) places Qwen3-ForcedAligner under **evaluated models not supported**. | A FluidAudio package dependency alone would not supply this aligner. |

The `speech-swift` author reports, on an **M2 Max with 64 GB**, a warm 20-second clip at about 365 ms with MLX 4-bit; Core ML INT8 has reported real-time factor 0.014 and peak process RSS 697 MB, versus FP16 factor 0.015 and 1,071 MB. The latter figures are debug-build medians of three warm runs. These are Mac measurements, not iPhone 17 Pro Max latency, memory, battery, or thermal results. [Source](https://github.com/soniqo/speech-swift/blob/main/docs/inference/forced-aligner.md#performance-m2-max-64-gb)

## Relevance and unresolved questions

The confirmed product stores the original transcript separately, allows editing the diary text, and replays audio, but [planned GUI behavior](../ux-gui.md) does not specify word-linked seeking or highlighting. Adding alignment would add another local model and derived timing data to the queue and asset schema. If playback highlights editable diary text, it would also need a rule for stale timestamps after edits. The current transcript-copy behavior does not require alignment.

If the owner wants word-synchronized playback, test the exact runtime and conversion on a physical iPhone 17 Pro Max with 30-second and five-minute `.m4a` diary clips in en-US and ko-KR. Measure cold download/load, model storage, end-to-end alignment latency, peak app memory, battery and temperature, timestamp error against hand-labeled words, leading/trailing silence, edits, and chunk boundaries. Keep alignment failure separate from transcription or asset-creation failure until its product role is decided. No target-phone result was found in the official model card or the native implementation's published benchmark.
