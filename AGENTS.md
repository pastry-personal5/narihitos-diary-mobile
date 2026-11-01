# AGENTS.md

Instructions for contributors and AI coding agents. This is the single source of agent instructions; `CLAUDE.md` imports it with `@AGENTS.md`.

## Project

`Narihito's Diary Mobile`: An iPhone app that creates personal data assets from other multimodal data.

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
- **Diary creation and destination:** use transcription output to initialize one managed diary body, generate a short read-only summary title with Apple's on-device model when available, and save automatically. Select an iCloud folder before the first recording and allow an explicit replacement for a pending recording whose original folder is permanently inaccessible; see [product behavior](docs/product-behavior.md).
- **V1 transcription:** offer Apple on-device and an on-device Cohere Transcribe method based on `CohereLabs/cohere-transcribe-03-2026` or a suitable English/Korean Cohere variant. Install the local model before use; ask the user to choose a ready approved method when the selected method is unavailable, without automatic switching. Hosted Qwen is future work; see [product behavior](docs/product-behavior.md).
- **Title, diary text, and conflicts:** prefer an Apple on-device AI summary of the whole diary body for the read-only title when the model is available; use the first-sentence fallback if it is unavailable or produces an unusable result. Both title paths have a strict 30-displayed-character maximum, including any ellipsis. Regenerate on body save, using the body's current language, and keep a fallback title until the next body save if the model later becomes ready. Store the title and its origin in Markdown front matter. User edits replace the managed body; do not retain a separate original transcript. Select the latest conflicting iCloud edit by iCloud modification time; see [product behavior](docs/product-behavior.md).
- **Recording limit and interruptions:** stop and queue automatically at five minutes; automatically queue a playable partial recording after an audio interruption; see [product behavior](docs/product-behavior.md).
- **First-launch microphone access:** explain and request microphone permission during the first-time experience. Denial leaves non-recording features usable; Record offers a system Settings recovery path and capture requires permission; see [product behavior](docs/product-behavior.md).
- **Future hosted Qwen:** its prior key, consent, budget, and network-retry decisions are preserved for future work, not v1 controls or jobs; see [product behavior](docs/product-behavior.md).
- **Manual retry and reminder:** a manual transcription retry uses current Settings at retry time and is allowed without a fixed count limit while the recording remains. Schedule a local pending-work reminder for the next local day at the same local time the user left the app; see [product behavior](docs/product-behavior.md).
- **Queue progress and removal:** process the oldest ready recording while the app is open; a waiting, failed, or destination-blocked job does not block newer ready work. Bound or cancel hung inference, preserve its audio and reason, and isolate malformed job state so other valid jobs continue. Continue local transcription and diary creation if the iCloud destination is temporarily unavailable, then wait to save the draft. Allow confirmed removal of pending or failed recordings and their private audio, with in-flight work invalidated; see [product behavior](docs/product-behavior.md).
- **Asset timestamps and optional metadata:** `created_at` is when recording started and controls local-date grouping; `updated_at` changes on a saved text or metadata edit, not on iCloud sync. Omit unavailable weather/location fields; see [product behavior](docs/product-behavior.md).
- **Asset references and provenance:** Markdown front matter includes a schema version, an explicit audio filename, and the effective transcription method/model/conversion and applicable settings. When location is allowed, save exact coordinates and a place name; see [product behavior](docs/product-behavior.md).
- **Optional context and replay:** request location permission on first launch and expose it in Settings; denial does not block recording. If recording-time weather is unavailable, omit it without later backfill. Replay offers play/pause, seeking, and elapsed/total time; see [product behavior](docs/product-behavior.md).
- **Root screen containment:** Main shows the full active-folder diary collection with on-demand loading and infinite scroll; All shows no diary snippets for now and is the sole Settings entry. Record is a floating control on Main; see [UX GUI](docs/ux-gui.md).
- **Architecture rule:** follow Clean Architecture's inward source-dependency rule and allow additional asset kinds and transcription methods through registered, type-specific adapters; see [software architecture](docs/architecture.md).
- **Pending and detail screens:** All contains entries to separate pending and failed recording screens. Asset detail shows title and diary text first, Favorite beside the title, and audio replay inside metadata at the bottom; see [UX GUI](docs/ux-gui.md).
- **Editing:** the editor changes only the diary body; a save regenerates the read-only title using the approved title policy. Favorite is a separate on/off toggle; see [UX GUI](docs/ux-gui.md).
- **Empty edits and commit recovery:** an empty edited diary body saves with the title "Untitled". Retry a saved draft automatically when iCloud access returns, and delete private local staging immediately after the complete iCloud bundle is verified; see [product behavior](docs/product-behavior.md).
- **Legacy and interrupted recordings:** show existing Markdown/audio pairs without the new schema fields as read-only without changing their files. Keep an unplayable interrupted recording in Failed Recordings with an entry-level reason; see [product behavior](docs/product-behavior.md).
- **Recovery edge cases:** unusable transcription fails with audio retained, no asset, manual retry, and an entry-level reason. Equal or missing iCloud conflict times present two separately openable versions for the user to choose between. Repair incomplete Diary Snippet writes from retained local candidates on reopen. When no repair copy exists, keep and flag the incomplete pair, show surviving content read-only, and offer confirmed removal; see [product behavior](docs/product-behavior.md).
- **Interaction model:** [ux-gui.md](docs/ux-gui.md). Component vocabulary is in [ux-terms.md](docs/ux-terms.md) and the layout containment model in [ux-information-architecture.md](docs/ux-information-architecture.md).
- **License:** Apache-2.0 for all project code.
- **Project generation:** use XcodeGen in P1-M3; see the [Phase 1 changelog](docs/phase-1/changelog.md).
- **P1-M1 and P1-M2 validation:** no build, lint, or test gate is required for completion; see the [Phase 1 changelog](docs/phase-1/changelog.md).
- **Process:** numbered phases contain numbered milestones; milestone numbering restarts per phase. IDs use `P1-M2`. See [docs/development-process.md](docs/development-process.md).

## Undecided — ask before inventing

The [P1-M1 open-decision inventory](docs/research/p1-m1-open-decisions.md) lists evidence and specific questions. Resolve these before implementation depends on them:

- Remaining title-generation implementation details, asset schema details, and screen interactions, including detail metadata controls.
- The v1 Cohere conversion, iOS runtime, model distribution, and target-phone quality, memory, battery, and latency targets. Hosted Qwen model IDs, controls, and budget details remain future work.
- iCloud access-loss detection and recovery details, sync details, and the conflict-resolution interface.
- Deployment-target representation of iOS 27.0.1 and a usable simulator fallback.
- Private-data protection and capture behavior on lock, pending-data backup/restore policy, security resource limits, and the model trust/distribution mechanism; see the [security review](docs/security-review.md#open-gates-and-residual-risks).

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
- Keep a phase's milestone and research docs in its active directories until the phase is complete, even when a milestone is done. When the phase is complete, update their status, `git mv` the phase directory under `docs/archive/phases/` and its concluded research under `docs/archive/`, and fix links. Superseded standalone docs may be archived earlier. Archived docs are not maintained.

## Token efficiency

- Skip build/dependency output (`build/`, `DerivedData/`, `.build/`, `Pods/`, `Carthage/Build/`), lockfiles, `LICENSE`, and `docs/archive/` unless needed. Search with `git grep` or `rg`.
- Start at `docs/README.md` and read only relevant docs or sections.
- Keep logs short with quiet flags or filtering. For milestones with a validation gate, run affected tests while iterating and the full gate once at the end.
- Consult only the needed dependency source/module for API details.
- Make targeted edits; inspect `git diff --stat` before a full diff.
- Reply with concise summaries, not raw logs.
