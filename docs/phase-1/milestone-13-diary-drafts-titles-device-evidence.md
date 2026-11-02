# P1-M13: Diary draft and title device evidence

Status: Active

Record redacted target-iPhone observations for the production candidate-to-draft path. Use synthetic English/Korean content; do not commit audio, diary text, prompts, private paths, identifiers, model output, or raw logs.

| ID | Required observable evidence | Status |
|---|---|---|
| M13-D01 | A verified Apple candidate becomes one codec-valid protected draft with exact managed body, stable asset ID, recording-start timestamp, correct provenance, backup exclusion, and no enduring transcript sidecar. | Not run |
| M13-D02 | A verified Cohere candidate follows the same path; both front-matter language fields keep the recording hint when the body's language differs, the title model uses the body's current language, and an unavailable or failed model yields a bounded first-sentence title while draft creation continues. | Not run |
| M13-D03 | Long English and Korean bodies exercise whole-body coverage and bounded fallback; Unicode/ellipsis titles remain at most 30 Swift grapheme clusters and record correct title origin. | Not run |
| M13-D04 | Termination between draft, binding record, queue transition, and candidate cleanup; locked protected data; stale title callback; and confirmed removal preserve audio and converge to one current draft or a visible recovery state. | Not run |
| M13-D05 | A temporary destination outage retains the verified draft for M14; offline title work and diagnostics reveal no body, prompt, path, or destination content. | Not run |

For each run, record device/iOS/app build, candidate method and synthetic input length class, model availability class, operation timing class, observed outcome, and the evidence collection method. Keep failed and unrun rows explicit. M13 device evidence does not establish M14 iCloud publication or M16 edited-body behavior.

## Simulator validation (does not satisfy D01–D05)

On 2026-11-02, `make lint`, `git diff --check`, and `scripts/validate.sh` passed with the booted iPhone 18 Pro simulator after the draft-store retry and recovery tests. The gate completed project generation, build, and the full test suite. Tests covered Apple/Cohere candidate adoption, title token/chunk/grapheme and timeout limits, old queue-record decoding, source and draft/binding substitution detection, protected-data and queue-store deferral, asset-ID and write/read faults, post-transition cleanup, restored-work quarantine, and a removal tombstone during title work. No physical iPhone was discoverable, so the target-device rows remain Not run; simulator tests do not prove real file protection, model behavior, lifecycle recovery, or privacy observations on the target phone.
