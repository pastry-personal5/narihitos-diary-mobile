# P1-M15: Evidenced legacy Diary Snippet format

Status: Active

The owner supplied two pre-v1 Markdown/audio examples on 2026-11-02, resolving M15's legacy-format prerequisite. This contract describes their structure using synthetic values; personal source content, coordinates, names, paths, and audio are not committed or used as test fixtures.

## Names and pairing

The existing layout is UTC `year/month/day`. A legacy Markdown basename is a UTC timestamp at millisecond precision, `YYYY-MM-DD_HH-mm-ss-SSS.md`, without a v1 UUID suffix. Its sibling directory has the same stem and the `.assets` extension. The examples each contain one regular `.m4a` whose basename is independent of the Markdown ID (the observed writer used two UUID-shaped components); do not infer audio ownership from that basename.

Discover regular `.m4a` siblings with confined, non-following access. Exactly one safe plausible sibling permits read-only Main/detail. Zero/multiple siblings produce explained recovery. Unsafe siblings are never opened. A single safe audio beyond the approved byte/duration bounds or failing decode leaves safe text readable with audio unavailable. This preserves the [approved pairing policy](milestone-05-decisions-architecture.md#diary-snippet-schema-contract); names grant no mutation authority.

## Header and body

The envelope is UTF-8 with LF endings and `---` front-matter delimiters. `id` equals the timestamp-only basename. `created_at` and `updated_at` are quoted ISO 8601 timestamps with milliseconds and an explicit numeric UTC offset. Parse the recording instant and require it to match the UTC stem and hierarchy; do not reinterpret the offset as local file naming.

The evidenced header includes `tags` as an empty array, written either inline or as the following indented `[]` line, and Boolean `favorite`. Accepting that exact empty-array spelling does not enable general nested YAML. The observed optional context fields are flat `weather_summary`, `weather_temperature_celsius`, `location_latitude`, `location_longitude`, and `location_place_name`. Legacy context does not acquire invented v1 sample/observation timestamps. Validate ranges and scalar types independently, omit unavailable context, and never look it up again. The observed provenance fields `transcription_model` and `transcription_prompt` remain inert, uninterpreted scalars. A language hint is displayed only if present; never derive one from the transcription model name.

Keep the existing M7 byte/key/scalar limits. Reject duplicate keys, tags/aliases/object construction, unexpected nesting, invalid known fields, ambiguous timestamps, and unsafe references. A document declaring v1 schema/kind cannot fall back to legacy. Other historical shapes need further evidence before broadening this reader.

The body is the text after the closing delimiter and optional single blank separator. Render it verbatim as inert native text. Use the existing pure first-sentence fallback for a nonpersisted display title. Do not expose a legacy Favorite/editor action or write a new schema, title, provenance, audio name, or metadata.

## Evidence and regression coverage

`LegacyDiaryReaderTests` uses a synthetic timestamp with an offset, empty tags, invented place/coordinates/weather, and inert text. `DiaryCatalogHandlerTests` generates synthetic AAC in a temporary directory and covers unique/zero/multiple/unsafe siblings and corrupt audio. No test reads the owner-supplied examples.
