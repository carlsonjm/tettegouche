# Architecture

Tettegouche 0.2.0 has two lifetimes: a persistent Plasma panel applet and an
on-demand launcher process. The applet owns the panel's launcher dot and the
Ambient island. The launcher owns search, Apps, local Files state
and the temporary layer-shell surface. It stays fully useful without Kadunce,
the optional related-setting tools, Bluetooth hardware or any Ambient source.
Every input is listed in [INPUT.md](INPUT.md).

## Process and surface model

The public entry point is a native Plasma applet. Its launcher button is direct
content of the root `PlasmoidItem`, and the root's explicit size hints are part
of the panel contract; the button must not move into a lone
`compactRepresentation`, which Plasma will not instantiate for this
direct-content applet. The installed SVG is Widget Explorer identity; live panel
content and its input target are QML items.

The launcher is a single-instance process. A second invocation forwards its
request over D-Bus, whether a toggle, a drawer, a folder, a drive or files to show, and
exits; one that finds the running launcher already leaving takes its place.
Standalone mode uses a full-display input surface
with a centered sheet; while files are carried out of Files, input narrows to
the sheet so the drop can land on a window beside it. Kadunce guest mode keeps
the layer-shell surface but masks input to Kadunce's negotiated guest geometry.
Neither mode reserves workspace. Dismissal normally ends the process; an outstanding asynchronous file
operation may keep its event loop alive after the surface hides.

The on-screen keys lie over the launcher and reserve no space. The launcher
reads where they lie from the compositor's report to the focused window, which
Qt gives as the keyboard rectangle, and keeps its sheet above them itself.

`Meta+G` and `Meta+E` are registered once per Plasma process in KDE's shortcut
settings, under Tettegouche, by whichever Tettegouche widget came first. A
press starts the launcher with `--drawer apps` or `--drawer files`, or asks a
running one through `openDrawer` on its D-Bus interface.

Where Shuffle is installed, Tettegouche names itself Search: in its tooltip,
its widget title, its launcher window and its Shortcuts entry. Each process
looks for Shuffle's bottom surface when it starts. Identifiers, D-Bus names and
settings keys keep the Tettegouche name.

A folder KDE opens in Files starts the launcher with `--folder`. The launcher
answers `org.freedesktop.FileManager1` only when D-Bus starts it for that name,
with `--file-manager`, from the service file placed where it looks. It then owns the
name until it quits, and leaves after five seconds if no request has shown it.
If a launcher already runs, the process D-Bus starts forwards each request to it
and leaves after three idle seconds.

The launcher is a top-layer surface, not an overlay one. KWin keeps the
on-screen keyboard in the overlay layer, and an overlay launcher mapped after it
stacked above the keys, so its full-screen backdrop took every touch meant for
them and closed the search. The keys now stack above the launcher, and a whole
search can be typed on them. Opening activates the launcher, which keeps a
full-screen window from covering it. Notification banners draw over it.

Tettegouche adds no daemon, polling loop, persistent activity history,
compositor ownership, replacement task manager or cross-product state owner.

## Ownership boundaries

Tettegouche owns launcher invocation and presentation, search and application
catalogue queries, result selection, ordinary application launch, local Files
state and operations, related-setting context, Ambient composition, and
interpretation of Kadunce's published integration schemas.

Kadunce exclusively owns KWin discovery, live window identity, cards, stacks,
focus, output state, existing-window activation, guest placement, neighboring
card motion, and the final Spread selection. Tettegouche never performs raw
KWin discovery or inserts its guest into Kadunce's persistent card model.

Source applications and KDE services own activity truth and supported actions.
Temperance owns notifications and transient event presentation; Tettegouche does
not duplicate that history in Ambient.

## Kadunce integration

At open time the launcher negotiates Kadunce launcher-guest protocol 3 and reads
workspace-context schema version 1; no other versions are accepted. Unsupported,
absent, or malformed endpoints fall back to the standalone launcher. Context
refreshes on Kadunce change signals and before window selection; there is no
timer or heartbeat.

Open application matches carry a live window identifier. Tettegouche asks Kadunce
to activate that exact window. New launches use Plasma's normal application job
and may hold the guest until Kadunce sees a matching window; a bounded timeout
returns to search. Horizontal guest drag sends only motion deltas, leaving
commit/cancel and real-card selection to Kadunce. Expanded Apps and Files
drawers request the negotiated presentation capability and otherwise use
standalone expansion. The expanded drawer has one accepted treatment, fitted to
the tablet's Active card; there is no separate expanded layout for a monitor.

## Search and catalogue

The compact search model combines an allowlisted set of KRunner providers and a
Tettegouche-owned confidence policy. Its behavior is owned by
[SEARCH-CONTRACT.md](SEARCH-CONTRACT.md).

Apps reads visible applications from `KApplicationTrader`, sorts by display
name, and launches with `KIO::ApplicationLauncherJob`, telling KDE's activity
service each start. Existing-window matching runs before launch.

`NotesDoor` looks for Gooseberry's Capture action in KDE's application list
each time Search opens. `QuickNote` speaks Gooseberry's quick-note interface on
the session bus, and `NotesPane` draws the note in Search's window; with an
older Gooseberry, `NotesDoor` runs the Capture action through
`KIO::ApplicationLauncherJob` instead
([SEARCH-CONTRACT.md](SEARCH-CONTRACT.md) § Notes). `GenieChat` speaks Split
Rock's conversation interface the same way and `GeniePane` draws it (§ Genie).
Both modes share the launcher's mode state, its drawer easing and its hand-off
to the application's own window.

`RecentUse` reads KDE's record of use through PlasmaActivitiesStats when Search
opens, for the first screen ([SEARCH-CONTRACT.md](SEARCH-CONTRACT.md) § First
screen). What the dock pins comes from the Bottom Surface's
`pinnedApplications`, what is open from Kadunce's workspace context, and
whether the screen is shared from the portal's status item; each is optional,
and with none of them nothing is left out on its account.
The same answer tells an application's sheet in Apps whether to offer Pin to
dock; it asks the Bottom Surface's `pinApplication` or `unpinApplication`.

## Files

`FileBrowser` owns listing folders, Recent and searches inside folders, tabs,
navigation, selection, clipboard, Properties and KIO jobs, and answers what
KIO asks during a copy through `FileQuestions`; `FilesPane.qml` renders that
state. `FileDevices` lists drives from Solid, mounting and ejecting them, and phones, by cable through kio-fuse and through KDE Connect. The launcher gives it thumbnails through `FileThumbnails`,
an image provider over KDE's previews, and a file's own details through
`FileDetails`, over KDE's metadata readers. Their behavior and
safety boundary is owned by [FILES-CONTRACT.md](FILES-CONTRACT.md).

## Ambient activity

The applet constructs one shared activity model per Plasma process from the
sources [AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md) lists; that contract owns
admission, source truth, width and actions. Waiting applications come from
Plasma's own window list (libtaskmanager), shared in process with Plasma's task
manager, and Ambient asks it, not Kadunce, to bring one forward; this is
neither KWin discovery nor a task manager of Tettegouche's own.

The panel shows Ambient as one island per kind of activity
(`AmbientSurface.qml`), clear over the panel and in the Plasma style's own
ground, the suite's black on a dark style, while the containment sets Plasma's
`ContainmentPrefersOpaqueBackground` hint.
`IslandRoom.js` decides, from each island's measured pieces, what each shows in
the width it has; the surface draws that and animates the change.
`DriveRules.h` holds KDE's rule for which storage is a drive, which Files and
Ambient's drives share. Opening an
island maps a clear top-layer surface over the whole display, set up as the
launcher's is, on which `AmbientIsland.qml` grows the island into its card; the surface takes the
keyboard so Esc closes it, and is destroyed when it closes.

`TETTE_AMBIENT_FIXTURE=transfer-media`, or `paused` for paused media, replaces
the live sources with one sample transfer and one media row for tests and
demonstrations. Normal startup uses live sources only and leaves the island
absent when no activity qualifies.

## Settings

The widget's own settings page stays and works everywhere. Where Shuffle
Settings is installed (desktop entry `studio.warbler.Shuffle.Settings`),
Configure opens it at this widget's page instead, passing the page's name, `search`,
as its one argument. The entry is looked for at each press, so there is one
build and no switch, and a Plasma that wires Configure some other way keeps the
widget's own page.

## Related settings

Related-setting children are read-only context under a settings result, owned by
[RELATED-SETTINGS.md](RELATED-SETTINGS.md).

## Words

Every word Tettegouche shows comes from one of two KI18n catalogs:
`tettegouche` for the launcher, and `plasma_applet_studio.warbler.tettegouche`,
the one Plasma gives the panel widget, for the widget and Ambient. QML asks
through a `KI18nContext` naming its catalog, so tests load the same words.
`tools/extract-messages.sh` writes the catalogs' templates; a translation is
`po/<language>/<catalog>.po`, which the build installs. Sizes, numbers and
counts follow the language.

## Look

- The Tette Dot is protected identity: a Ghost White (`#F8F8FF`) pearl, 20 px,
  lit from above and a shade deeper toward its lower edge, centred in a 44 px
  touch square at the panel's start, with a thin ring round it while the
  launcher is open. No icon family replaces or redraws it.
- Search follows the window's colour scheme, and Ambient the Plasma style's
  colours. On a dark one they keep the suite's dark values; on a light one
  their ground and text are the theme's, and every wash, control and line is
  that text laid over the ground (`qml/SearchColors.qml`,
  `applet/AmbientColors.qml`). Colours come from the theme alone. The Tette
  Dot, a note's paper and a recording's red dot keep their own colours.
- Action glyphs come from a pinned, vendored Lucide subset
  ([THIRD_PARTY.md](../assets/icons/THIRD_PARTY.md)), drawn in Ghost White and
  recoloured to the theme's text on a light ground. Applications, files and
  devices keep their own icons.
- Menus and questions are drawn inside the sheet they open in, never past its
  edge, in the sheet's colours with lines a finger can hit; a question names
  its action ("Move to Trash") and darkens only the sheet. Pressed controls
  are the suite's grey pill or, for a glyph alone, a circle.
- A pill-shaped control acts; a rounded box holds information. Corners follow
  the suite's three tiers: 8 px for the launcher's sheet and all laid in it,
  12 px for menus and the open island, which float above and close, and pills
  for what is pressed.
- Labels use sentence case, and OPEN is the one all-caps tag.
- Motion explains a change of state or place, can be interrupted, and never
  shows progress or success a source has not reported.
- Motion follows Plasma's animation speed, read through Kirigami's durations.
  The first screen's arrival in Search and an island's arrival and departure
  in Ambient keep their own pace, as moments meant to be seen; with animations
  set to instant they only fade.

## Verification boundaries

Native tests cover search policy, workspace schema, Files operations, related
providers, activity providers, and icon rendering. QML and private-bus tests
cover launcher controls, Ambient composition, panel geometry/input, and package
integration. A words test draws Files with test catalogs that mark every
phrase, and fails on any word not asked of a catalog. Disposable fixtures must
not write or delete real user files.

## Known issues

- A reported one-pixel line below Ghostty's window can make a floating Plasma
  panel go flat. Which component owns it, and why, is unconfirmed.
