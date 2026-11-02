# Contribution Guide

Status: Active

How to set up `Narihito's Diary Mobile`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- XcodeGen installed and available on PATH.
- Python 3 available on PATH for simulator destination selection.
- An iPhone simulator suitable for the target device.

```sh
make lint                                     # check Swift formatting and lint
make generate                                 # generate the Xcode project
make build                                    # generate and build for the iOS Simulator
make open                                     # generate and open the project in Xcode
TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh
```

The root Makefile is a convenience wrapper around XcodeGen and `xcodebuild`;
`project.yml` remains the project source of truth. `make build` regenerates the
project before building it for the generic iOS Simulator with code signing disabled;
`make open` regenerates it before opening it in Xcode.

Generation selects the first development team in Xcode's local account settings and
uses automatic signing. The generated project has no selected team when Xcode has no
available team; no machine-specific Team ID is committed to the repository.

## Required validation

For milestones other than P1-M1, P1-M2, P1-M4, P1-M5, and P1-M6, run the full checks from the repository root before opening a pull request. The owner exempted those milestones from build, lint, and test gates; see the [Phase 1 changelog](phase-1/changelog.md).

```sh
make lint
TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh
```

The lint script checks tracked and unignored new Swift files, including trial sources, while excluding ignored build and dependency output. It requires Git, swift-format, and SwiftLint; run it independently with `make lint`. The validation script selects a booted iPhone when exactly one is available. Otherwise, set `TEST_DESTINATION` to an available iPhone simulator ID; the script lists candidates when selection is ambiguous. It checks CoreSimulator access before generation, then builds and tests on the same destination. Successful command output stays quiet; failures print a short log tail and retain the full logs at the reported temporary path. Simulator destination resolution fails after 60 seconds, and each test receives at most 120 seconds. Positive-integer `SIMULATOR_DESTINATION_TIMEOUT_SECONDS` and `TEST_EXECUTION_TIMEOUT_SECONDS` overrides are available for slower machines or explicitly long-running tests. If CoreSimulator reports a connection or permission error under a restricted shell, run the gate in a shell with simulator service access.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org):
`<type>[(scope)]: <imperative summary>`. Keep the lowercase title at most 50
characters with no period. Use a short body only to explain why.

Keep each commit focused. Example:

    feat(parser): add support for nested lists

    Nested list items were flattened into a single level. Keep the nesting
    so the parsed document matches the source.

## Pull requests

TBD
