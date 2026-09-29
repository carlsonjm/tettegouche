#!/usr/bin/env bash
set -euo pipefail

rm -f "${HOME}/.local/bin/tettegouche"
rm -f "${HOME}/.local/share/applications/io.github.carlsonjm.Tettegouche.desktop"
rm -rf -- "${HOME}/.local/share/plasma/plasmoids/studio.warbler.tettegouche"
sudo rm -f /usr/bin/tettegouche
sudo rm -f /usr/share/applications/io.github.carlsonjm.Tettegouche.desktop
sudo rm -f /usr/lib/qt6/plugins/plasma/applets/studio.warbler.tettegouche.so
kbuildsycoca6

echo "Tettegouche removed."
