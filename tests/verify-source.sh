#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -n -i 'webos|project[[:space:]_-]*webos|ghostiepost|palm|chromeos|just[[:space:]_-]*type' \
    --glob '!build/**' --glob '!tests/verify-source.sh' "${project_root}"; then
    echo "Retired product identity found in the Tettegouche source tree." >&2
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
rg -q 'protocol\.value\(\) != 1' "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("beginLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'sessionBus\(\)\.baseService\(\)' "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("updateLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("finishLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QStringLiteral\("endLauncherGuest"\)' \
    "${project_root}/src/main.cpp"
rg -q 'QDBusConnection::ExportScriptableSlots' "${project_root}/src/main.cpp"
rg -q 'Q_INVOKABLE void completeGuestHandoff' "${project_root}/src/main.cpp"
rg -q 'enabled: root\.launcherController\.guestMode' \
    "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.OutBack' "${project_root}/qml/Launcher.qml"
rg -q 'Easing\.InCubic' "${project_root}/qml/Launcher.qml"
rg -q 'surfaceColor: "#141414"' "${project_root}/qml/Launcher.qml"
rg -q 'surfaceOutline: "#333333"' "${project_root}/qml/Launcher.qml"
rg -q 'controlColor: "#242424"' "${project_root}/qml/Launcher.qml"
rg -q 'cardRadius: 10' "${project_root}/qml/Launcher.qml"
rg -q 'contentInset: 22' "${project_root}/qml/Launcher.qml"

echo "Tettegouche source checks passed."
