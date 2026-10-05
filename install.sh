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

# Remove obsolete loose-QML installation paths before installing the native applet.
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/studio.warbler.tettegouche"
rm -f "${HOME}/.local/bin/tettegouche"
rm -f "${HOME}/.local/share/applications/io.github.carlsonjm.Tettegouche.desktop"
# Shuffle's install key, where it is set up, installs with no password: the
# build is laid out here with this account's own rights, and a root-owned helper
# takes the files as a stream and puts only Tettegouche's own in place. It also
# retires the old widget artwork, as the branch below does.
install_key=/usr/local/libexec/shuffle/install-step
if [[ -x "${install_key}" ]] \
        && sudo -n -l "${install_key}" tettegouche install >/dev/null 2>&1; then
    stage="$(mktemp -d "${TMPDIR:-/tmp}/tettegouche-stage.XXXXXX")"
    trap 'rm -rf -- "${stage}"' EXIT
    # An earlier install with sudo left this list owned by root.
    rm -f -- "${build_dir}/install_manifest.txt"
    DESTDIR="${stage}" cmake --install "${build_dir}" >/dev/null
    tar -C "${stage}" -cf - . | sudo -n "${install_key}" tettegouche install
else
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
fi
kbuildsycoca6

echo "Tettegouche installed. Restart Plasma to load the update; existing panel widgets stay in place."
