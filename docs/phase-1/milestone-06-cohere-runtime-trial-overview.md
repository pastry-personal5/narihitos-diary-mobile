# P1-M6: Cohere runtime trial overview

Status: Done

An isolated physical-iPhone trial compared compact Cohere Transcribe GGUF
models on available short English and Korean audio. The owner selected Q4_K_M
with `transcribe.cpp` Metal as the P1-M12 direction and explicitly closed the
unperformed five-minute and profiler matrix without claiming that evidence.

## Scope

- Add a separate, device-only trial app that does not change the production app
  target or its dependency graph.
- Pin the trial to an official `transcribe.cpp` release and verify the downloaded
  XCFramework before use.
- Load the repository's Q4_K_M and Q5_K_M Cohere candidates from Files rather
  than embedding multi-gigabyte models in the app bundle.
- Import consented audio, convert it to 16 kHz mono Float32, require an explicit
  English or Korean hint, and run local transcription with Metal when available.
- Expose cancellation and distinguish success, cancellation, input-too-long,
  output-truncated, out-of-memory, and other runtime failures.
- Inspect and display model/audio hashes, quantization, and audio duration before
  enabling an inference attempt; reject files changed after inspection.
- Export one structured result per settled inference attempt with
  device/build/model/audio identity,
  cold or warm run classification, wall time, transcript, truncation state,
  phase-tagged process-memory samples, thermal state, controlled conditions, and
  battery observations.
- Document a repeatable comparison protocol for 30-second and five-minute
  English and Korean diary-like recordings on the target iPhone.

P1-M6 may run while P1-M5 remains planned because this harness neither fixes
product/data/security policy nor feeds trial output into the production app.
Any production integration remains gated by P1-M5 decisions and owner approval.

## Out of scope

- Adding Cohere to the production app, queue, Settings, or model installer.
- Shipping a model, downloader, trusted manifest, cache deletion flow, or
  readiness policy.
- Choosing a production runtime, quantization, acceptance threshold, or audio
  encoding from simulator or Mac results.
- Treating battery percentage as an energy measurement; Xcode Power Profiler is
  the energy evidence source.
- Collecting or committing private trial audio or transcripts.

## Completion checklist

- [x] The milestone overview, implementation approach, and physical-device
  protocol distinguish harness validity from the later production decision.
- [x] The trial dependency is owner-approved, pinned, checksum-verified, and
  isolated from the production target.
- [x] The trial app imports a GGUF and an audio file, converts supported audio to
  16 kHz mono Float32, and transcribes with an explicit `en` or `ko` hint.
- [x] The app can cancel an in-flight run and reports truncation and typed runtime
  failures without presenting partial text as a complete transcript.
- [x] Each run exports a schema-versioned JSON result with reproducibility,
  latency, memory, thermal, battery-observation, and transcript fields.
- [x] Focused tests cover measurement serialization, run classification, input
  validation, and transcript completeness policy without requiring a model.
- [x] Strict swift-format and SwiftLint checks pass.
- [x] The production app builds after the isolated trial is added.
- [x] The production app tests pass on an available iPhone simulator.
- [x] The isolated trial app and model-free test bundle build for a generic iOS
  device with its verified local XCFramework.
- [x] The owner reviewed the available short English/Korean Q4_K_M and Q5_K_M
  phone evidence and explicitly closed the unperformed five-minute, true-cold,
  cancellation, and profiler matrix without claiming that evidence.
- [x] The research and open-decision docs record measured evidence separately
  from owner-approved production choices.
- [x] The owner approved Q4_K_M with `transcribe.cpp` Metal as the P1-M12
  direction, with trusted-manifest and bounded long-audio safeguards.

## Review follow-up checklist

- [x] Preflight shows candidate quantization, SHA-256 values, and audio duration,
  verifies the model against its Git LFS SHA-256, and prevents a changed input
  from running without another inspection.
- [x] Exported schema v3 records runtime artifact integrity, controlled
  conditions, model input/cancellation capabilities, measurement phases, and
  a stage-by-stage runtime diagnostic trail.
- [x] Cancellation propagates through run-time input verification, audio
  conversion, and inference, and conversion drains the resampler; the owner
  closed P1-M6 without claiming a physical-device cancellation probe.
- [x] Run classifications say `warmReload`, reflecting the implemented
  unload/reload lifecycle instead of claiming resident model reuse.

## Validation

The owner exempted P1-M6 from the repository gate as a completion requirement,
although the implemented harness still passed the available checks. Model-backed
inference is a physical-device acceptance check because the iOS simulator slice
is CPU-only and cannot establish phone memory, performance, battery, or thermal behavior.
Private audio, transcripts, result exports, model copies, generated projects, and
the downloaded XCFramework remain untracked local trial material.

## Current validation evidence

On 2026-11-01, strict swift-format and SwiftLint passed. The production project
generated, built, and passed its simulator tests through `scripts/validate.sh`.
The isolated project generated, its pinned runtime checksum passed, and its
post-review model-free test bundle built for generic iOS with code signing
disabled. CoreSimulatorService then refused connections, so the focused
streaming audio-conversion test could not be rerun. Short physical-phone
Q4_K_M and Q5_K_M English/Korean runs completed successfully with Metal and
nominal thermal state. The owner selected Q4_K_M and closed the remaining
protocol without claiming five-minute, cancellation, profiler, energy, or
accuracy evidence; see the [results](milestone-06-cohere-runtime-trial-results.md).
