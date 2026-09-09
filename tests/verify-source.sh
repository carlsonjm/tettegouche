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

echo "Tettegouche source checks passed."
