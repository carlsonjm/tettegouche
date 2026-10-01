#!/usr/bin/env bash
# Every word Tettegouche shows is asked of its catalogs. Test catalogs that
# mark each phrase "xx…xx" are made from the templates, and Files is drawn
# with them in a throwaway home on a private bus.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$1"
work="$(mktemp -d "${TMPDIR:-/tmp}/tettegouche-words.XXXXXX")"
trap 'rm -rf -- "${work}"' EXIT

python3 "${project_root}/tests/verify-words.py"
bash "${project_root}/tools/extract-messages.sh" "${work}/pot"
catalogs="${work}/data/locale/x-test/LC_MESSAGES"
mkdir -p "${catalogs}" "${work}/config" "${work}/cache" "${work}/state"
for pot in "${work}"/pot/*.pot; do
    name="$(basename "${pot}" .pot)"
    msgen --no-wrap -o "${work}/${name}.po" "${pot}"
    sed -i -e 's/charset=CHARSET/charset=UTF-8/' \
        -e 's/^"Plural-Forms: .*"$/"Plural-Forms: nplurals=2; plural=(n != 1);\\n"/' "${work}/${name}.po"
    msgfilter --keep-header --no-wrap -i "${work}/${name}.po" -o "${work}/${name}.marked.po" \
        sed -e 's/^/xx/' -e 's/$/xx/'
    msgfmt -o "${catalogs}/${name}.mo" "${work}/${name}.marked.po"
done

XDG_DATA_HOME="${work}/data" XDG_CONFIG_HOME="${work}/config" XDG_CACHE_HOME="${work}/cache" \
XDG_STATE_HOME="${work}/state" LANG=en_US.UTF-8 LANGUAGE=x-test TETTE_WORDS_SEALED=1 \
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    dbus-run-session --config-file="${project_root}/tests/panel-test-bus.conf" -- \
    "${test_binary}" wordsComeFromTheCatalogs
