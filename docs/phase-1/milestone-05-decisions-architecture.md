# P1-M5: Approved decision contracts

Status: Done

This document is the implementation handoff for the owner-approved P1-M5 decisions. It records the bounded contracts later milestones must implement and the evidence they must still obtain.

## Title contract

- Measure the 30-character limit with Swift extended grapheme clusters, including any ellipsis. Truncate an overlong title to 29 clusters plus `…`.
- Use prompt revision `title-v1`. Request one faithful concise phrase in the current body language, with no quotation marks, prefix, invented facts, emoji, or ending punctuation.
- For a long body, use at most eight token-aware chunks of at most 2,000 model tokens and at most two summary passes. Limit intermediate summaries to 80 grapheme clusters, intermediate output to 128 tokens, final output to 64 tokens, and the entire title operation to 30 seconds.
- Every body part must contribute within those bounds or the operation is unusable. Require language confidence of at least 0.8; unsupported, uncertain, wrong-language, empty, or failed output uses the fallback.
- The fallback trims the body, uses the native sentence tokenizer, then the first nonempty text if no sentence is found. An empty saved body uses `Untitled`.
- Record the prompt revision and iOS version for AI titles, plus the model identifier only when the platform exposes one. A saved fallback stays until the next body save.

## Diary Snippet schema contract

- Generate a random UUID v4 and serialize it as lowercase canonical hyphenated text. Serialize instants as RFC 3339 UTC with whole-second precision and `Z`, for example `2026-11-01T12:34:56Z`.
- Preserve the UTC `year/month/day` hierarchy. Name the Markdown `YYYY-MM-DD_HH-mm-ss-<uuid>.md`, its sibling directory `YYYY-MM-DD_HH-mm-ss-<uuid>.assets`, and its audio `<uuid>.m4a`.
- Serialize UTF-8 with LF endings, `---` delimiters, a fixed recognized-key order, double-quoted escaped strings, lowercase booleans, decimal numbers, and one blank line before the body. Accept only flat scalar YAML; reject duplicate keys, tags, aliases, nesting, and invalid required types.
- Required v1 fields, in canonical order, are `schema_version`, `kind`, `id`, `created_at`, `updated_at`, `title`, `title_origin`, `favorite`, `language`, `audio_filename`, `recording_duration_ms`, `audio_codec`, `audio_sample_rate_hz`, `audio_channels`, `audio_bitrate_bps`, `transcription_method_id`, `transcription_language_hint`, and `transcription_settings_revision`. `schema_version` and the initial `transcription_settings_revision` are integer `1`; duration/audio numeric fields are integers; `favorite` is Boolean; identifiers, timestamps, names, origins, languages, codec, and provenance are strings.
- For a new draft, `language` and `transcription_language_hint` both store the explicit recording hint, `en-US` or `ko-KR`, and remain recording metadata after body edits. A different detected body language affects title generation, not those fields.
- Conditional transcription fields are `transcription_model_id`, `transcription_model_version`, `transcription_runtime_id`, and `transcription_conversion_id`. AI title fields are `title_prompt_revision`, `title_os_version`, and optional `title_model_id`.
- A location group requires decimal `location_latitude`, decimal `location_longitude`, string `location_sampled_at`, and decimal `location_horizontal_accuracy_m`; string `location_place_name` is optional. A weather group requires string `weather_observed_at`, string `weather_summary`, and decimal `weather_temperature_celsius`. Timestamps use the canonical UTC form. Omit an unavailable group. Preserve malformed optional-group fields on unrelated rewrites but do not interpret the group.
- Stable values are kind `ndm.diary-snippet`, methods `ndm.transcription.apple` and `ndm.transcription.cohere`, and title origins `apple-ai`, `first-sentence`, and `empty-body`.
- Preserve unknown flat scalar keys byte-value-equivalently without interpreting them. Unknown schema, kind, method, or title-origin values are unsupported, untouched, and read-only in Incomplete Diary Snippets. A known v1 Diary Snippet with malformed required fields follows the same recovery containment when no repair copy exists.
- Legacy assets receive only an ephemeral path-based catalog identity and are never rewritten; existing names, including millisecond timestamp forms, remain unchanged. A legacy Markdown file with exactly one safe plausible audio sibling is read-only on Main; zero or multiple plausible audio siblings go read-only to Incomplete Diary Snippets with an explanation.

## Recording, queue, and privacy contract

- Target mono AAC `.m4a`, 44.1 kHz, about 64 kb/s. Continue capture through lock and app backgrounding until Stop & Transcribe, interruption, or five minutes. Finalize and durably queue immediately even while locked.
- After a crash or force quit, queue a playable partial recording automatically; retain an unreadable partial in Failed Recordings.
- Exclude pending audio and unsaved drafts from backup. Mark each install with a random Keychain installation ID using `ThisDeviceOnly`. Quarantine jobs restored from an older install in Pending Recordings with a review-required state; offer Resume and Remove. Resume creates a fresh attempt from current Settings.
- Refresh method readiness when Settings opens, when the app becomes active, and immediately before a worker claims a job. Missing method/model/destination/upload proof waits. Decoder/runtime failure, unusable text, or the ten-minute cutoff fails with audio retained. A queue-store failure pauses the queue.
- Use these exact sanitized entry messages and actions: `Apple transcription isn’t ready for {language}.`—Download Model/Choose Method; `Cohere model isn’t installed.`—Install Model/Choose Method; `Waiting for access to {folder}.`—Restore Access; `Waiting for iCloud upload verification.`—Retry Verification; `No usable diary text was found.`—Retry; `Transcription stopped after 10 minutes.`—Retry; `This recording can’t be read.`—Retry/Remove; `Pending work is paused because local storage isn’t available.`—Retry.
- Request notification permission only when the first reminder is needed. Schedule generic text `You have pending diary work.` for the next local day at the same local wall-clock time; recompute on reopen with the current timezone and choose the next valid time across DST. Cancel it when no pending work remains. On denial, retain in-app recovery and a nonblocking Settings route without repeated prompts.
- A confirmed removal cancels an unverified save. If complete verification won the mutation barrier first, preserve the finished asset and explain the completion.
- Cover all app content with a neutral privacy view outside the foreground. Logs and crash diagnostics may contain only operation/failure codes, durations, counts, and opaque IDs—not content, coordinates, paths, bookmarks, prompts, or raw SDK errors. V1 has no biometric app lock or app-level encryption.

## Storage, iCloud, and resource contract

- Require the folder picker to positively verify iCloud Drive; reject local, third-party, or ambiguous providers. Ordinary provider/network errors remain temporary. Offer replacement only after the user confirms removal or revoked access, and retarget only that job.
- Retain the protected local candidate until both files validate locally against the candidate and each reports successful upload. Missing or unavailable upload evidence keeps the job waiting without blocking other jobs.
- Keep conflict candidates as protected Markdown/audio pair snapshots. Publish and verify the chosen pair before removing obsolete iCloud versions and private snapshots.
- Limits: 64 KiB front matter, 1 MiB body, 64 MiB audio, 64 keys, 8 KiB per scalar, 301 seconds for new-schema audio, 50 catalog candidates per page, and a 100 MiB free-space reserve before recording. There is no collection or pending-job count cap.
- If the reserve is unavailable, show `Not enough storage to start recording.` with actions `Review Pending Recordings` and `OK`.
- Stream legacy audio only up to 60 minutes and 64 MiB; otherwise show the text with audio unavailable.
- Model downloads use HTTPS and an app-bundled URL/length/digest allowlist, at most three redirects among listed hosts, expanded-size validation, and a 1 GiB free-space preflight. New approvals and revocations require an app update. There is no fixed installed-model/cache cap.
- Repository-owned code remains Apache-2.0. Remove dependency-license compatibility as a milestone gate for every dependency, while retaining owner approval for dependency and build-tool changes.
- Render diary Markdown as inert native content: no interactive links, HTML/scripts, remote images, or automatic fetches.
- Before the first folder-backed save, show a one-time privacy notice explaining that diary text, audio, and optional exact location are readable files and that anyone with folder access may read them.

## Context and interface contract

- Context describes recording start. Begin acquisition then and accept results only before initial asset commit. Location must be no older than five minutes with horizontal accuracy at most 500 m. Keep coordinates if geocoding fails and display them when no place is available. Weather must be observed within 60 minutes; store Celsius and display with the system measurement locale. Show weather attribution beneath weather in Metadata. Amended 2026-11-11: the source is Open-Meteo with Open-Meteo attribution, behind a separate default-Off toggle, and manual snippets may carry context from their first Save; see the [M18 owner decisions](milestone-18-context-reminders-overview.md#owner-decisions-and-stages-2026-11-11).
- Completion into a former active folder uses a dismissible six-second banner, `Diary saved to {folder}.`, with a polite VoiceOver announcement and no motion under Reduce Motion.
- Icons are monochrome custom template bitmaps with outline and filled/state variants at 1x/2x/3x. Use conventional metaphors for tabs, recording, settings, recovery, favorite, and playback. Use 25 pt tab art, 24 pt inline/control art, and 32 pt Record/Stop art inside targets of at least 44 by 44 pt.
- Visible labels are their accessibility names; icon-only controls use the canonical action. Playback uses `Play audio`, `Pause audio`, and `Audio position`, with value `{elapsed} of {total}` and adjustable 15-second seek steps. Conflicts use `Version 1` and `Version 2` with modification date as the value when available.
- Main notice rotation pauses for VoiceOver and politely announces each newly appearing state once. Screen headings are the exact destination label, `Diary Snippet`, and `Edit Diary`; capture adds no extra heading.
- Word-linked replay/highlighting is outside v1.

## Evidence handoff

P1-M8, P1-M9, P1-M14, P1-M17, and P1-M19 must verify their assigned platform behavior before shipping. Those checks may refine mechanisms but must not silently change these owner-approved outcomes.
