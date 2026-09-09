#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
    CMakeLists.txt
    LICENSE
    README.md
    io.github.carlsonjm.Tettegouche.desktop
    src/main.cpp
    src/ApplicationCatalog.cpp
    src/ApplicationCatalog.h
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
rg -q 'KF6::KIOGui' "${project_root}/CMakeLists.txt"
rg -q 'KF6::Service' "${project_root}/CMakeLists.txt"

echo "Tettegouche package checks passed."
