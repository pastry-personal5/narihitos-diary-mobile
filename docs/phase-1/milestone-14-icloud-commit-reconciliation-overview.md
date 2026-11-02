# P1-M14: iCloud commit and reconciliation overview

Status: Planned

Publish a verified M13 Diary Snippet draft and its recording to the capture-time iCloud folder, prove the local pair and each file's upload before releasing private staging, and reconcile interrupted writes and conflicting versions without overwriting unrelated content.

## Entry and locked inputs

- Follow [Phase 1 order](phase-1.md): implementation follows P1-M13 completion unless the owner authorizes a reorder. Planning does not close earlier open gates or target-phone evidence.
- Use the [P1-M5 storage contract](milestone-05-decisions-architecture.md), [M7 codec and private workspace](milestone-07-asset-storage-architecture.md), [M8 destination capability](milestone-08-first-launch-settings-icloud-architecture.md), [M10 mutation barrier](milestone-10-durable-processing-queue-architecture.md), and [M13 verified draft handle](milestone-13-diary-drafts-titles-architecture.md). Preserve the approved [product behavior](../product-behavior.md) and [security boundary](../architecture.md#mutation-and-recovery-integrity).
- The original capture destination remains authoritative even when Settings changes the active folder. A temporary provider failure never authorizes replacement. M17 owns the explicit, per-job replacement flow after the user confirms permanent removal or revoked access.
- M14 implements commit and reconciliation mechanics. M15 owns collection/detail display, M16 supplies edited-body/Favorite saves through the same store contract, M17 owns full Incomplete Diary Snippets and Conflicting Versions screens, and M19 tests the complete experience.

## Scope

- Accept only a current verified draft and leased verified audio. Bind a durable commit record to the job, stable asset ID, attempt, source digests, exact UTC pair names, destination and body revisions, and observed external versions. Revalidate the original destination through a bounded security-scoped capability before each operation.
- Under the M10 per-job mutation barrier, coordinate exclusive or expected-version writes. Write audio before Markdown; never overwrite a different resource that happens to share a filename or asset ID. Reopen both through coordination and verify the decoded Markdown reference, exact expected bytes, audio identity, containment, and pair ownership.
- Observe successful upload separately for Markdown and audio in the selected user-picked iCloud folder. Local readability, bookmark resolution, and a single file's upload report cannot complete the job. Keep the draft and audio while either report is missing, unavailable, or failed; retry verification and saves on later foreground access without repeating transcription. If the platform cannot provide the required per-file signal on the target iPhone, leave the gate open for owner review rather than substituting a heuristic.
- Persist completion evidence before advancing the job; then promptly remove only its identified private staging. Resume interrupted cleanup without republishing. A save to a former active folder emits the approved completion event without changing the active collection.
- Reconcile partial writes on reopen only from a matching retained private candidate and commit record with expected external versions. Preserve changed, ambiguous, or unmatched files and surface typed incomplete/conflict items. For complete conflicts, compare iCloud modification times only after validating both whole pairs; select the later comparable version, or preserve equal/missing-time versions for explicit user choice. Keep protected pair snapshots until the chosen complete pair is published and verified, then remove only positively identified obsolete versions and snapshots.
- Fault-test queue and provider failures, stale callbacks, removal/retarget races, duplicate IDs, malicious references, upload-signal absence, and relaunch at each durable boundary. Unrelated ready jobs continue while a save waits.

## Out of scope

M14 does not change the approved schema or title, perform transcription, infer permanent folder loss, automatically retarget a job, remove a completed asset on user request, add a new provider or dependency, or build the full recovery screens. It does not claim that an upload report proves another device has received the files.

## Completion checklist

- [ ] A current M13 draft and audio publish once to the original destination with stable UTC names. Coordinated writes use the M10 barrier, exclusive creation or checked replacement, revalidated folder/file containment, and generation/revision fences; an active-folder change or duplicate asset ID cannot redirect or overwrite work.
- [ ] Local coordinated verification reopens the complete Markdown/audio pair, validates codec/reference and actual audio identity, and matches both files to private expected lengths and digests. Changed, malformed, unsupported, or ambiguous external content is preserved and never treated as a successful commit.
- [ ] Target-iPhone evidence establishes separate successful upload observation for both files in a user-picked iCloud Drive folder. Missing/uncertain status retains protected, backup-excluded staging and a truthful waiting reason; access recovery retries without retranscription. If this signal cannot be established, this item remains unchecked for owner review.
- [ ] Completion evidence is durable before the job is reported saved; private draft, audio, binding, destination snapshot, and other owned staging are removed promptly after proof. Faults between proof, state update, and cleanup converge on one saved asset with no premature deletion or duplicate publication.
- [ ] Reopen repairs an owned incomplete pair from a retained candidate only when commit evidence and observed versions agree. With no candidate, or after external change/collision, surviving files remain read-only recovery items. Complete conflicts use comparable iCloud modification times; equal/missing times preserve two selectable versions, and obsolete files/snapshots are removed only after the chosen pair verifies.
- [ ] Removal and explicit per-job destination-revision changes fence every save/repair callback. A removal accepted before publication prevents it; a verified completion accepted first remains saved; uncertain coordination stays recoverable. Adversarial file-reference and ownership tests cannot delete or overwrite another asset.
- [ ] The [target-iPhone evidence record](milestone-14-icloud-commit-reconciliation-device-evidence.md) has redacted pass evidence for M14-D01–M14-D07, including upload observation, offline/revoked access, partial-write repair, conflicts, removal races, and privacy.
- [ ] Affected docs describe the implemented handoff. `make lint` and `TEST_DESTINATION=… scripts/validate.sh` pass with the destination recorded; unavailable gates remain unchecked with the blocker reported.
