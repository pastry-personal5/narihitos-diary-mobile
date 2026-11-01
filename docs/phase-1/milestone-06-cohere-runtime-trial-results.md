# P1-M6: Cohere runtime trial results

Status: Done

The owner closed the physical-iPhone comparison after short English and Korean
runs established a viable local configuration. This summary deliberately omits
private audio names, transcripts, hashes, result identifiers, and device logs.

## Decision

Use `transcribe.cpp` with its Metal backend and the runtime-publisher's
`cohere-transcribe-03-2026-Q4_K_M.gguf` as the P1-M12 implementation direction.
Pin the runtime, model URL, byte count, and digest in the app-bundled trusted
manifest; do not switch to CPU automatically when Metal is unavailable.

Q5_K_M remains rejected as the default because the observed short English
transcript was identical to Q4_K_M while Q5 used more memory and ran more
slowly. The short Korean outputs differed, but no reference normalization or CER
grading was performed, so the trial does not claim that either output was more
accurate.

## Target-phone evidence

The harness ran on an iPhone 17 Pro Max with iOS 27.0.1. Both candidates loaded
the canonical `cohere_asr` architecture on the Apple A19 Pro Metal device,
reported cancellation support, completed the available English and Korean
clips, and stayed at the nominal thermal state while the phone was charging.

| Observation | Q4_K_M | Q5_K_M |
| --- | ---: | ---: |
| Model file size | 1.56 GB | 1.77 GB |
| Short English inference | 0.71 s | 0.92 s |
| Short English peak footprint | 1.75 GB | 1.96 GB |
| Short Korean inference | about 0.33 s | 0.35 s |
| Short Korean peak footprint | 1.73 GB | 1.96 GB |
| Observed model load | about 1.41 s | about 1.65 s |

Q4 output was deterministic across the repeated short runs. Q4 and Q5 produced
the same English output. These are exploratory single-device observations, not
an accuracy benchmark, energy measurement, or statistically controlled latency
study.

## Required P1-M12 safeguards

- Convert input to 16 kHz mono Float32 and require an explicit `en` or `ko`
  language hint.
- Treat only a successful, nontruncated result as complete diary text.
- Until a runtime release proves complete long-form output on the target phone,
  split recordings into silence-aware chunks no longer than 45 seconds and
  validate seam handling. The runtime's advertised 400-second input limit is
  not sufficient completeness evidence.
- Keep cancellation bounded, retain audio on every failure, and expose stable
  runtime status information without disclosing private transcript text in
  diagnostics.
- Preserve the model's Apache-2.0 notice and the runtime's MIT and bundled
  third-party notices.
- Record real build/runtime/model provenance in production. The trial exports
  left the build revision and runtime-artifact digest as `unknown`; those fields
  are not accepted as production evidence.

## Closed without evidence

At the owner's direction, P1-M6 ends without the planned five-minute matrix,
true cold-launch comparison, cancellation probe, Power Profiler trace, or
reference-text WER/CER calculation. No claim is made for five-minute quality,
energy impact, cancellation settlement, or long-run thermal behavior. P1-M12
must verify its production chunking and cancellation behavior, and P1-M19 keeps
the complete-experience device gate.
