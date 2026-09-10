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
# The widget picker prioritizes the plugin-ID icon over metadata.Icon. An old
# scalable dimple would mask the new photo at small sizes; preserve then retire it.
old_picker=/usr/share/icons/hicolor/scalable/apps/studio.warbler.tettegouche.svg
if [[ -f $old_picker && ! -L $old_picker ]]; then
    artwork_backup=$(sudo mktemp -d /var/tmp/tettegouche-artwork-backup.XXXXXX)
    sudo cp --preserve=all -- "$old_picker" "$artwork_backup/"
    sudo rm -- "$old_picker"
    echo "Previous widget artwork backed up to $artwork_backup"
fi
kbuildsycoca6

echo "Tettegouche installed. Restart Plasma to load the update; existing panel widgets stay in place."
