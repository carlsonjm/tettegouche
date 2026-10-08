#!/usr/bin/env bash
# Writes the translation templates for Tettegouche's two KI18n catalogs into
# the folder given, po/ by default: tettegouche.pot for the launcher, and
# plasma_applet_studio.warbler.tettegouche.pot for the panel widget and Ambient.
# A translation is po/<language>/<catalog>.po; the build installs it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-${root}/po}"
cd "${root}"

launcher_cpp=(src/main.cpp src/ApplicationCatalog.cpp src/FileBrowser.h src/FileDevices.h src/OmniResults.h src/RelatedInfo.cpp)
launcher_qml=(qml/*.qml)
widget_cpp=(src/LauncherKeys.cpp src/MprisActivityProvider.cpp src/DriveActivityProvider.cpp
    src/FinishNotices.cpp src/IncomingFileProvider.cpp src/TetteTransferProvider.cpp)
widget_qml=(applet/*.qml)

# Every file that asks for words belongs to one catalog.
listed=" ${launcher_cpp[*]} ${launcher_qml[*]} ${widget_cpp[*]} ${widget_qml[*]} "
missing=0
while IFS= read -r file; do
    if [[ "${listed}" != *" ${file} "* ]]; then
        echo "extract-messages: ${file} asks for words but is in no catalog" >&2
        missing=1
    fi
done < <(grep -lE '\bi18n[a-z]*\(' src/*.h src/*.cpp qml/*.qml applet/*.qml | sort)
(( missing == 0 )) || exit 1

keywords=(-ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3)
extract() {
    local pot="${out}/$1.pot"; shift
    local -n cpp=$1 qml=$2
    xgettext --from-code=UTF-8 --kde --add-comments=i18n --package-name=Tettegouche \
        --msgid-bugs-address=https://github.com/carlsonjm/tettegouche/issues \
        -C "${keywords[@]}" -o "${pot}" "${cpp[@]}"
    xgettext --from-code=UTF-8 --add-comments=i18n -j -L JavaScript \
        "${keywords[@]}" -o "${pot}" "${qml[@]}"
}
mkdir -p "${out}"
extract tettegouche launcher_cpp launcher_qml
extract plasma_applet_studio.warbler.tettegouche widget_cpp widget_qml
