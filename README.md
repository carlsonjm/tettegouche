<p align="center">
  <img src="assets/studio.warbler.tettegouche-logo.png" width="180" alt="Tettegouche widget icon">
</p>

# Tettegouche

Just type. Tettegouche brings apps, files, settings, and web search into one
focused search surface for KDE Plasma. Jump into an open app, find your files,
or go straight to the settings for a connected device. When nothing local
matches, continue in your default browser. Built for touch, keyboard, and mouse,
it opens on demand and gets out of your way when dismissed.

The supplied photo logo identifies the package and widget picker. The live panel
keeps its independent dimple and ripple. The installer also retires the previous
scalable picker icon into a backup, since Plasma prioritizes plugin-ID artwork
over the metadata icon name.

When Kadunce is running, Tettegouche reads its versioned workspace snapshot to
identify applications that are already open and asks Kadunce to activate the
exact existing window. Kadunce remains the sole owner of window and card state;
Tettegouche still works as a normal launcher when that optional context is
unavailable.

## Current seed

- Manual, application-first launch surface.
- Native Plasma panel entry with right-click configuration.
- Pull-up alphabetical application drawer with no behavioral ranking.
- Keyboard, pointer, and touch-friendly result selection.
- Versioned Kadunce context with exact existing-window activation.
- Version-gated Kadunce guest card with a horizontal Card Line handoff.
- Graceful standalone behavior without Kadunce.
- No background service, compositor polling, or workspace mutation.

Open matches are activated through Kadunce and unmatched results use Plasma's
normal application action. With a compatible Kadunce version, Tettegouche can
temporarily occupy Card Line's center without joining its card model. Older or
missing Kadunce versions always receive the standalone launcher.

At rest, users can type immediately or pull the **Browse everything** grabber
upward. The drawer reads Plasma's installed application catalogue, excludes
hidden entries, sorts by display name, and launches through KDE's normal
application job. Search filters an open drawer in place; search from the resting
card retains the compact ranked-results view.

## Build and run

```bash
./install.sh
```

The installer builds and tests the project, then installs its native Plasma
applet and launcher. Restart Plasma to load the new plugin. Existing Tettegouche
panel widgets stay in place. For a first install, open panel edit mode, choose **Add Widgets**, search for
**Tettegouche**, and add it to the panel. Right-click the widget and choose
**Configure Tettegouche** to disable optional Kadunce Card Line integration or
launcher motion. Run `./uninstall.sh` to remove the installed files without
deleting this checkout.

Tettegouche requires KDE Plasma on Wayland, Qt 6, KDE Frameworks 6,
LayerShellQt, BluezQt, Solid, CMake, and a C++20 compiler. Bluetooth hardware is optional;
connected-device context is omitted when unavailable.

Related setting information uses existing local services and optional read-only
tools (`pactl`, `nmcli`, `kscreen-doctor`, `powerprofilesctl`, `lpstat`, and
`kdeconnect-cli`). Missing tools omit those child rows, not the setting itself.

## Project layout

```text
src/                    native launcher and context boundary
qml/                    on-demand launcher surface
applet/                 native panel entry and configuration
tests/                  context tests, Plasma panel/input tests, source checks
install.sh              verified native Plasma installation path
uninstall.sh            remove the installed launcher
```

## License

Tettegouche is licensed under GPL-2.0-or-later.
