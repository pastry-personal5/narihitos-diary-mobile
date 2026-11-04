# AGENTS.md

Status: Active

Instructions for contributors and AI coding agents working on Narihito's Diary Mobile, a Swift/SwiftUI iPhone app. `CLAUDE.md` imports this file with `@AGENTS.md`.

## Agent workflow

- Work on a clear task in the active milestone. Start at the [documentation index](docs/README.md), follow the [roadmap](docs/roadmap.md) and phase execution order, and read the relevant plans and contracts before editing.
- Add a verifiable completion checklist to the milestone overview before implementation. Keep code, tests, and affected docs together; check items only with evidence. Follow the [definition of done](docs/development-process.md#definition-of-done) and [validation guide](docs/contribution-guide.md#required-validation); unavailable required checks stay unchecked with their blocker.
- Ask before changing approved decisions, building on an undecided item, changing dependencies/build tools, deleting user data, or broadly restructuring the repository. Other work within the approved task may proceed.
- Follow the [contributor conventions](docs/contribution-guide.md#code-and-repository-conventions) and [documentation rules](docs/development-process.md#documentation-rules). Update the owning document rather than copying its facts here.
- If using MobileBuildMCP, read the installed MobileBuildMCP skill before calling its tools. For restricted-shell simulator failures, follow the [access-retry procedure](docs/contribution-guide.md#coresimulator-access-in-restricted-shells).

## Decided — ask before changing

The linked documents own the detailed decisions; milestone records retain their evidence and later owner-approved amendments.

| Contract | Authoritative documentation |
|---|---|
| V1 scope, recording, transcription, titles, assets, recovery, and privacy | [Product behavior](docs/product-behavior.md), [P1-M5 contracts](docs/phase-1/milestone-05-decisions-architecture.md) |
| Clean Architecture, inward dependencies, adapters, state, and storage | [Software architecture](docs/architecture.md) |
| Interface behavior, containment, and vocabulary | [UX GUI](docs/ux-gui.md), [information architecture](docs/ux-information-architecture.md), [terms](docs/ux-terms.md) |
| Cohere runtime direction and approved Q4/Q5 scope | [P1-M6 results](docs/phase-1/milestone-06-cohere-runtime-trial-results.md), [M20 Transcription Settings](docs/phase-1/milestone-20-enhancements-fixes-refactoring-overview.md#task-2-dedicated-transcription-settings-and-model-choices) |
| Swift/SwiftUI, XcodeGen, iOS targets, licensing, and tooling | [Contribution guide](docs/contribution-guide.md) |
| Phase/milestone process, validation exemptions, and documentation lifecycle | [Development process](docs/development-process.md) |

## Undecided — ask before inventing

- A different Cohere runtime, backend, model host, quantization beyond approved Q4/Q5, or relaxed P1-M6 safeguards. P1-M12 still owes production provenance, chunk-seam, cancellation, and long-input evidence; P1-M6 did not establish five-minute quality, energy, or WER/CER.
- Mechanism changes that alter approved P1-M5 outcomes. P1-M8, P1-M9, P1-M14, P1-M17, and P1-M19 still owe platform and adversarial evidence.
- Hosted Qwen model IDs, controls, and budget details, which remain future work.

## Efficient work

- Search with `rg` or `git grep`. Skip build/dependency output (`build/`, `DerivedData/`, `.build/`, `Pods/`, `Carthage/Build/`), lockfiles, `LICENSE`, and `docs/archive/` unless needed.
- Read only relevant docs and dependency modules. Run affected checks while iterating and the full required gate once at the end.
- Keep logs short, inspect `git diff --stat` before a full diff, and report concise summaries with evidence limits.
