#!/usr/bin/env python3
"""Words a person reads are asked of a KI18n catalog, whole.

Qt's own translation calls are never loaded here, so none may remain. In QML,
a quoted phrase where a label, title or name is set, or one joined to others
with +, must be inside an i18n call; tests/verify-words.sh then draws Files
with a catalog that marks every phrase.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = sorted([*ROOT.glob("src/*.h"), *ROOT.glob("src/*.cpp"), *ROOT.glob("qml/*.qml"),
                  *ROOT.glob("applet/*.qml"), *ROOT.glob("applet/*.js")])
QML = [p for p in SOURCES if p.suffix in (".qml", ".js")]

ASKED = re.compile(r'\bi18nc?p?\(\s*"(?:[^"\\]|\\.)*"(?:\s*,\s*"(?:[^"\\]|\\.)*"){0,2}')
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
# Text set where a person reads it.
SHOWN = re.compile(r'\b(text|title|label|action|placeholderText|toolTipMainText|toolTipSubText'
                   r'|Accessible\.name|Accessible\.description|ToolTip\.text|launchingApplication)\s*[:=]')
# Not words: names, keys, kinds, files and colours.
NOT_WORDS = re.compile(r'^(#|qrc:|image:|file:|https?:|org\.|io\.|studio\.|application/|text/|inode/'
                       r'|Ctrl\+|Alt\+|Shift\+|Meta\+|Escape$)|\.(qml|js|svg|png)$')


def phrase(text: str) -> bool:
    return bool(re.search(r"[A-Za-z]{2,}", text)) and not NOT_WORDS.search(text) and (
        " " in text or "…" in text or re.match(r"^[A-Z][a-z]", text) is not None)


def main() -> int:
    problems = []
    for path in SOURCES:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = re.sub(r"//.*$", "", line)
            if re.search(r"\b(qsTr|qsTranslate|QT_TR_NOOP)\(|(?<![\w.:])tr\(|QObject::tr\(", code):
                problems.append(f"{path.relative_to(ROOT)}:{number}: Qt's translation call; use i18n")
            if path not in QML:
                continue
            bare = ASKED.sub("", code)
            for match in LITERAL.finditer(bare):
                text = match.group(1)
                before = bare[max(0, match.start() - 24):match.start()]
                if not phrase(text) or re.search(r"(objectName|glyph|id|name)\s*:\s*$|[=!]==?\s*$|case\s*$", before):
                    continue
                joined = re.search(r"\+\s*$", before) or re.match(r"\s*\+", bare[match.end():])
                if SHOWN.search(bare[:match.start()]) or joined:
                    problems.append(f"{path.relative_to(ROOT)}:{number}: \"{text}\" is not asked of a catalog")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print("Tettegouche words checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
