# P1-M8: First launch, Settings, and iCloud folder selection approach

Status: Active

Introduce permission and destination capabilities without letting UI or persisted file-system data become authority. The milestone uses Apple permission APIs and a directory picker at the edge, while application use cases consume current authorization and opaque, revalidated destination handles.

## Platform evidence boundary

Apple's [directory-access guidance](https://developer.apple.com/documentation/uikit/providing-access-to-directories) establishes that a folder picker can return local, iCloud, or third-party locations; the returned directory is security scoped, bookmarkable, and must be accessed with file coordination. It also says bookmark resolution, scope acquisition, and later I/O may fail after permission changes. Therefore picker success and bookmark resolution are access inputs, not provider proof or permanent authorization.

Foundation's [`isUbiquitousItemKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/isubiquitousitemkey) positively describes whether an item is in iCloud storage. [`ubiquityIdentityToken`](https://developer.apple.com/documentation/foundation/filemanager/ubiquityidentitytoken) indicates the current iCloud Drive Documents identity and changes across sign-out or account changes. Neither signal alone proves that an arbitrary picked URL belongs to the current account: that combined predicate remains a hypothesis until the device matrix passes. File Provider can return opaque item/domain identifiers for a user-visible URL, but Apple does not document those identifiers as provider branding or stable authority. Production acceptance and continuity therefore do not use them; the evidence harness may record only their availability and equality behavior for diagnosis.

The initial acceptance predicate is intentionally fail closed: while a picked URL's security scope is active and a coordinated metadata probe succeeds, require a directory, reject a symbolic link/alias where observable, require `isUbiquitousItem == true`, and require a non-`nil` current iCloud identity. Recheck the same properties after bookmark resolution, and bind the accepted record to an archived opaque equality snapshot of that identity. A later missing or unequal identity makes the record inaccessible until the user restores the original account/access or explicitly selects an active folder; a merely non-`nil` new identity cannot reactivate the old bookmark. The physical-device matrix must show that the admission predicate distinguishes iCloud Drive from every available local or third-party candidate and works for a folder created in Files. If any required signal is missing for a real iCloud folder or positive for a non-iCloud folder, do not substitute path spelling or display-name matching; return to owner review.

Microphone access uses AVFoundation's [capture authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media), including `NSMicrophoneUsageDescription`. Location uses optional [When In Use authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) and `NSLocationWhenInUseUsageDescription`; M8 does not request Always authorization or enable background location. Denied recovery uses the documented [`openSettingsURLString`](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring).

## Source boundaries

Keep the work in the existing app and test targets. Folder organization expresses the approved inward source dependency rule without adding a package or target.

| Area | Responsibility | Must not depend on |
|---|---|---|
| Domain access values | Extensible authorization states, opaque destination identity, safe display projection, and destination access outcomes | SwiftUI, UIKit, AVFoundation, CoreLocation, FileProvider, URLs, bookmarks, persistence |
| Application use cases and ports | First-launch progression, permission refresh/request intents, active-destination selection, replacement transaction, Record prerequisites, and Settings projections | Apple authorization enums, picker controllers, security scopes, coordinated URLs, concrete settings storage |
| Platform adapters | AVFoundation/Core Location authorization, app Settings route, directory picker bridge, iCloud metadata/account observation, bookmark creation/resolution, file coordination, and sanitized error mapping | Capture, queue, catalog, transcription, asset commit, per-job retarget policy |
| Presentation | First-launch explanations, root/All containment, Settings, disclosure, selection feedback, and Record prerequisite routing | Bookmark bytes, provider paths, raw platform errors, direct storage mutation |
| Tests and evidence | State/transaction tests, fake provider matrix, source-boundary checks, and redacted physical-device observations | Personal folders, recordings, diary content, account identifiers |

## Domain and application contracts

Use extensible values rather than platform enums or a closed list of future providers:

- `PermissionState` represents `notDetermined`, `authorized`, `denied`, and `restricted`. Adapters map temporary location authorization back from the live platform state; application code never persists authorization as truth.
- `DestinationID` is an app-generated opaque identity for one accepted selection. It is independent of a path, display name, File Provider item ID, or future asset ID.
- `DestinationSummary` contains only `DestinationID` and a bounded, single-line, display-only folder name projected from validated resource metadata. The adapter rejects or replaces control characters and unsafe directional formatting, never interprets the name as a path, and uses a generic localized fallback when no safe projection remains. It does not reveal a full path or account/provider token; the projection is identity neither for access nor for same-folder detection.
- `DestinationAccessState` distinguishes accessible, temporarily unavailable, restore-access-required, and invalid stored reference. Account identity absence/mismatch and revoked scope require restoration or an explicit new active-folder selection; ordinary provider/network failures remain temporary. These are recovery/presentation states, not authority to delete or retarget a pending job. Any platform result that cannot reliably prove permanent removal maps to a recoverable state.
- `RecordPrerequisites` reports current microphone authorization and active-destination accessibility independently so the presentation can explain the missing prerequisite. It does not start capture.

Application-owned ports keep effects replaceable:

- `MicrophoneAuthorizationPort` and `LocationAuthorizationPort` read current status and request only when eligible.
- `SystemSettingsPort` opens the app's Settings page without giving the use case general URL-opening authority.
- `FirstLaunchStorePort` persists explanation completion, a pre-request attempt marker, and progression state. It never persists permission truth, which always comes from the platform adapter.
- `DestinationSelectionPort` presents one folder candidate or cancellation. It is a presentation/platform bridge, not the destination repository.
- `DestinationPort` validates and accepts a candidate, returns the active summary/state, and lends a short-lived scoped capability to later adapters. Its public contract never returns a URL or bookmark.
- `ActiveDestinationStorePort` atomically persists the opaque destination record and bookmark payload behind the adapter. Core use cases cannot read or construct its representation.

Keep the destination capability separate from `PrivateWorkspacePort`: M7 owns app-private job artifacts, while M8 owns user-granted external-directory access. Do not place bookmark bytes in Diary Snippet front matter, queue-facing display values, `UserDefaults` keys exposed to UI, diagnostics, or navigation state.

## First-launch state machine

The first-launch coordinator is resumable and idempotent:

1. Read current microphone state. If undetermined and the explanation has not settled, show the microphone explanation. After explicit continuation, durably record that the first-launch request was attempted immediately before invoking the system request. Authorized, denied, or restricted results settle the step.
2. Read current location state. If undetermined and the explanation has not settled, explain that recording-time location is optional. After explicit continuation, durably record the attempt immediately before requesting When In Use access. Authorized, denied, or restricted results settle the step.
3. Enter the root interface regardless of either choice. Do not force folder selection during onboarding; Settings may select it at any time, and Record invokes the same selection flow when no accessible active destination exists.
4. On app activation, refresh live permission and destination states. Never replay a first-launch system request merely because UI state was reconstructed, a callback arrived twice, the app ended around a system prompt, or a request returned no callback.

Persist each attempt marker before the effect and persist progression after each settled explanation/request boundary. On relaunch, an attempted step whose live state remains `notDetermined` is treated as complete for first-launch progression rather than automatically prompting again; the root remains reachable and a later explicit user action may request again when the platform permits it. A request call is legal only for live `notDetermined`; denial and restriction offer the system Settings route. Location Allow Once may later return to undetermined, but that does not restart first launch or automatically prompt again. This deliberately favors no surprise repeat prompt over trying to infer whether an interrupted system sheet was seen.

## Root and Settings containment

M8 replaces the scaffold view with the smallest approved navigation shell needed for these features:

- five root labels: Main, Benefits, Calendar, Plugins, and All;
- the approved exact empty-state text for Benefits, Calendar, and Plugins;
- a Main Record entry that routes through `RecordPrerequisites` but cannot begin capture in M8; and
- All as the sole Settings entry.

Settings contains destination and optional-location sections. Destination shows the safe active-folder name and Select Folder or Change Folder. Location shows current authorization and only the action valid for that state. Microphone denial recovery remains attached to Record, matching the approved containment. Leave a registry-backed extension point for transcription method controls, but do not ship simulated readiness, fake installation, a Cohere artifact choice, or hosted Qwen controls. P1-M11 and P1-M12 add those sections with real adapters.

Final custom bitmap tab/control art remains P1-M15/P1-M16 work. M8 must preserve visible labels, semantic accessibility names, 44-by-44-point actions, Dynamic Type, and Reduce Motion; temporary presentation must not assert that the later icon brief is complete. Because Settings exposes a folder name and later screens will expose more sensitive data, M8 also establishes the approved neutral privacy cover before any scene leaves the foreground. It must cover every root/navigation state without briefly exposing the underlying view in an app-switcher snapshot; it is not a biometric lock.

## Destination selection transaction

Treat selection as a prepare/commit transaction:

1. Present a single-directory picker using the folder content type. Cancellation has no state effect.
2. Start the returned security scope. If acquisition fails, return a sanitized recoverable result. Balance every successful start with `defer`-style release.
3. Coordinate a read/probe and fetch only required resource values. Require an existing directory, reject links/aliases or unexpected file kinds where observable, require `isUbiquitousItem == true`, and require a current iCloud identity. Record File Provider identifier availability/equality only in the redacted device-evidence harness.
4. Create minimal bookmark data only for a validated candidate. Apply a strict small bookmark-size bound before private persistence so malformed restored state cannot allocate unbounded data; choose and document the concrete bound from observed Apple bookmark sizes with generous headroom during implementation, without logging bytes.
5. For the first accepted destination, present the approved readable-files disclosure. Cancellation discards the prepared candidate and retains the old selection.
6. Resolve the new bookmark, acquire scope, and repeat validation before commit. This proves that the persisted form resolves to the candidate under current conditions; it does not prove future access or upload.
7. Before commit, verify that the selection operation still owns the current selection generation and that the iCloud identity is unchanged from preparation. Atomically persist bookmark data, a fresh opaque `DestinationID`, safe display name, disclosure state, and an archived opaque iCloud-identity equality snapshot. Publish the new active destination to observers only after persistence succeeds.

Only the newest explicit selection operation may commit. A second selection, scene transition, or identity change invalidates an older prepared candidate; late picker, validation, bookmark, disclosure, and persistence callbacks become no-ops after releasing their resources. Never validate by checking a `/Mobile Documents/` prefix, a localized "iCloud Drive" label, a provider/domain identifier string, or the picker's last location. Never keep a security scope open for the lifetime of a screen or app.

## Resolution and lifecycle

Every destination operation asks the adapter to resolve the stored bookmark afresh and lend access for one bounded coordinated operation. The adapter:

- validates bookmark length and decode result before use;
- acquires the security scope and guarantees balanced release;
- validates directory kind and positive iCloud metadata again, then requires the current identity to equal the accepted record's opaque identity snapshot;
- if resolution reports stale, creates replacement bookmark data only from the resolved, scope-acquired, revalidated URL and atomically updates the record before reporting success;
- compares iCloud identity only as an opaque equality signal and invalidates all cached access before handling the system's identity-change notification;
- associates each loan with the current destination/identity generation and rechecks that generation before reporting the operation as valid, so an identity change or active-folder replacement during the loan cannot publish a stale success;
- maps cancellation, offline/provider unavailability, permission/scope failure, missing resource, corrupt bookmark, and contradictory metadata to sanitized typed outcomes; and
- retains the selection record for recovery unless the user explicitly commits another active folder.

A missing URL or same-named recreated folder never inherits the old `DestinationID`. Repeated temporary failures do not become permanent. M8 may let the user explicitly choose a new active folder, but it has no queue record and therefore no authority to retarget a recording; P1-M17 later applies the approved user-confirmed permanent-loss flow to one affected job.

## Persistence and disclosure

Store onboarding and destination records in a dedicated private Application Support settings adapter with atomic replacement and bounded decoding. Validate restored settings as untrusted input: an imported, corrupt, or account-mismatched record grants no access until its bookmark, metadata, and opaque account equality all pass. Archive and decode the identity token only through the platform-supported opaque representation and prove its restart round trip on the target phone; never derive account identity from a token description, reflection, hash of description, or private class name. If a bounded safe round trip is unavailable, the identity binding is not implemented and the milestone returns to owner review. The bookmark payload and archived identity snapshot are sensitive capability data: exclude them from diagnostics, crash annotations, accessibility, test failure dumps, and support exports. Do not reuse M7's backup-excluded pending-work workspace or claim that deleting a local record revokes Files access, removes remote content, or erases older backups.

Before committing the first active folder, explain that Diary Snippet Markdown, audio, and optional exact location are ordinary readable files and anyone with folder access may read them. This is a disclosure, not consent to upload audio for inference and not a promise about sharing, iCloud encryption, or deletion. Later folder changes may reference the prior acknowledgement, while Settings continues to make the destination visible.

## Test and evidence strategy

Use protocol fakes for deterministic tests and synthetic folders for adapter/device work:

- Table-test first-launch transitions across every live platform state, termination point, duplicate callback, and app-active refresh. Include termination before and after persisting the request-attempt marker and a request that never calls back. Assert at-most-once automatic requests and that an inconclusive, denied, or restricted result never blocks root navigation.
- Test permission mapping and Settings actions without invoking system prompts in unit tests. Inspect generated Info.plist settings for both purpose strings.
- Feed the destination validator all combinations of directory kind, link status, ubiquitous `true`/`false`/`nil`, account identity present/absent, scope result, coordination result, bookmark result, stale result, and persistence failure. Assert fail-closed acceptance and old-selection preservation.
- Instrument fake scopes so every successful start has exactly one stop across success, thrown error, cancellation, stale refresh, and replacement failure.
- Corrupt and oversize stored bookmark/settings records; substitute a target between validation and resolution; return a same-named replacement; restore a record under an absent or different iCloud identity; overlap two selection flows; and inject identity or lifecycle changes at every prepare/commit and scoped-loan boundary. Include empty, overlong, multiline, control-character, and directional-formatting folder names. No stale callback may commit or grant access, every acquired scope must still be released, and display projection must never become authority.
- Test view models for exact root/empty-state labels, All-only Settings routing, prerequisite-specific Record recovery, one-time disclosure, rejected provider feedback, authorization actions, accessibility projections, and the privacy cover across every scene transition.
- Run source checks proving inward layers do not import platform/persistence frameworks and inspect public error descriptions/captured diagnostics for paths, bookmark data, account/provider identifiers, and raw errors.

The physical-device trial is a completion gate, not optional research. Its lab prerequisites are the target iPhone and minimum OS, synthetic data, a controlled nonpersonal iCloud account, a second controlled account for identity-change evidence, On My iPhone, and at least one installed third-party File Provider. If a prerequisite or a required system control is unavailable, record the blocker and leave the corresponding checklist item open rather than weakening the scenario.

Use these stable scenario IDs in the redacted evidence record:

| ID | Scenario | Pass invariant |
|---|---|---|
| M8-D01 | Select an existing iCloud Drive folder | Both initial and bookmark-resolution probes pass the proposed predicate and the destination becomes accessible. |
| M8-D02 | Create and select a new folder in Files | The created folder passes the same predicate without path or label inference. |
| M8-D03 | Attempt On My iPhone and each installed third-party provider | Every non-iCloud candidate is rejected and the prior active destination is unchanged. |
| M8-D04 | Relaunch and restart the phone | The bookmark and bounded opaque identity snapshot round-trip, scope is balanced, identity matches, and access is revalidated rather than trusted from cache. |
| M8-D05 | Rename and move the selected folder within iCloud Drive | Record the platform's bookmark behavior; success requires revalidation, while failure preserves a recoverable record and never searches by name. |
| M8-D06 | Revoke and restore Files and Folders access | Revocation cannot grant access or clear the record; restoration re-resolves and revalidates before access. |
| M8-D07 | Delete the folder, then create another with the same name | The replacement never inherits the old `DestinationID` or access authority. |
| M8-D08 | Enter airplane mode and restore connectivity | Uncertain provider/network failures remain temporary and do not replace or clear the destination. |
| M8-D09 | Sign out, sign back into the original controlled account | Missing identity blocks access; restored access requires opaque identity equality plus complete revalidation. Record observed token behavior without assuming equality. |
| M8-D10 | Change to the second controlled iCloud account | An unequal identity cannot reactivate or refresh the old bookmark even if its URL resolves and reports ubiquitous. |
| M8-D11 | Move the app through inactive/background/app-switcher states | The neutral cover prevents a snapshot of the folder name or underlying content and foreground return refreshes live state. |

For each scenario, record device model, OS build, app revision, scenario ID, candidate class, directory/link/ubiquity Boolean availability, iCloud-identity presence and opaque equality only, bookmark stale flag, scope/coordination success, typed app outcome, and whether the prior destination remained unchanged. Never record paths, display names, token or bookmark bytes, account identifiers, or folder contents. A simulator cannot close this evidence.

At completion, delegate strict format, lint, build, and test execution and first-pass failure analysis to the required `test_runner` agent. Record concise evidence in the overview; do not mark device items from simulator results.

## Implementation sequence

1. Add validated access values, permission/destination ports, fake adapters, and state-machine tests.
2. Implement bounded private settings persistence, request-attempt persistence, selection-generation fencing, and transactional destination selection/resolution tests.
3. Implement microphone, location, system Settings, document-picker, iCloud metadata/identity, bookmark, and coordinated-access adapters.
4. Build the first-launch, root containment, Settings, disclosure, prerequisite routing, and scene privacy cover with accessibility/lifecycle tests.
5. Run the simulator checks, then the target-phone provider/bookmark matrix. Adjust only mechanisms that preserve the approved outcome; escalate any inability to distinguish iCloud positively.
6. Run the delegated full validation gate, update checklist evidence and affected docs, and change M8 to Done only when both automated and physical-device gates are complete.

## Downstream handoff

- P1-M9 consumes current microphone authorization, `RecordPrerequisites`, and a validated active `DestinationID`, then attaches the capture-time destination to durable recording work and verifies lock/background behavior.
- P1-M10 persists destination identity in jobs without persisting a path or live URL and reconciles it through `DestinationPort`.
- P1-M11 and P1-M12 extend Settings with real Apple/Cohere readiness, selection, installation, and refresh behavior; M8 supplies no fabricated readiness.
- P1-M14 borrows bounded destination access for coordinated pair publication and separately verifies local bytes and per-file upload status. M8 bookmark success is not commit evidence.
- P1-M15 replaces Main's collection placeholder and consumes active-folder change notifications to invalidate paging.
- P1-M17 owns Restore Access and confirmed per-job replacement after removal/revocation, preserving M8's rule that transient failure never retargets work.
- P1-M18 consumes live optional-location authorization for recording-start context and adds notification controls without changing first-launch denial behavior.
- P1-M19 repeats provider, permission, privacy, and hostile-state checks in the complete v1 adversarial matrix.
