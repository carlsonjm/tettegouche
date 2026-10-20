#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

if rg -n -i 'webos|project[[:space:]_-]*webos|ghostiepost|palm|chromeos' \
    --glob '!build*/**' --glob '!tests/verify-source.sh' .; then
    echo "Retired product identity found in the Tettegouche source tree." >&2
    exit 1
fi

# Files is the file manager's one name in what a person reads.
if rg -n -i 'tette[[:space:]]+files' --glob '!build*/**' --glob '!tests/verify-source.sh' .; then
    echo "Files carries a retired name." >&2
    exit 1
fi

# Kadunce's launcher-guest handshake, the calls the launcher makes as it
# opens, launches and closes, and what is open, are exercised by
# launcher-controller-test against a stand-in Kadunce.
rg -q 'co\.goodinput\.kadunce\.workspace-context' \
    "${project_root}/src/WorkspaceContext.cpp"
rg -q 'SupportedVersion = 1' "${project_root}/src/WorkspaceContext.cpp"
rg -q 'enabled: root\.launcherController\.guestMode' \
    "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.OutBack' "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.InCubic' "${project_root}/qml/Launcher.qml"
# The sheet keeps the suite's dark values on a dark colour scheme, leaning
# with its tint.
rg -q 'surfaceColor: tone\.surface' "${project_root}/qml/Launcher.qml"
rg -q 'surfaceOutline: tone\.outline' "${project_root}/qml/Launcher.qml"
rg -q 'controlColor: tone\.control' "${project_root}/qml/Launcher.qml"
rg -q 'surface: dark \? suite\("#141414"\)' "${project_root}/qml/SearchColors.qml"
rg -q 'outline: dark \? suite\("#5a5a5a"\)' "${project_root}/qml/SearchColors.qml"
rg -q 'control: dark \? suite\("#242424"\)' "${project_root}/qml/SearchColors.qml"
rg -q 'paperRadius: 10' "${project_root}/qml/Launcher.qml"
rg -q 'contentInset: 24' "${project_root}/qml/Launcher.qml"
# KWin's open animation takes no utility surface: Search does not zoom in.
rg -Fq 'setScope(QStringLiteral("utility"))' "${project_root}/src/main.cpp"
rg -q 'applicationLaunchPending' "${project_root}/qml/Launcher.qml"
rg -q 'interval: 10000' "${project_root}/qml/Launcher.qml"
rg -q 'centroid\.velocity\.x' "${project_root}/qml/Launcher.qml"
rg -Fq 'words.i18n("Just type")' "${project_root}/qml/SearchField.qml"
rg -q 'Q_INVOKABLE void showInputMethod' "${project_root}/src/LauncherController.h"
rg -q 'launcherController\.showInputMethod\(\)' \
    "${project_root}/qml/SearchField.qml"
rg -q 'required property var applicationCatalog' \
    "${project_root}/qml/Launcher.qml"
# Search's modes run along its top, the dot returning to search, and an open
# drawer has no Close drawer pill.
rg -Fq 'objectName: "mode-row"' "${project_root}/qml/ModeRow.qml"
rg -Fq 'objectName: "home-dot"' "${project_root}/qml/ModeRow.qml"
if rg -Fq 'Close drawer' "${project_root}/qml/"; then
    echo "An open drawer closes by the dot or its top edge, not a Close drawer pill" >&2
    exit 1
fi
rg -q 'Q_PROPERTY\(int sortOrder' \
    "${project_root}/src/ApplicationCatalog.h"
rg -q 'setFilterText' "${project_root}/src/ApplicationCatalog.cpp"
rg -Fq 'objectName: "sort-button"' \
    "${project_root}/qml/Launcher.qml"
rg -q 'property: "drawerProgress"' "${project_root}/qml/Launcher.qml"
rg -q 'KApplicationTrader::query' \
    "${project_root}/src/ApplicationCatalog.cpp"
rg -q 'KIO::ApplicationLauncherJob' \
    "${project_root}/src/ApplicationCatalog.cpp"
rg -q 'activateCatalogIfOpen' "${project_root}/qml/Launcher.qml"
rg -q '\-\-standalone' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q 'cfg_useKadunce' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -Fq 'Q_PROPERTY(bool launcherActive' \
    "${project_root}/src/TettegoucheApplet.h"
# Panel rendering and input are exercised by panel-applet-test through Plasma.
rg -q 'cfg_animateIndicator' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q 'cfg_showAmbient' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q 'cfg_offerRecent' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q 'cfg_recentApps' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q 'cfg_recentFiles' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q '\-\-no-recent-apps' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q '\-\-no-recent-files' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q '\-\-no-recent' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q 'cfg_offerNotes' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q '\-\-no-notes' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"

echo "Tettegouche source checks passed."
