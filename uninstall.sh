#!/usr/bin/env bash
set -euo pipefail

rm -f "${HOME}/.local/bin/tettegouche"
rm -f "${HOME}/.local/share/applications/io.github.carlsonjm.Tettegouche.desktop"
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/co.goodinput.tettegouche"
install_key=/usr/local/libexec/shuffle/install-step
if [[ -x "${install_key}" ]] \
        && sudo -n -l "${install_key}" tettegouche remove >/dev/null 2>&1; then
    sudo -n "${install_key}" tettegouche remove
else
    sudo rm -f /usr/bin/tettegouche
    sudo rm -f /usr/share/applications/io.github.carlsonjm.Tettegouche.desktop
    sudo rm -f /usr/lib/qt6/plugins/plasma/applets/co.goodinput.tettegouche.so
fi
kbuildsycoca6

echo "Tettegouche removed."
