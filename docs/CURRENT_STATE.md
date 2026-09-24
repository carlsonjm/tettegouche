# Current state

Tettegouche 0.2.0 builds as a native KDE Plasma applet plus an on-demand Wayland
launcher. The `main` branch contains the launcher, application and file drawers,
Kadunce integration, related-setting context, and the live Ambient activity
surface. There is no separate daemon.

## Launcher and integration

- Panel or Meta activation toggles one single-instance launcher process.
- A whole search can be typed on the on-screen keyboard: the keys stack above
  the launcher, and a touch on them never closes it.
- Standalone mode uses a centered responsive sheet. A compatible Kadunce session
  may host it as a temporary Spread guest and expand Apps or Files into the
  negotiated Active presentation.
- Workspace-context schema version 1 and launcher-guest protocol 3 are the only
  supported Kadunce contracts. Missing or mismatched integration falls back to
  standalone behavior.
- Open applications activate their exact Kadunce window when available. New
  application launches use Plasma's normal application job and may hold the
  guest until the matching window appears.

## Search and applications

- Compact search combines allowlisted local KRunner sources: applications,
  indexed filenames/recent documents, KDE settings, calculator, and unit
  conversion.
- Ranking uses confidence before provider preference and pins an interacted
  selection by destination identity.
- Everyday scope suppresses quiet folders, repositories, and technical/internal
  files. All files relaxes Tettegouche's scope filters without changing KDE's
  index.
- Browser search occurs only after explicit submission when no eligible local
  result exists.
- Browse everything is an alphabetical visible-application catalogue with no
  behavioral ranking.

## Files

- Explore files provides asynchronous local listing, Places, up to 20 tabs,
  per-tab history and scroll, breadcrumbs, path entry, refresh, filename filter,
  sort modes, and hidden-file display.
- Mouse, touch, and keyboard support selection, ranges, box selection, opening,
  copy/paste, cut/move, folder creation, rename, internal drag-copy, confirmed
  Trash, and recovery of the last Tette-recorded trashed item.
- File operations are asynchronous KIO jobs. They refuse silent overwrite,
  report partial failure, and keep the process alive when the launcher surface
  closes during work.

## Ambient

- The right-side panel strip shows live MPRIS media, Plasma desktop jobs,
  Tette-owned file operations, and observed direct-child arrivals in Downloads.
- Each row is driven by an authoritative source. Actions are capability-checked
  and generation-checked. Source loss removes the row without claiming success.
- Responsive composition preserves each activity's useful core before revealing
  title, artist, filename, byte count, duration, or other optional context.
- `TETTE_AMBIENT_FIXTURE=transfer-media` remains a test/demo override; normal
  startup uses live providers and is empty when no qualifying activity exists.

## Related settings

Read-only context is available for supported Bluetooth, sound, networking,
display, power, printer, KDE Connect, removable-storage, default-application,
and Night Light settings. Child rows open the parent settings page. They do not
pair, connect, mount, switch outputs, manage jobs, or change power state.

## Known limits

- Files is local-first: there is no recursive search, thumbnail/preview budget,
  Open With or properties surface, external drag/drop, network-location workflow,
  mount lifecycle UI, split view, full Trash browser, or general undo.
- File collisions stop rather than presenting overwrite/merge choices. Recovery
  covers one Tette-recorded Trash item at a time and may become stale after
  external Trash changes.
- Incoming-file observation covers ordinary direct children of Downloads. It
  cannot prove completion from quiet time, infer browser controls, or guarantee
  mmap and remote-filesystem changes.
- Search cannot rank candidates KDE never retrieves. Browser new-tab behavior
  outside verified Firefox-family handlers follows the desktop URL handler.
- Most related-setting providers are per-launcher snapshots; Bluetooth alone is
  continuously event-driven.
- Drawer expansion has an accepted tablet/Active treatment; there is no distinct
  monitor-specific expanded-layout contract.
- A reported Ghostty one-pixel bottom line can trigger the flat dock; ownership
  and cause remain unconfirmed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and
[NEXT-ROADMAP.md](NEXT-ROADMAP.md) for planned work.
