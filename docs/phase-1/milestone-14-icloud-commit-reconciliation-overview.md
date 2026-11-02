# P1-M14: iCloud commit and reconciliation overview

Status: Implementation complete; target-iPhone evidence pending

Publish a verified M13 Diary Snippet draft and its recording to the capture-time iCloud folder, prove the local pair and each file's upload before releasing private staging, and reconcile interrupted writes and conflicting versions without overwriting unrelated content.

## Entry and locked inputs

- Follow [Phase 1 order](phase-1.md): implementation follows P1-M13 completion unless the owner authorizes a reorder. Planning does not close earlier open gates or target-phone evidence.
- Use the [P1-M5 storage contract](milestone-05-decisions-architecture.md), [M7 codec and private workspace](milestone-07-asset-storage-architecture.md), [M8 destination capability](milestone-08-first-launch-settings-icloud-architecture.md), [M10 mutation barrier](milestone-10-durable-processing-queue-architecture.md), and [M13 verified draft handle](milestone-13-diary-drafts-titles-architecture.md). Preserve the approved [product behavior](../product-behavior.md) and [security boundary](../architecture.md#mutation-and-recovery-integrity).
- The original capture destination remains authoritative even when Settings changes the active folder. A temporary provider failure never authorizes replacement. M17 owns the explicit, per-job replacement flow after the user confirms permanent removal or revoked access.
- M14 implements commit and reconciliation mechanics. M15 owns collection/detail display, M16 supplies edited-body/Favorite saves through the same store contract, M17 owns full Incomplete Diary Snippets and Conflicting Versions screens, and M19 tests the complete experience.

## Scope

- Accept only a current verified draft and leased verified audio. Bind a durable commit record to the job, stable asset ID, attempt, source digests, exact UTC pair names, destination and body revisions, and observed external versions. Resolve the capture-time destination snapshot independently of the current Settings selection, while revalidating its original iCloud identity and security scope before each operation.
- Under the M10 per-job mutation barrier, coordinate exclusive or expected-version writes. Write audio before Markdown; never overwrite a different resource that happens to share a filename or asset ID. Reopen both through coordination and verify the decoded Markdown reference, exact expected bytes, audio identity, containment, and pair ownership.
- Observe successful upload separately for Markdown and audio in the capture-time user-picked iCloud folder. Local readability, bookmark resolution, and a single file's upload report cannot complete the job. Keep the draft and audio while either report is missing, unavailable, or failed; retry verification and saves on later foreground access without repeating transcription. If the platform cannot provide the required per-file signal on the target iPhone, leave the gate open for owner review rather than substituting a heuristic.
- Persist completion evidence before advancing the job; then promptly remove only its identified private staging. Resume interrupted cleanup without republishing. A save to a former active folder emits the approved completion event without changing the active collection.
- Bound each active provider and upload-observation attempt. When proof is unavailable, durably record the wait, cancel observers, let coordinated work relinquish, and release the per-job barrier before scheduling other work; a later retry reacquires it and verifies the pair again. An unsettled operation keeps ownership until it actually relinquishes; show `Cancelling` if removal is confirmed during that interval.
- Reconcile partial writes on reopen only from a matching retained private draft/audio candidate and commit record with expected external versions. Classify independently discovered incomplete pairs without a local candidate as read-only recovery items for M15's catalog and M17's screens. Preserve changed, ambiguous, or unmatched files. For complete conflicts, compare iCloud modification times only after validating both whole pairs; select the later version only when whole-pair ordering is unambiguous, or preserve equal, missing, or ambiguous times for explicit user choice. Keep protected pair snapshots until the chosen complete pair is published and verified, then remove only positively identified obsolete versions and snapshots.
- Fault-test queue and provider failures, stale callbacks, removal/retarget races, duplicate IDs, malicious references, upload-signal absence, and relaunch at each durable boundary. Unrelated ready jobs continue while a save waits.

## Out of scope

M14 does not change the approved schema or title, perform transcription, infer permanent folder loss, automatically retarget a job, remove a completed asset on user request, add a new provider or dependency, or build the full recovery screens. It does not claim that an upload report proves another device has received the files.

## Completion checklist

- [x] A current M13 draft and audio publish once to the original destination with stable UTC names. Coordinated writes use the M10 barrier, exclusive creation or checked replacement, revalidated folder/file containment, and generation/revision fences; an active-folder change or duplicate asset ID cannot redirect or overwrite work.
- [x] Local coordinated verification reopens the complete Markdown/audio pair, validates codec/reference and actual audio identity, and matches both files to private expected lengths and digests. Changed, malformed, unsupported, or ambiguous external content is preserved and never treated as a successful commit.
- [ ] Target-iPhone evidence establishes separate successful upload observation for both files in a user-picked iCloud Drive folder. Missing/uncertain status retains protected, backup-excluded staging and a truthful waiting reason; access recovery retries without retranscription. If this signal cannot be established, this item remains unchecked for owner review.
- [x] A bounded save attempt that cannot observe upload proof durably waits, settles provider work, and releases its per-job barrier; retry reclaims and re-verifies before using any prior observation. A nonsettling operation never acknowledges cancellation or starts a conflicting attempt.
- [x] Completion evidence is durable before the job is reported saved; private draft, audio, binding, destination snapshot, and other owned staging are removed promptly after proof. Faults between proof, state update, and cleanup converge on one saved asset with no premature deletion or duplicate publication.
- [x] Reopen repairs an owned incomplete pair from a retained candidate only when commit evidence and observed versions agree. Independently discovered pairs with no candidate, or pairs changed after the intent, remain read-only recovery items. Complete conflicts use unambiguous whole-pair iCloud modification-time ordering; equal, missing, and cross-ordered times preserve two selectable versions. Obsolete files/snapshots are removed only after the chosen pair verifies.
- [x] Reconciliation exposes typed, non-destructive recovery records with the surviving Markdown or playable audio and the missing component; M17 can render and confirm removal without reinterpreting raw provider state. Ambiguous pair ordering also retains both versions for user choice.
- [x] Removal and explicit per-job destination-revision changes fence every save/repair callback. A removal accepted before publication prevents it; a verified completion accepted first remains saved; uncertain coordination stays recoverable. Adversarial file-reference and ownership tests cannot delete or overwrite another asset.
- [ ] The [target-iPhone evidence record](milestone-14-icloud-commit-reconciliation-device-evidence.md) has redacted pass evidence for M14-D01–M14-D07, including upload observation, offline/revoked access, partial-write repair, conflicts, removal races, and privacy.
- [x] Affected docs describe the implemented handoff. `make lint` and `TEST_DESTINATION=… scripts/validate.sh` pass with the destination recorded; unavailable gates remain unchecked with the blocker reported. The gate passed on 2026-11-02 with `platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082`.

## Implementation review follow-up (2026-11-02)

- [x] Preserve two validated text conflict candidates sharing one uniquely matched audio version, with explicit choice under the existing equal-time policy; continue rejecting ambiguous digest matches.
- [x] Checkpoint the exact verified interrupted-conflict publication observation without a later unchecked read.
- [x] Refresh provider resource metadata around hashing, and distinguish temporarily missing files from unsafe resources during verification.
- [x] Confirmed pending-recording removal deletes only its identified private conflict snapshots, retries partial cleanup, and preserves unrelated snapshots.
- [x] Add regression coverage and rerun `make lint` and the simulator validation gate; retain the separate target-iPhone evidence blockers.

Evidence: `AppleDiaryPairStoreTests` covers shared-audio choice, ambiguous digest rejection, unchanged shared audio, and interrupted publication adoption. `DiaryFileObservationTests` covers refreshed real file metadata and retryable missing files. `DiaryConflictSnapshotTests` covers interrupted/idempotent private-copy removal while preserving unrelated snapshots. The delegated review gate passed `make lint` and `TEST_DESTINATION='platform=iOS Simulator,id=993AECCC-055E-4C46-8F3B-D2913A5C1082' scripts/validate.sh` on 2026-11-02: generation, lint, build, and 243 tests across 29 suites passed. This does not close M14-D01–M14-D07.
