# P1-M3: Scaffolding overview

Status: Done

Create the smallest buildable iPhone app and test target, with reproducible XcodeGen generation and concise validation output.

## Scope

- Add a SwiftUI app entry point and a small, testable launch policy for the approved iOS 27.0.1 minimum.
- Generate an iPhone-only Xcode project and test scheme with XcodeGen.
- Provide one quiet validation script for generation, formatting, lint, build, and tests.
- Document local setup and the current simulator limitation.

## Out of scope

- Recording, transcription, iCloud, model packaging, asset schema, and undecided screen behavior.
- Third-party app dependencies beyond the approved XcodeGen project generator.

## Completion checklist

- [x] XcodeGen generated the app and test targets with an iPhone-only iOS 27.0 deployment target.
- [x] Launch checks for iOS 27.0.1 or later and presents a minimal scaffold screen; a focused version-policy test is present.
- [x] README and contribution instructions explain generation and quiet checks.
- [x] `swift-format lint --strict --recursive .` passed.
- [x] `swiftlint lint --strict --quiet --no-cache` passed.
- [x] The generated project built for the generic iOS simulator destination with code signing disabled.
- [x] The test scheme passed on the installed iOS 27.1 iPhone Duo simulator (UDID `F028B470-6B21-4391-96AE-E025DAF660CA`). CoreSimulator requires access outside the workspace sandbox in this environment.

## Review follow-up checklist

- [x] The full validation script exits with status 2 and a clear message when no test destination is configured.
- [x] Version-policy tests cover an older major release and the minimum patch boundary.
- [x] The documented full gate passed after the review changes on the iOS 27.1 iPhone Duo simulator.
