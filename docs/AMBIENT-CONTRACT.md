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

Static system status, completed work past its end's minute (§ Ends),
ordinary notifications, and historical activity do not remain in Ambient. Ambient owns composition and routing; it does
not own the source operation or retain a completion history.

## Lifecycle and truth

- An activity appears, updates in place, and leaves with its authoritative
  source. Owner generations reject stale actions after source replacement.
- Paused resumable media remains visible. A lost job leaves, and a stopped one
  leaves or gives its place to its end (§ Ends). A hidden
  Tette launcher may remain alive to finish and publish an operation.
- Source fields and actions override filesystem enrichment. Filesystem evidence
  merges only on exact destination and current file identity; there is no suffix
  guessing.
- Determinate progress, transferred bytes, ETA, completion, and controls appear
  only when the source supplies evidence. Unknown progress stays indeterminate.
- Source loss, quiet filesystem state, cancellation, and disappearance must not
  be presented as successful completion.
- The person may set an item aside, which never stops or changes its source:
  media stays away until it starts playing again, a transfer until its source
  ends, its end then filed without its minute, and an end is filed at once.
  While carried or flicked, the island stays within Ambient's own bounds.

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

Tettegouche shares Plasma's jobs model in process. Where Plasma's Notifications
widget holds the job-view service, Ambient reads that model and never competes
for the service; where nothing holds it, Ambient holds it, so applications'
transfers still report, and closes each job once it has ended. Running and
suspended jobs expose only the identity, progress, counts, descriptions, and
controls supplied by that model. Zero percent without a total is unknown
progress. A job's file is its destination when that is a file; a destination
folder counts only with a description value naming a regular file directly
inside it, as KDE Connect reports one. Descriptions' labels are never read.

### Ends

A job's end earns a line when it brought something new, a file arriving in
Downloads, or failed; a cancelled job, or one writing elsewhere, ends quietly
because the person started it and saw it run. An end that earns a line takes
its job's place for a minute and says how it ended, an arrival with Show in
Files. Then it is filed as a notification in the freedesktop transfer
categories, `transfer.complete` or `transfer.error`, which the history keeps
and Temperance's ticker does not play. One used in Ambient is filed at once.
Filesystem evidence alone never files anything.

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

## The islands

Each kind of activity is its own island: media, transfers under way, and ends
waiting out their minute (§ Ends). The islands sit side by side in the order
they arrived, an end in its transfer's place, the group centred in the width
the panel hands Ambient. They are clear, so the panel shows through them. While
the panel prefers an opaque background, as Shuffle's band does while it is
black, they take the suite's black, `#141414`, the band's own, and melt into it.
An island is 44 px tall in a 64 px band and shorter on a shorter panel. Each
control reaches the island's full height and, where the panel allows, 44 px
across.

The islands share the width by turns (`applet/IslandRoom.js`). Every island
keeps its first piece; then each takes one more piece per turn in its own
order, and stops at the first that does not fit. The newest island takes its
turn first for 2.4 s; after that the more urgent goes first, a transfer's end
before a transfer and a transfer before media. Names, such as a player or where
a transfer comes from, wait until every island has had the rest, so they are
the first to go; a song's title and artist are not names. What cannot keep even
its first piece folds into a round bubble after the islands, which counts what
it holds. As the width changes hands, islands and pieces grow and shrink
together and settle without overshoot.

| Island | Its pieces, the last to go first |
| --- | --- |
| Media | play or pause, title (the artist rides with it), art, previous and next, time, length, player |
| Transfer | progress ring (the percentage rides inside it), name, size, source, Cancel |
| End | how it ended, Show in Files, name, what happened |

Beside a neighbour, an island reads what it is, then its words, then its
buttons last. Media alone keeps its controls at its centre, with art and title
on one side and the time and player on the other, the sides alike when both
hold something. Media shows one player at a time: the one that started playing
last, or one you picked in the open island, where the others wait. Several
transfers show their count, and several ends theirs.

A tap away from the controls opens the island in place. It opens on a clear
surface over the whole display, the island growing out of its place into a
black card, and a tap outside the card or Esc closes it back into the band. The
card holds the media's art, position, previous, play or pause, next, the other
players, and a button that brings the player forward when the player can be
raised. For transfers, ended ones included, it lists each one with its own
progress, Pause or Resume, Cancel and Show in Files, as its source supports.

The panel decides the width. On an ordinary panel Ambient measures from the
launcher dot to the next visible widget on its right in the same panel,
ignoring spacers; with no widget there, it keeps only the island's core.
Shuffle's band instead hands Ambient the whole of its side of the dock, so the
islands never plan for room they will not get. It never pushes a centred dock off
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
