# P1-M7: Asset schema and private storage approach

Status: Done

Build a small trusted boundary around untrusted asset bytes and private app-owned files. The domain sees validated values, application code owns storage capabilities, and Foundation adapters perform bounded parsing and file operations.

## Source boundaries

Keep the feature within the existing app and test targets; folders express the approved source dependencies without introducing a new package or target in this milestone.

| Area | Responsibility | Must not depend on |
|---|---|---|
| Domain asset values | Asset identity and kind, Diary Snippet v1 metadata, provenance, optional context, canonical instants, bounded body, and validation errors | SwiftUI, file URLs, YAML text, FileManager, Keychain, iCloud |
| Application storage contracts | Private workspace identity, typed artifact roles, codec operations, file-attribute policy seam, and sanitized result types | Concrete directories, security-scoped URLs, provider APIs, UI state |
| Foundation adapters | Strict Markdown/front-matter codec, UTC layout, private Application Support workspace, atomic replacement, confinement, and backup exclusion | SwiftUI, queue decisions, iCloud commit policy, transcription providers |
| Tests and fixtures | Golden encoding, hostile-input corpus, randomized round trips, storage-attribute and confinement checks | User data, network services, physical-device claims |

The codec and private-workspace protocols are inward-owned. Concrete adapters translate bytes and file-system results into typed values and errors; no core value stores a live URL or grants deletion authority.

## Domain model

Use small validated wrappers instead of passing schema strings throughout the app:

- `AssetID` accepts and emits only random UUID v4 values in lowercase canonical hyphenated form for new Diary Snippets.
- `AssetKindID`, `TranscriptionMethodID`, and `TitleOriginID` remain extensible identifiers. A separate v1 support policy recognizes only the owner-approved values; the identifier types themselves do not become closed enums that block future registration. The encoder emits schema version and initial transcription-settings revision `1`; do not infer an unapproved language, codec, provenance, or future revision allowlist.
- `SchemaInstant` parses and serializes RFC 3339 UTC at whole-second precision with `Z`. File layout derives from `created_at` in UTC, never from the display calendar or current timezone.
- `DiarySnippetV1` contains every required field in the approved contract and the bounded body. Complete location/weather groups decode to typed values; incomplete or malformed optional-group fields are retained as preserved scalars but are not exposed as valid context. Declared numeric metadata receives overflow and domain checks, including the approved 301-second duration declaration limit, without treating it as evidence about the referenced audio file.
- `TranscriptionProvenance` exposes the approved conditional string fields without inventing a method-specific required set; the creating adapter in P1-M11/P1-M12 must supply its effective available provenance. `TitleProvenance` applies the approved title-origin shape, including the AI-title fields. Unknown stable values are unsupported, while a known value with an invalid required shape is malformed.
- `PreservedScalar` retains a preservation-only entry: either an unknown key or a recognized optional-group field that cannot form a valid group, together with its raw scalar-value bytes and source order. It is never interpreted as a path, identifier, Boolean, or mutation instruction.

Do not add unapproved semantic restrictions. Enforce the types, stable values, conditional groups, and resource limits in P1-M5; later milestones may add workflow preconditions without changing the file contract.

## Codec pipeline

Avoid a general-purpose YAML object decoder. The accepted grammar is deliberately smaller and can be parsed as bounded UTF-8 lines:

1. Scan incrementally with explicit byte counters: require an opening `---` line, locate the closing delimiter within the 64 KiB front-matter limit, require UTF-8 with LF-only line endings, and retain at most the 1 MiB body limit. A missing delimiter or oversized section fails without reading the whole file into a second unbounded buffer.
2. Tokenize at most 64 top-level key/scalar pairs and reject duplicate keys, blank or invalid keys, nesting, sequences, tags, anchors, aliases, block scalars, and other syntax outside the approved flat-scalar grammar. Cap every scalar at 8 KiB.
3. Decode recognized scalars with explicit double-quoted-string, base-10 integer, finite decimal, and lowercase-Boolean routines. Parse integers and decimals with overflow checks and locale-independent behavior. A string routine handles only the approved escapes; no parsed scalar can instantiate a type or invoke an implicit resolver.
4. Validate required fields, stable-value support, conditional provenance field types, title provenance, complete optional groups, canonical identity/time forms, numeric domains and the approved duration declaration limit, and the audio filename as one safe confined filename.
5. Return one of three outcomes: supported `DiarySnippetV1`, unsupported bounded document with a reason and untouched source bytes, or malformed document with a sanitized reason. Preserve original bytes only when they fit the retention bounds; an oversized input returns metadata about the bound failure, never an unbounded copy. Unsupported and malformed outcomes confer no write capability.
6. Serialize supported data from typed fields in canonical recognized-key order. Append preserved unknown scalar entries in stable source order, retaining their scalar-value bytes. Emit UTF-8, LF, exact delimiters, and one blank line before the body.

The adapter keeps bounded original bytes alongside unsupported/malformed results so later catalog and recovery code can present or preserve them without normalizing the source. Rewriting is allowed only from a supported typed value and an explicit later use case. M7 does not render Markdown or decide whether a recovery item may be removed.

## Layout and reference safety

`DiarySnippetLayout` derives the approved relative resources from a validated asset ID and `created_at`:

```text
<UTC year>/<UTC month>/<UTC day>/
  YYYY-MM-DD_HH-mm-ss-<uuid>.md
  YYYY-MM-DD_HH-mm-ss-<uuid>.assets/
    <uuid>.m4a
```

The v1 `audio_filename` is a filename, not a URL or arbitrary path. Reject absolute paths, separators, parent components, URL syntax, percent-encoded ambiguity, control characters, links, aliases, and a name that differs from the layout's validated audio filename. Revalidate containment and resource identity at the file operation, not only when parsing text. String-prefix comparison is never sufficient.

M7 implements this filename/layout validator for new-schema assets and private files. It validates declared duration and audio metadata but does not decode the referenced audio. P1-M9 validates capture output, P1-M15 validates actual external resource format/size/duration before catalog playback, and P1-M14/P1-M17 reapply reference and ownership checks during coordinated commit, repair, conflict, and confirmed external removal.

## Private workspace

Define a `PrivateWorkspacePort` around opaque workspace and artifact handles. Its operations allocate or reopen a validated workspace, create/open a typed artifact, atomically replace an artifact, inspect expected attributes, and remove only a validated app-owned workspace. It does not accept an asset filename, arbitrary path/URL, or external asset ID as authority. Handles are capabilities scoped to one adapter instance; persisted workspace text must be parsed as a canonical `WorkspaceID` and reconciled beneath the owned root before the adapter issues a fresh handle.

The local adapter:

- roots durable work in a dedicated Application Support subtree, never Documents, Caches, or a temporary directory;
- creates unpredictable per-workspace directories from validated internal identities and uses fixed adapter-owned filenames for pending audio, draft Markdown, replacement, and recovery roles;
- resolves the production root beneath Application Support once, validates its directory identity, and anchors operations to already-opened owned directories with no-follow and opened-resource identity checks where the platform exposes them; it refuses links/aliases and unexpected file kinds and rechecks identity around replacement or removal so a check/use race fails closed rather than following a substituted resource;
- writes a sibling temporary file inside the same validated workspace, applies required attributes, verifies bytes and attributes with bounded or streaming work, atomically replaces the destination, then reapplies and verifies attributes on the resulting file;
- excludes pending audio, unsaved drafts, replacements, and recovery copies from backup on every creation/replacement path;
- keeps an adapter-owned rollback/recovery artifact until the replacement bytes and attributes verify, so the prior bytes remain durable either at the destination or in that recovery artifact when any write, attribute, replacement, or verification step fails; never report replacement success before final verification; and
- maps platform errors immediately to sanitized typed codes without retaining raw error descriptions in domain/application values or logs.

The storage API reserves an injected protection-policy seam, but production M7 does not choose or claim a concrete Data Protection class. Tests can prove that a supplied policy is applied, verified, and fails closed. P1-M9 must select the production policy and use physical-device tests to reconcile locked capture/finalization with protection of closed sensitive files. M7 does not create an installation identity: P1-M10 owns its inward contract and job usage, with Keychain accessibility and backup/restore evidence closed by P1-M9/P1-M10/P1-M19 as assigned.

## Test strategy

Use checked-in synthetic fixtures only; never copy a user's diary or recording into tests.

- Golden tests cover a minimal document, all conditional provenance fields, full location/weather groups, escaped strings, empty body, Unicode grapheme content, canonical layout, and timezone independence.
- Mutation tables remove or mistype each required field and break each conditional group. Separate cases cover duplicate keys, malformed UTF-8, forbidden YAML constructs, delimiter confusion, CRLF input, embedded delimiter-like body text, unsafe references, and every resource boundary at limit and limit-plus-one.
- Declared-metadata tests cover duration and audio numeric fields at the approved boundary and just above it. Actual file size, decodability, format, and decoded duration are deliberately left to P1-M9/P1-M15 tests that have an audio adapter; M7 must not claim that front matter proves them.
- Preservation tests decode unknown strings, integers, decimals, Booleans, and quoted escape spellings, modify an unrelated recognized field, and assert byte-equivalent scalar values and stable unknown ordering.
- Support-policy tests distinguish unknown schema/kind/method/title origin from malformed known v1 content and prove neither path writes or normalizes the source.
- Randomized tests generate valid typed documents and bounded unknown scalars, then assert encode/decode equality and deterministic output. Random invalid data must settle within the configured bounds without a crash or partial supported value.
- File-system tests use a fresh test-owned root injected into the adapter, while a separate root-resolution test proves the production adapter selects Application Support. They exercise traversal, absolute/URL, percent-encoding, sibling-prefix, symlink/alias and deterministically injected swap races where supported, wrong file kinds, target replacement, every injected replacement failure point, backup-exclusion reapplication, and removal confinement.
- Diagnostic tests inspect public error descriptions and captured allowlisted fields, proving that parser and file-system failures do not retain or emit content, paths, source bytes, or raw platform errors.
- Source-boundary checks ensure Domain/Application files do not import SwiftUI, Security, provider SDKs, or persistence implementations.

Run focused tests while implementing. At completion, delegate the strict format/lint/build/test gate to the required `test_runner` and record concise evidence in the overview checklist.

## Downstream handoff

- P1-M9 consumes workspace allocation and pending-audio roles, then chooses and validates lock-compatible protection mechanics and the recording reserve.
- P1-M10 owns queue/job persistence, creates and records installation identity, reconciles workspace contents, and quarantines restored or malformed jobs without granting paths from persisted data.
- P1-M13 creates the typed managed body/title metadata and draft through this codec and workspace port.
- P1-M14 coordinates the iCloud pair, verifies bytes/upload evidence, and releases staging only after the approved commit barrier.
- P1-M15 uses the bounded decoder/support classification for active-folder catalog pages, validates actual audio size/format/decoded duration before use, and adds legacy discovery without rewriting legacy files.
- P1-M17 presents malformed, unsupported, incomplete, and ambiguous resources and applies revalidated ownership rules to repair or confirmed removal.
- P1-M19 closes the adversarial and physical-device backup/restore evidence; M7 simulator evidence alone is not a shipping claim.
