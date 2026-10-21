# Tettegouche — Claude Code entry point

`AGENTS.md` is the working contract and applies unchanged; read it first.

- Tettegouche must stay fully functional without the Shuffle dock, which lives
  downstream. An installation without it is supported, not degraded.
- `src/KadunceClient.h` names Kadunce's D-Bus interface, `co.goodinput.Kadunce`,
  for every call Search makes to it. Changing that namespace is coordinated
  across all the suite's repositories and versioned, never a local cleanup.
- `./verify.sh` needs a local session with the Qt and KDE development stack.
