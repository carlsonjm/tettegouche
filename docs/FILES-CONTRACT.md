# Files contract

This document defines the current Explore files behavior and the invariants that
must survive future work. Historical slice and physical-validation records are
in [archive/](archive/README.md).

## State and navigation

- `FileBrowser` owns listing, tabs, path history, selection, focus, clipboard
  interpretation, and file operations. `FilesPane.qml` renders that state.
- `KCoreDirLister` performs asynchronous local listing. Navigation disconnects
  the previous lister, and generation/state checks prevent stale replies from
  replacing a newer location.
- Home, standard user folders, and already-mounted local/removable paths form
  Places. Mount metadata is read without `statvfs` or readiness probing.
- Tabs are bounded at 20. Path, history, scroll, sort, filter, hidden state, and
  selection are local to the applicable process/tab state. Saved absolute tab
  paths may persist, but history and selection do not.
- Filename filtering is case-insensitive within the current directory. It is not
  recursive search and must not route Enter to hidden application results.

## Selection and opening

- Mouse click selects and double-click opens. Ctrl toggles, Shift selects a
  visible range, and empty-space click clears selection.
- Touch tap selects; double-tap opens. Hold exposes context/drag behavior without
  allowing synthesized mouse handlers to double-handle the event.
- Keyboard supports arrows, Home/End, range extension, focus-only movement,
  Ctrl+A/C/X/V, Alt+Left/Right/Up, Ctrl+L, F2, and Escape for the current context.
- Mouse box selection validates intersected items against the visible listing.
  Modifier behavior is computed from the selection captured at press.
- Files open through `KIO::OpenUrlJob` with executable prompts disabled. Native
  associations choose the application. URLs are data, never shell commands.

## Mutations

- Copy, move, folder creation, rename, Trash, recovery, and internal folder drops
  use asynchronous KIO jobs. Only one write job runs at a time.
- Copy and ordinary internal drag preserve originals. Paste honors an explicit
  KDE cut marker and then moves. A successful move clears only the unchanged,
  matching cut clipboard.
- Internal drops validate listed sources and destination, deduplicate paths, and
  reject self/descendant folder copies. External drop is not part of the current
  contract.
- Folder and rename inputs reject empty names, dot/dotdot, slash, and NUL. A
  captured target check prevents a changed selection from renaming another item.
- No job receives an overwrite flag. A collision stops with a visible error;
  already-completed items may remain and partial completion must be stated.
- Trash requires confirmation and has no permanent-delete fallback. Recovery is
  limited to the latest Tette-recorded item, persists its URL, refuses overwrite,
  and retains the record after failure.

## Lifecycle and activity

- Closing or handing off hides the launcher and releases its Kadunce guest
  immediately. An outstanding job defers process exit until it finishes.
- Reopening cancels deferred quit and restores current operation status. Late
  errors remain available to the reopened process.
- The launcher exports a revisioned operation snapshot and UUID-checked Cancel on
  `/Activities`, interface `io.github.carlsonjm.Tettegouche.Activities1`.
- Ambient may present KIO progress and source-supported Cancel. Presentation does
  not take ownership of the operation and must generation-check actions.
- Forced process termination is not transaction-safe; a partial destination may
  remain. Navigation remains independent of the active job's destination.

## Safety invariants

- Never execute file names or paths through a shell.
- Never infer an overwrite, merge, move, permanent delete, or successful
  completion that the user/source did not request or prove.
- Validate operation sources against the current listing and revalidate targets
  captured by delayed UI.
- Do not synchronously touch saved or removable paths during launcher startup.
- Use isolated disposable fixtures for mutation tests. Do not use the user's
  files or Trash.

## Current boundary

There is no recursive search, thumbnail/preview service, Recent provider, Open
With, properties, external drag/drop, mount/unmount/eject workflow, network
location workflow, split view, full Trash browser, or general undo. Conflict
handling refuses overwrite rather than offering merge/replace choices.
