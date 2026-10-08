# Tettegouche — Claude Code entry point

`AGENTS.md` is the working contract and applies unchanged; read it first.

- Tettegouche must stay fully functional without the Shuffle dock, which lives
  downstream. An installation without it is supported, not degraded.
- `src/main.cpp` hard-codes `co.goodinput.Kadunce` in seven places. Changing that
  namespace is coordinated across all the suite's repositories and versioned,
  never a local cleanup.
- `./verify.sh` needs a local session with the Qt and KDE development stack.
