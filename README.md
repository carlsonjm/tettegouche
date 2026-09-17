<p align="center">
  <img src="assets/studio.warbler.tettegouche-logo.png" width="180" alt="Tettegouche widget icon">
</p>

# Tettegouche

Tettegouche is a touch-first KDE Plasma launcher for applications, files,
settings, and deliberate web search. Its panel applet also presents current
media and transfer activity in a responsive Ambient strip.

The launcher works by itself. When a compatible Kadunce session is present, it
uses Kadunce's versioned workspace context to activate exact existing windows
and may temporarily occupy Card Line as a guest. Kadunce remains the only owner
of windows, cards, stacks, focus, and output state.

## Current capabilities

- Ranked local search across applications, indexed filenames, KDE settings,
  calculator, and unit conversion, with an explicit browser fallback.
- An alphabetical installed-application drawer with no usage ranking.
- A local Files drawer with tabs, history, breadcrumbs, filtering, sorting,
  selection, default-app opening, copy/move, rename, folders, drag-copy, Trash,
  and last-item recovery.
- Read-only related context for supported settings such as Bluetooth, sound,
  networking, displays, power, printers, storage, and default applications.
- A responsive Ambient panel surface for MPRIS sessions, shared Plasma desktop
  jobs, Tette-owned file operations, and observed arrivals in Downloads.
- Keyboard, pointer, and touch interaction; Meta/panel invocation toggles the
  launcher and exposes it above fullscreen applications.

No background service, usage-learning database, compositor polling, or
workspace mutation is introduced. Missing optional services remove only their
associated context.

## Build and install

```bash
./install.sh
```

The installer builds and tests the project, then installs the launcher and
native Plasma applet. Restart Plasma to load the plugin. For a first install,
open panel edit mode, choose **Add Widgets**, search for **Tettegouche**, and add
it to the panel. The widget configuration can disable Kadunce integration and
launcher motion. Run `./uninstall.sh` to remove installed files without deleting
the checkout.

Requirements: KDE Plasma on Wayland, Qt 6, KDE Frameworks 6, LayerShellQt,
BluezQt, Solid, CMake, and a C++20 compiler. Bluetooth hardware and Kadunce are
optional. Some related-setting rows use optional read-only local tools; absence
of a tool omits those rows.

## Repository map

```text
src/          native launcher, search, Files, integration, and activity providers
qml/          launcher and Files presentation
applet/       Plasma panel entry, Ambient surface, and configuration
tests/        native, QML, private-bus, packaging, and source checks
docs/         current state, roadmap, architecture, contracts, and opt-in archive
```

Start with [the documentation index](docs/README.md). Tettegouche is licensed
under GPL-2.0-or-later.
