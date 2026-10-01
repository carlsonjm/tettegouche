# Architecture

Tettegouche 0.2.0 has two lifetimes: a persistent Plasma panel applet and an
on-demand launcher process. The applet owns the panel's launcher dot and the
Ambient island. The launcher owns search, Browse everything, local Files state
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

The Browse drawer reads visible applications from `KApplicationTrader`, sorts by
display name, and launches with `KIO::ApplicationLauncherJob`. It has no usage,
recency, or recommendation layer. Existing-window matching runs before launch.

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
admission, source truth, width and actions.

The panel shows Ambient as one island per kind of activity
(`AmbientSurface.qml`), clear over the panel and the suite's black while the
containment sets Plasma's `ContainmentPrefersOpaqueBackground` hint.
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

## Related settings

Related-setting children are read-only context under a settings result, owned by
[RELATED-SETTINGS.md](RELATED-SETTINGS.md).

## Look

- The Tette Dot is protected identity: a Ghost White (`#F8F8FF`) pearl, 20 px,
  lit from above and a shade deeper toward its lower edge, centred in a 44 px
  touch square at the panel's start, with a thin ring round it while the
  launcher is open. No icon family replaces or redraws it.
- Action glyphs come from a pinned, vendored Lucide subset
  ([THIRD_PARTY.md](../assets/icons/THIRD_PARTY.md)), drawn in Ghost White.
  Applications, files and devices keep their own icons.
- Menus and questions are drawn inside the sheet they open in, never past its
  edge, in the sheet's colours with lines a finger can hit; a question names
  its action ("Move to Trash") and darkens only the sheet. Pressed controls
  are the suite's grey pill or, for a glyph alone, a circle.
- A pill-shaped control acts; a rounded box holds information. Corners follow
  the suite's three tiers: 8 px for the launcher's sheet and all laid in it,
  12 px for menus and the open island, which float above and close, and pills
  for what is pressed.
- Quiet spatial invitations are lowercase, as in "browse everything" and
  "explore files"; other labels use sentence case, and OPEN is the one
  all-caps tag.
- Motion explains a change of state or place, can be interrupted, and never
  shows progress or success a source has not reported.

## Verification boundaries

Native tests cover search policy, workspace schema, Files operations, related
providers, activity providers, and icon rendering. QML and private-bus tests
cover launcher controls, Ambient composition, panel geometry/input, and package
integration. Disposable fixtures must not write or delete real user files.

## Known issues

- A reported one-pixel line below Ghostty's window can make a floating Plasma
  panel go flat. Which component owns it, and why, is unconfirmed.
