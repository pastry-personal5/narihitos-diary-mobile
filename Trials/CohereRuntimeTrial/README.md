# Cohere runtime trial

Status: Active

This isolated iPhone app measures the P1-M6 Cohere Q4/Q5 candidates without
adding a dependency to the production app. Follow the
[physical-device protocol](../../docs/phase-1/milestone-06-cohere-runtime-trial-protocol.md)
when collecting evidence.

## Setup

From the repository root:

```sh
scripts/setup-cohere-trial.sh
cd Trials/CohereRuntimeTrial
xcodegen generate --quiet
open CohereRuntimeTrial.xcodeproj
```

The setup script downloads the official `transcribe.cpp` v0.2.4 XCFramework,
checks its published SHA-256, and extracts it into ignored `Vendor/` storage.
It also writes an ignored local build setting with the current Git revision and
a dirty-worktree marker plus the verified runtime-artifact SHA-256 for result
provenance.
The models are not bundled. Transfer one model and private trial audio to Files,
select both in the app, and tap Inspect Inputs before Transcribe. Confirm the
displayed quantization, hashes, and duration against the intended run.

The trial requires a physical iPhone for valid inference measurements. The
simulator target exists only for model-free tests and build diagnostics.

For a model-free compile check:

```sh
xcodebuild -quiet \
  -project CohereRuntimeTrial.xcodeproj \
  -scheme CohereRuntimeTrial \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cohere-trial-derived \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## Privacy

Selected source files remain in their Files locations. Result JSON is written to
the app's Documents directory and may include transcript text and file hashes.
Export it only to the approved private evidence location. Use Delete Results in
the app after export. Raw result files, audio, transcripts, and profiler traces
must not be committed.

## Dependency notices

The verified XCFramework contains the upstream `transcribe.cpp`, ggml, and miniz
license files. They remain beside the downloaded framework under `Vendor/`.
This trial approval does not approve the runtime or model distribution for the
production app.
