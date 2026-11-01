# P1-M6: Cohere physical-iPhone trial protocol

Status: Done

Run this protocol on the target iPhone to compare the Q4_K_M and Q5_K_M GGUF
candidates with the same private English and Korean diary-like recordings.

The owner closed P1-M6 after the available short-file comparison. The full
matrix below is retained as the original protocol, not as a claim that every
case was run; the [results](milestone-06-cohere-runtime-trial-results.md) list
the evidence collected and the cases explicitly closed without evidence.

## Inputs

- Target physical iPhone running iOS 27.0.1 or later.
- Q4_K_M and Q5_K_M model files from `assets/models/cohere/`.
- One consented 30-second and one five-minute recording for each of en-US and
  ko-KR, plus reviewed reference text. Do not commit these files.
- Xcode Instruments for memory and Xcode Power Profiler for energy evidence.

## Controlled conditions

Record device model/OS, trial revision, charge percentage and charging state,
Low Power Mode, screen brightness, network state, and approximate ambient
temperature. Keep them comparable across candidate runs. Let the phone return to
its nominal thermal state before each cold run.

## Run matrix

| Model | Language | Duration | Cold | Warm reload | Back to back | Cancel |
|---|---|---:|---:|---:|---:|---:|
| Q4_K_M | en | 30 s | 1 | 1 | — | — |
| Q4_K_M | en | 5 min | 1 | 1 | 2 | 1 |
| Q4_K_M | ko | 30 s | 1 | 1 | — | — |
| Q4_K_M | ko | 5 min | 1 | 1 | 2 | 1 |
| Q5_K_M | en | 30 s | 1 | 1 | — | — |
| Q5_K_M | en | 5 min | 1 | 1 | 2 | 1 |
| Q5_K_M | ko | 30 s | 1 | 1 | — | — |
| Q5_K_M | ko | 5 min | 1 | 1 | 2 | 1 |

## Per-run procedure

1. Select the model and audio, tap Inspect Inputs, and confirm the displayed
   quantization, hashes, and duration. Record language, run class, network
   condition, and optional ambient temperature.
2. Start an Instruments recording before tapping Transcribe for measured runs.
3. Wait for a settled outcome. For a cancellation probe, cancel at the protocol's
   fixed elapsed time and wait until the app reports cancellation complete.
4. Export the result JSON. Name external traces with the result ID so evidence can
   be joined without putting private content in the filename.
5. Mark any crash or jetsam termination as a failed run and retain the device log.

## Review sheet

For each settled result, record WER for English or CER for Korean, plus omissions,
repetitions, silence hallucinations, code-switch errors, punctuation/numeral
differences, and incomplete output. Compare total storage including runtime and
caches, cold/warm-reload elapsed time, phase-specific peak footprint,
available-memory low point,
Power Profiler energy impact, thermal escalation, and cancellation settlement.

Summaries may be committed only after private audio, transcripts, filenames,
hashes, result IDs, and device logs are removed. Raw exports stay outside Git.
