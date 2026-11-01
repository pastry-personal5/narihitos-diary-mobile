# AGENTS.md

Instructions for contributors and AI coding agents. This is the single source of agent instructions; `CLAUDE.md` imports it with `@AGENTS.md`.

## Project

`Narihito's Diary Mobile`: An iPhone app that creates personal data assets from other multimodal data.

Stack: Swift and SwiftUI for iOS.

See [README.md](README.md) for the overview and [docs/product-behavior.md](docs/product-behavior.md) for product scope. Setup and contribution rules are in [docs/contribution-guide.md](docs/contribution-guide.md); other docs are indexed at [docs/README.md](docs/README.md).

## Agent workflow

- Work only on a clear task in the active milestone. Read its plans, relevant design docs, and applicable "Undecided" items first.
- Before implementation, add a verifiable completion checklist to the milestone overview. Check items only when evidence exists.
- Keep implementation, tests, and affected docs together. A milestone is done only when its checklist is complete and the gate passes: `swift-format lint --strict --recursive .`, `swiftlint lint --strict`, and `TBD: xcodebuild test with the generated project, scheme, and simulator`. The owner exempts P1-M1, P1-M2, P1-M4, P1-M5, and P1-M6 from build, lint, and test gates. For other milestones, if a required command cannot run, leave its item unchecked and report the blocker.
- Ask before building on an undecided item, changing dependencies or build tools, deleting user data, or broadly restructuring the repository. Other work within the approved task and milestone may proceed.
- Follow the active phase and milestone order in `docs/roadmap.md` unless the phase plan says otherwise. Create the roadmap when planning the first phase.

## Decided — ask before changing

- **Technical stack:** Swift and SwiftUI for iOS.
- **Product scope:** [product-behavior.md](docs/product-behavior.md).
- **Owner-confirmed v1 behavior:** [confirmed v1 behavior](docs/product-behavior.md#confirmed-v1-behavior).
- **Diary creation and destination:** use transcription output to initialize one managed diary body, generate a short read-only summary title with Apple's on-device model when available, and save automatically. Select an iCloud folder before the first recording and allow an explicit replacement for a pending recording whose original folder is permanently inaccessible; see [product behavior](docs/product-behavior.md).
- **V1 transcription:** offer Apple on-device and an on-device Cohere Transcribe method based on `CohereLabs/cohere-transcribe-03-2026` or a suitable English/Korean Cohere variant. Install the local model before use; pin approved model versions and digests in the app, requiring an app update for new approvals. Show download size and preflight free space without a fixed policy cap on model/cache size. Ask the user to choose a ready approved method when the selected method is unavailable, without automatic switching. Hosted Qwen is future work; see [product behavior](docs/product-behavior.md).
- **V1 Cohere implementation direction:** P1-M6 selected the runtime-publisher `cohere-transcribe-03-2026-Q4_K_M.gguf` with `transcribe.cpp` and Metal for P1-M12. Production must pin the runtime, URL, byte count, and digest in its trusted manifest, require an explicit `en` or `ko` hint, reject truncated output, avoid automatic CPU fallback, and use silence-aware chunks no longer than 45 seconds until longer input is proven complete on the target phone. See the [P1-M6 results](docs/phase-1/milestone-06-cohere-runtime-trial-results.md).
- **Title, diary text, and conflicts:** prefer an Apple on-device AI summary of the whole diary body for the read-only title when the model is available; use the first-sentence fallback if it is unavailable or produces an unusable result. Both title paths have a strict 30-Swift-grapheme-cluster maximum, including any ellipsis. Long-body summarization must consider all parts within bounded work or use the fallback. Regenerate on body save, using the body's current language, and keep a fallback title until the next body save if the model later becomes ready. Store the title and its origin in Markdown front matter. User edits replace the managed body; do not retain a separate original transcript. Select the latest conflicting iCloud edit by iCloud modification time; see [product behavior](docs/product-behavior.md).
- **Recording limit and interruptions:** Stop & Transcribe is the only user control during capture and queues playable audio for automatic processing while the app is open. Locking the iPhone does not stop capture; if capture ends while locked, finalize and durably queue it immediately. Target mono 44.1 kHz AAC `.m4a` at about 64 kb/s, subject to target-phone compatibility checks. Stop and queue automatically at five minutes or after an audio interruption with a playable partial recording; see [product behavior](docs/product-behavior.md).
- **First-launch microphone access:** explain and request microphone permission during the first-time experience. Denial leaves non-recording features usable; Record offers a system Settings recovery path and capture requires permission; see [product behavior](docs/product-behavior.md).
- **Future hosted Qwen:** its prior key, consent, budget, and network-retry decisions are preserved for future work, not v1 controls or jobs; see [product behavior](docs/product-behavior.md).
- **Manual retry and reminder:** a manual transcription retry uses current Settings at retry time and is allowed without a fixed count limit while the recording remains. Schedule a local pending-work reminder for the next local day at the same local time the user left the app, and cancel it if all pending work finishes first. If notification permission is denied, show in-app pending state and a nonblocking system Settings path without repeated permission prompts; see [product behavior](docs/product-behavior.md).
- **Queue progress and removal:** process the oldest ready recording while the app is open; a waiting, failed, or destination-blocked job does not block newer ready work. Apply a ten-minute hard cutoff to nonsettling local inference, preserve its audio and reason, and isolate malformed job state so other valid jobs continue. Advance only after the adapter relinquishes work. Continue local transcription and diary creation if the iCloud destination is temporarily unavailable, then wait to save the draft. Allow confirmed removal of pending or failed recordings and their private audio, with in-flight work invalidated. Show Cancelling for an in-flight removal until work stops and removal completes. Cancel unverified saves after removal confirmation; preserve an asset fully verified before confirmation and explain completion; see [product behavior](docs/product-behavior.md).
- **Pending-data backup:** exclude pending audio and unsaved diary drafts from device backup, accepting possible loss after device loss; earlier backups may still contain copies. Quarantine any pending jobs restored from an older backup for user review before transcription or iCloud save. See [product behavior](docs/product-behavior.md).
- **Asset timestamps and optional metadata:** `created_at` is when recording started and controls local-date grouping; `updated_at` changes on a saved text or metadata edit, not on iCloud sync. Omit unavailable weather/location fields; see [product behavior](docs/product-behavior.md).
- **Asset references and provenance:** preserve the existing UTC `year/month/day` Markdown layout with a sibling UTC-named `.assets` audio directory. New Markdown front matter uses flat keys and includes a schema version, an explicit audio filename, and the effective transcription method/model/conversion and applicable settings. When location is available, save exact returned coordinates and a place name if lookup succeeds; see [product behavior](docs/product-behavior.md).
- **P1-M5 contract:** canonical UUID/timestamp forms, exact Diary Snippet fields and limits, title budgets, queue copy, recovery placement, privacy controls, icon/accessibility rules, and downstream evidence assignments are in the [approved decision contracts](docs/phase-1/milestone-05-decisions-architecture.md).
- **Optional context and replay:** request location permission on first launch and expose it in Settings; denial does not block recording. Location and weather describe recording start; accept a location sample no older than five minutes with accuracy at most 500 m, and weather observed within 60 minutes. Keep accepted coordinates even if place lookup fails. If recording-time weather is unavailable, omit it without later backfill. Replay offers play/pause, seeking, and elapsed/total time; see [product behavior](docs/product-behavior.md).
- **Root screen containment:** Main shows the full active-folder diary collection with on-demand loading and infinite scroll; All shows no diary snippets for now and is the sole Settings entry. Record is a floating control on Main. Main's top one-line notice bar rotates processing, queued, and recovery messages every 10 seconds, pausing for VoiceOver or Reduce Motion; see [UX GUI](docs/ux-gui.md).
- **Architecture rule:** follow Clean Architecture's inward source-dependency rule and allow additional asset kinds and transcription methods through registered, type-specific adapters; see [software architecture](docs/architecture.md).
- **Pending, recovery, and detail screens:** All contains separate Pending Recordings, Failed Recordings, Incomplete Diary Snippets, and Conflicting Versions screens. Conflict versions appear in vertically scrollable tabs; confirm before removing the unchosen version. Diary Snippet detail shows Title and Diary body first, Favorite beside Title, and Audio replay plus read-only recording details inside bottom Metadata; see [UX GUI](docs/ux-gui.md).
- **Editing:** the editor changes only the diary body; a save regenerates the read-only title using the approved title policy. Favorite is a separate on/off toggle; see [UX GUI](docs/ux-gui.md).
- **Empty edits and commit recovery:** an empty edited diary body saves with the title "Untitled". Retry a saved draft automatically when iCloud access returns, and delete private local staging immediately after the complete iCloud pair is verified locally and both files report successful upload; see [product behavior](docs/product-behavior.md).
- **Legacy and interrupted recordings:** show existing Markdown/audio pairs without the new schema fields as read-only without changing their files. Keep an unplayable interrupted recording in Failed Recordings with an entry-level reason; see [product behavior](docs/product-behavior.md).
- **Recovery edge cases:** unusable transcription fails with audio retained, no asset, manual retry, and an entry-level reason. Equal or missing iCloud conflict times present two separately openable versions for the user to choose between. Repair incomplete Diary Snippet writes from retained local candidates on reopen. When no repair copy exists, keep and flag the incomplete pair, show surviving content read-only, and offer confirmed removal; see [product behavior](docs/product-behavior.md).
- **Interaction model:** [ux-gui.md](docs/ux-gui.md). Component vocabulary is in [ux-terms.md](docs/ux-terms.md) and the layout containment model in [ux-information-architecture.md](docs/ux-information-architecture.md).
- **License:** Apache-2.0 for all project code.
- **Project generation:** use XcodeGen in P1-M3; see the [Phase 1 changelog](docs/phase-1/changelog.md).
- **Minimum iOS version:** set the Xcode deployment target to iOS 27.0 and enforce iOS 27.0.1 at launch; see the [P1-M3 approach](docs/phase-1/milestone-03-scaffolding-architecture.md).
- **P1-M1, P1-M2, P1-M4, P1-M5, and P1-M6 validation:** These milestones have no build, lint, or test completion gate. Their checklists and documentation remain required. See the [Phase 1 changelog](docs/phase-1/changelog.md).
- **Process:** numbered phases contain numbered milestones; milestone numbering restarts per phase. IDs use `P1-M2`. See [docs/development-process.md](docs/development-process.md).

## Undecided — ask before inventing

P1-M5 and P1-M6 resolved the current v1 product and Cohere-direction choices. Ask before inventing:

- A different Cohere runtime, quantization, backend, model host, or relaxation of the P1-M6 safeguards. P1-M12 still owes production integration, provenance, chunk-seam, cancellation, and long-input evidence; P1-M6 did not establish five-minute quality, energy, or WER/CER.
- Mechanism changes that would alter the approved P1-M5 outcomes. P1-M8, P1-M9, P1-M14, P1-M17, and P1-M19 still owe platform and adversarial evidence.
- Hosted Qwen model IDs, controls, and budget details, which remain future work.

## Environment

- macOS with Xcode 27.2 or later and the iOS SDK.
- SwiftLint installed and available on PATH.
- An iPhone simulator suitable for the target device.

## Commands

```sh
swift-format format --in-place --recursive .  # format Swift source
swift-format lint --strict --recursive .      # check Swift formatting
swiftlint lint --strict                       # lint Swift source
TEST_DESTINATION='platform=iOS Simulator,name=<available iPhone>' scripts/validate.sh  # quiet full gate
```

## Code conventions

- Use Swift and SwiftUI for the iOS app.
- Format Swift with swift-format and keep SwiftLint warnings resolved.
- Use UTC for asset file and directory names and local time for display.

## Dependencies

Project-owned code remains Apache-2.0. Dependency license compatibility is not an approval or milestone gate. Changes to dependencies or build tools still require owner approval.

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
