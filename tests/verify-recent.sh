#!/usr/bin/env bash
# Runs Files' Recent against KDE's own activity service on a private bus with a
# throwaway home and data folders, so the person's own record of what they used
# is never read. Exits 77, which CTest reports as skipped, where the service or
# KDE's Recent location is not installed.
set -euo pipefail

test_binary="$1"
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [[ "${2:-}" != "--inside" ]]; then
    if [[ ! -x /usr/lib/kactivitymanagerd ]] \
            || ! compgen -G '/usr/lib*/qt6/plugins/kf6/kio/recentlyused.so' >/dev/null; then
        echo "skip: KDE's activity service or its Recent location is not installed here"
        exit 77
    fi
    work="$(mktemp -d "${TMPDIR:-/tmp}/tette-recent.XXXXXX")"
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
        QT_QPA_PLATFORM=offscreen WORK="${work}" \
        dbus-run-session --config-file="${work}/bus.conf" -- bash "$0" "${test_binary}" --inside
    exit
fi

documents="${HOME}/Documents"
photos="${HOME}/Pictures/Photos"
mkdir -p "${documents}" "${photos}"
notes="${documents}/notes.txt"
budget="${documents}/budget.ods"
report="${HOME}/report.pdf"
gone=("${documents}/gone-1.txt" "${documents}/gone-2.txt" "${HOME}/gone-3.txt")
for file in "${notes}" "${budget}" "${report}" "${gone[@]}"; do echo test > "${file}"; done

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

# Each use as an application reports it; the service stamps uses by the second,
# so they are spaced to keep their order.
use() {
    busctl --user call org.kde.ActivityManager /ActivityManager/Resources \
        org.kde.ActivityManager.Resources RegisterResourceEvent susu org.kde.dolphin 0 "file://$1" 0
    sleep 2.5
}
# Files used and then deleted sit between the others: KDE's Recent can skip the
# file after one when it first answers.
use "${notes}"
use "${gone[0]}"
use "${budget}"
use "${gone[1]}"
use "${photos}"
use "${gone[2]}"
use "${report}"
rm -- "${gone[@]}"

# The service writes its record in batches; wait until every use is in it.
database="${XDG_DATA_HOME}/kactivitymanagerd/resources/database"
recorded() {
    python3 - "${database}" "${notes}" "${budget}" "${photos}" "${report}" "${gone[@]}" <<'PY_'
import sqlite3, sys
try:
    db = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
    for path in sys.argv[2:]:
        if not db.execute("select count(*) from ResourceScoreCache where targettedResource = ?", (path,)).fetchone()[0]:
            sys.exit(1)
except sqlite3.Error:
    sys.exit(1)
PY_
}
for _ in $(seq 100); do recorded && break; sleep 0.2; done
if ! recorded; then
    echo "KDE's activity service did not record the files' use." >&2
    cat "${WORK}/activity.log" >&2
    exit 1
fi

# Once the service has finished announcing those uses, nothing else refreshes
# Recent while the test reads it.
sleep 3
TETTE_RECENT_FILES="$(printf '%s\n' "${report}" "${photos}" "${budget}" "${notes}")" "${test_binary}" recentPlace
# A file Files itself opens comes back first.
TETTE_RECENT_SEALED=1 "${test_binary}" filesOpenedAreRecent
