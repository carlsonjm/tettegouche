#!/usr/bin/env bash
# Runs the Files checks that write to Trash, Ark's settings or the default
# applications, on a private bus with a throwaway home made on the home
# filesystem, so Trash stays on one filesystem and the person's own Trash and
# settings are never touched.
set -euo pipefail

test_binary="$1"

if [[ "${2:-}" != "--inside" ]]; then
    base="${XDG_CACHE_HOME:-${HOME}/.cache}"
    mkdir -p -- "${base}"
    work="$(mktemp -d "${base}/tette-trash-test.XXXXXX")"
    trap 'rm -rf -- "${work}"' EXIT
    mkdir -p "${work}/runtime" "${work}/home" "${work}/tmp"
    chmod 700 "${work}/runtime"
    cat > "${work}/bus.conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
CONF
    env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE \
        HOME="${work}/home" TMPDIR="${work}/tmp" XDG_RUNTIME_DIR="${work}/runtime" \
        XDG_STATE_HOME="${work}/state" XDG_CONFIG_HOME="${work}/config" XDG_DATA_HOME="${work}/data" \
        XDG_CACHE_HOME="${work}/cache" QT_QPA_PLATFORM=offscreen TETTE_SEALED=1 \
        dbus-run-session --config-file="${work}/bus.conf" -- bash "$0" "${test_binary}" --inside
    exit
fi

"${test_binary}" renameMoveTrash staleTrashRecordStepsAside emptyTrash openWithAlways compressAndExtract

# Drives, on Solid's stand-in hardware instead of the machine's own: a built-in
# drive, a USB stick to mount in the throwaway home, one hidden in Dolphin and
# one the system ignores.
stick="${HOME}/media/STICK"
mkdir -p -- "${stick}"
hardware="${HOME}/hardware.xml"
volume() { # udi label mounted mount-point ignored parent
    cat <<XML
  <device udi="/org/kde/solid/fakehw/$1">
    <property key="name">$2</property>
    <property key="interfaces">Block,StorageVolume,StorageAccess</property>
    <property key="parent">/org/kde/solid/fakehw/$6</property>
    <property key="isIgnored">$5</property>
    <property key="isMounted">$3</property>
    <property key="mountPoint">$4</property>
    <property key="usage">filesystem</property>
    <property key="fsType">vfat</property>
    <property key="label">$2</property>
  </device>
XML
}
drive() { # udi removable bus
    cat <<XML
  <device udi="/org/kde/solid/fakehw/$1">
    <property key="interfaces">Block,StorageDrive</property>
    <property key="parent">/org/kde/solid/fakehw/computer</property>
    <property key="bus">$3</property>
    <property key="driveType">disk</property>
    <property key="isRemovable">$2</property>
    <property key="isHotpluggable">$2</property>
  </device>
XML
}
{
    echo '<machine>'
    echo '  <device udi="/org/kde/solid/fakehw/computer"><property key="name">Computer</property></device>'
    drive internal false scsi
    drive usb true usb
    volume volume_root ROOTFS true / false internal
    volume volume_system SYSTEM false /boot/efi true internal
    volume volume_stick STICK false "${stick}" false usb
    volume volume_hidden HIDDEN false "${HOME}/media/HIDDEN" false usb
    echo '</machine>'
} > "${hardware}"
SOLID_FAKEHW="${hardware}" TETTE_FAKE_STICK="${stick}" "${test_binary}" drives
