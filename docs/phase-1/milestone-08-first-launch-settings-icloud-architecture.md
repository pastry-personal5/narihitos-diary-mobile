# P1-M8: First launch, Settings, and iCloud folder selection approach

Status: Planned

Introduce permission and destination capabilities without letting UI or persisted file-system data become authority. The milestone uses Apple permission APIs and a directory picker at the edge, while application use cases consume current authorization and opaque, revalidated destination handles.

## Platform evidence boundary

Apple's [directory-access guidance](https://developer.apple.com/documentation/uikit/providing-access-to-directories) establishes that a folder picker can return local, iCloud, or third-party locations; the returned directory is security scoped, bookmarkable, and must be accessed with file coordination. It also says bookmark resolution, scope acquisition, and later I/O may fail after permission changes. Therefore picker success and bookmark resolution are access inputs, not provider proof or permanent authorization.

Foundation's [`isUbiquitousItemKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/isubiquitousitemkey) positively describes whether an item is in iCloud storage. [`ubiquityIdentityToken`](https://developer.apple.com/documentation/foundation/filemanager/ubiquityidentitytoken) indicates the current iCloud Drive Documents identity and changes across sign-out or account changes. File Provider can return opaque item/domain identifiers for a user-visible URL, but Apple does not document those identifiers as provider branding; M8 may record equality/availability for the device trial but must not infer "iCloud" from their text.

The initial acceptance predicate is intentionally fail closed: while a picked URL's security scope is active and a coordinated metadata probe succeeds, require a directory, reject a symbolic link/alias where observable, require `isUbiquitousItem == true`, and require a non-`nil` current iCloud identity. Recheck the same properties after bookmark resolution. The physical-device matrix must show that this distinguishes iCloud Drive from every available local or third-party candidate and works for a folder created in Files. If any required signal is missing for a real iCloud folder or positive for a non-iCloud folder, do not substitute path spelling or display-name matching; return to owner review.

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
- `DestinationSummary` contains only `DestinationID` and a safe user-facing folder name obtained from validated resource metadata. It does not reveal a full path or account/provider token.
- `DestinationAccessState` distinguishes accessible, temporarily unavailable, restore-access-required, and invalid stored reference. These are recovery/presentation states, not authority to delete or retarget a pending job. Any platform result that cannot reliably prove permanent removal maps to a recoverable state.
- `RecordPrerequisites` reports current microphone authorization and active-destination accessibility independently so the presentation can explain the missing prerequisite. It does not start capture.

Application-owned ports keep effects replaceable:

- `MicrophoneAuthorizationPort` and `LocationAuthorizationPort` read current status and request only when eligible.
- `SystemSettingsPort` opens the app's Settings page without giving the use case general URL-opening authority.
- `FirstLaunchStorePort` persists only the completed explanation/progression state. Permission truth always comes from the platform adapter.
- `DestinationSelectionPort` presents one folder candidate or cancellation. It is a presentation/platform bridge, not the destination repository.
- `DestinationPort` validates and accepts a candidate, returns the active summary/state, and lends a short-lived scoped capability to later adapters. Its public contract never returns a URL or bookmark.
- `ActiveDestinationStorePort` atomically persists the opaque destination record and bookmark payload behind the adapter. Core use cases cannot read or construct its representation.

Keep the destination capability separate from `PrivateWorkspacePort`: M7 owns app-private job artifacts, while M8 owns user-granted external-directory access. Do not place bookmark bytes in Diary Snippet front matter, queue-facing display values, `UserDefaults` keys exposed to UI, diagnostics, or navigation state.

## First-launch state machine

The first-launch coordinator is resumable and idempotent:

1. Read current microphone state. If undetermined and the explanation has not settled, show the microphone explanation and request after explicit continuation. Authorized, denied, or restricted results settle the step.
2. Read current location state. If undetermined and the explanation has not settled, explain that recording-time location is optional and request When In Use access after explicit continuation. Authorized, denied, or restricted results settle the step.
3. Enter the root interface regardless of either choice. Do not force folder selection during onboarding; Settings may select it at any time, and Record invokes the same selection flow when no accessible active destination exists.
4. On app activation, refresh live permission and destination states. Never replay a settled system request merely because the app was reinstalled from UI state, a callback arrived twice, or a platform prompt returned an unexpected transition.

Persist progression after each settled explanation/request boundary so termination resumes at the first unresolved step. A request call is legal only for live `notDetermined`; denial and restriction offer the system Settings route. Location Allow Once may later return to undetermined, but that does not restart first launch or automatically prompt again; Settings may offer a user-initiated request when the platform permits it.

## Root and Settings containment

M8 replaces the scaffold view with the smallest approved navigation shell needed for these features:

- five root labels: Main, Benefits, Calendar, Plugins, and All;
- the approved exact empty-state text for Benefits, Calendar, and Plugins;
- a Main Record entry that routes through `RecordPrerequisites` but cannot begin capture in M8; and
- All as the sole Settings entry.

Settings contains destination and optional-location sections. Destination shows the safe active-folder name and Select Folder or Change Folder. Location shows current authorization and only the action valid for that state. Microphone denial recovery remains attached to Record, matching the approved containment. Leave a registry-backed extension point for transcription method controls, but do not ship simulated readiness, fake installation, a Cohere artifact choice, or hosted Qwen controls. P1-M11 and P1-M12 add those sections with real adapters.

Final custom bitmap tab/control art remains P1-M15/P1-M16 work. M8 must preserve visible labels, semantic accessibility names, 44-by-44-point actions, Dynamic Type, and Reduce Motion; temporary presentation must not assert that the later icon brief is complete.

## Destination selection transaction

Treat selection as a prepare/commit transaction:

1. Present a single-directory picker using the folder content type. Cancellation has no state effect.
2. Start the returned security scope. If acquisition fails, return a sanitized recoverable result. Balance every successful start with `defer`-style release.
3. Coordinate a read/probe and fetch only required resource values. Require an existing directory, reject links/aliases or unexpected file kinds where observable, require `isUbiquitousItem == true`, and require a current iCloud identity. Record File Provider identifier availability/equality only in the redacted device-evidence harness.
4. Create minimal bookmark data only for a validated candidate. Apply a strict small bookmark-size bound before private persistence so malformed restored state cannot allocate unbounded data; choose and document the concrete bound from observed Apple bookmark sizes with generous headroom during implementation, without logging bytes.
5. For the first accepted destination, present the approved readable-files disclosure. Cancellation discards the prepared candidate and retains the old selection.
6. Resolve the new bookmark, acquire scope, and repeat validation before commit. This proves that the persisted form resolves to the candidate under current conditions; it does not prove future access or upload.
7. Atomically persist bookmark data, a fresh opaque `DestinationID`, safe display name, disclosure state, and only the opaque identity comparisons needed to invalidate cached access. Publish the new active destination to observers after persistence succeeds.

Never validate by checking a `/Mobile Documents/` prefix, a localized "iCloud Drive" label, a provider/domain identifier string, or the picker's last location. Never keep a security scope open for the lifetime of a screen or app.

## Resolution and lifecycle

Every destination operation asks the adapter to resolve the stored bookmark afresh and lend access for one bounded coordinated operation. The adapter:

- validates bookmark length and decode result before use;
- acquires the security scope and guarantees balanced release;
- validates directory kind and positive iCloud identity again;
- if resolution reports stale, creates replacement bookmark data only from the resolved, scope-acquired, revalidated URL and atomically updates the record before reporting success;
- compares iCloud identity only as an opaque equality signal and invalidates cached access after the system's identity-change notification;
- maps cancellation, offline/provider unavailability, permission/scope failure, missing resource, corrupt bookmark, and contradictory metadata to sanitized typed outcomes; and
- retains the selection record for recovery unless the user explicitly commits another active folder.

A missing URL or same-named recreated folder never inherits the old `DestinationID`. Repeated temporary failures do not become permanent. M8 may let the user explicitly choose a new active folder, but it has no queue record and therefore no authority to retarget a recording; P1-M17 later applies the approved user-confirmed permanent-loss flow to one affected job.

## Persistence and disclosure

Store onboarding and destination records in a dedicated private Application Support settings adapter with atomic replacement and bounded decoding. The bookmark payload is sensitive capability data: exclude it from diagnostics, crash annotations, accessibility, test failure dumps, and support exports. Do not reuse M7's backup-excluded pending-work workspace or claim that deleting a local record revokes Files access, removes remote content, or erases older backups.

Before committing the first active folder, explain that Diary Snippet Markdown, audio, and optional exact location are ordinary readable files and anyone with folder access may read them. This is a disclosure, not consent to upload audio for inference and not a promise about sharing, iCloud encryption, or deletion. Later folder changes may reference the prior acknowledgement, while Settings continues to make the destination visible.

## Test and evidence strategy

Use protocol fakes for deterministic tests and synthetic folders for adapter/device work:

- Table-test first-launch transitions across every live platform state, termination point, duplicate callback, and app-active refresh. Assert request counts and that denial never blocks root navigation.
- Test permission mapping and Settings actions without invoking system prompts in unit tests. Inspect generated Info.plist settings for both purpose strings.
- Feed the destination validator all combinations of directory kind, link status, ubiquitous `true`/`false`/`nil`, account identity present/absent, scope result, coordination result, bookmark result, stale result, and persistence failure. Assert fail-closed acceptance and old-selection preservation.
- Instrument fake scopes so every successful start has exactly one stop across success, thrown error, cancellation, stale refresh, and replacement failure.
- Corrupt and oversize stored bookmark/settings records; substitute a target between validation and resolution; return a same-named replacement; and inject identity changes while a selection or resolution is in flight. No case may grant access from stale UI state or log raw data.
- Test view models for exact root/empty-state labels, All-only Settings routing, prerequisite-specific Record recovery, one-time disclosure, rejected provider feedback, authorization actions, and accessibility projections.
- Run source checks proving inward layers do not import platform/persistence frameworks and inspect public error descriptions/captured diagnostics for paths, bookmark data, account/provider identifiers, and raw errors.

The physical-device trial is a completion gate, not optional research. On the target iPhone, use synthetic directories to select and create iCloud folders; attempt On My iPhone and an installed third-party provider; relaunch and restart; rename/move/delete/recreate; revoke and restore Files access; toggle airplane mode; and sign out, sign in, and change iCloud identity where the controlled device permits it. Record only metadata availability/Boolean results, opaque equality changes, access success, and typed app outcomes. A simulator cannot close this evidence.

At completion, delegate strict format, lint, build, and test execution and first-pass failure analysis to the required `test_runner` agent. Record concise evidence in the overview; do not mark device items from simulator results.

## Implementation sequence

1. Add validated access values, permission/destination ports, fake adapters, and state-machine tests.
2. Implement bounded private settings persistence and transactional destination selection/resolution tests.
3. Implement microphone, location, system Settings, document-picker, iCloud metadata/identity, bookmark, and coordinated-access adapters.
4. Build the first-launch, root containment, Settings, disclosure, and prerequisite-routing presentation with accessibility tests.
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
