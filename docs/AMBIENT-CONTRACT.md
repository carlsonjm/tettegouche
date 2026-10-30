# Ambient activity contract

Ambient shows what is happening now, such as media and transfers, in the
panel beside the launcher dot. Temperance handles notifications and passing
events. Beside them stands one door that is always there, the quick note's
island (§ Quick note). Its inputs are in [INPUT.md](INPUT.md).

The widget's setting "Show islands beside the launcher", off, leaves the
launcher's dot alone in the panel: Ambient shows nothing and takes no width.

While a slide from the launcher dot shows Search's doors in the band, the
islands fade and an open island closes; they return when it lets go
([INPUT.md](INPUT.md) § The dot).

## Admission and ownership

An item enters Ambient only while it has meaningful current state, is worth
keeping in view, comes from a source Ambient can identify, and has actions
Ambient can send truthfully to that source.

Current sources are:

- MPRIS media sessions;
- running or suspended jobs from Plasma's shared desktop-jobs model;
- Tettegouche's own KIO copies and moves, through the launcher's activity bridge;
- filesystem evidence for new direct children in the configured Downloads folder;
- drives plugged in that nothing has mounted, from Solid (§ Drives);
- a screen shared or recorded through Plasma's portal (§ Shared screen);
- windows raising Plasma's attention flag, from Plasma's window list
  (§ Waiting applications);
- a fact Split Rock's Core asks attention for, such as the drive filling up,
  from Core's bus interface where Split Rock is installed (§ Core);
- the quick note's island, while Gooseberry is installed, with the note pinned
  in Gooseberry beside its door (§ Quick note).

The quick note's island is the one island that stays without activity. It is a
launcher, not an activity: a door to the quick note, and to the pinned note
when there is one. Its source owner is Gooseberry, and it leaves when
Gooseberry is removed or the widget's setting turns it off.

Plasma's jobs model and window list come from Plasma's own libraries, which
change between releases, so a build reads them only on the Plasma it was built
for. On another, those two sources stay off, with a warning in the log, until a
rebuild; every other source runs as usual. A Plasma or build that names no
version counts as a match.

Static system status, completed work past its end's minute (§ Ends),
ordinary notifications and past activity leave Ambient. Ambient arranges the
islands and routes actions to their sources; the source keeps the operation,
and Ambient keeps no history of finished work.

## Lifecycle and truth

- An activity appears, updates in place, and leaves when its source does. When
  a source is replaced, its generation number rejects actions meant for the
  old one.
- Paused resumable media stays three minutes, then leaves until it plays
  again, a phone's through KDE Connect included. A lost job leaves, and a stopped one
  leaves or gives its place to its end (§ Ends). A hidden
  launcher may remain alive to finish and publish an operation.
- Source fields and actions override filesystem enrichment. Filesystem evidence
  merges only on exact destination and current file identity; there is no suffix
  guessing.
- Determinate progress, transferred bytes, ETA, completion, and controls appear
  only when the source supplies evidence. Unknown progress stays indeterminate.
- A lost source, a quiet file, a cancellation or a disappearance is never shown
  as a success.
- The person may set an item aside, which never stops or changes its source,
  except the quick note's island, which stays:
  media stays away until it starts playing again, a transfer until its source
  ends, its end then filed without its minute, and an end is filed at once.
  While carried or flicked, the island stays within Ambient's own bounds.

## Provider behavior

### MPRIS

Discovery takes an initial snapshot and then follows owner, property, and seek
events. A title, artist, album, artwork, duration or capability the player does
not give stays empty. Artwork is shown from a local file, the web, or an image the player
carries inline (`data:image/…`), which is how a player such as Elisa hands over
a cover embedded in the track; anything else leaves the player's icon in its
place. The player's icon is its installed application's icon, found by the
desktop entry the player names, by an application ID ending in that name (a
Flatpak's), by the window class the application declares, or by the player's
own name; a player none of these finds shows a generic player icon. The shown
position advances from the player's own position and rate, and stops on pause.
A control shows only while the player supports it, and its owner is checked
before it acts. A jump to a point names the
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
A destination on a network or user-space mount is never looked at on disk,
since its server can go away and a look there would hold the panel; such a
job shows from its reported progress alone. A job whose producer goes away
ends as a failure.

### Ends

A job's end earns a line when it brought something new, a file arriving in
Downloads, or failed; a cancelled job, or one writing elsewhere, ends quietly
because the person started it and saw it run. An end that earns a line takes
its job's place for a minute and says how it ended, an arrival with Show in
Files. Then it is filed as a notification in the freedesktop transfer
categories, `transfer.complete` or `transfer.error`, which the history keeps
and Temperance's ticker does not play. One used in Ambient is filed at once.
A copy or move in Files ends the same way when it fails, titled as incomplete
when it carried everything but files it could not read; one the person stops
or cancels ends quietly. Filesystem evidence alone never files anything.

### Drives

A drive Files lists, plugged in while Ambient runs, on removable or
hot-pluggable media and not mounted, waits in Ambient for a minute; so does a
memory card put in a reader. Drives already there at startup, built-in drives,
phones, and drives the system or the person mounts never wait, and one mounted
meanwhile leaves quietly. A tap on its island asks Files to open it, mounting it
first, and it leaves. Ignored, or set aside, it is filed as a notification in
the freedesktop `device.added` category with Open in Files, which the history
keeps and Temperance's ticker does not play. Unplugged, it leaves, and its
notice is closed.

### Shared screen

While a screen is shared or recorded, Plasma's portal shows a status notifier
item; Ambient follows it through the StatusNotifierWatcher as it comes, changes
and goes. The island shows a red dot, the portal's own line naming who receives
the screen, and Stop, which clicks the item's End. A tap elsewhere on it opens
nothing. It lasts while the share does and leaves nothing behind.

### Waiting applications

Ambient reads Plasma's window list, the one its task manager shows, in process.
A window raising Plasma's standard attention flag is an application waiting on
the person: Kadunce raises it for an application whose dialog waits while the
application is not in front, and an application may raise it for itself. The
list does not say which, so both show. The island shows the application's icon
and name and, where its process has exactly one window kept off the task bar,
that window's title, less the application's name, as the question; with none
or several, it shows the icon and name alone. A tap on the island, or on the
bubble holding it, asks Plasma to activate the window, which brings the
application and its dialog forward. It lasts while the flag does and leaves no
line and no history. With several waiting, the island shows the newest. A
window moving or restacking is not read.

### Core

Split Rock's Core watches the computer and decides, by its own fixed limits,
when a fact deserves the island: a drive that has crossed a mark or is filling
fast, never a fact merely restated. Ambient shows a fact only while Core says
it wants the island, and asks Core nothing on a timer: it reads Core's facts
when Core appears, the first question starting Core where Split Rock is
installed, and follows `FactChanged` after that. A Core that speaks another
version of its interface is left alone. The island shows the fact's icon, what
it is and how it stands ("Storage · 91% full") and, below, its detail and what
can be done ("45 GB free · Free up space"). A tap on the island, or on the
bubble holding it, asks Core to open the card that acts on it; Core opens it
and takes the fact off the island. Setting it aside tells Core it was
dismissed, and Core stays quiet about it until it gets worse. A fact about a
Windows program in Downloads, and no other, adds a "Don't tell me again" pill
after its words; a tap on the pill asks Core never to raise Windows programs
again, and a tap anywhere else on the island still opens the card.

A fact that asks a question, such as bringing back the last sign-in's apps or
an offer to open a set of apps at sign-in, is not answered by a tap on the
island: the tap, or the bubble holding it, opens the island in place on the
question, its detail and its answers as pills. The tap's own words come first,
then the choices Core lists beside it (`choices`, each an action and its
words, such as Always), then Not now, in Core's words where it gives them
(`dismissText`). A fact asks when Core lists choices or words for Not now, and
bringing back apps and an automation's offer always ask. Each answer is passed
to Core as Core names it, Not now as `not-now`, and closes the island; an
action the fact does not list is not passed. The words are Core's; Ambient
draws them as given. Core owns the fact and its history; Ambient keeps
neither. Without Split Rock there is no
Core island and nothing else changes.

### Layouts

Search's Layouts result opens the Layouts island in place, the way a Core
question does: grown up from the band's end over the desk, on a surface of its
own that is never a window Cards takes as a card, so it never becomes part of a
layout. It opens on the widget on Search's display, with its islands shown or
not; where they are not, it grows from the dot. Split Rock's Core keeps the
layouts; the island reads them from Core (`Layouts()`) and asks Core for every
change.

The island's title reads "Layouts · 2 saved". Each saved layout is a row: its
name, "Opens when you sign in" beneath where that is on, and its miniature, each
group a small card, 6 px corners, naming its front app, a Stack's cards fanned
5 px behind it, and the group's apps beneath; then an Open pill, 32 tall, the
first row's filled. A tap on a row off its pill shows its own "Open when I sign
in" switch (`SetLayoutAtSignIn`) and Remove (`RemoveLayout`). With none saved,
a line says how to make one. Below the rows are the pills Save what's open,
filled, and Close.

Save what's open turns the same island into the form: "Save this layout ·
what's open on Work", the workspace named as KWin names it, a name field,
then one row per group Core reads from Cards (`CurrentLayout()`), "Stack ·
Ghostty, Claude" or "Zen · On its own", each with Remove, which takes that
group out, and the switch "Open when I sign in", off; then Save and Not now.
Save needs a name and at least one group, and passes the groups left
(`SaveLayout`); a name already used replaces that layout. Open, Save and Not
now close the island, as do Close, Esc and a tap outside it.

When a layout's run ends with apps that didn't come, Core's island says so
once: "Mail didn't open", and beneath, "The rest of Coding is in place". A tap
takes it away and opens Layouts; setting it aside, or a minute, takes it away
and opens nothing. Core is told nothing of either.

Without Split Rock, or with a Core that has no `Layouts()`, there is no Layouts
island and nothing else changes.

### Quick note

While Gooseberry is installed with its Capture action, the test Search's Notes
door uses, the quick note's island stands in the band: a dot with a plus,
Lucide's plus on a faint disc of the style's ink. A tap on the dot, or on the
island off the pinned note, starts a quick note on Gooseberry's own card,
through its Capture action. Where Gooseberry has a note pinned, the note sits
beside the dot in the same island: a bead of the note's colour and its first
words, one line, elided where long. A tap there opens that note on Gooseberry's
card (`OpenNote`), or starts a new one where the note has gone. The island
opens no card of its own; Search's Notes takes the tap only where Gooseberry
cannot.

Ambient reads the pinned note from Gooseberry's quick-note interface on the
session bus, version 1, only while Gooseberry runs: it asks `Pinned` when
Gooseberry appears and follows `PinnedChanged` after that, and never starts
Gooseberry for it. A Gooseberry without `Pinned`, or one speaking another
version, shows the dot alone; so does Gooseberry not running. Gooseberry owns
the note and its pinning; Ambient keeps neither.

The window in use's notes stand last in the same island while it has any that
are not tucked away: Gooseberry's dot, an 18 px disc of the top note's colour
with a 1 px soft edge and the notes' shadow, the count in 11 px demibold where
there are several ("9+" past nine), in a 44 px target. It is ringed while the
notes are up over the window. A tap brings them up there, open, when they are
away or folded (`Show`), and puts them away when they are up (`Toggle`). The
window in use is the one Plasma's window list marks active, and the one before
stays while none is, as while the panel or the notes hold the keys. Ambient
reads the windows from Gooseberry's stuck-notes interface, version 1
(Gooseberry's `docs/DESKTOP.md` § Stuck notes on the bus), as it reads the
pinned note. While a widget shows the island it tells Gooseberry so
(`DrawFolded`), and folded notes leave no dot over their window; the island
brings them back.

The island is never set aside: a drag does not carry it and Delete leaves it.
It stands first in the group, before what comes and goes, and takes its turn
for room after every other island, so the pinned note is the first piece to go,
then the window's notes, and the dot the last. The widget's setting "Show the quick note island", on by
default, shows it while "Show islands beside the launcher" is on; off, the
island is gone, and folded notes show their dot over the window again. Without
Gooseberry there is no island.

### Tettegouche's own copies and moves

`FileBrowser` and KIO own each operation. The launcher publishes revisioned snapshots
of each copy or move, one for each change to its rows, and UUID-checked Cancel, Pause and Resume over its activity
D-Bus interface. A copy or move that failed stays in the snapshots for ten
seconds as a failed row, which the applet reports once as an end (§ Ends); a
hidden launcher waits a second after such a failure before it quits. The applet
checks the source's generation before sending an action.

### Incoming files

A nonblocking inotify descriptor observes the Downloads directory and its parent
for recovery. Direct writes, witnessed renames, atomic arrivals, preallocation,
and disappearance are filesystem evidence. Observed length is file size, not
bytes transferred. A row leaves after a set quiet time, without being shown as
complete.

Only ordinary local direct children are covered. There is no recursion, browser
scraping, notification parsing, or polling fallback. mmap writes and remote
filesystem changes may be missed. Overflow or watch invalidation clears uncertain
state and rearms without inventing missed work. A file already there is not shown
just because the applet started.

## The islands

Each kind of activity is its own island: media, transfers under way, ends
waiting out their minute (§ Ends), drives plugged in (§ Drives), a shared
screen (§ Shared screen), applications waiting (§ Waiting applications),
Core's facts (§ Core) and the quick note (§ Quick note). The islands sit side
by side in the order they arrived, the quick note's first, an end in its transfer's place, the group against the
launcher dot, or placed in the width the host hands Ambient as it asks
(§ Host settings). They are clear, so the panel shows through them. While
the panel prefers an opaque background, as Shuffle's band does while it is
black, they take the Plasma style's ground, on a dark style the band's own
black, `#141414`, and melt into it. Their words and glyphs are the
style's text colour, Ghost White on a dark style.
An island is 44 px tall in a 64 px band and shorter on a shorter panel. Each
control reaches the island's full height and, where the panel allows, 44 px
across.

The islands share the width by turns (`applet/IslandRoom.js`). Every island
keeps its first piece; then each takes one more piece per turn in its own
order, and stops at the first that does not fit. The newest island takes its
turn first for 2.4 s; after that the more urgent goes first: a waiting
application, a shared screen, a drive, a transfer's end, a transfer, media,
then a fact from Core, which never takes room from what is happening now,
then the quick note's island. Names, such as a player or where
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
| Drive | icon, size, Open, name |
| Shared screen | Stop, red dot, who receives it |
| Waiting application | icon, name, question |
| Core | icon, what it is and how it stands, Don't tell me again (Windows programs only), detail and what can be done |
| Quick note | dot with a plus, pinned note (its bead and first words) |

Beside a neighbour, an island reads what it is, then its words, then its
buttons last. Media alone keeps its controls at its centre, with art and title
on one side and the time and player on the other, the sides alike when both
hold something. Media shows one player at a time: the one that started playing
last, or one you picked in the open island, where the others wait. Several
transfers show their count, and several ends theirs.

A tap away from the controls opens the island in place. It opens on a clear
surface over the whole display, the island growing out of its place into a
card in the style's ground, black on a dark style, and a tap outside the card or Esc closes it back into the band. The
card holds the media's art, position, previous, play or pause, next, the other
players, and a button that brings the player forward when the player can be
raised. For transfers, ended ones included, it lists each one with its own
progress, Pause or Resume, Cancel and Show in Files, as its source supports.

The panel decides the width. On an ordinary panel the widget is the launcher
dot and its islands whole, so whatever stands next on the panel follows
straight after them, with any spare room beyond it; with nothing going on it
is the dot alone. An island arriving opens its room before it shows, and one
leaving closes its room as it goes. Where the panel has less, it gives the
widget less, down to each island's first piece, and the islands share what it
gives. Where a host sets `ambientAlign`, Ambient instead measures from the
launcher dot to the next visible widget on its right in the same panel,
ignoring spacers, and places the islands in that width; with no widget there,
it keeps only the island's core. Shuffle's band hands Ambient the whole of its
side of the dock, so the islands never plan for room they will not get. It never pushes a centred dock off
the display's centre. On a vertical panel only the launcher dot shows.

### Host settings

Six settings let a host lay the widget out around something of its own, such
as a centred dock with a widget on each side. They are written by the host,
not offered in the widget's settings, and their defaults are the widget as it
is on an ordinary panel.

| Setting | Values | Default |
| --- | --- | --- |
| `launcherPlacement` | `start`, the dot before the islands; `end`, after them; `none`, no dot, for a widget that shows islands alone | `start` |
| `ambientShows` | `all`; `media`, the media island alone; `others`, every island but media, the quick note's among them | `all` |
| `ambientAlign` | `center`, `start` or `end` of the width the islands have | unset: against the dot, the widget as wide as its islands |
| `islandOutline` | on, each island a faint pill; off, words and glyphs on the panel alone | on |
| `islandSpacing` | the room between islands, 4 to 32 px, a value outside held to the nearer end; without an outline, also the room the group keeps from the end it is set against | unset: 8 px outlined, 24 px without |
| `pearlLook` | `pearl`, the Tette Dot; `magnifier`, a magnifying-glass mark in the dot's Ghost White, at its size and place, with nothing drawn behind or round it | `pearl` |

With the dot at the end, the slide that brings the doors runs left from it,
and the doors line up leftward from the dot. A widget with no dot has
no shortcut, takes no keyboard focus and opens nothing when Plasma's launcher
key is pressed; its islands open as any island does. While the panel prefers
an opaque background, an island takes the style's ground whatever
`islandOutline` says. A host that places two widgets, one showing media and one
the others, shows every island exactly once.

Without an outline, only room parts one island from the next: they stand
24 px apart, three of Kirigami's large spacing, and the group keeps the same
24 px from the end of its width it is set against, where the host places
something of its own, such as the dock; centred, it keeps none.
`islandSpacing`, where a host writes it, takes the place of both. Each island's
pieces then start and end at its own edges. Album art, a waiting application's
icon and a drive's take an application's place in Shuffle's dock, whose icon
square is five sevenths of the band's height: art as large as an
application's artwork in that square, 42 of its 48, which is 40 px in a 64 px
band, a square with softened corners, 0.15 of its side; an icon
drawn at the whole square, as the dock draws one. The words beside them begin
8 px away. Outlined, art keeps to its pill, 68% of the island's height with
10 px corners, and the icons are 24 px, each a little less on a short panel.

## Interaction and safety

- Touch, mouse and keyboard reach the same actions, as far as the source
  supports them; [INPUT.md](INPUT.md) lists them.
- An island's actions act only on its own source, and one the source does not
  support is not shown.
- Closing the open island returns it to the band; it never opens search.
- With nothing to show, Ambient leaves the panel clean; the quick note's island
  is a door, not activity, and keeps only its own width.
- Do not add a daemon, polling loop, persistent history, replacement task
  manager, notification-derived progress, or an activity owner shared with
  other applications.
