# Ambient activity contract

Ambient Tette answers what matters now. It presents ongoing media and transfer
state in its panel strip beside the launcher dot, while Temperance remains
responsible for notifications and transient events. Its inputs are in
[INPUT.md](INPUT.md).

## Admission and ownership

An item may enter Ambient only while it has meaningful current state, continued
presence is useful, a source owner is identifiable, and available actions can be
routed truthfully to that owner.

Current sources are:

- MPRIS media sessions;
- running or suspended jobs from Plasma's shared desktop-jobs model;
- Tette-owned KIO copy/move operations through the launcher's activity bridge;
- filesystem evidence for new direct children in the configured Downloads folder.

Static system status, completed work, ordinary notifications, and historical
activity do not remain in Ambient. Ambient owns composition and routing; it does
not own the source operation or retain a completion history.

## Lifecycle and truth

- An activity appears, updates in place, and leaves with its authoritative
  source. Owner generations reject stale actions after source replacement.
- Paused resumable media remains visible. Lost/stopped jobs leave. A hidden
  Tette launcher may remain alive to finish and publish an operation.
- Source fields and actions override filesystem enrichment. Filesystem evidence
  merges only on exact destination and current file identity; there is no suffix
  guessing.
- Determinate progress, transferred bytes, ETA, completion, and controls appear
  only when the source supplies evidence. Unknown progress stays indeterminate.
- Source loss, quiet filesystem state, cancellation, and disappearance must not
  be presented as successful completion.

## Provider behavior

### MPRIS

Discovery takes an initial snapshot and then follows owner, property, and seek
events. Missing title, artist, album, artwork, duration, or capabilities remain
absent. Artwork is shown only from a local file or the web. The presentation
clock advances from source position/rate samples and freezes on pause. Controls
require current capabilities and owner validation. A jump to a point names the
track where the player gives one, so a late request cannot move the next track,
and stays inside the track's length. Bringing a player forward needs the
player's own permission to be raised.

### Plasma desktop jobs

Tettegouche consumes Plasma's shared jobs model in process; it never registers a
competing job-view server. Running and suspended jobs expose only the identity,
progress, counts, descriptions, and controls supplied by that model. Zero
percent without a total is unknown progress.

### Tette operations

`FileBrowser` and KIO keep ownership. The launcher publishes revisioned snapshots
of each copy or move and UUID-checked Cancel, Pause and Resume over its activity
D-Bus interface. The applet validates
the source owner generation before dispatching an action.

### Incoming files

A nonblocking inotify descriptor observes the Downloads directory and its parent
for recovery. Direct writes, witnessed renames, atomic arrivals, preallocation,
and disappearance are filesystem evidence. Observed length is file size, not
bytes transferred. Rows retire after bounded quiet observation without claiming
completion.

Only ordinary local direct children are covered. There is no recursion, browser
scraping, notification parsing, or polling fallback. mmap writes and remote
filesystem changes may be missed. Overflow or watch invalidation clears uncertain
state and rearms without inventing missed work. Existing files are not admitted
merely because the applet starts.

## The island

Ambient is one island centred in the width its panel hands it. It is clear, so
the panel shows through it. While the panel prefers an opaque background, as
Shuffle's band does while it is black, the island takes the suite's black,
`#141414`, the band's own, and melts into it. It is 44 px tall in a 64 px band
and shorter on a shorter panel. Each control reaches the island's full height
and, where the panel allows, 44 px across.

Media and transfers each take one place. The first kind to arrive keeps the
island; the next waits in a round bubble beside it, which shows a count when
it holds more than one activity. When the island's own kind ends, the next
takes the island.

Media shows one player at a time: the one that started playing last, or one
you picked in the open island, where the others wait. Music alone keeps
its controls at the island's centre, with art and title on one side and the
time and player on the other. Width reveals information, not capability: the
words go first, then previous and next, and play or pause stays. A single
transfer shows its reported progress, name, detail, percentage and Cancel;
several show their count.

A tap away from the controls opens the island in place. It opens on a clear
surface over the whole display, the island growing out of its place into a
black card, and a tap outside the card or Esc closes it back into the band. The
card holds the media's art, position, back and forward 10 s, previous, play or
pause, next, the other players, and a button that brings the player forward
when the player can be raised. For transfers it lists each one with its own
progress, Pause or Resume, Cancel and Show in Files, as its source supports.

The panel decides the width. On an ordinary panel Ambient measures from the
launcher dot to the next visible widget on its right in the same panel,
ignoring spacers; with no widget there, it keeps only the island's core.
Shuffle's band instead hands Ambient the whole of its side of the dock, so the
island never plans for room it will not get. It never pushes a centred dock off
the display's centre. On a vertical panel only the launcher dot shows.

## Interaction and safety

- Touch, mouse, and keyboard must reach equivalent source-supported actions;
  [INPUT.md](INPUT.md) lists them.
- The island's actions affect only the identified source and disappear when
  unsupported.
- Closing the open island returns it to the band; it never opens search.
- Empty Ambient leaves clean panel space.
- Do not add a daemon, polling loop, persistent history, replacement task
  manager, notification-derived progress, or cross-product activity owner.
