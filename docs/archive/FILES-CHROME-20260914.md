# Compact Files actions and touch timing

Candidate following J's full drag/drop pass (local checkpoint 717118e).

- Action-row controls use neutral pill backgrounds, 12px horizontal padding and
  the existing 42px hit height. Breadcrumbs retain their quieter presentation.
- Operation status occupies the middle of the action row, eliding when needed;
  it no longer adds a vertical row. Errors still have wrapping space for safety.
- Touch file hold shortened from 500ms to 180ms. J suggested potentially 90ms;
  180ms is the first trial because files must distinguish normal taps/scrolling
  from holding, unlike a dedicated divider rail. Hold-release menu and hold-move
  drag are otherwise unchanged.

Build and QML controls passed, including touch holds exercised after 230ms rather
than the old 650ms wait. UI render inspected. Physical acceptance pending.
Dock-safe Active sizing remains in PRODUCTION-READINESS.md; no geometry change.

Installer: install-tette-files-chrome-20260914.sh (workspace root).
Candidate: b4bceaeb7c748cdc4095ac26835b28284869c67a4133791f2eca845ff3cd5275.
Rollback: accepted fcc13575 drag build. No install or push performed.
