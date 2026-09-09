#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
    CMakeLists.txt
    LICENSE
    README.md
    io.github.carlsonjm.Tettegouche.desktop
    src/main.cpp
    src/WorkspaceContext.cpp
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
rg -q 'No background service' "${project_root}/README.md"

echo "Tettegouche package checks passed."
