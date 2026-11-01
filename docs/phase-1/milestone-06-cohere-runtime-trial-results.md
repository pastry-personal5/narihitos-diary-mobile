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

Q5_K_M remains rejected as the default because the matched back-to-back English
comparison produced identical text while Q5 used more memory, loaded more
slowly, and inferred more slowly. An additional Q4 cold-classified English run
was slower than that Q5 run, so the trial does not claim a general latency
ranking. The short Korean outputs differed, but no reference normalization or
CER grading was performed, so the trial does not claim that either output was
more accurate.

## Target-phone evidence

The harness ran on an iPhone 17 Pro Max with iOS 27.0.1. Both candidates loaded
the canonical `cohere_asr` architecture on the Apple A19 Pro Metal device,
reported cancellation support, completed the available English and Korean
clips, and stayed at the nominal thermal state while the phone was charging.

| Observation | Q4_K_M | Q5_K_M |
| --- | ---: | ---: |
| Model file size | 1,558,162,944 bytes | 1,770,270,208 bytes |
| 23.10 s English inference | 0.71–2.19 s (2 successes) | 0.92 s (1 success) |
| English peak footprint | 1.74–1.75 GB | 1.96 GB |
| 10.08 s Korean inference | 0.328–0.331 s (3 successes) | 0.349 s (1 success) |
| Korean peak footprint | 1.73–1.75 GB | 1.96 GB |
| Successful model loads | 1.40–1.42 s | 1.64–1.66 s |

Q4 transcript text was deterministic for each repeated short clip, but its
English inference time was not. Q4 and Q5 produced the same English output.
These are exploratory single-device observations, not an accuracy benchmark,
energy measurement, or statistically controlled latency study.

## Research and troubleshooting findings

The sanitized review covered ten private exports: seven successful runs and
three pre-fix harness failures. It records aggregate technical facts only; raw
transcripts, filenames, file hashes, result IDs, and device logs remain outside
Git.

- The successful path used the official `transcribe.cpp` v0.2.4 XCFramework,
  pinned by archive SHA-256
  `243e96ea569583245c9732de3955111210d986c03a34b81424dacde169f9de6a`;
  the runtime reported commit `4807eda`. Metal was requested and the actual
  device was `MTL0`, the Apple A19 Pro GPU. The runtime also registered a CPU
  device, but no successful run switched to it.
- Every successful export ended with runtime status `ok (0)`, `aborted false`,
  and `truncated false`. The runtime reported the canonical `cohere_asr`
  architecture, a 400,000 ms input capability, and cancellation support. The
  trial verified neither the advertised long-input completeness nor physical
  cancellation settlement.
- An early audio-conversion build surfaced `OSStatus -39`. The harness replaced
  the failing ingestion path with bounded streaming `AVAudioConverter` input,
  explicit remaining-frame/end-of-stream handling, converter draining, and a
  no-progress guard. Later exports converted the 10.08 s and 23.10 s inputs to
  the expected 16 kHz mono Float32 sample counts. This resolves the observed
  files, not every possible audio container.
- Three early exports settled as `runtimeFailure` with `unsupported
  architecture (5)` after the GGUF had loaded on Metal but before inference.
  The detailed export already reported `model architecture: cohere_asr`; the
  failure was therefore a harness policy mismatch, not evidence that the model
  or phone lacked Cohere support. The policy now accepts canonical `cohere_asr`
  and legacy `cohere`, and later runs with the same candidates settled as
  `success / ok (0)`.
- The exports include both schema v2 and v3 evidence. All retained exports
  correctly classified their run, but `trialBuildRevision` and the verified
  runtime-artifact SHA-256 were `unknown`. Those missing values prevent the raw
  exports from serving as production provenance even though the setup script
  independently pins and verifies the XCFramework archive.

The Hugging Face repository metadata checked on 2026-11-01 identifies
`handy-computer/cohere-transcribe-03-2026-gguf` revision
`7353b6040bdc1be9e5a3823d99d5fe12afe88264` as an Apache-2.0 quantization of
`CohereLabs/cohere-transcribe-03-2026`, names `transcribe.cpp` as its library,
and lists both English and Korean. Its repository contains the selected Q4_K_M
and compared Q5_K_M artifacts, plus `LICENSE` and `NOTICE`; see the
[model repository](https://huggingface.co/handy-computer/cohere-transcribe-03-2026-gguf).

The 45-second production ceiling is a defensive caller policy, not a claim that
the runtime's advertised 400-second maximum is safe. Upstream issue
[`transcribe.cpp` #128](https://github.com/handy-computer/transcribe.cpp/issues/128)
reproduces successful-but-incomplete Cohere output beyond roughly 50 seconds
with `was_truncated == false`; splitting the same input at natural silences into
pieces shorter than 45 seconds recovered the complete passage. P1-M12 must keep
chunking until the pinned production runtime proves the defect fixed on the
target phone.

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
  are not accepted as production evidence. Treat absent or placeholder
  provenance as a failed result export rather than silently publishing it.

## Closed without evidence

At the owner's direction, P1-M6 ends without the planned five-minute matrix,
true cold-launch comparison, cancellation probe, Power Profiler trace, or
reference-text WER/CER calculation. No claim is made for five-minute quality,
energy impact, cancellation settlement, or long-run thermal behavior. P1-M12
must verify its production chunking and cancellation behavior, and P1-M19 keeps
the complete-experience device gate.
