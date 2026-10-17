#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/tette-panel-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/runtime" "$test_root/config" "$test_root/data/applications" "$test_root/cache"
chmod 700 "$test_root/runtime"
# Nothing from a running desktop reaches the test: no display, no system bus,
# and a home of its own, so its windows, drives and files stay out.
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET XAUTHORITY SESSION_MANAGER \
    XDG_SESSION_TYPE XDG_SESSION_ID XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
    DESKTOP_SESSION KDE_FULL_SESSION KDE_SESSION_VERSION KDE_SESSION_UID
mkdir -p "$test_root/home" "$test_root/state"
export HOME="$test_root/home"
export XDG_STATE_HOME="$test_root/state"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$test_root/no-system-bus"
export XDG_RUNTIME_DIR="$test_root/runtime"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_CACHE_HOME="$test_root/cache"
export QT_QPA_PLATFORM=offscreen
export QT_QPA_PLATFORMTHEME=generic
export QT_STYLE_OVERRIDE=Fusion
export QT_QUICK_BACKEND=software
export QT_PLUGIN_PATH="$2"
export TETTE_TEST_PLUGIN_ROOT="$2"
# The machine's own Gooseberry would add the quick note's island to every
# count; NotesIslandProviderTest covers it apart.
export TETTE_AMBIENT_WITHOUT_NOTES=1

dbus-run-session --config-file="$(dirname "$0")/panel-test-bus.conf" -- "$1" "${@:3}"
