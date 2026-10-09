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
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/co.goodinput.tettegouche"
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
    sed -i "s|^${stage}||" "${build_dir}/install_manifest.txt"
else
    sudo cmake --install "${build_dir}"
    # The widget picker prioritizes the plugin-ID icon over metadata.Icon. An old
    # scalable dimple would mask the new photo at small sizes; preserve then retire it.
    old_picker=/usr/share/icons/hicolor/scalable/apps/co.goodinput.tettegouche.svg
    if [[ -f $old_picker && ! -L $old_picker ]]; then
        artwork_backup=$(sudo mktemp -d /var/tmp/tettegouche-artwork-backup.XXXXXX)
        sudo cp --preserve=all -- "$old_picker" "$artwork_backup/"
        sudo rm -- "$old_picker"
        echo "Previous widget artwork backed up to $artwork_backup"
    fi
fi
kbuildsycoca6

# A restarted shell has sometimes come back not knowing the current activity,
# and then shows no desktop on any screen until the activity is announced
# again. Once the shell answers, make sure it knows.
announce_activity() {
    command -v qdbus6 >/dev/null 2>&1 || return 0
    local shell_activity="" tries=0
    while (( tries < 40 )); do
        if shell_activity="$(qdbus6 org.kde.plasmashell /PlasmaShell \
                org.kde.PlasmaShell.evaluateScript 'print(currentActivity())' 2>/dev/null)"; then
            break
        fi
        sleep 0.25
        tries=$((tries + 1))
    done
    if [[ -z "${shell_activity}" ]]; then
        local current
        current="$(qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
            org.kde.ActivityManager.Activities.CurrentActivity 2>/dev/null || true)"
        if [[ -z "${current}" ]]; then
            current="$(qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
                org.kde.ActivityManager.Activities.ListActivities 2>/dev/null | head -n 1 || true)"
        fi
        [[ -n "${current}" ]] && qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
            org.kde.ActivityManager.Activities.SetCurrentActivity "${current}" >/dev/null 2>&1 || true
    fi
}

# The shell keeps the widget it loaded, so it restarts to run the new one.
# Windows and the session stay as they are.
widget="$(grep -m1 '/plasma/applets/co\.goodinput\.tettegouche\.so$' \
    "${build_dir}/install_manifest.txt" || true)"
if systemctl --user --quiet is-active plasma-plasmashell.service 2>/dev/null; then
    systemctl --user restart plasma-plasmashell.service
    announce_activity
    shell_pid="$(systemctl --user show --property=MainPID --value plasma-plasmashell.service)"
    mapped=""
    for _ in $(seq 40); do
        if [[ -n "${widget}" && "${shell_pid}" != 0 ]] \
                && mapped="$(grep -F "${widget}" "/proc/${shell_pid}/maps" 2>/dev/null)"; then
            break
        fi
        sleep 0.25
    done
    if [[ -z "${mapped}" ]]; then
        echo "Tettegouche installed and the panel restarted. The widget is not on a panel, so nothing else needed loading."
    elif grep -qF '(deleted)' <<<"${mapped}"; then
        echo "Tettegouche installed, but the restarted panel still holds the previous widget. Sign out and back in to load it." >&2
        exit 1
    else
        echo "Tettegouche installed. The panel restarted and is running the new widget; existing panel widgets stay in place."
    fi
else
    echo "Tettegouche installed. The panel is not running here, so the new widget loads at the next sign-in."
fi
