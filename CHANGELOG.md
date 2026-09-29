# Changelog

This file records product-level changes. Commit history carries implementation
provenance.

## Unreleased

- Corners follow the suite's three tiers: the launcher's sheet and all it holds
  at 8 px, menus and the open island at 12 px, and Files' buttons as pills.
- Files lists drives under its places as they are plugged in, opens one with a
  tap, mounting it if needed, and ejects a plugged-in one, after any copy to it.
  Files can be the file manager: made KDE's default for folders, with its
  D-Bus service in place, Plasma's drive pop-up and other applications' "Show
  in folder" open it, and Dolphin keeps Trash and network shares.
- Files trades files with other applications by dragging. Carried past its
  edge, a selection goes on to any application as a copy; files dragged in from
  an application on another display are copied into the folder shown, or the
  folder tile they are dropped on, and never moved.
- Files asks when a name is taken, with Replace, Skip, Keep both and Merge for
  folders, once or for the rest; opens with any application, optionally as the
  new default; compresses and extracts through Ark; and empties Trash after a
  confirmation.
- Files shows thumbnails of photos, videos, PDFs and documents, made at most
  four at a time from KDE's shared cache, and Properties: kind, size, folder and
  dates, a folder's total size, and a photo's, song's or video's own details.
- Files opens Recent, the files and folders used most recently, and searches a
  folder and everything inside it for a name from a pill that appears as you
  type, or Enter, with no file index needed.
- The launcher keeps search, its results and both drawers above the on-screen
  keys, and Files gives the folder the room while they are up. Meta+G opens
  Browse everything and Meta+E Files, listed in System Settings' Shortcuts.
  Files' pills are as wide as their labels.
- Made Files touch-first: a tap opens, a touch and hold chooses several with an
  action bar, and tiles resize by pinch or Ctrl with + or −. Copies and moves run
  beside other file actions, each with its own progress, Pause and Cancel.
- Made Ambient one clear island centred in its side of the panel, black when
  the panel is black. The first activity keeps it and the next waits in a
  bubble; a tap opens it in place with album art, the track's position, back
  and forward 10 s, the other players, and each transfer's own actions.
- Made the launcher a 44 px touch square with a 24 px dot, the size of a
  panel's status icons, starting 10 px from the square's edge.
- Added a responsive Ambient panel surface backed by live MPRIS sessions,
  shared Plasma desktop jobs, Tette file operations, and observed Downloads
  arrivals.
- Added local file browsing, opening, selection, copy/move, rename, folder
  creation, drag-copy, Trash, and last-item recovery.
- Added expanded Kadunce guest presentation for application and Files drawers,
  with dock-safe bounds and standalone fallback.
- Adopted the suite Lucide action-icon foundation and shared motion language.

## September 2026 baseline

- Added confidence-based local search, Everyday/All files scope, quiet folders,
  related settings context, and stable destination selection.
- Added versioned Kadunce workspace context and Card Line guest integration.
- Added Meta/panel toggle behavior and fullscreen panel access.
