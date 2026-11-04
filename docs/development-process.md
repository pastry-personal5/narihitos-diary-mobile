# Development process

Status: Active

Work is organized into numbered phases and milestones. This guide owns planning, completion, and documentation rules; [AGENTS.md](../AGENTS.md) defines agent workflow and approval boundaries.

## Structure and status

- A **phase** is a product increment with a goal and exit criteria. Status: `Planned`, `Active`, or `Done`.
- A **milestone** is a small, verifiable step that fits one reviewable change or short series. Numbering restarts per phase. Status: `Planned`, `Active`, `Done`, or `Dropped`.
- IDs use `P<phase>-M<milestone>` (for example, `P1-M2`).
- Keep one active phase and follow its milestones in order unless its plan says otherwise.
- Phase and milestone numbers may change. Update IDs, filenames, and links together. Mark a dropped milestone `Dropped` with a one-line reason.

## Definition of done

A milestone is done when:

1. Its completion checklist is checked with acceptance evidence.
2. The [required validation gate](contribution-guide.md#required-validation) passes. The owner exempts P1-M1, P1-M2, P1-M4, P1-M5, and P1-M6 from build, lint, and test gates; their checklists and documentation remain required. For other milestones, leave unavailable required checks unchecked and report the blocker.
3. Affected docs and its phase-doc status are updated in the same change.

A phase is done when every milestone is `Done` or `Dropped` and its exit criteria hold.

## Plan files

Create a phase directory when planning that phase.

| File | Purpose |
|---|---|
| `docs/roadmap.md` | All phases with ID, title, status, and phase-doc link; the sole authority for the active phase. |
| `docs/phase-N/phase-N.md` | Phase goal, exit criteria, and brief milestone entries. |
| `docs/phase-N/milestone-NN-<theme>-overview.md` | Milestone goal, in/out scope, and completion checklist. |
| `docs/phase-N/milestone-NN-<theme>-architecture.md` | Affected modules, interfaces, approach, and sequencing. |
| `docs/phase-N/changelog.md` | Reverse-chronological decisions and plan changes not clear from commits. |

`N` is the phase number. `NN` is the zero-padded milestone number matching its ID; `<theme>` is kebab-case. Do not use a generic `phase.md` filename.

Keep phase-doc milestone entries short:

```markdown
# Phase 1: <title>

Status: Active
Goal: <one sentence>

## Exit criteria
- <observable outcome>

## Milestones

### P1-M1: <title>
Status: Done
Goal: <one sentence>
Plan: [overview](milestone-01-<theme>-overview.md), [architecture](milestone-01-<theme>-architecture.md)
Notes: <optional decisions or links>
```

Before implementation, create and link `milestone-NN-<theme>-overview.md` and `milestone-NN-<theme>-architecture.md`, with a verifiable completion checklist in the overview. Resolve related [undecided items](../AGENTS.md#undecided--ask-before-inventing) first. Create the roadmap when planning the first phase.

Record owner decisions, departures from the architecture plan, decided open questions, and reordered/dropped milestones in `changelog.md`:

```markdown
# Phase 1 changelog

Status: Active

## Entries

- 2026-09-28 — <who> — <what changed and why; optional link>
```

## Documentation rules

- `README.md` is user-facing; `AGENTS.md` holds agent workflow and links to contributor rules; `docs/` holds plans and design; `docs/archive/` holds inactive docs.
- Use lowercase kebab-case filenames for new docs. Start each standalone doc with a title, `Status:` line, and a one- to three-sentence summary. Preserve conventional entry filenames such as `README.md` and `AGENTS.md`; `CLAUDE.md` remains an import of the agent instructions.
- Add every doc to the [documentation index](README.md). Link to the owning document instead of copying facts. Keep product contracts in [product behavior](product-behavior.md), interface behavior in [UX GUI](ux-gui.md), mechanisms in [architecture](architecture.md), setup/commands in the [contribution guide](contribution-guide.md), and decisions/evidence in milestone records.
- Update affected docs with code, including the root README for user-visible changes. Update the relevant contributor guide for tooling/commands and `AGENTS.md` when agent workflow or approval boundaries change.
- Record resolved owner decisions in the appropriate contract and phase changelog; keep the [decision links](../AGENTS.md#decided--ask-before-changing) and undecided list current.

## Document lifecycle

- Other docs use `Draft`, `Proposal`, `Active`, `Superseded by <link>`, or `Archived`. Proposals are not decisions.
- Keep milestone plans and their research in active directories until their phase is complete, even when a milestone is done. Then update their status, use `git mv` to move the phase directory under `docs/archive/phases/` and concluded research under `docs/archive/`, and fix roadmap, index, and other affected links. Superseded standalone docs may be archived earlier. Archived docs are not maintained.
