# Contribution Guide

Status: Active

How to set up `Narihito's Diary Mobile`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- An iPhone simulator suitable for the target device.

```sh
swift-format format --in-place --recursive .  # format Swift source
swift-format lint --strict --recursive .      # check Swift formatting
swiftlint lint --strict                       # lint Swift source
TBD: xcodebuild test                          # run tests after the Xcode project and scheme exist
```

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
swift-format lint --strict --recursive .
swiftlint lint --strict
TBD: xcodebuild test with the generated project, scheme, and simulator
```

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
