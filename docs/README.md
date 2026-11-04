# Documentation index

Status: Active

Start with the guides below, then read only the relevant milestone or research record. Follow the [documentation rules](development-process.md#documentation-rules) when editing or adding docs.

## Guides

| Doc | What it covers |
|---|---|
| [../README.md](../README.md) | User overview and known issues. |
| [../AGENTS.md](../AGENTS.md) | Agent workflow, approval boundaries, and decision links; imported by `CLAUDE.md`. |
| [roadmap.md](roadmap.md) | Project phases and the active phase. |
| [architecture.md](architecture.md) | Clean Architecture boundaries, state ownership, title settlement, recording removal, diary deletion, purge recovery, and implementation evidence gates. |
| [security-review.md](security-review.md) | Architecture threat model, approved controls, prioritized findings, and pending adversarial verification. |
| [development-process.md](development-process.md) | Phases, milestones, definition of done, validation exemptions, documentation rules, and archival. |
| [contribution-guide.md](contribution-guide.md) | Setup, commands, code/repository conventions, simulator access, real-iPhone testing, and commit messages. |
| [product-behavior.md](product-behavior.md) | Product scope: what the app does and what it deliberately does not do. |
| [ux-terms.md](ux-terms.md) | Exact approved labels and canonical workflow concepts with code-facing identifiers. |
| [ux-information-architecture.md](ux-information-architecture.md) | The Standard Layout: root hierarchy, destinations, and recovery boundaries. |
| [ux-gui.md](ux-gui.md) | Current interface and owner-approved GUI behavior, with planned behavior kept separate. |

## Phase 1 plans and evidence

| Doc | What it covers |
|---|---|
| [phase-1/phase-1.md](phase-1/phase-1.md) | Phase 1 milestones. |
| [phase-1/milestone-01-research-overview.md](phase-1/milestone-01-research-overview.md) | Completed P1-M1 research scope, evidence checklist, and Cohere device-trial handoff. |
| [phase-1/milestone-01-research-architecture.md](phase-1/milestone-01-research-architecture.md) | P1-M1 research approach. |
| [phase-1/milestone-02-software-architecture-overview.md](phase-1/milestone-02-software-architecture-overview.md) | P1-M2 scope and completion checklist. |
| [phase-1/milestone-02-software-architecture-architecture.md](phase-1/milestone-02-software-architecture-architecture.md) | P1-M2 architecture work sequence and review criteria. |
| [phase-1/milestone-03-scaffolding-overview.md](phase-1/milestone-03-scaffolding-overview.md) | P1-M3 scope and completion checklist. |
| [phase-1/milestone-03-scaffolding-architecture.md](phase-1/milestone-03-scaffolding-architecture.md) | P1-M3 target structure, project generation, and validation approach. |
| [phase-1/milestone-04-ux-overview.md](phase-1/milestone-04-ux-overview.md) | P1-M4 scope, completion checklist, and validation exemption. |
| [phase-1/milestone-04-ux-architecture.md](phase-1/milestone-04-ux-architecture.md) | P1-M4 design sequence and review criteria. |
| [phase-1/milestone-05-decisions-overview.md](phase-1/milestone-05-decisions-overview.md) | Completed P1-M5 decision checklist and downstream evidence assignments. |
| [phase-1/milestone-05-decisions-architecture.md](phase-1/milestone-05-decisions-architecture.md) | Owner-approved title, schema, recording, queue, iCloud, security, context, and interface contracts. |
| [phase-1/milestone-06-cohere-runtime-trial-overview.md](phase-1/milestone-06-cohere-runtime-trial-overview.md) | Completed P1-M6 isolated Cohere iPhone trial scope and evidence checklist. |
| [phase-1/milestone-06-cohere-runtime-trial-architecture.md](phase-1/milestone-06-cohere-runtime-trial-architecture.md) | P1-M6 trial boundaries, implementation approach, result contract, and decision gate. |
| [phase-1/milestone-06-cohere-runtime-trial-protocol.md](phase-1/milestone-06-cohere-runtime-trial-protocol.md) | Original target-iPhone Q4/Q5 English/Korean measurement protocol. |
| [phase-1/milestone-06-cohere-runtime-trial-results.md](phase-1/milestone-06-cohere-runtime-trial-results.md) | P1-M6 target-phone evidence, troubleshooting findings, Q4_K_M/Metal decision, and explicitly unperformed checks. |
| [phase-1/milestone-07-asset-storage-overview.md](phase-1/milestone-07-asset-storage-overview.md) | P1-M7 asset-schema and private-storage scope, checklist, and acceptance evidence. |
| [phase-1/milestone-07-asset-storage-architecture.md](phase-1/milestone-07-asset-storage-architecture.md) | P1-M7 domain boundaries, strict codec, confined workspace, tests, and downstream handoff. |
| [phase-1/milestone-08-first-launch-settings-icloud-overview.md](phase-1/milestone-08-first-launch-settings-icloud-overview.md) | P1-M8 permission onboarding, Settings, iCloud-only destination scope, checklist, and device evidence. |
| [phase-1/milestone-08-first-launch-settings-icloud-architecture.md](phase-1/milestone-08-first-launch-settings-icloud-architecture.md) | P1-M8 permission state machines, transactional bookmarks, provider validation, tests, and handoffs. |
| [phase-1/milestone-08-first-launch-settings-icloud-device-evidence.md](phase-1/milestone-08-first-launch-settings-icloud-device-evidence.md) | P1-M8 redacted target-iPhone evidence matrix and current physical-device blockers. |
| [phase-1/by-human-test-required.md](phase-1/by-human-test-required.md) | Pending physical-device scenarios and redacted evidence, including the M16 follow-up. |
| [phase-1/milestone-09-recording-capture-recovery-overview.md](phase-1/milestone-09-recording-capture-recovery-overview.md) | P1-M9 capture, durable settlement, recovery scope, and verifiable completion checklist. |
| [phase-1/milestone-09-recording-capture-recovery-architecture.md](phase-1/milestone-09-recording-capture-recovery-architecture.md) | P1-M9 audio/workspace boundaries, receipt handoff, sequencing, and target-phone evidence matrix. |
| [phase-1/milestone-09-recording-capture-recovery-device-evidence.md](phase-1/milestone-09-recording-capture-recovery-device-evidence.md) | P1-M9 redacted target-iPhone scenario record awaiting owner runs. |
| [phase-1/milestone-10-durable-processing-queue-overview.md](phase-1/milestone-10-durable-processing-queue-overview.md) | P1-M10 queue scope, entry condition, and verifiable completion checklist. |
| [phase-1/milestone-10-durable-processing-queue-architecture.md](phase-1/milestone-10-durable-processing-queue-architecture.md) | P1-M10 receipt adoption, scheduling, quarantine, cancellation, removal, and validation sequence. |
| [phase-1/milestone-10-durable-processing-queue-device-evidence.md](phase-1/milestone-10-durable-processing-queue-device-evidence.md) | P1-M10 redacted backup/restore and prior-install quarantine evidence awaiting owner runs. |
| [phase-1/milestone-11-apple-on-device-transcription-overview.md](phase-1/milestone-11-apple-on-device-transcription-overview.md) | P1-M11 Apple transcription, readiness, installation, result-handoff scope, and completion checklist. |
| [phase-1/milestone-11-apple-on-device-transcription-architecture.md](phase-1/milestone-11-apple-on-device-transcription-architecture.md) | P1-M11 SpeechAnalyzer boundaries, asset state machine, file inference, staging, and cancellation sequence. |
| [phase-1/milestone-11-apple-on-device-transcription-device-evidence.md](phase-1/milestone-11-apple-on-device-transcription-device-evidence.md) | P1-M11 redacted English/Korean installation, offline inference, and cancellation evidence awaiting target-phone runs. |
| [phase-1/milestone-12-cohere-transcription-overview.md](phase-1/milestone-12-cohere-transcription-overview.md) | P1-M12 model installation and Cohere transcription scope, entry conditions, and completion checklist. |
| [phase-1/milestone-12-cohere-transcription-architecture.md](phase-1/milestone-12-cohere-transcription-architecture.md) | P1-M12 trusted installation, Metal inference, chunking, queue integration, and target-phone evidence plan. |
| [phase-1/milestone-12-cohere-transcription-device-evidence.md](phase-1/milestone-12-cohere-transcription-device-evidence.md) | P1-M12 redacted trusted-installation, English/Korean long-input, cancellation, and privacy evidence record. |
| [phase-1/milestone-13-diary-drafts-titles-overview.md](phase-1/milestone-13-diary-drafts-titles-overview.md) | P1-M13 managed-draft and title scope, entry conditions, and completion checklist. |
| [phase-1/milestone-13-diary-drafts-titles-architecture.md](phase-1/milestone-13-diary-drafts-titles-architecture.md) | P1-M13 candidate adoption, bounded title policy, durable draft ordering, and recovery sequence. |
| [phase-1/milestone-13-diary-drafts-titles-device-evidence.md](phase-1/milestone-13-diary-drafts-titles-device-evidence.md) | P1-M13 redacted target-iPhone title, draft, lifecycle, and privacy evidence record. |
| [phase-1/milestone-14-icloud-commit-reconciliation-overview.md](phase-1/milestone-14-icloud-commit-reconciliation-overview.md) | P1-M14 coordinated iCloud pair, upload proof, repair, conflict scope, and completion checklist. |
| [phase-1/milestone-14-icloud-commit-reconciliation-architecture.md](phase-1/milestone-14-icloud-commit-reconciliation-architecture.md) | P1-M14 commit record, publication ordering, upload observation, recovery, and validation approach. |
| [phase-1/milestone-14-icloud-commit-reconciliation-device-evidence.md](phase-1/milestone-14-icloud-commit-reconciliation-device-evidence.md) | P1-M14 redacted target-iPhone iCloud publication, upload, repair, conflict, and race evidence record. |
| [phase-1/milestone-15-main-collection-diary-detail-overview.md](phase-1/milestone-15-main-collection-diary-detail-overview.md) | P1-M15 active-folder collection, read-only detail, notice, icon, and completion checklist. |
| [phase-1/milestone-15-main-collection-diary-detail-architecture.md](phase-1/milestone-15-main-collection-diary-detail-architecture.md) | P1-M15 normalized ordering, bounded discovery/I/O, active-session integration, typed recovery, and read-only presentation. |
| [phase-1/milestone-15-main-collection-diary-detail-device-evidence.md](phase-1/milestone-15-main-collection-diary-detail-device-evidence.md) | P1-M15 redacted target-iPhone ordering/paging, refresh, legacy/audio, resource/cancellation, conflict, accessibility, and privacy evidence record. |
| [phase-1/milestone-16-diary-editing-favorite-audio-replay-overview.md](phase-1/milestone-16-diary-editing-favorite-audio-replay-overview.md) | Active P1-M16 editing/Favorite/replay implementation, completion evidence and remaining device checklist. |
| [phase-1/milestone-16-diary-editing-favorite-audio-replay-architecture.md](phase-1/milestone-16-diary-editing-favorite-audio-replay-architecture.md) | Implemented independent edit journal, stable submissions, shared titles, checked replacement/retirement, conflict snapshots, replay/capture ownership, and purge integration. |
| [phase-1/milestone-16-diary-editing-favorite-audio-replay-device-evidence.md](phase-1/milestone-16-diary-editing-favorite-audio-replay-device-evidence.md) | Passing simulator gate and 73 iPhone checks, cleanup correction, unresolved hosted interaction tests, and partial M16-D01–D11 evidence. |
| [phase-1/milestone-17-recovery-overview.md](phase-1/milestone-17-recovery-overview.md) | P1-M17 recovery scope, owner-specific prerequisites, and verifiable completion checklist. |
| [phase-1/milestone-17-recovery-architecture.md](phase-1/milestone-17-recovery-architecture.md) | P1-M17 typed inventories/actions, restore/retry/retargeting, exact-resource removal, conflict choice, and validation sequence. |
| [phase-1/milestone-17-recovery-device-evidence.md](phase-1/milestone-17-recovery-device-evidence.md) | P1-M17 redacted target-iPhone recovery navigation, retry, restore, replacement/removal races, incomplete/conflict, and privacy evidence record. |
| [phase-1/milestone-18-context-reminders-overview.md](phase-1/milestone-18-context-reminders-overview.md) | P1-M18 recording-start location/weather, pending-work reminder scope, prerequisites, and completion checklist. |
| [phase-1/milestone-18-context-reminders-architecture.md](phase-1/milestone-18-context-reminders-architecture.md) | P1-M18 bounded context acquisition, protected draft/publication handoff, permission boundaries, and departure/calendar reminder sequence. |
| [phase-1/milestone-18-context-reminders-device-evidence.md](phase-1/milestone-18-context-reminders-device-evidence.md) | P1-M18 redacted target-iPhone context, WeatherKit, revocation, lock/lifecycle, reminder, accessibility, and privacy evidence record. |
| [phase-1/milestone-15-legacy-format.md](phase-1/milestone-15-legacy-format.md) | Owner-evidenced pre-v1 timestamp/header/audio layout and synthetic-fixture contract. |
| [phase-1/milestone-20-enhancements-fixes-refactoring-overview.md](phase-1/milestone-20-enhancements-fixes-refactoring-overview.md) | Active P1-M20 checklists, Settings and transcription repairs, installed-Q4 false storage pause, phone/runtime evidence, recording controls, Danger Zone purges, Diary Snippet deletion, and implementation-review fixes. |
| [phase-1/milestone-20-enhancements-fixes-refactoring-architecture.md](phase-1/milestone-20-enhancements-fixes-refactoring-architecture.md) | P1-M20 repair approaches, folder-picker, Settings, Q4 result handoff/storage pause, Korean Q4/Q5 recovery, Apple Local diagnosis, pair metadata, responsiveness, exact-pair deletion, and purge/interaction safeguards. |
| [phase-1/milestone-21-architecture-gui-enhancement-overview.md](phase-1/milestone-21-architecture-gui-enhancement-overview.md) | Active post-M16 work, delivered task evidence, remaining GUI/device checks, and staged Main-loading implementation criteria. |
| [phase-1/milestone-21-architecture-gui-enhancement-architecture.md](phase-1/milestone-21-architecture-gui-enhancement-architecture.md) | Lifecycle/identity/save evidence, upcoming-task review findings, and the Main catalog proposal's demand, frontier, action, cache, and benchmark contracts. |
| [phase-1/changelog.md](phase-1/changelog.md) | Phase 1 owner decisions and plan changes. |

## Research

| Doc | What it covers |
|---|---|
| [research/initial-ideas-from-owner.md](research/initial-ideas-from-owner.md) | Narihito's Diary Mobile, in short, NDM, or ndm is an app that creates assets. |
| [research/p1-m1-qwen-transcription.md](research/p1-m1-qwen-transcription.md) | Qwen transcription research for English and Korean diary recordings. |
| [research/p1-m1-audio-format.md](research/p1-m1-audio-format.md) | iPhone recording format research and provisional codec/bitrate recommendation. |
| [research/p1-m1-whisper-cpp-iphone.md](research/p1-m1-whisper-cpp-iphone.md) | whisper.cpp iPhone 17 Pro Max feasibility and compatible local model candidates. |
| [research/p1-m1-qwen3-asr-iphone.md](research/p1-m1-qwen3-asr-iphone.md) | On-device Qwen3-ASR 0.6B/1.7B iPhone feasibility, published benchmarks, and device-test gaps. |
| [research/p1-m1-qwen3-forced-aligner-iphone.md](research/p1-m1-qwen3-forced-aligner-iphone.md) | Qwen3-ForcedAligner-0.6B word-timing evidence, native runtimes, and iPhone test gaps. |
| [research/p1-m1-swift-speech-sdks.md](research/p1-m1-swift-speech-sdks.md) | WhisperKit and FluidAudio Swift/Core ML integration, English/Korean model coverage, and long-audio constraints. |
| [research/p1-m1-cohere-transcribe-iphone.md](research/p1-m1-cohere-transcribe-iphone.md) | ASR-only Cohere Transcribe en-US/ko-KR iPhone paths across Core ML, GGUF, and Swift/MLX, with measured evidence and efficient device-trial design. |
| [research/p1-m1-platform-decision-evidence.md](research/p1-m1-platform-decision-evidence.md) | Apple platform evidence and device-trial gaps for iCloud commits, speech readiness, titles, context, private staging, and reminders. |
| [research/p1-m1-open-decisions.md](research/p1-m1-open-decisions.md) | Closed P1-M1/P1-M5 decision inventory with remaining implementation-evidence and P1-M6 handoffs. |
