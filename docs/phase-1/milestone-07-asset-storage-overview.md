# P1-M7: Asset schema and private storage overview

Status: Active

Implement the bounded Diary Snippet v1 schema and the private local-workspace foundation that later recording, queue, title, and iCloud milestones can use without passing unvalidated paths, unbounded bytes, or persistence details into core use cases.

## Entry condition

- Follow Phase 1 milestone order: implementation starts after P1-M6 is complete or the owner explicitly reorders the phase.
- The owner explicitly reordered P1-M7 ahead of P1-M6 on 2026-11-01 by requesting its implementation.
- Use the approved [P1-M5 schema, storage, and resource contracts](milestone-05-decisions-architecture.md). This milestone has no product decision to resolve and does not select a Cohere runtime, model artifact, dependency, or build tool.

## Scope

- Add domain values for asset identity, kind, schema version, canonical UTC instants, Diary Snippet metadata, optional context groups, transcription provenance, title provenance, and bounded diary bodies without adding a dependency. Domain values do not expose file URLs or persistence APIs.
- Implement the v1 Markdown codec: strict bounded UTF-8 front matter, fixed recognized-key order, canonical scalar serialization, body separation, supported/unsupported/malformed classification, and preservation of unknown flat scalar values.
- Generate and validate the approved UTC directory/file layout, lowercase canonical UUID v4 identity, and confined audio filename reference.
- Add an application-owned private-workspace port and a local adapter rooted in nonpurgeable Application Support storage. Callers use validated workspace identities and typed artifact roles rather than caller-supplied paths or persisted file URLs.
- Apply backup exclusion to pending audio, unsaved Markdown drafts, replacements, and recovery copies, and verify the attribute after creation and atomic replacement.
- Reserve an injected file-protection policy boundary without choosing a production Data Protection class. Provide typed, sanitized failures for bounds, malformed content, unsupported content, unsafe references, storage unavailability, atomic-write verification, backup exclusion, and an injected protection-policy failure.
- Add deterministic malformed-input fixtures, randomized round-trip/bounds coverage, and private-storage confinement tests.
- Document the contracts consumed by P1-M9, P1-M10, P1-M13, P1-M14, P1-M15, and P1-M17.

## Out of scope

- Recording, audio-session behavior, playable-audio inspection, decoded duration/format validation, the 100 MiB pre-recording reserve, queue state or job-record formats, transcription, title generation, optional-context acquisition, notifications, and user interface. M7 validates the declared schema fields and 301-second declaration; P1-M9 and P1-M15 validate the actual audio resource before their workflows trust it.
- Selecting Data Protection or Keychain accessibility classes for capture and durable queue settlement while locked. P1-M9 must choose and verify those mechanics on a physical device without changing the approved behavior.
- Creating the installation identity or deciding whether restored queue work is quarantined. M7 exposes the private-storage boundary needed by the queue; P1-M10 owns the identity contract, records it in jobs, and implements the approved restore classification, using the platform mechanism verified with P1-M9/P1-M19 evidence.
- Security-scoped bookmarks, iCloud folder selection, coordinated iCloud writes, upload observation, conflict handling, and deletion of finished or external resources.
- Active-folder enumeration, paging, legacy sibling discovery, audio decoding/playback, recovery screens, and rendering Markdown. Later milestones consume M7's bounded codec and reference validator for those workflows.
- Adding a YAML package or any other third-party dependency. A dependency or build-tool change still requires owner approval.

## Completion checklist

- [x] Domain types cannot represent an invalid canonical asset UUID or canonical whole-second UTC timestamp at a schema boundary. The v1 support policy recognizes exactly the approved schema, kind, transcription-method, and title-origin values, while other well-formed values classify as unsupported; unit tests separate valid, unsupported, and malformed forms.
- [x] Layout tests prove the approved UTC `year/month/day`, Markdown, `.assets`, and `.m4a` names, including independence from the device timezone.
- [x] Minimal and all-fields golden v1 fixtures decode to typed values and re-encode deterministically with the approved recognized-key order, scalar spelling and escaping, UTF-8 LF endings, exact delimiters, and one blank line before the body.
- [x] Round-trip tests prove unknown flat scalar keys retain byte-equivalent scalar values and stable relative order while unrelated recognized fields change; incomplete or malformed optional groups remain preserved but uninterpreted and are not emitted as typed context.
- [x] The codec rejects malformed UTF-8, CRLF input, duplicate or invalid keys, tags, anchors, aliases, nesting, sequences, block scalars, invalid or missing required fields, unsafe audio references, noncanonical identity/timestamps, and each exceeded 64 KiB front-matter, 1 MiB body, 64-key, and 8 KiB scalar bound without partially constructing a supported asset. Declared new-schema duration and audio fields are validated for their approved types and the 301-second declaration limit without claiming that M7 inspected the referenced audio bytes.
- [x] Boundary tests cover exact-limit and limit-plus-one inputs, delimiter-like body text, empty and Unicode bodies, integer/decimal overflow, and random invalid bytes; every case settles within bounded memory and work and never traps.
- [x] Tests classify unknown schema, kind, transcription method, and title origin as unsupported and read-only data rather than malformed data, without rewriting the source.
- [x] Private-workspace tests prove all created, opened, replaced, and removed resources remain within the validated app-owned root, including traversal, absolute/URL, encoded, sibling-prefix, symlink-swap, and alias cases where the platform exposes them; rejected input cannot read, overwrite, or delete another resource.
- [x] Storage tests prove the production root resolves beneath Application Support rather than Documents, Caches, or temporary storage. Atomic creation/replacement uses a same-workspace temporary, verifies intended bytes and attributes with bounded or streaming work, reapplies and verifies backup exclusion, and durably retains the prior bytes in place or in an adapter-owned recovery artifact at every injected failure point.
- [x] The port exposes only opaque validated workspace/artifact handles and typed roles; tests prove callers cannot use an external asset ID, filename, persisted URL, or malformed workspace identity as read, write, replacement, or deletion authority.
- [x] Production M7 applies no unapproved Data Protection class. An injected protection-policy seam and failure tests demonstrate that later P1-M9 policy can be applied and verified without silently downgrading or treating an inaccessible protected file as missing.
- [x] Failure values and test diagnostics contain only typed codes and opaque local identifiers, not diary text, titles, coordinates, paths, bookmarks, source bytes, or raw platform errors; tests inspect error descriptions and captured diagnostic fields.
- [x] The implementation contains no new dependency or build-tool change and preserves the inward dependency rule documented in [architecture.md](../architecture.md).
- [x] Affected documentation identifies the downstream consumers and leaves physical-device Data Protection, restore, and iCloud evidence assigned to their existing milestones.
- [ ] `swift-format lint --strict --recursive .` passes.
- [ ] `swiftlint lint --strict` passes.
- [ ] The generated project builds and all tests pass through `scripts/validate.sh` on an available iPhone simulator.

## Acceptance evidence

Check an item only with a focused test name, inspected file attribute/result, source-boundary check, or validation command result. Simulator tests may establish codec logic, path confinement, atomic replacement, and observable backup-exclusion attributes. They do not prove that backup exclusion removed an older backup, validate real backup/restore classification, choose a lock-compatible Data Protection class, validate actual audio bytes, or close iCloud behavior assigned to later milestones.

## Implementation evidence

- Domain values, the application-owned private-workspace port, Foundation codec/layout/storage adapters, and synthetic tests are implemented under `NarihitosDiary/Domain`, `NarihitosDiary/Application`, `NarihitosDiary/Adapters`, and `NarihitosDiaryTests` without changing `project.yml` or adding a dependency.
- The 2026-11-01 implementation review tightened the strict scalar grammar, added a typed 64 MiB workspace bound, kept URL-based protection policy out of the application contract, made overwrite publication atomic with a retained prior version, restored absence after failed initial publication, and failed closed on an unexpected recovery artifact. Focused regression tests cover each corrected state transition.
- On 2026-11-01 the required test runner reported passing scoped strict `swift-format` and `swiftlint`, the generic simulator build, and the complete M7 test suite on an iPhone 18 Pro simulator running iOS 27.0. `git diff --check` also passes.
- After the implementation review, the required test runner again reported passing scoped strict format and lint checks, a generic simulator build, and `git diff --check`; a host-side probe also confirmed that Foundation atomic replacement retained the old destination as the requested backup. The current CoreSimulatorService outage prevented rerunning the changed focused tests in that pass, so this is not additional completion-gate evidence.
- The exact repository-wide `scripts/validate.sh` gate remains incomplete: its recursive checks traverse the separate `tmp/worktrees/p1-m6-cohere-trial` worktree with existing format/lint failures outside P1-M7, and CoreSimulatorService currently refuses connections before a concrete test destination can be discovered. The final gate item remains unchecked.
