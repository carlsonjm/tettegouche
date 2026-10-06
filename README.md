<p align="center">
  <img src="assets/studio.warbler.tettegouche-logo.png" width="180" alt="Tettegouche">
</p>

# Tettegouche

Tettegouche is a touch-oriented Search and file launcher for KDE Plasma. It helps
you find, launch, browse, and act without sorting through separate menus.

Its panel island also shows current media and file activity. Tettegouche works with
touch, a pointer, or a keyboard. No background service is required.

## Controls

| Task | Touch | Keyboard |
| --- | --- | --- |
| Search | Tap the dot | `Meta`, once set in Plasma |
| Apps | Tap Apps in Search | `Meta+G` |
| Files | Tap Files in Search | `Meta+E` |
| Ambient | Tap the island | — |

`Meta+G` and `Meta+E` are listed under Tettegouche, or Search where Shuffle is
installed, in System Settings' Shortcuts, where you can change them. Dolphin
takes `Meta+E` when it is installed; give the key to Tettegouche there. Every other input is in [docs/INPUT.md](docs/INPUT.md).

## Search

Tap the dot in the panel. Before you type, Search offers Apps and Files, Notes
where Gooseberry is installed, and beside them what you used lately: files, and
applications that are not already open or pinned in the dock. Start typing and
Search can find:

- Installed applications
- Indexed files and recent documents
- KDE settings
- Calculator results
- Unit conversions

Local results appear first. If nothing local matches, submitting the query can open
it in your web browser. Tettegouche does not learn from or rank results by your
usage history.

**Apps** opens an alphabetical list of installed applications when you would
rather look than search.

## Files

**Files** is a local file browser inside Tettegouche. It includes Places,
tabs, history, breadcrumbs, filtering, sorting, selection, and hidden-file display.

You can open, copy, move, rename, and delete files; create folders; drag files
between folders and to or from other applications; open drives and phones, and
eject drives; and recover the last item Tettegouche sent to Trash. File work
continues safely if you close Search while an operation is running.

Tettegouche currently focuses on local files; what Files does not yet do is
listed in [docs/FILES-CONTRACT.md](docs/FILES-CONTRACT.md).

## Live activity

The Ambient island in the panel shows useful activity while it is happening:

- Music and other media sessions
- Plasma file and desktop jobs
- Copy and move operations started in Tettegouche
- New files arriving in Downloads
- A drive or memory card plugged in: one tap opens it in Files
- A screen shared or recorded through Plasma's portal, with Stop
- An application waiting on you: one tap brings it and its dialog forward

Available controls come from the application or service responsible for the
activity. Tettegouche removes an item when its source disappears and does not claim
that an unknown operation completed successfully.

Each kind of activity is its own island, side by side and centred in the room
the panel gives them, clear so the panel shows through. When they share the
room, each gives up names first and keeps its buttons at its end. A tap opens
an island in place, larger, with the media's art, position and controls or each
transfer's own actions; a sideways flick sets one aside.

## Related settings

Search can include useful information from supported Bluetooth, sound, network,
display, power, printer, storage, KDE Connect, default-application, and Night Light
settings.

These results open the appropriate KDE settings page. Tettegouche does not silently
pair devices, connect networks, mount storage, change displays, or alter power
settings.

## Kadunce integration

Tettegouche works on its own. If Kadunce is available, Search can open an existing
application Card instead of launching a duplicate window. Expanded Apps and Files
views can also use the space Kadunce provides.

If Kadunce is missing or incompatible, Tettegouche returns to its normal standalone
window.

## Install

```bash
./install.sh
```

The installer builds and tests Tettegouche, installs the launcher and Plasma
widget, then restarts the panel so it runs the new widget. On a first install,
open panel edit mode, choose **Add Widgets**, search for **Tettegouche**, and add
it to the panel.

```bash
./uninstall.sh
```

Uninstalling removes the installed files without deleting this source folder.

## Requirements

- KDE Plasma 6.7 or newer, on Wayland
- Qt 6.10 and KDE Frameworks 6.26, or newer
- LayerShellQt 6.7, BluezQt, Solid, and AppStreamQt 1.0
- CMake and a C++20 compiler
- gettext, for translations and the checks on them

Bluetooth hardware and Kadunce are optional. Some related-setting results use
optional local system tools; those results are simply omitted when a tool is not
available.

## Development

Read `AGENTS.md` before working in this repository. The documentation index is in
`docs/README.md`.

```text
src/          launcher, Search, Files, integration, and activity providers
qml/          Search and Files presentation
applet/       panel entry, Ambient island, and configuration
tests/        native, QML, private-session, packaging, and source checks
docs/         current contracts, architecture, and roadmap
```

Run the repository checks before proposing a build:

```bash
./verify.sh
```

GitHub runs the same checks on every pull request and on `main`, against the
Qt and KDE packages Arch Linux ships at the time.

## License

Tettegouche is licensed under GPL-2.0-or-later.

The project names and marks are not covered by that licence. See
[TRADEMARKS.md](TRADEMARKS.md).
