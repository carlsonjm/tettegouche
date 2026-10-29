#!/usr/bin/env bash
set -euo pipefail

manifest="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/install_manifest.txt"

# Tettegouche takes the launcher's place, so a panel left without it would
# have no launcher. While the panel still runs, each panel that holds the dot
# gets Plasma's own Application Launcher back where the dot was, unless it
# already has a launcher; a dot on the desktop is only taken away.
panel_shell_running() {
    command -v qdbus6 >/dev/null 2>&1 \
        && systemctl --user --quiet is-active plasma-plasmashell.service 2>/dev/null
}
restored=""
if panel_shell_running; then
    restored="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
        var dot = "co.goodinput.tettegouche";
        var launchers = ["org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.kickerdash"];
        var restored = 0;
        panels().forEach(function (panel) {
            var held = [], launcher = false;
            panel.widgets().forEach(function (widget) {
                if (widget.type === dot) held.push(widget);
                else if (launchers.indexOf(widget.type) >= 0) launcher = true;
            });
            if (held.length === 0) return;
            if (!launcher) {
                var added = panel.addWidget("org.kde.plasma.kickoff");
                panel.currentConfigGroup = ["General"];
                var order = String(panel.readConfig("AppletOrder", "")).split(";")
                    .filter(function (id) { return id !== "" && id !== String(added.id); });
                var at = order.indexOf(String(held[0].id));
                if (at >= 0) {
                    order[at] = String(added.id);
                    panel.writeConfig("AppletOrder", order.join(";"));
                }
                restored += 1;
            }
            held.forEach(function (widget) { widget.remove(); });
        });
        desktops().forEach(function (desktop) {
            desktop.widgets(dot).forEach(function (widget) { widget.remove(); });
        });
        print(restored);' 2>/dev/null || true)"
fi

rm -f "${HOME}/.local/bin/tettegouche"
rm -f "${HOME}/.local/share/applications/io.github.carlsonjm.Tettegouche.desktop"
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/co.goodinput.tettegouche"
install_key=/usr/local/libexec/shuffle/install-step
if [[ -x "${install_key}" ]] \
        && sudo -n -l "${install_key}" tettegouche remove >/dev/null 2>&1; then
    sudo -n "${install_key}" tettegouche remove
else
    # Every file install.sh puts in place, as CMakeLists.txt installs them.
    # A copy left behind would keep a launcher entry, and would stop Shuffle's
    # own package from installing over it.
    installed=(
        /usr/bin/tettegouche
        /usr/share/applications/io.github.carlsonjm.Tettegouche.desktop
        /usr/share/applications/io.github.carlsonjm.Tettegouche.Files.desktop
        /usr/share/applications/io.github.carlsonjm.Tettegouche.Apps.desktop
        /usr/share/tettegouche/org.freedesktop.FileManager1.service
        /usr/share/icons/hicolor/512x512/apps/co.goodinput.tettegouche.png
        /usr/share/icons/hicolor/512x512/apps/co.goodinput.tettegouche-logo.png
        /usr/share/icons/hicolor/scalable/apps/co.goodinput.tettegouche-apps.svg
        /usr/share/icons/hicolor/scalable/apps/co.goodinput.tettegouche.svg
        /usr/lib/qt6/plugins/plasma/applets/co.goodinput.tettegouche.so
    )
    shopt -s nullglob
    installed+=(/usr/share/locale/*/LC_MESSAGES/tettegouche.mo
        /usr/share/locale/*/LC_MESSAGES/plasma_applet_co.goodinput.tettegouche.mo)
    shopt -u nullglob
    # And whatever the build folder's list adds, from a build newer than this
    # list. A file a package owns is the package's to remove, never this one's.
    if [[ -f ${manifest} ]]; then
        while IFS= read -r listed; do
            case ${listed} in /usr/* | /etc/*) installed+=("${listed}") ;; esac
        done < "${manifest}"
    fi
    present=()
    for path in "${installed[@]}"; do
        if [[ -f ${path} || -L ${path} ]] \
                && ! { command -v pacman >/dev/null 2>&1 && pacman -Qqo -- "${path}" >/dev/null 2>&1; }; then
            present+=("${path}")
        fi
    done
    if ((${#present[@]} > 0)); then
        sudo rm -f -- "${present[@]}"
    fi
    sudo rmdir --ignore-fail-on-non-empty /usr/share/tettegouche 2>/dev/null || true
fi
kbuildsycoca6

# A restarted shell has sometimes come back not knowing the current activity,
# and then shows no desktop on any screen until the activity is announced
# again. Once the shell answers, make sure it knows.
announce_activity() {
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

# The panel keeps a widget's plugin loaded until it restarts.
if panel_shell_running; then
    systemctl --user restart plasma-plasmashell.service
    announce_activity
    if [[ "${restored}" =~ ^[1-9] ]]; then
        echo "Tettegouche removed, and Plasma's Application Launcher is back on its panel."
    else
        echo "Tettegouche removed."
    fi
else
    echo "Tettegouche removed. Sign out and back in to finish."
fi
