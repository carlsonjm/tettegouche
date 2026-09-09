#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
    CMakeLists.txt
    LICENSE
    README.md
    io.github.carlsonjm.Tettegouche.desktop
    applet/main.qml
    applet/ConfigGeneral.qml
    applet/config.qml
    applet/main.xml
    assets/studio.warbler.tettegouche.svg
    src/TettegoucheApplet.cpp
    src/TettegoucheApplet.h
    src/metadata.json
    src/main.cpp
    src/ApplicationCatalog.cpp
    src/ApplicationCatalog.h
    src/WorkspaceContext.cpp
    tests/PanelAppletTest.cpp
    tests/run-panel-test.sh
    tests/panel-test-bus.conf
    qml/Launcher.qml
    docs/ARCHITECTURE.md
    install.sh
    uninstall.sh
)

for path in "${required[@]}"; do
    test -f "${project_root}/${path}" || {
        echo "Missing package file: ${path}" >&2
        exit 1
    }
done

test ! -e "${project_root}/tettegouche.service"
rg -q '^Exec=tettegouche$' \
    "${project_root}/io.github.carlsonjm.Tettegouche.desktop"
rg -q '^NoDisplay=true$' \
    "${project_root}/io.github.carlsonjm.Tettegouche.desktop"
rg -q 'plasma_add_applet' "${project_root}/CMakeLists.txt"
rg -q 'KDE_INSTALL_ICONDIR.*/hicolor/scalable/apps' \
    "${project_root}/CMakeLists.txt"
rg -q 'K_PLUGIN_CLASS_WITH_JSON' \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q 'No background service' "${project_root}/README.md"
rg -q 'KF6::KIOGui' "${project_root}/CMakeLists.txt"
rg -q 'KF6::Service' "${project_root}/CMakeLists.txt"

echo "Tettegouche package checks passed."
