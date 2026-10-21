# Files contract

How Files behaves, and the rules any change to it has to keep. Its inputs are
in [INPUT.md](INPUT.md).

## State and navigation

- `FileBrowser` owns listing, tabs, path history, selection, focus, clipboard
  interpretation, and file operations. `FilesPane.qml` renders that state.
- `KCoreDirLister` performs asynchronous listing. Navigation disconnects
  the previous lister, and generation/state checks prevent stale replies from
  replacing a newer location.
- A folder arrives in batches, in no order, and is shown once it is whole,
  sorted once, so nothing shown moves. One slow to list, a phone's or a
  share's, shows what it has after half a second and fills in once a second,
  or less often while filling in takes long. A listed file's type comes from
  its name; only a name that says nothing has the file's start read.
- A place is a local folder, Recent (`recentlyused:/`), Trash (`trash:/`) or a
  search of a folder and everything inside it (`filenamesearch:`). Items in
  Recent and a search are known by the local file they stand for, and every
  action applies to that file. Nothing is created or pasted into Recent, Trash
  or a search, and Recent and a search are listed afresh, since KDE watches
  only folders.
- Files tells KDE's activity service each file and folder it opens, as Dolphin
  does, so they come back in Recent here and across Plasma; Plasma's privacy
  setting decides whether they are kept.
- Recent is KDE's record for the current activity, newest first. KDE's first
  answer can skip the file after one that no longer exists, so Files asks twice.
- A search is explicit, runs KDE's filename search, which walks folders itself
  and needs no file index, and matches names only, the text taken literally.
  Hidden files are searched only while shown. A search from a search replaces
  it, so Back returns to the folder.
- The places are KDE's own list (`user-places.xbel`, read and written by
  `PlaceBook`), shared with Dolphin and every Open dialog: a place added,
  renamed, hidden or moved in Files is the same there, and the other way round.
  Recent always comes first. Only local folders and Trash are places in Files;
  network and search places are left to Dolphin. Other media mounted under
  `/run/media`, `/media` or `/mnt` are found from mount metadata, read without
  `statvfs` or readiness probing.
- Drives follow the places, built-in first: those KDE's file dialogs and Dolphin
  list, by KDE's own rule read from Solid, less any hidden in Dolphin's places.
  They follow drives coming, going, mounting and unmounting. A mounted drive's
  free space is read off the GUI thread, at most every half minute; network
  mounts are never read. Solid is first asked when Files opens, never at
  launcher startup. KDE's places model is not used:
  it answers a failed lookup of its own with a widget message box, which aborts
  the launcher.
- A drive not mounted is mounted by Solid when opened. A plugged-in drive, once
  mounted, can be ejected: unmounted and powered off where the system can, or an
  optical disc ejected. A file action Files runs inside it holds the eject until
  the last one finishes. A drive that unmounts or leaves takes every tab showing
  or searching it Home.
- An Android phone is listed with the plugged-in drives: by cable while it
  shares its files, and through KDE Connect while it is paired, in reach and
  sharing them. One by cable opens through kio-fuse, which shows KDE's address
  for it as a folder; one through KDE Connect opens at the storage it shares,
  inside the folder KDE Connect mounts it on with sshfs, and that mount is not
  listed again as a network share. A phone has no eject: unplugging it or
  taking it out of reach takes every tab showing it Home. A phone that refuses
  says what to allow on it, and a missing kio-fuse or sshfs is named. KDE
  Connect is asked only while it runs, and never waited on.
- Tabs are bounded at 20. Path, history, scroll, sort, filter, hidden state, and
  selection are local to the applicable process/tab state. Saved tab folders,
  Recent and Trash may persist, a search as its folder, but history and
  selection do not.
- Filename filtering is case-insensitive within what is shown. It must not route
  Enter to hidden application results.

## Selection and opening

- Every selection, opening and file-action input is listed in
  [INPUT.md](INPUT.md).
- A touch is handled once: synthesized mouse events never repeat a tap or hold.
- Mouse box selection validates intersected items against the visible listing.
  Modifier behavior is computed from the selection captured at press.
- Files open through `KIO::OpenUrlJob` with executable prompts disabled. Native
  associations choose the application. URLs are data, never shell commands.
- Open With launches the chosen application through
  `KIO::ApplicationLauncherJob`, and "Always use it" sets KDE's default for the
  file's kind through `KApplicationTrader`. A file no application claims offers
  Open With instead of failing.

## Answering as the file manager

- Tettegouche offers KDE a folder handler, `io.github.carlsonjm.Tettegouche.Files.desktop`,
  which takes every KIO address, and `org.freedesktop.FileManager1`. Installing
  Tettegouche switches on neither: the handler ranks below Dolphin, and the D-Bus
  service file is installed aside under `share/tettegouche`. Files is the file
  manager once it is KDE's default for folders and that file is placed where
  D-Bus looks for services.
- A local folder opens in Files, the first in the tab shown and each other in a
  tab of its own; Recent opens Files' Recent. Files asked to be shown open chosen
  in their folder, less any outside the first one's; asked for Properties, the
  first one's open. Trash opens Files' own Trash place. A plugged-in phone's
  address opens it as its row does. An address Files does not browse, such as
  a network share, goes on to Dolphin, and Files says so when Dolphin is
  absent.
- An open Dolphin window holds `org.freedesktop.FileManager1` and answers "Show
  in folder" while it runs.

## Seeing files

- Photos, videos, PDFs and documents show KDE's thumbnail in place of their
  icon, from the thumbnail cache KDE shares with Dolphin; sound, text, fonts and
  folders keep their icons. Word and Excel files have no KDE thumbnailer.
- At most four thumbnails are made at once and the rest wait in order. A tile
  that leaves the screen or a folder that changes cancels its request, and
  KDE's own file size limits apply. A thumbnail is asked for at the display's
  own pixel size, in KDE's 128, 256 and 512 pixel steps.
- Properties shows at once what the listing knows. A folder's total size is
  counted by KIO in the background; a photo's, song's or video's own details
  are read by KDE's metadata readers off the GUI thread. Closing Properties
  drops whatever is still on its way.

## Mutations

- Copy, move, folder creation, rename, Trash, recovery, and internal folder drops
  use asynchronous KIO jobs. They run side by side, each with its own identity,
  reported progress, and the Pause and Cancel its job supports; no other action
  waits on one.
- Copy and ordinary internal drag preserve originals. Paste honors an explicit
  KDE cut marker and then moves. A successful move clears only the unchanged,
  matching cut clipboard.
- Internal drops validate listed sources and destination, deduplicate paths, and
  reject self/descendant folder copies.
- Files carried out to another application are offered as a copy only, as the
  addresses of items still listed, and are exported to KDE's document portal so
  a sandboxed application can read them. The process stays alive until the
  other application takes or refuses them.
- A drop from another application is always a copy, whatever the other side
  offers, into the folder shown or a folder listed in it. Only local files and
  web addresses are accepted; a file already in that folder, or a folder
  dropped into itself or its own descendant, is left alone. Name clashes ask as
  a paste does.
- Folder and rename inputs reject empty names, dot/dotdot, slash, and NUL. A
  captured target check prevents a changed selection from renaming another item.
- No job receives an overwrite flag. A name already taken asks you, one
  question at a time: Replace, Skip, Keep both under KDE's suggested name, or
  Stop, with a choice for the rest; a folder merges instead of being replaced.
  Nothing is replaced without Replace. In a copy or move of several, a file
  that cannot be read is skipped and the rest go on; the job ends saying what
  was left behind, to Files and to Ambient. Any other error, or an unreadable
  file alone, stops the job with its message; items already done stay, and
  the job says it finished only in part.
- Permanent deletion happens only in Trash, and only after a confirmation:
  Empty Trash, from the folder's menu, giving the count and size, which also
  forgets the restore records; or Delete for good on items chosen in the Trash
  place. Restore there puts the chosen items back where they came from through
  KIO's own restore.
- Compress and Extract are Ark's own batch jobs, which Plasma tracks, so Ambient
  shows them. Files starts them and owns none of their progress.
- Trash requires confirmation and has no permanent-delete fallback. Restore
  last trashed item covers only what Files itself sent to Trash, the latest
  first, one item at a time. Each record persists the item's place in Trash
  with where it came from and when it went; restoring refuses overwrite and
  keeps the record after failure. Before restoring, Files asks Trash what it
  holds there; when Trash no longer holds the item, or holds another item there, from
  elsewhere or trashed at another time, because Trash changed elsewhere, the
  record is dropped so the one behind it can be restored.

## Files' own window

- Pop out opens Files in an ordinary window in the same process, starting with
  the tabs, folder and view Files in Search has, and Search closes. Each window
  has a `FileBrowser` of its own after that, so Pop out again opens another
  window, as many as are asked for. Only Files in Search remembers its tabs
  for the next start. A window opens at the size Search has as a card inside
  Kadunce's Spread, or at Search's own size elsewhere, and is resized and
  moved as any window is.
- The windows' application identity is `io.github.carlsonjm.Tettegouche.Files`,
  Files' own entry, so the dock and Plasma's window list name them Files, and
  Kadunce takes each as a card rather than as the launcher's surface. Inside
  Spread a window is awaited as a launch from Search is and takes Search's
  card.
- Files in Search opens Files in Search, whatever windows are open. While a
  window is open, `Meta+E`, a folder or file another application asks to show,
  and a drive reach the window last used instead, brought forward and back
  from minimized. A question a copy asks comes back to the Files that started
  the copy.
- Each window's copies and moves are told to Ambient with Search's. A window
  closed during a copy is kept, hidden, until the copy finishes, and windows
  closed are used again for the next Pop out.

## Lifecycle and activity

- Closing or handing off hides the launcher and releases its Kadunce guest
  immediately. An outstanding job defers process exit until it finishes, as
  an open Files window does until it closes. A job that meets a name already
  taken while the launcher is closed reopens it on Files to ask.
- Reopening cancels the deferred quit and shows the current state of each
  operation, including errors that arrived while it was closed.
- The launcher exports a revisioned snapshot of its copies and moves, and
  UUID-checked Cancel, Pause and Resume, on `/Activities`, interface
  `io.github.carlsonjm.Tettegouche.Activities1`.
- Ambient may show KIO progress and the Cancel its source supports. Showing a
  job does not make Ambient its owner, and Ambient checks the generation before
  acting on it.
- If the process is killed mid-job, a partly written destination may be left
  behind. Navigation is independent of a running job's destination.

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

There is no content search, network location browsing, split view, or general
undo. An iPhone is not verified.
