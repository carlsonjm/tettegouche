# Architecture

Tettegouche has two lifetimes: a persistent Plasma panel applet and an on-demand
launcher process. The applet owns the panel entry and Ambient activity surface.
The launcher owns search, drawers, local Files state, and the temporary
layer-shell surface.

## Process and surface model

The public entry point is a native Plasma applet. Its launcher button is direct
content of the root `PlasmoidItem`; it must not move into a lone
`compactRepresentation`, which Plasma will not instantiate for this direct-content
applet. The installed SVG is Widget Explorer identity; live panel content and
its input target are QML items.

The launcher is a single-instance process. A second invocation forwards a
`toggle` request over D-Bus. Standalone mode uses a full-display input surface
with a centered sheet. Kadunce guest mode keeps the layer-shell surface but
masks input to Kadunce's negotiated guest geometry. Neither mode reserves
workspace. Dismissal normally ends the process; an outstanding asynchronous file
operation may keep its event loop alive after the surface hides.

## Ownership boundaries

Tettegouche owns launcher invocation and presentation, search and application
catalogue queries, result selection, ordinary application launch, local Files
state and operations, related-setting context, Ambient ranking/presentation,
and interpretation of Kadunce's published integration schemas.

Kadunce exclusively owns KWin discovery, live window identity, cards, stacks,
focus, output state, existing-window activation, guest placement, neighboring
card motion, and the final Card Line selection. Tettegouche never performs raw
KWin discovery or inserts its guest into Kadunce's persistent card model.

Source applications and KDE services own activity truth and supported actions.
Temperance owns notifications and transient event presentation; Tettegouche does
not duplicate that history in Ambient.

## Kadunce integration

At open time the launcher negotiates Kadunce launcher-guest protocol 3 and reads
workspace-context schema version 1. Unsupported, absent, or malformed endpoints
fall back to the standalone launcher. Context refreshes on Kadunce change signals
and before window selection; there is no timer or heartbeat.

Open application matches carry a live window identifier. Tettegouche asks Kadunce
to activate that exact window. New launches may hold the guest until Kadunce sees
a matching window; a bounded timeout returns to search. Horizontal guest drag
sends only motion deltas, leaving commit/cancel and real-card selection to
Kadunce. Expanded Apps and Files drawers request the negotiated presentation
capability and otherwise use standalone expansion.

## Search and catalogue

The compact search model combines an allowlisted set of KRunner providers and a
Tettegouche-owned confidence policy. Selection is pinned by destination identity
so late results cannot redirect an activated row. Search remains local until the
user explicitly submits an empty eligible result set to the browser. The
behavioral authority is [SEARCH-CONTRACT.md](SEARCH-CONTRACT.md).

The Browse drawer reads visible applications from `KApplicationTrader`, sorts by
display name, and launches with `KIO::ApplicationLauncherJob`. It has no usage,
recency, or recommendation layer. Existing-window matching runs before launch.

## Files

`FileBrowser` owns local directory listing, tabs, navigation, selection,
clipboard and KIO jobs. `FilesPane.qml` renders that state. Listings are
asynchronous and generation-guarded; saved locations are not synchronously
probed during launcher startup. Writes never use an overwrite flag, never invoke
a shell, and may defer process exit. The complete behavioral and safety boundary
is [FILES-CONTRACT.md](FILES-CONTRACT.md).

## Ambient activity

The applet constructs one shared activity model per Plasma process. It combines
MPRIS sessions, Plasma's shared desktop-jobs model, Tette's revisioned operation
bridge, and nonblocking filesystem observation of direct Downloads children.
Rows preserve source authority and generation-check actions. The compositor
reserves activity cores before revealing optional context and keeps the center
task dock physically stable. See [AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md).

## Related settings

Related-setting children are read-only context keyed by stable setting IDs.
They may open the parent settings page but never mutate a device or system state.
Most providers are lazy per-launcher snapshots; Bluetooth is event-driven. See
[RELATED-SETTINGS.md](RELATED-SETTINGS.md).

## Verification boundaries

Native tests cover search policy, workspace schema, Files operations, related
providers, activity providers, and icon rendering. QML and private-bus tests
cover launcher controls, Ambient composition, panel geometry/input, and package
integration. Disposable fixtures must not write or delete real user files.
