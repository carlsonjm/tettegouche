# Search contract

Search reveals recognizable destinations rather than rewarding incidental
strings. Screenshot-specific changes must become general rules tested against
unrelated examples before adoption. Its inputs are in [INPUT.md](INPUT.md).

## First screen

Before anything is typed, Search offers its doors, Apps and Files, then Notes
where Gooseberry is installed, and beside them what was used lately, newest
first: at most six, as many as the width holds, spaced evenly to the field's
width. Its source is KDE's record of use for the current activity, read when
Search opens; Tettegouche tells that record each application it starts and
each file it opens, and Plasma's privacy setting decides what is kept.

- An application is offered unless it is open, pinned in the dock, hidden from
  Apps, hidden from menus, or Tettegouche itself.
- A file is offered while it exists on this machine; a folder, a hidden file and
  anything remote are not.
- Nothing is offered while the screen is shared or recorded, so no file's name
  is on show; the doors stay.
- Typing hands the room to the results.
- The widget's setting "Show recent files and apps", off, leaves the doors
  alone, and nothing is read.

### Notes

Notes is one of Search's modes. Gooseberry keeps the note; Search draws it in
its own window and loads none of Gooseberry's code. Gooseberry is a separate
application and Tettegouche never depends on it.

- Notes is offered while the application `io.github.carlsonjm.Gooseberry.desktop`
  is installed with its Capture action, looked for each time Search opens and
  whenever KDE's application list changes. Without it, the first screen has
  Apps and Files only.
- Notes opens in the same window with the drawer's motion: the field becomes
  the note pad, the pills fade, and Back, the note's five colours and All notes
  come into the header where Apps has Back and its sort button. The window
  keeps its size. Folder, Stuck to, Saved as you go, Tuck away and Done sit
  under the pad. Back or `Esc` returns to Search and the note stays open, so
  Notes resumes it; Done and Tuck away finish it and Search closes.
- Folder and Stuck to are Gooseberry's own card's two chips, each showing
  what is chosen and opening its choices in a row under it. Folder offers
  Gooseberry's folders in its order, the workspace's own marked, and a field
  for a new one; Stuck to offers the windows Gooseberry gives, in its order,
  and Don't stick to a window. A choice closes the row and returns to the pad,
  and `Esc` closes an open row before it leaves the note. A Gooseberry that
  offers no folders gets its Belongs to row instead, as it offers it.
- The note is Gooseberry's quick note over its session-bus interface, version
  1 (Gooseberry's `docs/DESKTOP.md` § The quick note in Search). Typing is sent
  half a second after it pauses and at least every three seconds, and on
  closing; each change is written by Gooseberry before its reply.
- All notes grows the window as Apps does, and Gooseberry's board, its own
  window, takes the window's place with no Back. Inside Kadunce's Spread the
  board is awaited as any launch from Search is. Over an Active card Search
  fades once the board has drawn, since Kadunce puts it in the Active card's
  place. A board that does not draw within ten seconds leaves the note as it
  was.
- An older Gooseberry without the interface keeps the earlier door: Notes runs
  the Capture action and Search closes.
- The widget's setting "Show Notes when Gooseberry is installed" is on by
  default; off, Notes is never offered.

### Genie

Genie is one of Search's modes, as Notes is. Split Rock keeps the
conversation; Search draws it in its own window and loads none of Split Rock's
code, and Tettegouche never depends on it.

- Genie is offered while Split Rock's conversation service is running or can
  be started from the session bus and answers version 1
  (`io.github.carlsonjm.splitrock`, `/Conversation`). Without it, the first
  screen has no Genie.
- Genie opens in the same window with the drawer's motion: the field travels
  into the header and holds the question, Back comes in on its left and Expand
  on its right, and the answer arrives below. The window keeps its size.
  Enter asks; a suggestion is asked as typed. An answer shows its steps and
  any paragraphs after them, and offers Do it where it asks for a change, Show
  me how, Keep this and That fixed it; Stop ends one in progress. What Genie
  offers to remember about the person is asked as "Remember that?", and
  written only after Remember. Before an assistant is chosen
  or signed in, Genie says so and Open Genie finishes it in Genie's window.
  Back or `Esc` returns to Search and the conversation stays.
- Expand grows the window as Apps does, and Genie's own window takes its place
  with no Back: inside Kadunce's Spread through its launch hand-off, over an
  Active card once the window has drawn. A window that does not draw within ten
  seconds leaves Genie as it was.
- The widget's setting "Show Genie when Split Rock is installed" is on by
  default; off, Genie is never offered.

## Eligibility and confidence

1. Scope decides eligibility, not authorship. Everyday hides quiet collections,
   repositories, technical/internal files, and file matches shorter than three
   characters. All files relaxes those Tettegouche filters but does not widen
   KDE indexing or scan content.
2. Confidence precedes provider preference: exact name, named intent, prefix,
   query words, descriptive context, then unrelated. Unrelated rows are omitted.
3. Apps, files, and system aids break ties only within comparable confidence. A
   precise setting may beat an incidental app; an explicit filename stays strong.
4. Aliases describe destinations. Two-letter aliases remain ambiguous; longer
   alias prefixes express stronger intent without per-query exceptions.
5. Matching ignores punctuation and case and uses word boundaries rather than
   arbitrary scattered letters.
6. No browsing or settings change occurs merely because the user types. Web
   fallback appears only after explicit submission of an empty eligible result.
7. Ranking has no usage-learning requirement; history cannot overpower relevance.

## Providers and execution

Allowed local sources are applications/services, Baloo and recent documents,
KDE settings, calculator, and unit conversion. Shell, session/kill actions,
browser history, and online runners are excluded.

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
