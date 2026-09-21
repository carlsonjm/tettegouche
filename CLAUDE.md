# Tettegouche — Claude Code entry point

`AGENTS.md` is the authoritative startup and working contract for this repository
and applies unchanged to Claude Code. Read it first. This file adds only the suite
context and session facts `AGENTS.md` does not carry.

## Which checkout

The working tree is `Projects/Shuffle/tettegouche`. A second checkout at
`Projects/Itasca/tettegouche` predates the current execution plan. Confirm the
path before reading or editing.

## Suite position

Tettegouche is one of three open-source component repositories in the Shuffle
suite. Block order across the suite is owned by
`../kadunce/docs/ROADMAP-CC.md`. Tettegouche completion is its Block 6; the
Ambient and ticker width work is blocked by the Bottom Surface in Block 5.

`docs/NEXT-ROADMAP.md` holds this repository's execution plan and task detail.
`ROADMAP-CC.md` decides which block is next; `NEXT-ROADMAP.md` decides what the
work inside it is. When only this repository is checked out, work from
`NEXT-ROADMAP.md` and say that the suite plan was unavailable.

The Shuffle dock is infrastructure that resolves the asymmetric Ambient and
ticker width, and it lives downstream of the component repositories rather than
in one of them. Tettegouche must stay fully functional without it: an
installation that lacks the dock is a supported configuration, not a degraded
one.

## Verification

Run `./verify.sh` before treating a source, packaging, test or documentation
change as complete. It configures, builds and runs CTest, so it needs a local
session with the Qt and KDE development stack.

`tests/verify-docs.py` enforces index coverage: a new tracked document must be
added to `docs/README.md` in the same change.

## Suite rules

- J approves product behavior and visual direction before implementation begins.
- One implementation owner per repository; a second worker is read-only review or
  a disjoint file set.
- Reproduce a defect and measure the property controlling it before changing it.
- Keep plans, current truth, durable rationale and live handoffs in their own
  documents. Git carries history; live documents carry no narration.
- `src/main.cpp` hard-codes `studio.warbler.Kadunce` in seven places. Changing
  that namespace is Block 10b, coordinated across all three repositories and
  versioned — never a local cleanup.
