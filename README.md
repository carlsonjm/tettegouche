<p align="center">
  <img src="assets/studio.warbler.tettegouche-logo.png" width="180" alt="Tettegouche">
</p>

# Tettegouche

Tettegouche is a touch-oriented Search and file launcher for KDE Plasma. It helps
you find, launch, browse, and act without sorting through separate menus.

Its panel strip also shows current media and file activity. Tettegouche works with
touch, a pointer, or a keyboard. No background service is required.

## Search

Open Tettegouche from its panel button or with the Meta key, then start typing.
Search can find:

- Installed applications
- Indexed files and recent documents
- KDE settings
- Calculator results
- Unit conversions

Local results appear first. If nothing local matches, submitting the query can open
it in your web browser. Tettegouche does not learn from or rank results by your
usage history.

**Browse everything** opens an alphabetical list of installed applications when
you would rather look than search.

## Files

**Explore files** is a local file browser inside Tettegouche. It includes Places,
tabs, history, breadcrumbs, filtering, sorting, selection, and hidden-file display.

You can open, copy, move, rename, and delete files; create folders; drag files
between folders; and recover the last item Tettegouche sent to Trash. File work
continues safely if you close the launcher while an operation is running.

Tettegouche currently focuses on local files. File previews, recursive search,
Open With, properties, external drag and drop, network locations, and a complete
Trash browser are planned work.

## Live activity

The Ambient strip in the panel shows useful activity while it is happening:

- Music and other media sessions
- Plasma file and desktop jobs
- Copy and move operations started in Tettegouche
- New files arriving in Downloads

Available controls come from the application or service responsible for the
activity. Tettegouche removes an item when its source disappears and does not claim
that an unknown operation completed successfully.

The strip adjusts to the available panel width. It keeps essential controls first,
then adds titles, artists, filenames, progress, and duration when space allows.

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

The installer builds and tests Tettegouche, then installs the launcher and Plasma
widget. Restart Plasma after installation. On a first install, open panel edit mode,
choose **Add Widgets**, search for **Tettegouche**, and add it to the panel.

Widget settings can disable Kadunce integration and launcher motion.

```bash
./uninstall.sh
```

Uninstalling removes the installed files without deleting this source folder.

## Requirements

- KDE Plasma on Wayland
- Qt 6 and KDE Frameworks 6
- LayerShellQt, BluezQt, and Solid
- CMake and a C++20 compiler

Bluetooth hardware and Kadunce are optional. Some related-setting results use
optional local system tools; those results are simply omitted when a tool is not
available.

## Development

Read `AGENTS.md` before working in this repository. The documentation index is in
`docs/README.md`.

```text
src/          launcher, Search, Files, integration, and activity providers
qml/          Search and Files presentation
applet/       panel entry, Ambient strip, and configuration
tests/        native, QML, private-session, packaging, and source checks
docs/         current contracts, architecture, roadmap, and archive
```

Run the repository checks before proposing a build:

```bash
./verify.sh
```

## License

Tettegouche is licensed under GPL-2.0-or-later.
