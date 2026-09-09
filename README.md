# Tettegouche

Tettegouche is a focused application launcher for KDE Plasma. It opens on
demand, searches installed applications, and exits when dismissed.

When Kadunce is running, Tettegouche reads its versioned workspace snapshot to
identify applications that are already open. Kadunce remains the sole owner of
window and card state; Tettegouche still works as a normal launcher when that
optional context is unavailable.

## Current seed

- Manual, application-first launch surface.
- Keyboard, pointer, and touch-friendly result selection.
- Read-only Kadunce context with strict schema-version validation.
- Graceful standalone behavior without Kadunce.
- No background service, compositor polling, or workspace mutation.

The initial context contract is deliberately read-only. An exact **focus an
existing card** action will be added only after that command has a defined and
tested Kadunce contract. Until then, an open application is labeled and the
normal Plasma application action is used.

## Build and run

```bash
./install.sh
```

The installer builds and tests the project, then installs it for the current
user. Open **Tettegouche** from Plasma's application launcher. Run
`./uninstall.sh` to remove the installed files without deleting this checkout.

Tettegouche requires KDE Plasma on Wayland, Qt 6, KDE Frameworks 6,
LayerShellQt, CMake, and a C++20 compiler.

## Project layout

```text
src/                    native launcher and context boundary
qml/                    on-demand launcher surface
tests/                  context parser tests and source checks
install.sh              verified per-user installation path
uninstall.sh            remove the installed launcher
```

## License

Tettegouche is licensed under GPL-2.0-or-later.
