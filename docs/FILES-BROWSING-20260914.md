# Explore files — first browsing slice

First candidate 99efbfe was installed and REJECTED: Meta stalled, Files opened
slowly and the expansion canceled. Corrective candidate 3de1df6 was installed;
J passed startup and Files opening. Pull gesture failed; chrome needed refinement.
7ab043a was installed; J requested independent label/tab hover and clearer crumbs.
d361f16 was installed and J passed the first slice. Final copy-only correction:
“Explore files” in compact entry and expanded header. Final binary d405e49
is built and packaged; installed d361f16 differs only in that capitalization.
Accepted slice frozen locally, not pushed. Base6596031; accepted Kadunce
8029a94 unchanged. J approved real browsing first, then expand file operations.
Visual reference inspected: J's Desktop attachment, Dark File Browser Over Pixel-Art Wallpaper.png.
Preserve its minimal Places/content layout at the accepted Active size, not its
old compact dimensions. Header matches Apps: Explore files / Close drawer / Sort.
Tabs and path navigation occupy separate rows within the content column.

## Implemented boundary

- Top All Files tap or downward pull opens the shared expanded guest presentation.
  Apps remains the bottom upward drawer. Only one drawer is open at a time.
- KCoreDirLister performs asynchronous local directory listing with no shell.
  Each navigation replaces/disconnects the prior lister; stale replies cannot
  overwrite the new tab. Live directory additions/deletions/refresh update entries.
- Home, standard user folders and already-mounted removable paths; no invented
  Recent list or mounting UI. Absolute path entry, breadcrumbs, back/forward,
  refresh, name ascending/descending, newest, largest and hidden files.
- Search is a case-insensitive filename filter in the current directory, NOT a
  recursive indexed search. Enter cannot launch hidden catalogue/search results.
- Tabs: add, close except last, select, Ctrl+T/W/Tab; bounded20 open tabs.
  History, scroll and selected-file state live per tab during the process.
  Closing only the drawer preserves them. Across launcher process dismissal,
  QSettings restores absolute local tab paths/current tab, not history/selection.
  Missing/offline folders report asynchronously on opening, not via startup stat.
- Directories open on tap. Files highlight only; explicit preview-slice footer.
  No file launch, MIME actions, mutations, drag/drop, network browsing, thumbnails,
  multi-select or mount/unmount yet. Icons use the installed KDE icon theme.

## Verification and handoff

Private-bus FileBrowserTest uses temporary files/settings: listing, sorting,
filter, tabs, retained scroll, rapid history transitions, hidden files and missing
folder errors. QML checks entry/Active/compact/Apps switching, no hidden app launch,
and existing controls. Software-rendered mock screenshot inspected at
/tmp/tette-files-preview.png: layout verified; icon theme isn't loaded by that
test host, so actual themed icons and touch feel need J's desktop acceptance.
No live compositor toggles or Kadunce changes in the corrective pass.

## Startup failure correction

Logs did not establish a sole cause. Code inspection found synchronous
QStorageInfo::mountedVolumes() inside the Places getter, invoked by an eagerly
constructed hidden pane and re-invoked on every shared changed notification.
Saved-folder existence checks also touched storage during launcher construction.
Both violate the no-blocking-storage-on-Meta boundary. Removed those probes:
Places is cached with its own notify signal and reads Linux mountinfo metadata
only when Files is requested. No statvfs/readiness probing; unavailable mounts
can remain listed and fail through the asynchronous directory lister.
FilesPane loads lazily/asynchronously; guest expansion is requested before
directory opening is queued. No caching/prewarming of file contents added.

The original separate mock-UI/native-backend tests missed their interaction.
Corrective checks now render the real FilesPane with FileBrowser, temporary
folders/settings and a UI heartbeat (no >=500ms stalls in this scoped run).
Mount parsing covers escaped names and deduplication; Places must not change
during directory operations. Rebuilt native/UI test passed, drawer controls
passed. These are not a substitute for J's real-device startup check.

## Gesture/chrome refinement

J confirmed startup/opening fixed. Downward pull now retains the active drag's
distance for release, rather than reading release-time handler translation.
Touchscreen pull test passes alongside existing drawer controls. Files entry
matches Apps' 220ms label-hover/100ms color feedback and brightening/widening tab.
Shared Close drawer keeps its touch area but shows fill/outline only on hover or
press. Breadcrumbs are plain separated labels; tabs use a selected underline;
navigation buttons retain 42px height with hover/press backgrounds. No backend
or guest ownership changes. Software preview inspected; real theme remains J's
acceptance surface. Startup-pass and stable App-only binaries both preserved.

Latest refinement: compact top/bottom label edges are mirrored at 12px from the
sheet. Label hover is independent of grab-tab hover on both sides. Top label and
expanded header now say Explore Files. Navigation uses full back/forward arrows
and a divider before the plain chevron-separated crumbs. Crumb width is measured
from text (minimum42px), independent of the theme's button minimum. Pull release
uses persistent translation delta; touch test includes motion after activation.
QML tests cover both edge distances and separate hover colors, pull, Apps/Files
open/close, and existing controls. No storage or Kadunce changes in this pass.

Installer ../../install-tette-files-20260914.sh; one launcher binary. Rollback is
the J-passed compact hierarchy b681ec7. Restart Tette after install.

J checks: top tap/pull opens above dock; navigate folders/back/crumbs; open another
tab and switch back; filter/sort; close Files and open Apps; normal compact search.
Next after acceptance: keyboard/list accessibility depth and native MIME/open
actions, then explicit safe multi-file operations/drag-and-drop. Recursive search,
thumbnail budgets, device lifecycle and split view need their own scoped checks.
