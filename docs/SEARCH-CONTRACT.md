# Search contract

Search reveals recognizable destinations rather than rewarding incidental
strings. Screenshot-specific changes must become general rules tested against
unrelated examples before adoption. Its inputs are in [INPUT.md](INPUT.md).

## First screen

Search's modes run along its top on every screen, one row above the field: the
dot for this first screen, then Apps, Files and, where Gooseberry is installed,
Notes. The grey pill marks the mode shown, and a tap moves straight to another;
the dot comes back here with what was typed. The window's own buttons end
that row: Expand while Apps or Files is open, Pop out in Files, and Close,
last; at rest, Close alone. The field is the same on every screen: a pill
44 tall on the row's own edges, the dot's pill starting where it starts and
Close ending where it ends, 16 below the row, with 24 between everything and
the sheet's edge, so only what is under it changes. Before anything is typed,
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
desktop screen shows it no bigger than the tablet does; only a smaller screen
trims it. It is centred on the screen at
rest, and typing, a drawer or a mode grows it to its full height downward
from there, moving up only as far as the screen's edge needs. Inside Spread,
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

### Notes

Notes is one of Search's modes. Gooseberry keeps the note; Search draws it in
its own window and loads none of Gooseberry's code. Gooseberry is a separate
application and Tettegouche never depends on it.

- Notes is offered while the application `io.github.carlsonjm.Gooseberry.desktop`
  is installed with its Capture action, looked for each time Search opens and
  whenever KDE's application list changes. Without it, the row of modes has
  no Notes.
- Notes opens in the same window with the drawer's motion on its board, a
  search over every note: the field becomes Find or start a note, with a row
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
  the card has ‹ Notes on top, which reopens Notes here (`Back`). A
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

## Eligibility and confidence

1. Scope decides eligibility, not authorship. Everyday hides quiet collections,
   repositories, technical/internal files, and file matches shorter than three
   characters. All files relaxes those Tettegouche filters but does not widen
   KDE indexing or scan content.
2. Confidence precedes provider preference: exact name, named intent, prefix,
   query words, descriptive context, then unrelated. Unrelated rows are omitted.
3. A note Gooseberry found ranks by its first words like any name; found
   only inside, it ranks as descriptive context. Notes sit with system aids.
4. Apps, files, and system aids break ties only within comparable confidence. A
   precise setting may beat an incidental app; an explicit filename stays strong.
5. Aliases describe destinations. Two-letter aliases remain ambiguous; longer
   alias prefixes express stronger intent without per-query exceptions.
6. Matching ignores punctuation and case and uses word boundaries rather than
   arbitrary scattered letters.
7. No browsing or settings change occurs merely because the user types. Web
   fallback appears only after explicit submission of an empty eligible result.
8. Ranking has no usage-learning requirement; history cannot overpower relevance.

## Providers and execution

Allowed local sources are applications/services, Baloo and recent documents,
KDE settings, calculator, unit conversion, notes from a running
Gooseberry, and, where Split Rock is installed, its Core's facts and Helpers.
Core's facts ("Storage · 91% full") and its Helpers (Check for updates,
Free up space, Install an app, Health check, What changed, Restore points,
Community apps) are held as Core last told them and found by the start of
their words or a query holding one, three letters or more, so typing asks Core
nothing. A fact or Helper found this way ranks above every file and folder,
below only an application named exactly what was typed: "update" means the
Helper, not a folder called update. Enter on one asks Core to open the card on its own; Install an app
gets what was typed, so "install pdf editor" opens it searching. A card changes
nothing until the person's yes on it. Shell, session/kill actions, browser history, and online runners
are excluded.

Application results may activate an exact existing Kadunce window. Files and
settings execute their provider or verified module action. Web dispatch sends an
encoded URL through the registered HTTPS browser; query text is never executed.
Whether the browser opens a new tab is the desktop URL handler's choice; only
Firefox-family handlers are verified.

## Destination identity

- Equivalent normalized local paths collapse across file providers. Same-named
  files at different paths remain distinct; no symlink traversal or title-only
  merging is performed.
- Desktop application identities collapse across app rows. A `kcm_*.desktop`
  shortcut may collapse with the same KDE module; the canonical module wins so
  related children remain attached.
- Context children belong to the parent destination and are not extra ranked
  results. Selecting one opens the parent settings page after revalidating that
  the child is still present.
- Independent tools with similar names remain separate destinations.

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
| unmatched text | No invented destination; explicit browser fallback |

Provider retrieval remains a hard boundary: policy cannot rank a candidate that
KDE never returns.
