#!/usr/bin/env bash
# Runs Search's record of what was used lately against KDE's own activity
# service on a private bus with a throwaway home and data folders, so the
# person's own record is never read or written. Exits 77, which CTest reports
# as skipped, where the service is not installed.
set -euo pipefail

test_binary="$1"

if [[ "${2:-}" != "--inside" ]]; then
    if [[ ! -x /usr/lib/kactivitymanagerd ]]; then
        echo "skip: KDE's activity service is not installed here"
        exit 77
    fi
    work="$(mktemp -d "${TMPDIR:-/tmp}/tette-used.XXXXXX")"
    trap 'rm -rf -- "${work}"' EXIT
    mkdir -p "${work}/runtime" "${work}/home"
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
        HOME="${work}/home" XDG_RUNTIME_DIR="${work}/runtime" XDG_STATE_HOME="${work}/state" \
        XDG_CONFIG_HOME="${work}/config" XDG_DATA_HOME="${work}/data" XDG_CACHE_HOME="${work}/cache" \
        XDG_DATA_DIRS="${work}/system:/usr/share" QT_QPA_PLATFORM=offscreen WORK="${work}" \
        dbus-run-session --config-file="${work}/bus.conf" -- bash "$0" "${test_binary}" --inside
    exit
fi

mkdir -p "${HOME}/Documents"
first="${HOME}/Documents/first.txt"
last="${HOME}/Documents/last.txt"
echo first > "${first}"
echo last > "${last}"

/usr/lib/kactivitymanagerd > "${WORK}/activity.log" 2>&1 &
service_pid=$!
trap 'kill "${service_pid}" 2>/dev/null || true' EXIT
# A use is filed under the current activity, so wait until there is one.
current_activity() {
    busctl --user call org.kde.ActivityManager /ActivityManager/Activities \
        org.kde.ActivityManager.Activities CurrentActivity 2>/dev/null | sed -n 's/^s "\(.\+\)"$/\1/p'
}
for _ in $(seq 50); do [[ -n "$(current_activity)" ]] && break; sleep 0.1; done
if [[ -z "$(current_activity)" ]]; then
    echo "KDE's activity service did not start an activity." >&2
    cat "${WORK}/activity.log" >&2
    exit 1
fi

# Each use as another launcher reports it; the service stamps uses by the
# second and writes its record in batches, so they are spaced to keep their
# order.
use() {
    busctl --user call org.kde.ActivityManager /ActivityManager/Resources \
        org.kde.ActivityManager.Resources RegisterResourceEvent susu "$1" 0 "$2" 0
    sleep 2.5
}
use org.kde.dolphin "file://${first}"
use org.kde.plasmashell "applications:alpha.desktop"
use org.kde.dolphin "file://${last}"

# Wait until every use is in the record.
database="${XDG_DATA_HOME}/kactivitymanagerd/resources/database"
recorded() {
    python3 - "${database}" "${first}" "applications:alpha.desktop" "${last}" <<'PY_'
import sqlite3, sys
try:
    db = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
    for resource in sys.argv[2:]:
        if not db.execute("select count(*) from ResourceScoreCache where targettedResource = ?", (resource,)).fetchone()[0]:
            sys.exit(1)
except sqlite3.Error:
    sys.exit(1)
PY_
}
for _ in $(seq 100); do recorded && break; sleep 0.2; done
if ! recorded; then
    echo "KDE's activity service did not record the uses." >&2
    cat "${WORK}/activity.log" >&2
    exit 1
fi

"${test_binary}" --record
