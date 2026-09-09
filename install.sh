#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${project_root}/build"

"${project_root}/tests/verify-source.sh"
"${project_root}/tests/verify-package.sh"
cmake -S "${project_root}" -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "${build_dir}" -j"$(nproc)"
ctest --test-dir "${build_dir}" --output-on-failure

# Remove the short-lived loose-QML package before installing the native applet.
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/studio.warbler.tettegouche"
rm -f "${HOME}/.local/bin/tettegouche"
rm -f "${HOME}/.local/share/applications/io.github.carlsonjm.Tettegouche.desktop"
sudo cmake --install "${build_dir}"
kbuildsycoca6

echo "Tettegouche installed. Restart Plasma to load the update; existing panel widgets stay in place."
