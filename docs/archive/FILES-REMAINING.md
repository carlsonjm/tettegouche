# Files remaining after accepted operations and compact UI

Accepted foundation: asynchronous local listing, tabs/history/breadcrumbs,
filter/sort/hidden files, default-app opening, mouse/keyboard/touch selection,
box selection, folder-copy drag/drop with edge scroll, copy/paste, create folder,
rename, clipboard cut/move, confirmed Trash and persistent last-item recovery.

Next cross-app priority is dock-safe Active bounds and the square launcher touch
target in PRODUCTION-READINESS.md. Files expansion follows that pass.

Remaining proposed batches (not implementation claims):

1. Transfer robustness: useful progress/cancel, deliberate conflict choices
   (currently refuse overwrite), large-copy and interrupted/unavailable-device
   tests. Preserve partial-success reporting and safe quit behavior.
2. Desktop integration: external app/file-manager drag/drop, Open With and
   properties. Existing default-app opening is already implemented.
3. Discovery: bounded asynchronous thumbnails/previews, recursive search and
   Recent. Current filter is for the listed directory, not global file search.
4. Storage lifecycle: removable mount/unmount/eject, stale/offline locations,
   optional network locations. Current sidebar lists local mounted places.
5. Release validation: keyboard/accessibility audit, large directories, live
   external changes, and stale Trash recovery records. Split view/full Trash
   browser are later power-user work, not blockers for current local browsing.

Keep new capabilities in related 2–3 feature batches; test without using real
user files as destructive fixtures. Do not confuse historical slice omissions
with current gaps: rename, move and Trash have since passed.
