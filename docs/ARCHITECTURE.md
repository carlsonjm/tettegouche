# Architecture

Tettegouche 1.1.0 has two lifetimes: a persistent Plasma panel applet and an
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
exits; one that finds the launcher still starting waits, a few seconds at most,
until it answers, and one that finds it already leaving takes its place.
The applet starts the launcher as a command in a scope of its own
(`KIO::CommandLauncherJob`), not as its child, so restarting or removing the
panel leaves the launcher, Files' window and any copy running. The applet knows
the launcher by its name on the bus, whoever started it. Before it forwards a
request it asks the launcher to leave for the widget's current settings
(`leaveFor`); one started with others leaves when hidden and idle, and the
request goes to the launcher started in its place.
Standalone mode uses a full-display input surface
with a centered sheet; while files are carried out of Files, input narrows to
the sheet so the drop can land on a window beside it. Kadunce guest mode keeps
the layer-shell surface but masks input to Kadunce's negotiated guest geometry.
Neither mode reserves workspace. Dismissal hides the surface and keeps the
process ready, so the next open shows at once; it releases its graphics
resources, skips workspace updates while hidden, and tells the applet it hid.
It ends instead when its program was replaced since it started, when
`tettegoucherc` `[Launcher] StayReady=false`, or when an applet whose settings
changed asks it to leave for them. An open Files window keeps it until the window closes. Each is an ordinary window beside
the layer-shell surface, sharing its QML engine, with a `FileBrowser` of its own
([FILES-CONTRACT.md](FILES-CONTRACT.md) § Files' own window).

The on-screen keys lie over the launcher and reserve no space. The launcher
reads where they lie from the compositor's report to the focused window, which
Qt gives as the keyboard rectangle, and keeps its sheet above them itself.

`Meta+G` and `Meta+E` are registered once per Plasma process in KDE's shortcut
settings, under Tettegouche, by whichever Tettegouche widget came first. A
press starts the launcher with `--drawer apps` or `--drawer files`, or asks a
running one through `openDrawer` on its D-Bus interface; a slide from the dot
does the same for any of `apps`, `files`, `notes` or `helpers`. The Apps desktop
entry, `io.github.carlsonjm.Tettegouche.Apps.desktop`, runs `--drawer apps`.
The widget declares itself Plasma's application launcher
(`org.kde.plasma.launchermenu`), so Plasma's launcher key reaches it as it
reaches Kickoff.

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

The launcher's layer surface asks for KWin's `utility` scope. KWin makes a
layer surface of any scope it does not know a normal window, and its stock
open and close animation zooms a normal window in from four fifths with a
fade and a blur; a utility surface is left out of it, so Search shows where it
rests and at its size from the first frame.

Tettegouche adds no daemon or polling loop and keeps no activity history. It
does not take over the compositor or the task manager, or hold state for other
products.

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

`src/shared` holds the code Tettegouche and Temperance both run: whether Shuffle
is installed, Configure opening Shuffle Settings, and the room a widget has along
its panel. It changes here. Temperance builds from a byte-for-byte copy that its
`tools/shared.sh` records and checks, so one change reaches both widgets.

## Kadunce integration

At open time the launcher negotiates Kadunce launcher-guest protocol 3 and reads
workspace-context schema version 1; no other versions are accepted. The protocol
is asked once for each Kadunce on the bus. Neither question waits: the launcher
shows when Kadunce answers its guest, or on its own after half a second, so a
busy KWin never holds it still, and a place Kadunce makes after that is given
back. Unsupported, absent, or malformed endpoints fall back to the standalone
launcher; a declined guest that names an output floats the launcher on that
display. Context
refreshes on Kadunce change signals and before window selection; there is no
timer or heartbeat.

Open application matches carry a live window identifier. Tettegouche asks Kadunce
to activate that exact window. Where Kadunce does not answer, what is open
comes from Plasma's own window list instead, through the task manager's QML
module (`org.kde.taskmanager`, so no private library is linked), read the
first time Kadunce is found absent: OPEN, Recent's exclusions and bringing an
open application forward work the same, and the list activates the window. The
launcher's desktop entry asks KWin for the window-management interface this
needs. A tap uses what was read as Search opened and at each change, and waits
for Kadunce only while that reading has not answered. New launches use Plasma's normal application job
and may hold the guest until Kadunce sees a matching window; a bounded timeout
returns to search. Horizontal guest drag sends only motion deltas, leaving
commit/cancel and real-card selection to Kadunce. Expanded Apps and Files
drawers request the negotiated presentation capability and otherwise use
standalone expansion. The expanded drawer has one treatment, fitted to the
tablet's Active card or the screen's work area. Floating, the launcher reads
the work area as the screen reports it, less the band Shuffle's dock reserves
there: on Wayland the screen reports itself whole. The band comes from the
Bottom Surface's `dockExtent` (version 1) as the launcher opens and as it
changes; the one Bottom Surface on the bus answers for the display it presents,
and a display it does not answer for takes the same band. A display it answers
for as not presenting has no band, so expanded Search fills it. With no Bottom
Surface, the work area is the screen's report. Every drawer and mode opens from Search's
pills at Search's size, a card in Spread, and from `openDrawer` (the dot's slide,
Meta+G, Meta+E) filling the screen; Expand, in the corner they all share, fills the screen and
brings it back, and moving between Apps and Files keeps the size chosen.

## Search and catalogue

The compact search model combines an allowlisted set of KRunner providers and a
Tettegouche's own confidence policy, described in
[SEARCH-CONTRACT.md](SEARCH-CONTRACT.md).

Apps reads visible applications from `KApplicationTrader`, again whenever
KDE's application list changes, and orders them by
display name, by use, or by when each application arrived: when Apps first
found it, kept by desktop file id, since a desktop file's own dates change at
every update. Those already there when Apps began keeping count are Older. By name it is one
run, each folder at its name's place; by use or arrival it is divided into
sections by last use or arrival. Use is KDE's
own score and last use from the activity service, summed over every activity
and read again each time Apps opens while it decides the order; the order
chosen is kept in Tettegouche's settings. Its folders live there too, as {id,
name, apps} by desktop file id, with the ids of those left open; a folder is
drawn while two or more of its applications are here and shown. The catalog
is one list of rows, each a section, a folder, an application or an
application in an open folder, and `AppsGrid.qml` lays them out in lines:
sections on lines of their own, folders as tiles among the applications, and
an open folder's applications on lines of their own under its tile's line. An application carried from Apps carries its desktop file and
`application/x-tettegouche-application` with its id, which a tile reads to make
a folder; a folder carried carries its applications' desktop files and
`application/x-tettegouche-folder` with `{"name": …}`, which Shuffle's dock reads
to pin them as one folder, while any other launcher pins them one by one. Apps
launches with `KIO::ApplicationLauncherJob`, telling KDE's activity
service each start. Edit Application… hands the application's desktop file id to
KDE's menu editor, which keeps the person's copy of the entry; Apps reads it
from KDE's application list like any other. Existing-window matching runs before launch.

`NotesDoor` looks for Gooseberry's Capture action in KDE's application list
each time Search opens. `QuickNote` speaks Gooseberry's quick-note interface on
the session bus, and `NotesPane` draws the board of notes and the note's page
in Search's window; with an older Gooseberry, `NotesDoor` runs the Capture
action through `KIO::ApplicationLauncherJob` instead
([SEARCH-CONTRACT.md](SEARCH-CONTRACT.md) § Notes). Notes uses the launcher's
mode state, its drawer easing and its hand-off to the application's own window.

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
`FileDetails`, over KDE's metadata readers. [FILES-CONTRACT.md](FILES-CONTRACT.md)
describes their behavior and safety rules.

## Ambient activity

The applet constructs one shared activity model per Plasma process from the
sources [AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md) lists; that contract owns
admission, source truth, width and actions. Waiting applications come from
Plasma's own window list (libtaskmanager), shared in process with Plasma's task
manager, and Ambient asks it, not Kadunce, to bring one forward. Reading that
list is not KWin discovery, and Tettegouche keeps no task manager of its own.
The quick note's island is a row of that model too, from `NotesIslandProvider`,
which reads Gooseberry's pinned note without starting Gooseberry; its taps ask
the launcher for Search's Notes through the applet's `openDrawer`.

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
demonstrations. Otherwise Ambient uses live sources only, and shows no island
when no activity qualifies. `TETTE_AMBIENT_WITHOUT_NOTES`, set, leaves the
quick note's island out whether or not Gooseberry is installed, and sends the
island's taps to Search's Notes as where Gooseberry is not, so tests of the
other islands and of the panel count the same on any machine.

## Settings

The widget's own settings page stays and works everywhere. Where Shuffle
Settings is installed (desktop entry `co.goodinput.Shuffle.Settings`),
Configure opens it at this widget's page instead, passing the page's name, `search`,
as its one argument. The entry is looked for at each press, so there is one
build and no switch, and a Plasma that wires Configure some other way keeps the
widget's own page and says so in the log; the panel test checks both ways
against the Plasma it builds with.

## Related settings

Related-setting children are read-only details under a settings result,
described in [RELATED-SETTINGS.md](RELATED-SETTINGS.md).

## Words

Every word Tettegouche shows comes from one of two KI18n catalogs:
`tettegouche` for the launcher, and `plasma_applet_co.goodinput.tettegouche`,
the one Plasma gives the panel widget, for the widget and Ambient. QML asks
through a `KI18nContext` naming its catalog, so tests load the same words.
`tools/extract-messages.sh` writes the catalogs' templates; a translation is
`po/<language>/<catalog>.po`, which the build installs. Sizes, numbers and
counts follow the language.

## Look

- The Tette Dot is protected identity: a Ghost White (`#F8F8FF`) dot, 20 px,
  lit from above and a shade deeper toward its lower edge, centred in a 44 px
  touch square at the panel's start, with a thin ring round it while the
  launcher is open. No icon family replaces or redraws it. A host may set
  `pearlLook` to draw Lucide's search mark in its place, a stroke in the same
  Ghost White at the same size and place; the touch square, ring and press are
  the dot's either way ([AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md) § Host
  settings).
- Search, Files and Ambient follow the Plasma style's colours where the
  style brings its own, and the window's colour scheme where it doesn't. On a dark one Search and Files keep the suite's dark
  values, each leaning toward the scheme's ground as far as that ground leans
  from grey, so a tinted scheme tints them and a plain one leaves them as
  they are; Ambient keeps them exactly. On a light one their ground and text
  are the theme's, and every wash, control and line is that text laid over
  the ground (`qml/SearchColors.qml`,
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
  Search's opening and an island's arrival and departure in Ambient keep
  their own pace, as moments meant to be seen; with animations set to instant
  they only fade. Search's opening moves only the sheet's opacity and place,
  and its first screen is set out before the window shows, so its first frame
  is already the screen it opens to.

## Verification boundaries

Native tests cover the launcher controller against a stand-in Kadunce on a
private bus (guest handshake, launch, activation and Plasma's window list in
Kadunce's absence), search policy, workspace schema, Files operations, related
providers, activity providers, and icon rendering. QML and private-bus tests
cover launcher controls, Ambient composition, panel geometry/input, and package
integration. A words test draws Files with test catalogs that mark every
phrase, and fails on any word not asked of a catalog. Tests use throwaway
fixtures and never write or delete real user files.

## Known issues

- A reported one-pixel line below Ghostty's window can make a floating Plasma
  panel go flat. Which component owns it, and why, is unconfirmed.
