# Agent instructions

## Startup order

1. Read `AGENTS.md`.
2. Read `docs/CURRENT_STATE.md`.
3. Read `docs/NEXT-ROADMAP.md`.
4. Read `SWARM.md`.
5. Read only the canonical or reference documents relevant to the assigned work;
   use `docs/README.md` to find them.

`docs/archive/` is opt-in evidence. Consult it only for regression diagnosis,
provenance, or a failed approach. Do not reconstruct ordinary task context from
archived sprint records or Git history.

`docs/NEXT-ROADMAP.md` is this repository's execution plan and the source of task
detail. Suite block order, cross-repository dependencies and open product decisions
are owned by `ROADMAP-CC.md` in the Kadunce repository; read it when that checkout
is present. Put durable architecture and product decisions in `docs/DECISIONS.md`,
current facts in `docs/CURRENT_STATE.md`, and runtime coordination in `SWARM.md`.

Claude Code loads `CLAUDE.md` automatically. It routes into this same startup set
and adds no separate protocol.

## Work packets

Keep assignments compact and ordered: repository and roadmap item; required
outcome; task-relevant contracts; acceptance checks; stop conditions; permissions
already granted. Omit history and unrelated reading. If another worker must act,
reduce the dependency to one `SWARM.md` handoff and delete it when resolved.

Run `./verify.sh` before treating a source, packaging, test, or documentation
change as complete.
