# Contribution Guide

Status: Active

How to set up `Narihito's Diary Mobile`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- XcodeGen installed and available on PATH.
- An iPhone simulator suitable for the target device.

```sh
swift-format format --in-place --recursive .  # format Swift source
swift-format lint --strict --recursive .      # check Swift formatting
swiftlint lint --strict                       # lint Swift source
xcodegen generate --quiet                     # generate the Xcode project
TEST_DESTINATION='platform=iOS Simulator,name=<available iPhone>' scripts/validate.sh
```

## Required validation

For milestones other than P1-M1, P1-M2, and P1-M4, run the full checks from the repository root before opening a pull request. The owner exempted P1-M1 and P1-M2 from all build, lint, and test gates, and P1-M4 from its build, lint, and test exit gate; see the [Phase 1 changelog](phase-1/changelog.md).

```sh
swift-format lint --strict --recursive .
swiftlint lint --strict
TEST_DESTINATION='platform=iOS Simulator,name=<available iPhone>' scripts/validate.sh
```

The validation script keeps successful command output silent and prints a short log tail on failure. Set `TEST_DESTINATION` to a working iPhone simulator; without it, the script exits before running checks because the full gate requires tests. Simulator destination resolution fails after 60 seconds, and each test receives at most 120 seconds, so unavailable simulators and nonsettling tests do not stall the gate. Positive-integer `SIMULATOR_DESTINATION_TIMEOUT_SECONDS` and `TEST_EXECUTION_TIMEOUT_SECONDS` overrides are available for slower machines or explicitly long-running tests.

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
