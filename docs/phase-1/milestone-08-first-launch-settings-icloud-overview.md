# P1-M8: First launch, Settings, and iCloud folder selection overview

Status: Planned

Build the permission onboarding, Settings foundation, and persistent iCloud-only destination boundary needed before recording can begin. The milestone must prove on a physical iPhone that a selected or newly created Files folder is positively identifiable as iCloud Drive and remains safely accessible through a persisted bookmark without treating a path, picker success, or repeated provider error as authority.

## Entry condition

- Follow Phase 1 milestone order: implementation starts after P1-M7 is complete or the owner explicitly reorders the phase.
- Use the approved [P1-M5 storage, iCloud, privacy, and interface contracts](milestone-05-decisions-architecture.md), [product behavior](../product-behavior.md), and [information architecture](../ux-information-architecture.md).
- P1-M8 may select an implementation mechanism only when device evidence preserves those outcomes. If iOS does not expose a reliable positive iCloud identity for arbitrary picked folders, stop for owner review rather than accepting a path, display name, provider label, or picker location as proof.
- Do not add a dependency or change a build tool without owner approval. No dependency is expected for this milestone.

## Scope

- Implement a resumable first-launch flow that explains and requests microphone access, then explains and requests optional When In Use location access. A denial or restriction completes that step without blocking the root interface or causing repeated system prompts.
- Add application-owned permission ports and Apple adapters for current microphone and location authorization state, one eligible request, and the app's system Settings route. M8 authorizes no recording and acquires no coordinates.
- Establish the approved root containment needed to reach Settings from All and to gate Main's Record entry. Benefits, Calendar, and Plugins use their approved empty-state text; collection, notice, recovery, and capture behavior remain owned by later milestones.
- Add a Settings foundation that shows the active folder, selects or changes it, reports optional location authorization, and offers an appropriate location request or system Settings action. Microphone recovery stays on Record as approved. A folder change affects only the active folder and never moves finished assets or retargets pending work.
- Define inward-owned, opaque destination values and a `DestinationPort`. Core code receives a destination ID, safe display name, and typed access state, never a bookmark, provider URL, account token, File Provider identifier, or path.
- Present the system folder picker for one directory, allow the Files UI to create a folder, and validate a picked candidate while its security scope is active. Accept only a real directory positively reported by platform metadata as an iCloud ubiquitous item while an iCloud identity is available; reject local, third-party, symbolic-link, non-directory, and ambiguous candidates without replacing the current destination.
- Persist the accepted directory as minimal bookmark data in private app settings. Resolve it afresh for every operation, balance every acquired security scope, coordinate the probe, refresh a stale bookmark only after the same validation passes, and atomically retain the old selection if replacement fails.
- Observe iCloud identity and app-active changes, re-resolve the active bookmark, and map results to sanitized typed states. Missing, revoked, stale, signed-out, offline, and provider failures do not authorize a replacement or prove permanent loss; M8 offers restore access or a new explicit active-folder choice, while per-job replacement remains a later recovery workflow.
- Show the approved one-time disclosure before accepting the first active folder: diary text, audio, and optional exact location are readable files, and anyone with folder access may read them. Persist only completion of that disclosed choice, not a claim that the folder is private or encrypted by the app.
- Add deterministic unit, adapter, presentation, and lifecycle tests, plus the assigned physical-device evidence for iCloud selection, folder creation, provider identity, bookmark relaunch, revocation, and restoration.

## Out of scope

- Audio capture, the five-minute limit, recording language selection, audio-session behavior, the 100 MiB recording reserve, locked/background behavior, and queue creation. P1-M9 consumes the permission and destination gates.
- Queue records, attaching a destination snapshot to a recording, restore quarantine, worker readiness, and per-job destination replacement. P1-M10 and P1-M17 own those workflows.
- Apple speech readiness/download behavior, Cohere installation, model artifact or runtime selection, effective transcription settings, and production method selection. M8 leaves extension points in Settings; P1-M11 and P1-M12 add truthful method-specific controls after their adapters exist.
- Location sampling, geocoding, WeatherKit, recording-time context acceptance, and notification permission. P1-M18 owns them; M8 requests only the approved optional location authorization and exposes its recovery control.
- Active-folder enumeration, paging, diary detail, final custom tab/control bitmap assets, notice rotation, and recording UI. P1-M15 and P1-M16 own those interfaces.
- Coordinated Markdown/audio publication, upload observation, conflict handling, staging cleanup, external deletion, or claims that bookmark resolution proves upload. P1-M14 and P1-M17 own those mutations.
- Adding an app-managed iCloud container, silently falling back to local storage, searching for a moved destination, or inferring iCloud from a path, label, or opaque File Provider domain identifier.

## Completion checklist

- [ ] First-launch state tests cover fresh install, each permission already decided, denial, restriction, Allow Once returning to undetermined, interruption after every step, relaunch, and duplicate callbacks. Each eligible system request occurs at most once per unresolved step, and all settled outcomes reach the root interface.
- [ ] The app contains clear microphone and When In Use location usage descriptions before requesting access. Microphone denial leaves non-recording areas usable; location denial never blocks recording eligibility; neither denied state causes another system request.
- [ ] The root exposes the five approved tab labels and exact Benefits, Calendar, and Plugins empty-state text. Settings is reachable only from All, and the Record entry cannot authorize capture unless current microphone access and an accessible active destination both pass.
- [ ] Settings shows current location state, requests only an undetermined location authorization, and offers a nonblocking app Settings route after denial or restriction. Record provides the corresponding microphone recovery route. Returning active refreshes displayed authorization instead of trusting persisted permission flags.
- [ ] Domain and application tests prove that onboarding and destination use cases do not import SwiftUI, UIKit, AVFoundation, CoreLocation, FileProvider, or persistence implementations, and that no core value exposes bookmark bytes, URLs, paths, provider/account tokens, or raw platform errors.
- [ ] Candidate validation accepts only a coordinated, scope-acquired directory with positive iCloud metadata and an available iCloud identity. Local, third-party, symbolic-link, missing, non-directory, `false`, `nil`, unreadable, and contradictory metadata candidates are rejected without replacing a valid current selection.
- [ ] Selection is transactional: cancellation, disclosure cancellation, validation failure, bookmark failure, persistence failure, or stale-refresh failure leaves the prior active destination intact. The first accepted folder records the disclosure acknowledgement; later changes do not move assets or mutate any pending destination.
- [ ] Bookmark tests cover creation, atomic private persistence, relaunch resolution, stale refresh after revalidation, rename/move behavior exposed by the platform, corrupted or oversized data, target replacement, scope-acquisition failure, coordinated-access failure, and balanced `startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()` calls on success, error, and cancellation.
- [ ] Access-state tests default uncertain provider and network failures to temporary unavailability, never search another folder, never accept a same-named replacement as the old destination, and never classify repeated timeouts as confirmed permanent loss. Diagnostics contain only typed codes, counts, and opaque local IDs.
- [ ] iCloud identity-change and app-active tests invalidate cached access, resolve and validate again, and keep the stored selection recoverable rather than silently clearing or retargeting it. An opaque File Provider item/domain identifier may support consistency checks but is never treated as proof of iCloud or shown as provider branding.
- [ ] Presentation tests cover VoiceOver names, Dynamic Type, Reduce Motion, cancellation, unavailable access, rejected non-iCloud choices, disclosure, and system Settings recovery. Sensitive bookmark/path/account data never appears in visible errors, accessibility values, logs, snapshots, or test diagnostics.
- [ ] On the target physical iPhone, evidence records selection of an existing iCloud Drive folder and creation/selection of a new one, rejection of On My iPhone and at least one available third-party provider, relaunch and device restart, folder rename/move, Files permission revocation/restoration, folder deletion and same-name recreation, airplane mode, iCloud sign-out/sign-in, and account identity change. Each case records observed metadata and typed result without recording private paths, bookmark bytes, or account data.
- [ ] The device evidence demonstrates that the selected positive-iCloud predicate distinguishes every available non-iCloud provider. If it does not, the milestone remains incomplete and the owner reviews the mechanism; implementation does not weaken the approved iCloud-only rule.
- [ ] The implementation adds no dependency or build-tool change and affected documentation records the M9, M10, M11, M12, M14, M15, M17, and M18 handoffs.
- [ ] `swift-format lint --strict --recursive .` passes.
- [ ] `swiftlint lint --strict` passes.
- [ ] The generated project builds and all tests pass through `scripts/validate.sh` on an available iPhone simulator.

## Acceptance evidence

Check an item only with a focused test, inspected Info.plist/build setting, source-boundary check, or redacted physical-device trial record. Simulator fakes can prove state transitions, transactionality, error mapping, and scope balancing; they cannot prove provider identity, bookmark survival, Files revocation behavior, or arbitrary iCloud Drive folder creation on the target phone.

The device trial must use synthetic folders and files. It may record Boolean/availability results, opaque equality comparisons, typed outcomes, and whether access succeeded, but not a user's path, account identifier, bookmark bytes, or folder contents.
