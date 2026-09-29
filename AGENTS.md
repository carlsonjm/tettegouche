# Agent instructions

## Startup

1. Read `AGENTS.md`.
2. Read `docs/ARCHITECTURE.md`.
3. Read `docs/ROADMAP.md`. Suite block order, cross-repository dependencies,
   open product decisions and this component's task detail belong to the suite
   record, kept privately in the Shuffle repository:
   `../shuffle/docs/suite/ROADMAP-CC.md` and
   `../shuffle/docs/suite/roadmaps/TETTEGOUCHE.md`. Read them when that checkout
   is present, and say so when it is not.
4. Open only the other documents the work touches; `docs/README.md` routes to
   them.

Archived evidence is kept privately with the suite record, for regression
diagnosis, provenance or a failed approach. Do not build task context from it or
from Git history.

## Rules

- Every input Tettegouche handles is defined in `docs/INPUT.md`. It opens with
  the controls map: each destination by its product name, with the touch and key
  that reach it, and every other action under that name below. A README quick
  start repeats rows of the map; `tests/verify-public.py` checks both.
- This repository is public. Its documents, code comments and commit messages
  describe the product: Tettegouche does things, you act, shipped behavior is in
  the present tense, and planned behavior lives only in `docs/ROADMAP.md`. They
  carry no names, approvals or approval dates, no chat or handover narration,
  and nothing of Table, whose design stays with Kadunce. `tests/verify-public.py`
  checks what a check can, in files and in commits not yet pushed; who decided
  what belongs in the private suite record.
- Each document owns one subject and states what is true now. Removed text lives
  in Git history.
- Keep an assignment compact: roadmap item, required outcome, relevant
  contracts, acceptance checks, stop conditions, permissions already granted.
- Establish an authoritative data source and a narrow fixture before changing
  presentation or lifecycle behavior.
- Code comments explain code behavior or reasoning only: no agent conversation,
  handoffs, instructions, implementation history or authorship notes.
- Run `./verify.sh` before treating a source, packaging, test, or documentation
  change as complete.
