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

rg -q 'QStringLiteral\("workspaceContext"\)' "${project_root}/src/main.cpp"
rg -q 'studio\.warbler\.kadunce\.workspace-context' \
    "${project_root}/src/WorkspaceContext.cpp"
rg -q 'SupportedVersion = 1' "${project_root}/src/WorkspaceContext.cpp"
rg -q 'Q_INVOKABLE void finishLaunch\(\)' "${project_root}/src/main.cpp"
rg -Fq 'QTimer::singleShot(750' "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("activateApplicationWindow"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("launcherGuestProtocolVersion"\)' \
    "${project_root}/src/main.cpp"
rg -q 'protocol\.value\(\) != 3' "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("beginLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'sessionBus\(\)\.baseService\(\)' "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("updateLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("finishLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("endLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("prepareLauncherGuestLaunch"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("cancelLauncherGuestLaunch"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QDBusConnection::ExportScriptableSlots' "${project_root}/src/main.cpp"
rg -q 'Q_INVOKABLE void completeGuestHandoff' "${project_root}/src/main.cpp"
rg -q 'Q_SCRIPTABLE void completeGuestNavigation' \
    "${project_root}/src/main.cpp"
rg -q 'enabled: root\.launcherController\.guestMode' \
    "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.OutBack' "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.InCubic' "${project_root}/qml/Launcher.qml"
# The sheet keeps the suite's dark values on a dark colour scheme.
rg -q 'surfaceColor: tone\.surface' "${project_root}/qml/Launcher.qml"
rg -q 'surfaceOutline: tone\.outline' "${project_root}/qml/Launcher.qml"
rg -q 'controlColor: tone\.control' "${project_root}/qml/Launcher.qml"
rg -q 'surface: dark \? "#141414"' "${project_root}/qml/SearchColors.qml"
rg -q 'outline: dark \? "#5a5a5a"' "${project_root}/qml/SearchColors.qml"
rg -q 'control: dark \? "#242424"' "${project_root}/qml/SearchColors.qml"
rg -q 'paperRadius: 8' "${project_root}/qml/Launcher.qml"
rg -q 'contentInset: 22' "${project_root}/qml/Launcher.qml"
rg -q 'applicationLaunchPending' "${project_root}/qml/Launcher.qml"
rg -q 'interval: 10000' "${project_root}/qml/Launcher.qml"
rg -q 'centroid\.velocity\.x' "${project_root}/qml/Launcher.qml"
rg -Fq 'text: words.i18n("Just type")' "${project_root}/qml/Launcher.qml"
rg -q 'Q_INVOKABLE void showInputMethod' "${project_root}/src/main.cpp"
rg -q 'launcherController\.showInputMethod\(\)' \
    "${project_root}/qml/Launcher.qml"
rg -q 'required property var applicationCatalog' \
    "${project_root}/qml/Launcher.qml"
# An open drawer's header holds Back on the left and no Close drawer pill.
rg -Fq 'objectName: "drawer-back"' "${project_root}/qml/Launcher.qml"
rg -Fq 'glyph: "chevron-left"' "${project_root}/qml/Launcher.qml"
if rg -Fq 'Close drawer' "${project_root}/qml/Launcher.qml"; then
    echo "An open drawer closes by Back or its top edge, not a Close drawer pill" >&2
    exit 1
fi
rg -q 'Q_PROPERTY\(int sortOrder' \
    "${project_root}/src/ApplicationCatalog.h"
rg -q 'setFilterText' "${project_root}/src/ApplicationCatalog.cpp"
rg -q 'view-sort-descending-symbolic' \
    "${project_root}/qml/Launcher.qml"
rg -q 'property: "drawerProgress"' "${project_root}/qml/Launcher.qml"
rg -q 'KApplicationTrader::query' \
    "${project_root}/src/ApplicationCatalog.cpp"
rg -q 'KIO::ApplicationLauncherJob' \
    "${project_root}/src/ApplicationCatalog.cpp"
rg -q 'activateCatalogIfOpen' "${project_root}/src/main.cpp" \
    "${project_root}/qml/Launcher.qml"
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
rg -q '\-\-no-recent' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"
rg -q 'cfg_offerNotes' \
    "${project_root}/applet/ConfigGeneral.qml"
rg -q '\-\-no-notes' "${project_root}/src/main.cpp" \
    "${project_root}/src/TettegoucheApplet.cpp"

echo "Tettegouche source checks passed."
