# Documentation index

Canonical documentation states what is true now, why it is true, and what must
be preserved. Git and [archived evidence](archive/README.md) record how the
implementation arrived there.

## Normal startup

Read only:

1. [`AGENTS.md`](../AGENTS.md)
2. [`CURRENT_STATE.md`](CURRENT_STATE.md)
3. [`NEXT-ROADMAP.md`](NEXT-ROADMAP.md)
4. [`SWARM.md`](../SWARM.md)

Then open a subsystem document only when the assigned work touches it. Do not
scan `docs/archive/` during normal startup.

Run `../verify.sh` for the repository's build, tests, source, package, and
documentation checks. The documentation guard enforces archive isolation, compact
runtime handoffs, current-state hygiene, and index coverage.

## Classification

### Canonical

| Document | Authority |
| --- | --- |
| [`AGENTS.md`](../AGENTS.md) | Agent startup and documentation routing |
| [`CLAUDE.md`](../CLAUDE.md) | Claude Code entry point; routes into the `AGENTS.md` startup set |
| [`CURRENT_STATE.md`](CURRENT_STATE.md) | Current implemented behavior and known limits only |
| [`NEXT-ROADMAP.md`](NEXT-ROADMAP.md) | This repository's execution plan and task detail; suite block order lives in Kadunce's `ROADMAP-CC.md` |
| [`DECISIONS.md`](DECISIONS.md) | Durable architecture and product decisions |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Process, ownership, integration, and safety boundaries |
| [`SEARCH-CONTRACT.md`](SEARCH-CONTRACT.md) | Search eligibility, ranking, identity, and execution |
| [`FILES-CONTRACT.md`](FILES-CONTRACT.md) | Files behavior, lifecycle, and mutation safety |
| [`AMBIENT-CONTRACT.md`](AMBIENT-CONTRACT.md) | Activity admission, source truth, layout, and actions |
| [`RELATED-SETTINGS.md`](RELATED-SETTINGS.md) | Read-only related-setting provider contract |
| [`SWARM.md`](../SWARM.md) | Ephemeral runtime coordination; empty when no live handoff exists |

### Reference

| Document | Purpose |
| --- | --- |
| [`README.md`](../README.md) | Product and build overview |
| [`CHANGELOG.md`](../CHANGELOG.md) | Product-level release summary |
| [`docs/README.md`](README.md) | Classification and routing index |
| [`archive/README.md`](archive/README.md) | Old-path mapping for archived evidence |
| [`ITASCA-VISUAL-LANGUAGE.md`](ITASCA-VISUAL-LANGUAGE.md) | Shared suite visual, icon, and motion language |
| [`assets/icons/THIRD_PARTY.md`](../assets/icons/THIRD_PARTY.md) | Vendored icon provenance and license mapping |

### Historical evidence

The 21 dated freezes, candidate audits, handoffs, superseded plans, and physical
validation records formerly at the top of `docs/` are indexed in
[`archive/README.md`](archive/README.md). They are opt-in evidence and carry no
current execution authority.

### Obsolete or redundant

No document was deleted in this pass. The former `PRODUCTION-READINESS.md` and
`FILES-REMAINING.md` execution roles are obsolete; both were archived because
their provenance and old references remain useful. Their live content is
normalized into `CURRENT_STATE.md` and `NEXT-ROADMAP.md`.

## Updating documentation

- Update current facts in `CURRENT_STATE.md`; do not add acceptance chronology.
- Update planned work only in `NEXT-ROADMAP.md`.
- Add a durable invariant or ownership decision to `DECISIONS.md` and the
  relevant subsystem contract.
- Move completed packet evidence to `archive/` and add its old/new path mapping
  to `archive/README.md`.
- Keep candidate hashes, installers, physical checklists, and rejected approaches
  out of canonical documents.
