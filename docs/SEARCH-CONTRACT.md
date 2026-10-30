# Search contract

Search shows destinations a person recognizes, not whatever happens to contain
the typed letters. Every ranking rule is general, tested against unrelated
examples rather than tuned to one query. Its inputs are in [INPUT.md](INPUT.md).

## First screen

Search's modes run along its top on every screen, one row above the field: the
dot for this first screen, then Apps and Files, then Notes where Gooseberry is
installed, and Helpers where Split Rock's Core lists them. The grey pill marks
the mode shown, and a tap moves straight to another; the dot comes back here
with what was typed. The window's own buttons end that row: Expand while Apps,
Files or Notes is open, Pop out in Files and Notes, and Close, last; at rest,
Close alone. The field is the same on every screen: a pill
44 tall on the row's own edges, the dot's pill starting where it starts and
Close ending where it ends, 16 below the row, with 24 between everything and
the sheet's edge, so only what is under it changes. Every search is that
field, Files' own window's too: the search glyph 16 in, the words 12 past it
at the size of what is typed, reading Just type on the first screen and
Find an app, Find a file or Find a note in a mode. Before anything is typed,
what was used lately is under it in two labelled sections, each newest first:
Recent apps, a row of eight icons with their whole names, and Recent files,
eight cards in two rows of four, each with its picture or its kind's icon,
its name, its folder and when it was used. See all at a section's end opens
Apps or Files. A narrow sheet shows fewer applications and fewer columns of
files rather than smaller ones. Sizes and spacing follow Kadunce's
`docs/ITASCA-VISUAL-LANGUAGE.md`.

How tall Search rests depends on which sections are on: with neither, the
sheet holds the modes and the field alone, and is only as wide as the field
needs; with one, it is as tall as that
section; with both, it is its full height. Floating, Search is one size
on every display, 840 wide and at most as tall as both sections, so a large
desktop screen shows it no bigger than a tablet does; only a smaller screen
trims it. It is centred on the screen at every height, above the keys
while they are up: typing, a drawer or a mode grows it to its full height,
evenly up and down, with the field moving in step. Growing, shrinking or
Expand moves only the sheet's edge: what it holds is laid out once at the
size the sheet is going to, which growing uncovers and shrinking closes in
on, so nothing inside lays itself out again on each frame. It opens at its resting
size in one motion: the whole sheet, already as it will rest, fades in as it
rises the last 12 pixels into place over 180 ms, and nothing inside it
arrives on its own. Apps, Files and Notes fade in where they stand. Inside Spread,
Kadunce sets its size; with neither section on, the field rests in the middle
of it. Its source is KDE's record of use for the current activity, read when
Search opens; Tettegouche tells that record each application it starts and
each file it opens, and Plasma's privacy setting decides what is kept.

- An application is offered unless it is open, pinned in the dock, hidden from
  Apps, hidden from menus, or Tettegouche itself.
- A file is offered while it exists on this machine; a folder, a hidden file and
  anything remote are not.
- Nothing is offered while the screen is shared or recorded, so no file's name
  is on show; the modes stay.
- Typing hands the room to the results.
- The widget's settings "Recent apps" and "Recent files" each turn their
  section on, both by default. With both off nothing is read; an older
  setting "offerRecent" off counts as both off.
- A section that is on with nothing to show says so in a line, and keeps its
  room, so Search's size does not depend on what the record holds.

### Helpers

The Helpers pill opens this first screen with only Split Rock's Helpers on it,
so nobody has to remember a Helper's name to find it. Under the field, labelled
Helpers, every upkeep card Core lists is a tile in Core's own order: its icon
and its name on the subtle paper, 96 by 88 and 12 apart, narrower only when
more than fit in one row. The field reads "Look over the computer, free up
space…"; what is typed lists only Helpers, by the same words that find them
on the first screen, best first, and never searches the web. A tap or Enter
opens a Helper on its own, as its row does, and Search closes; Enter with
nothing typed opens the first. Escape or the dot comes back to the first
screen, and any other mode closes the Helpers. Without Core, or while Core
lists none, there is no pill. Helpers still answer a search from the first
screen.

#### Ask

Where Split Rock's Ask is installed, the chip, its slide door and Helpers in
the panel are named Ask, and the field reads "Ask a question, or find a
Helper". With nothing typed it is the same row of tiles. Typed words that read
as a question, three words or more or ending in "?", go to Ask once typing
pauses for 0.7 seconds, or at once on Enter when nothing is listed; a Helper's
name alone is never sent. Ask's answer sits above the list on the subtle
paper, 10 round, 12 by 16 inside, its words at 15 as they are written, and
beneath at 12 who gave it: "Answered on this computer · nothing changes until
you open a Helper". The Helpers the answer names come first in its order,
then those the words find; Install an app opens searching for the app the
answer named. Ask changes nothing; only a Helper's row does, after a tap. Until
the first words come, which on a computer without a fast graphics chip can
take most of a minute, the box reads "Looking into it…", and beneath, "On this
computer · an answer can take up to a minute", so the web search never stands
alone. A question Ask stops for another surface's says Ask couldn't answer
this time; one this Search typed over is simply replaced.

Where the person's apps offer Ask their tools, as Notes does, an answer that
reads them names what it read in its line beneath: "On this computer · Read:
Testing notes, Tablet round 30 Oct". An answer that would write in an app,
such as keeping it as a note, ends with its Do it card inside the box: what it
does and, beneath at 12 in quotes, the first words it writes, with a Do it
pill 32 tall, the light pill, at its end. Only the tap makes the write: Search
hands the card's token to Split Rock's broker (`Run` at
`io.github.carlsonjm.splitrock.Broker`, `/Broker`), once, and the pill becomes
"Done", or "Didn't work" with the broker's reason beneath. Until then the line
beneath reads "Answered on this computer · nothing changes until you tap Do
it". A card that runs a settings command is not shown in Search.

Where Split Rock's Codex is signed in, an answer's list ends with an Ask Codex
row, a row like a Helper's: "For a bigger fix, with your ChatGPT plan". Only a
tap on it hands the question on, to Codex's own window, and Search closes as
from a Helper's row; Codex speaks there under its own name. Where the person
switched on "Hand bigger questions to Codex" in Settings, Ask hands a bigger
question on itself: the answer says so, its line beneath reads "From this
computer · Codex answers in its own window", and no Ask Codex row is offered.
Signed out, no row is offered and the answer says where to sign in.

Before the model is downloaded, the first question gets what Ask needs in the
answer's place, under a heading at 16, demi-bold: the model by name, that it
runs on this computer, its size, and that nothing asked leaves the computer,
with whose model it is at 12 beneath. Its pills, 40 tall and 8 apart: Download
and the model's name, the light pill; Codex only, on the raised grey, where
Codex is installed; and Not now, bare until hovered. Not now holds until the
field is cleared. Where llama.cpp, which runs the model, isn't installed, the
box says so first, and Install llama.cpp takes Download's place: it opens
Install an app at llama.cpp, and Search closes as from a Helper's row. Codex
only leaves the model out from then on, at the person's choice: the question
is asked again, and the box says it waits for Codex, with Ask Codex, the light
pill. Ask Codex or Enter sends it to Codex's own window, which signs in first
where it must, and Search closes; nothing goes to Codex before that tap, and
the safety check still answers on this computer. While it downloads, a 4 tall
bar fills in the same box under "Downloading" and the model's name, with "N%
of" its size beneath, the Helpers stay listed under it, and the question is
answered when the download ends if Search is still open. Leaving the chip, or
Search closing, stops the question. Without
Ask, the chip is Helpers, as above, and nothing is asked.

### Notes

Notes is one of Search's modes. Gooseberry keeps the note; Search draws it in
its own window and loads none of Gooseberry's code. Gooseberry is a separate
application, and Tettegouche works without it.

- Notes is offered while the application `io.github.carlsonjm.Gooseberry.desktop`
  is installed with its Capture action, looked for each time Search opens and
  whenever KDE's application list changes. Without it, the row of modes has
  no Notes.
- Notes opens in the same window with the drawer's motion on its board, a
  search over every note: the field becomes Find a note, Search's
  own 44 px pill in its place under the modes, which holds still as Notes
  comes, with a row
  of filters under it, Everything, the current day's, On windows, each folder in the
  order its newest note came, and Tucked away, quieter, last. The notes are
  listed under them, each with a dot of its colour, its first words and a
  quiet line with a reminder's time on the current day, its folder, and the window it is
  stuck to or when it last changed. Everything and a folder group them under
  the current day, for a note changed or due that day, On windows, and Notes; tucked away
  notes are only under their own filter. Words typed ask Gooseberry for the
  notes with them and underline where they are found; a folder whose name
  holds them is listed after the notes and opens its filter. The window
  keeps its size, and the row of modes stays above it.
- Enter, or New note floating in the board's corner in the highlight colour,
  starts a new note with the words
  typed; `Down` and `Up` pick a note for Enter to open instead. A tap opens a
  note. Each goes to Gooseberry's own card (`OpenOnCard`) and Search closes;
  the card has ‹ Notes on top, which reopens Notes here (`Back`) at the size
Notes had when the note left. A
  Gooseberry with only `OpenNote` takes a kept note with no way back, and
  only one whose card cannot take it has the note open on the page here.
- A note on the page here is paper of its colour filling the room, with dark ink on
  any ground. Its colour is a dot in its corner, opening the five colours
  beside it. One quiet line under it holds the folder's name, the window it
  is stuck to or Not stuck, a mark that it is kept, or what is wrong, and
  Checklist, Remind and More. Back and `Esc` return to the board, and the
  note stays open, so Start resumes it.
- The folder's name and the window's open their choices in a row above the
  line. Folder offers Gooseberry's folders in its order, the workspace's own
  marked, and a field for a new one; Stuck to offers the windows Gooseberry
  gives, in its order, and Don't stick to a window. A choice closes the row
  and returns to the page, and `Esc` closes an open row before it leaves the
  page. A Gooseberry that offers no folders gets its Belongs to row instead,
  as it offers it.
- Checklist turns the note into Gooseberry's checklist, a box on each line
  that ticks in place, and back. Remind offers Gooseberry's times in its
  order, Pick a time, a day of the coming week then an hour, and No reminder
  when one is set; Remind then names the time. Both are there only where
  Gooseberry offers them. More, on a kept note, offers Copy all, Pin
  where Gooseberry offers it (Unpin on the pinned note), Tuck away and
  Remove; Tuck away and Remove return to the board, or close Search when
  the note was opened straight onto its page.
- The panel's quick note island opens Gooseberry's own card: its dot on a
  new quick note, and its pinned note on that note. Only where Gooseberry
  cannot take it does it open Notes at Search's size, straight onto the page
  with no Back.
- The board and the note are Gooseberry's over its session-bus interface,
  version 1 (Gooseberry's `docs/DESKTOP.md` § The quick note in Search):
  `Find` lists the notes, every one for no words, `OpenOnCard` hands one to
  Gooseberry's card with the way back `Back` answers, `Edit` opens one on the page here, and
  `SetPinned` pins it.
  Typing is sent half a second after it pauses and at least every three
  seconds, and on closing; each change is written by Gooseberry before its
  reply.
- Expand, Pop out and Close are Search's own, at the right of the modes row,
  as for Apps and Files; Notes adds no band of its own under it. Expand
  fills the screen as Apps does and Notes stays in Search; again, or the dot,
  returns Search to its size. Moving to Apps or Files, or to Notes from
  them, keeps the size chosen.
- Pop out grows the window as Apps does, and Gooseberry's board, its own
  window open on the note, takes the window's place with no Back. Inside Kadunce's Spread the
  board is awaited as any launch from Search is. Over an Active card Search
  fades once the board has drawn, since Kadunce puts it in the Active card's
  place. A board that does not draw within ten seconds leaves the note as it
  was.
- An older Gooseberry without the interface keeps the earlier door: Notes runs
  the Capture action and Search closes.
- Typed words also find notes. While Gooseberry is running and offers `Find`
  (its `docs/DESKTOP.md`), each query of two letters or more asks it for up to
  five notes with those words, and they are listed among the results: the
  note's first words with a square of its colour, and under them the line
  with the words and its folder, or the window it is stuck to. A tap opens
  the note on Gooseberry's own card and Search closes. Gooseberry is never
  started for this and never waited on; an answer to an older query is
  dropped.
- The widget's setting "Show Notes when Gooseberry is installed" is on by
  default; off, Notes is never offered and no note is asked for.
- "Show the Notes pill", on by default, hides only the first screen's Notes
  pill, and the dot's Notes door with it; notes still answer a search.
- "Show the Helpers pill when Split Rock is installed", on by default, hides
  the first screen's Helpers
  pill and the dot's Helpers door; Helpers still answer a search. The door is
  offered where Split Rock's Core is running or ready to start.

## Eligibility and confidence

1. Scope decides eligibility, not authorship. Everyday hides quiet collections,
   repositories, technical/internal files, and file matches shorter than three
   characters. All files relaxes those Tettegouche filters but does not widen
   KDE indexing or scan content.
2. Confidence precedes provider preference: exact name, named intent, prefix,
   query words, descriptive context, then unrelated. Unrelated rows are omitted.
   Files and folders are the exception: they follow every app, setting, Helper
   and sum the words found, so a folder called settings never comes
   before Settings. A file whose whole name is typed with its extension keeps
   its place by confidence. A file Baloo found by the words inside it, its name
   holding none of them, follows every file and folder named for them. It is
   listed from three characters, and Everyday lists only a document someone
   wrote that way (PDF, Word, LibreOffice, RTF, EPUB), outside hidden folders;
   a word list, a log or a data file found by its words is left out.
3. Notes come last, after every file and folder, those found by the words
   inside them too: Notes has its own search. Among themselves, a note
   Gooseberry found ranks by its first words like any name; found only
   inside, it ranks as descriptive context. A note listed after documents
   found only inside does not keep Enter from the web.
4. Apps and system aids break ties only within comparable confidence. A
   precise setting may beat an incidental app; an explicit filename stays strong.
5. Aliases describe destinations. Two-letter aliases remain ambiguous; longer
   alias prefixes express stronger intent without per-query exceptions.
   The names Windows gives its own tools are aliases for the apps that do
   those jobs here: Control Panel for System Settings, Task Manager for System
   Monitor, File Explorer, Windows Explorer, This PC and My Computer for
   Dolphin, and Device Manager for Info Center. Such a name counts once its
   second word is begun ("file e"), so "file" still means files, and it lists
   the app even where KDE's own search would not, wherever the app is
   installed.
6. Matching ignores punctuation and case and uses word boundaries rather than
   arbitrary scattered letters.
7. Typing alone never opens the browser or changes a setting. The web fallback
   appears only when the person submits a search with no eligible result, or
   with only documents found by the words inside them and no row chosen; the
   line after the results offers it whatever was found.
8. Ranking does not need to learn from use, and history never outranks
   relevance.

## Providers and execution

Allowed local sources are applications/services, Baloo and recent documents,
KDE settings, calculator, unit conversion, times in other zones, notes from a running
Gooseberry, and, where Split Rock is installed, its Core's facts and Helpers.
Core's facts ("Storage · 91% full") and its Helpers (Check for updates,
Free up space, Install an app, Health check, What changed, Restore points,
Community apps) are held as Core last told them and found by the start of
their words or a query holding one, three letters or more, so typing asks Core
nothing. A fact or Helper found this way ranks above every file and folder,
below only an application named exactly what was typed: "update" means the
Helper, not a folder called update. Enter on one asks Core to open the card on its own; Install an app
gets what was typed, so "install pdf editor" opens it searching. A card changes
nothing until the person's yes on it. Shell commands, session and kill actions, browser history and online runners
are left out.

### Layouts

Where Split Rock's Core keeps saved layouts, named desks of apps, each group
one app on its own or a Stack, Search finds them as it finds Core's facts and
ranks them the same. "Layouts" is found by "layout", "layouts", "desk" or "save
layout", or the start of one of them, never by "desktop", and reads "2 saved"
beneath, or "Save what's open as a layout" with none. Each saved layout is
found by the start of its name or of a word in it, three letters or more, or
its whole name however short: "Open your Coding layout", its groups' apps
beneath ("Ghostty, Claude · Zen"), and one Open pill at the row's end, the
light pill, 32 tall. Search holds the layouts as Core last listed them
(`Layouts()`), reads them again on `LayoutsChanged`, and asks Core nothing
while typing.

Enter, or a tap on the row or its pill, opens a saved layout through Core
(`OpenLayout`): Core launches what isn't running, Cards moves the rest to its
place, nothing is closed, and Search closes. Layouts itself opens in place in
the band: Search closes and asks the widget on its display for the Layouts
island (`islandRequested` on the launcher's interface,
[AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md) § Layouts). It is never a window or a
card, so it never becomes part of the desk it saves. Without Split Rock, or
with a Core that has no `Layouts()`, there is no Layouts result and nothing
else changes.

Application results may activate an exact existing Kadunce window. Files and
settings execute their provider or verified module action. Web dispatch sends an
encoded URL through the registered HTTPS browser; query text is never executed.
Whether the browser opens a new tab is the desktop URL handler's choice; only
Firefox-family handlers are verified.

## Destination identity

- Equivalent normalized local paths collapse across file providers. Same-named
  files at different paths stay distinct. Symlinks are not followed, and a
  title alone never merges two results.
- Desktop application identities collapse across app rows. A `kcm_*.desktop`
  shortcut may collapse with the same KDE module; the canonical module wins so
  related children remain attached.
- Context children sit under their parent destination and are not ranked as
  results of their own. An application's or a file's actions are children
  of the highlighted row only, shown while it is highlighted; another row's
  stay hidden, so every other row is one line. Selecting one opens the parent settings page after revalidating that
  the child is still present.
- Independent tools with similar names stay separate destinations.

## Stable interaction

Keyboard navigation and pointer/touch press pin the destination identity and a
snapshot of displayed order. Late arrivals follow that snapshot; a replacement
row for the same destination keeps its position. Execution resolves the pinned
identity rather than trusting an old row number. If it disappears, submission
does nothing. A new query or scope releases the lock.

## Reference examples

| Query | Expected relationship |
| --- | --- |
| `wi` | Winetricks before Wi-Fi; Wi-Fi before Window Manager |
| `so` | Sound and other short prefixes remain ambiguous |
| `soun` | Sound intent before a Soundcloud asset prefix |
| `soundcloud` | Exact Soundcloud name beats the Sound alias |
| `sound.png` | Explicit file beats unrelated settings |
| `task manager` | System Monitor before any file or folder of that name |
| unmatched text | No invented destination; explicit browser fallback |

Ranking works only on what KDE's providers return: it cannot rank a candidate
KDE never returned.
