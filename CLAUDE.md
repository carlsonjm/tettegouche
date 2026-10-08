# Tettegouche — Claude Code entry point

`AGENTS.md` is the working contract and applies unchanged; read it first.

- Tettegouche must stay fully functional without the Shuffle dock, which lives
  downstream. An installation without it is supported, not degraded.
- `src/main.cpp` hard-codes `co.goodinput.Kadunce` in seven places. The suite
  moved from `studio.warbler` to `co.goodinput` in one coordinated change
  (J, 8 October); any further change is coordinated the same way, never a local
  cleanup.
- `./verify.sh` needs a local session with the Qt and KDE development stack.
