# Contribution Guide

Status: Active

How to set up `Narihito's Diary Mobile`, validate changes on Simulator and a real iPhone, and follow code, repository, and commit conventions.

## Setup and development

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- swift-format installed and available on PATH.
- XcodeGen installed and available on PATH.
- Python 3 available on PATH for simulator destination selection.
- An iPhone simulator suitable for the target device.

```sh
make generate                                 # generate the Xcode project
make build                                    # generate and build for the iOS Simulator
make open                                     # generate and open the project in Xcode
```

The root Makefile is a convenience wrapper around XcodeGen and `xcodebuild`;
`project.yml` remains the project source of truth. `make build` regenerates the
project before building it for the generic iOS Simulator with code signing disabled;
`make open` regenerates it before opening it in Xcode.

Generation selects the first development team in Xcode's local account settings and
uses automatic signing. The generated project has no selected team when Xcode has no
available team; no machine-specific Team ID is committed to the repository.

## Required validation

Run the full checks from the repository root before opening a pull request, subject to the milestone exemptions in the [definition of done](development-process.md#definition-of-done).

```sh
make lint
TEST_DESTINATION='platform=iOS Simulator,id=<available iPhone UDID>' scripts/validate.sh
```

The lint script checks tracked and unignored new Swift files, including trial sources, while excluding ignored build and dependency output. It requires Git, swift-format, and SwiftLint. The validation script selects a booted iPhone when exactly one is available. Otherwise, set `TEST_DESTINATION` to an available iPhone simulator ID; the script lists candidates when selection is ambiguous. It checks CoreSimulator access before generation, then builds and tests on the same destination. Successful command output stays quiet; failures print a short log tail and retain the full logs at the reported temporary path. Simulator destination resolution fails after 60 seconds, and each test receives at most 120 seconds. Positive-integer `SIMULATOR_DESTINATION_TIMEOUT_SECONDS` and `TEST_EXECUTION_TIMEOUT_SECONDS` overrides are available for slower machines or explicitly long-running tests.

### CoreSimulator access in restricted shells

If `xcrun simctl list devices available` or `scripts/validate.sh` reports `CoreSimulatorService connection became invalid`, `Connection refused`, or a permission error for CoreSimulator logs, first suspect restricted-shell access to the simulator service. Retry discovery with simulator service access (request command escalation in an agent sandbox), then run the gate with an explicit available iPhone simulator ID under the same access. A successful retry identifies an environment restriction; do not change app code or reset simulators to address it. If access cannot be granted or the retry still fails, leave the validation checklist item unchecked and report the blocker. A generic build or lint pass alone does not satisfy the simulator test gate.

## Code and repository conventions

- Use Swift and SwiftUI, following the [inward source-dependency rule](architecture.md#clean-architecture-layers-and-dependency-rule). Format Swift with swift-format and resolve SwiftLint warnings.
- Use UTC for asset file/directory names and local time for display, following the [asset contract](product-behavior.md#assets-and-metadata).
- Use XcodeGen for project generation. Set the deployment target to iOS 27.0 and enforce iOS 27.0.1 at launch; see the [P1-M3 approach](phase-1/milestone-03-scaffolding-architecture.md).
- Project-owned code is Apache-2.0. Dependency license compatibility is not an approval or milestone gate; changes to dependencies or build tools still require owner approval.
- Do not place Git worktrees under the project root's `tmp/` directory, including `tmp/worktree/`; they cause SwiftLint to fail.
- Keep implementation, tests, and affected docs in the same change. Follow the [documentation rules](development-process.md#documentation-rules).

## Real-iPhone testing with MobileBuildMCP

Use device tests for native framework and phone-storage behavior in addition to the
required simulator gate above. The [M16 connected-iPhone results](phase-1/milestone-16-diary-editing-favorite-audio-replay-device-evidence.md#connected-iphone-results)
record 70 storage/state/recovery checks, two native replay checks, and one native
title check passing on an iPhone 17 Pro Max with iOS 27.0.1. Hosted interface tests
still failed their initial accessibility lookup; those passes do not close the
remaining physical interaction or real-iCloud scenarios.

### Prepare the phone and signing

1. Connect the iPhone to the Mac, unlock it, accept Trust/pairing prompts, and enable
   Developer Mode. Keep it unlocked while Xcode prepares it and starts tests. The
   app requires iOS 27.0.1 or later at launch.
2. Confirm Xcode can use the phone in **Window → Devices and Simulators**. Copy its
   hardware **Identifier (UDID)** for the test destination. In the recent run, the
   CoreDevice identifier from discovery timed out; the hardware UDID reached the
   signed test build.
3. Run `make generate` from the repository root. Use the existing Xcode account and
   automatic signing described above; resolve missing team/profile errors in
   Xcode before retrying. Use synthetic fixtures and preserve personal app data,
   settings, and installed models.

### Choose MCP tools or the installed CLI

- **MCP device tools:** read the installed MobileBuildMCP skill, call
  `session_show_defaults`, then set the project path, `NarihitosDiary` scheme,
  `Debug` configuration, and hardware `deviceId` with `session_set_defaults`.
  Use `list_devices` and `test_device` when exposed. Pass additional Xcode test
  arguments through `extraArgs`.
- **CLI fallback:** if the connected MCP session exposes only simulator tools,
  the already-installed CLI may still provide `device test`. This is the route
  used for the successful M16 phone runs. Check availability with
  `mobilebuildmcp device --help`. To expose MCP device tools, enable the device
  workflow in `.mobilebuildmcp/config.yaml` and reload the client session; changing
  workflow configuration is unnecessary when using the CLI fallback.

These examples match the installed MobileBuildMCP 2.7.1 CLI. Check local help when
using another version; installing or upgrading build tools requires owner approval.

```sh
mobilebuildmcp --version
mobilebuildmcp device list
mobilebuildmcp device test --help

# Use Xcode's hardware Identifier, not the CoreDevice discovery UUID.
NDM_DEVICE_UDID='<hardware UDID from Xcode>'

# Focused native replay run; test builds, signs, and executes the selected suite.
mobilebuildmcp device test \
  --project-path "$PWD/NarihitosDiary.xcodeproj" \
  --scheme NarihitosDiary \
  --device-id "$NDM_DEVICE_UDID" \
  --configuration Debug \
  --progress \
  --json '{"extraArgs":["-allowProvisioningUpdates","-parallel-testing-enabled","NO","-only-testing:NarihitosDiaryTests/DiaryNativeReplayTests"]}'
```

Run `DiaryNativeTitleTests` separately by replacing the suite name. For a focused
storage batch, replace the `extraArgs` JSON with, for example:

```json
{"extraArgs":["-allowProvisioningUpdates","-parallel-testing-enabled","NO","-only-testing:NarihitosDiaryTests/DiaryEditStorageTests","-only-testing:NarihitosDiaryTests/DiaryEditCleanupTests"]}
```

### Device-test options

| Option | Use |
|---|---|
| `--project-path` / `--workspace-path` | Select one project or workspace; this repository uses `NarihitosDiary.xcodeproj`. |
| `--device-id`, `--scheme`, `--configuration` | Explicit hardware UDID, `NarihitosDiary`, and normally `Debug`. |
| `--json '{"extraArgs":[...]}'` | Safely pass arrays of Xcode arguments, including arguments beginning with `-`. |
| `-only-testing:NarihitosDiaryTests/<Suite>` / `-skip-testing:NarihitosDiaryTests/<Suite>` in `extraArgs` | Include or exclude suites; repeat to select multiple suites. Omit filters only after checking that the batch supports physical execution. |
| `-parallel-testing-enabled`, `NO` in `extraArgs` | Disable Xcode test parallelization for phone runs. Run native audio/model suites in separate invocations as well. |
| `-destination-timeout`, `60` in `extraArgs` | Bound destination discovery in seconds; this does not resolve a locked phone. |
| `-test-timeouts-enabled`, `YES`, `-maximum-test-execution-time-allowance`, `120` in `extraArgs` | Bound individual test execution. The simulator script's timeout environment variables do not configure this CLI. |
| `-allowProvisioningUpdates` in `extraArgs` | Allow automatic signing to update provisioning with the configured Xcode account. |
| `--derived-data-path` | Choose a local build-artifact directory outside the tracked source tree. |
| `--test-products-path` / `--xctestrun-path` | Supply prebuilt device test artifacts matching the current source, SDK, signing, and destination. `device build --build-for-testing` provides the build-only path; inspect its help first. |
| `--progress`, `--output json`, `--verbose` | Show progress, return structured output, or include more diagnostic detail. |
| `--profile` | Choose configured session defaults for one command; explicit project/device flags make ad hoc runs easier to audit. |

### Troubleshooting and recording results

- If device discovery fails with Xcode-service permission errors in a restricted
  shell, retry with service access before changing app code. The successful M16
  discovery required that access.
- If Xcode stays at **Connecting to the target iPhone**, reports device-preparation
  code `-3`, or rejects launch as `Locked`, unlock/reconnect the phone and resolve
  its prompts. Check that the previous runner has exited before starting another
  run. A signed build or install alone is not an executed test pass.
- Select phone-compatible tests. Tests that inspect the Mac checkout using
  `#filePath` cannot find those source files on the phone; keep those checks in
  the simulator gate. Native replay passed alone after audio-session activation
  failed in a combined batch; that combined-run failure remains unresolved.
- Simulator tap/snapshot tools do not establish physical UI behavior. The five
  M16 hosted interface tests failed before Edit/Favorite actions ran on the phone;
  retain those failures and use the outstanding manual interaction scenarios.
- Keep the reported log and `.xcresult` paths locally. Record the source revision,
  device/iOS, selected suites, pass/fail/skip counts, and evidence limits in the
  milestone's device-evidence doc. Redact device identifiers and personal content;
  commit sanitized observations and artifact basenames rather than raw logs.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org):
`<type>[(scope)]: <imperative summary>`. Keep the lowercase title at most 50
characters with no period. Use a short body only to explain why.

Keep each commit focused. Example:

    feat(parser): add support for nested lists

    Nested list items were flattened into a single level. Keep the nesting
    so the parsed document matches the source.
