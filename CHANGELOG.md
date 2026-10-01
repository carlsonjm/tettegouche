# Changelog

This file records product-level changes. Commit history carries implementation
provenance.

## Unreleased

- Files' menus open inside Files, under the button or beside the finger, in
  its own look with lines a finger can hit; choosing a line no longer also
  taps what lies under it. Its buttons are the suite's grey pills, the actions
  button a circle with a vertical ellipsis, and the order a pill naming it.
  Move to Trash and Empty Trash ask in Files' own look and name the action.
  A finger lifts the file or place under it.
- A copy or move in Files that fails keeps its place in the band for a minute,
  saying why, then is filed in the notification history, as other failed
  transfers are. A long list of transfers scrolls in the open island.
  The setting to open inside Kadunce uses its name, Spread.
- Paused music leaves the band after three minutes and comes back when it
  plays again, so a player that stopped long ago, a phone's through KDE
  Connect among them, no longer holds an island.
- A drive or memory card plugged in that nothing has mounted gets an island for
  a minute: one tap mounts it and opens it in Files. Ignored or flicked away, it
  is filed in the notification history with Open in Files, and unplugging it
  takes that away.
- Ambient shows each kind of activity as its own island, side by side: media,
  a transfer, and a transfer's end waiting out its minute. They share the width
  by turns, the newest first and then the most urgent, give up names before
  anything else, keep their buttons at their end, and settle without overshoot
  as the room changes hands. What cannot fit folds into a counted bubble. Each
  island is flicked aside on its own, and an arrival's island offers Show in
  Files.
- A sideways flick sets the island aside, by finger or mouse: music until it
  plays again, a transfer until it ends. Dragged slowly, the island sheds its
  details down to play or pause and springs back if let go.
- Ambient holds the desktop's job service where no Notifications widget does,
  so KDE Connect and other applications report their transfers. A file that
  arrives in Downloads, or a transfer that fails, stays a minute in the island
  saying how it ended, then is filed quietly in the notification history.
- The open island's transfer rows keep their ring steady as progress moves.
- Files lists an Android phone with the drives, by cable and through KDE
  Connect, and opens it like one: at the storage it shares, with no eject, and
  with a plain word on what to allow when the phone refuses. Plasma's device
  pop-up opens a plugged-in phone in Files.
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
- Made Ambient clear, centred in its side of the panel and black when the
  panel is black. A tap opens an island in place with album art, the track's
  position, the other players, and each transfer's own actions.
- Made the launcher a 44 px touch square with a 20 px pearl dot centred in it,
  a little smaller than a status icon, since a filled disc weighs more.
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
