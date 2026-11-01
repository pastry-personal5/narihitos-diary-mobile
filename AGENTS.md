# AGENTS.md

Instructions for contributors and AI coding agents. This is the single source of agent instructions; `CLAUDE.md` imports it with `@AGENTS.md`.

## Project

`Narihito's Diary Mobile`: An iPhone app that creates diary assets from voice recordings.

Stack: Swift and SwiftUI for iOS.

See [README.md](README.md) for the overview and [docs/product-behavior.md](docs/product-behavior.md) for product scope. Setup and contribution rules are in [docs/contribution-guide.md](docs/contribution-guide.md); other docs are indexed at [docs/README.md](docs/README.md).

## Agent workflow

- Work only on a clear task in the active milestone. Read its plans, relevant design docs, and applicable "Undecided" items first.
- Before implementation, add a verifiable completion checklist to the milestone overview. Check items only when evidence exists.
- Keep implementation, tests, and affected docs together. A milestone is done only when its checklist is complete and the gate passes: `swift-format lint --strict --recursive .`, `swiftlint lint --strict`, and `TBD: xcodebuild test with the generated project, scheme, and simulator`. The owner exempts P1-M1 and P1-M2 from all build, lint, and test gates. For other milestones, if a required command cannot run, leave its item unchecked and report the blocker.
- Ask before building on an undecided item, changing dependencies or build tools, deleting user data, or broadly restructuring the repository. Other work within the approved task and milestone may proceed.
- Follow the active phase and milestone order in `docs/roadmap.md` unless the phase plan says otherwise. Create the roadmap when planning the first phase.

## Decided — ask before changing

- **Technical stack:** Swift and SwiftUI for iOS.
- **Product scope:** [product-behavior.md](docs/product-behavior.md).
- **Owner-confirmed v1 behavior:** [confirmed v1 behavior](docs/product-behavior.md#confirmed-v1-behavior).
- **Interaction model:** [ux-gui.md](docs/ux-gui.md). Component vocabulary is in [ux-terms.md](docs/ux-terms.md) and the layout containment model in [ux-information-architecture.md](docs/ux-information-architecture.md).
- **License:** Apache-2.0 for all project code.
- **Project generation:** use XcodeGen in P1-M3; see the [Phase 1 changelog](docs/phase-1/changelog.md).
- **P1-M1 and P1-M2 validation:** no build, lint, or test gate is required for completion; see the [Phase 1 changelog](docs/phase-1/changelog.md).
- **Process:** numbered phases contain numbered milestones; milestone numbering restarts per phase. IDs use `P1-M2`. See [docs/development-process.md](docs/development-process.md).

## Undecided — ask before inventing

The [P1-M1 open-decision inventory](docs/research/p1-m1-open-decisions.md) lists evidence and specific questions. Resolve these before implementation depends on them:

- Diary text transformation, detailed asset schema, and remaining screen interactions.
- Exact Qwen model IDs and ASR controls, secure API-key storage, Apple-unavailable behavior, and quality, privacy, cost, and latency targets.
- Permanent iCloud permission loss, sync and conflict timestamp rules, recording interruption and replay details, and incomplete-pair recovery.
- Deployment-target representation of iOS 27.0.1 and a usable simulator fallback.

## Environment

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- An iPhone simulator suitable for the target device.

## Commands

```sh
swift-format format --in-place --recursive .  # format Swift source
swift-format lint --strict --recursive .      # check Swift formatting
swiftlint lint --strict                       # lint Swift source
TBD: xcodebuild test                          # run tests after the Xcode project and scheme exist
```

## Code conventions

- Use Swift and SwiftUI for the iOS app.
- Format Swift with swift-format and keep SwiftLint warnings resolved.
- Use UTC for asset file and directory names and local time for display.

## Dependencies

Approved dependencies must have licenses compatible with Apache-2.0.

## Documentation

- `README.md` is user-facing; `AGENTS.md` holds contributor rules; `docs/` holds plans and design; `docs/archive/` holds inactive docs.
- Use lowercase kebab-case filenames. Start each doc with a title, `Status:` line, and one- to three-sentence summary.
- Add every doc to [docs/README.md](docs/README.md). Follow [docs/development-process.md](docs/development-process.md) for phase and milestone plans.
- Update affected docs with code. Update `README.md` for user-visible changes and this file for tooling, commands, or decisions.
- Link instead of copying facts.
- Archive completed or superseded docs: update status, `git mv` them under `docs/archive/` (completed phase directories go under `docs/archive/phases/`), and fix links. Archived docs are not maintained.

## Token efficiency

- Skip build/dependency output (`build/`, `DerivedData/`, `.build/`, `Pods/`, `Carthage/Build/`), lockfiles, `LICENSE`, and `docs/archive/` unless needed. Search with `git grep` or `rg`.
- Start at `docs/README.md` and read only relevant docs or sections.
- Keep logs short with quiet flags or filtering. For milestones with a validation gate, run affected tests while iterating and the full gate once at the end.
- Consult only the needed dependency source/module for API details.
- Make targeted edits; inspect `git diff --stat` before a full diff.
- Reply with concise summaries, not raw logs.
