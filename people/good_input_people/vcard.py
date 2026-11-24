"""Contact cards as source records: one record per card, as the source wrote it.

Reads vCard 2.1, 3.0 and 4.0 well enough for what phones export: folded lines,
quoted-printable values, bare and TYPE= parameters. Photos are skipped.
"""

from __future__ import annotations

import quopri
import re
from dataclasses import dataclass, field
from pathlib import Path

PERSONAL_TEL = {"CELL", "MOBILE", "IPHONE"}
PLACE_TEL = {"HOME", "WORK", "FAX", "MAIN", "PAGER"}
GENERIC_MAILBOX = {"info", "office", "sales", "support", "contact", "admin", "hello", "team",
                   "help", "billing", "service", "mail", "enquiries", "inquiries", "reception",
                   "frontdesk", "noreply", "no-reply"}


@dataclass(frozen=True)
class Handle:
    """One way to reach someone on one service."""
    kind: str               # "tel" or "email"
    value: str              # normalized: +16125550100, name@example.com
    personal: bool | None   # True: one person's own; False: a place's; None: unknown

    @property
    def key(self) -> str:
        return f"{self.kind}:{self.value}"


@dataclass
class Record:
    """What one source says about someone."""
    source: str
    id: str
    name: str
    org: str = ""
    handles: list[Handle] = field(default_factory=list)
    raw: dict[str, str] = field(default_factory=dict)   # handle key -> as written


def phone(text: str, country: str = "1") -> str:
    """A number the way every source should spell it. Anything after an
    extension mark is dropped: the extension is not part of the number."""
    text = re.split(r"(?i)(?:ext\.?|x|;|,|#)", text.strip(), maxsplit=1)[0]
    plus = text.lstrip().startswith("+")
    digits = re.sub(r"\D", "", text)
    if not digits:
        return ""
    if plus:
        return "+" + digits
    if digits.startswith("011") and len(digits) > 10:
        return "+" + digits[3:]
    if digits.startswith("00") and len(digits) > 9:
        return "+" + digits[2:]
    if country == "1":
        if len(digits) == 10:
            return "+1" + digits
        if len(digits) == 11 and digits[0] == "1":
            return "+" + digits
    return "local:" + digits      # short codes and numbers with no area code


def mailbox(text: str) -> str:
    text = text.strip().strip("<>").lower()
    return text if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", text) else ""


def _unfold(text: str) -> list[str]:
    lines: list[str] = []
    soft = False
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if soft:                                   # quoted-printable soft break
            lines[-1] = lines[-1][:-1] + line
        elif line[:1] in (" ", "\t") and lines:    # folded line
            lines[-1] += line[1:]
        else:
            lines.append(line)
        soft = lines[-1].endswith("=") and "QUOTED-PRINTABLE" in lines[-1].split(":", 1)[0].upper()
    return lines


def _params(head: str) -> tuple[str, set[str], bool]:
    parts = head.split(";")
    name = parts[0].split(".")[-1].upper()         # drop "item1." groups
    types: set[str] = set()
    quoted = False
    for p in parts[1:]:
        k, _, v = p.partition("=")
        if not v:
            k, v = "TYPE", k
        if k.upper() == "ENCODING" and v.upper() == "QUOTED-PRINTABLE":
            quoted = True
        elif k.upper() == "TYPE":
            types |= {t.strip().strip('"').upper() for t in v.split(",")}
    return name, types, quoted


def parse(text: str, source: str, fallback_id: str = "") -> list[Record]:
    out: list[Record] = []
    cur: Record | None = None
    n = ""
    for line in _unfold(text):
        head, sep, value = line.partition(":")
        if not sep:
            continue
        name, types, quoted = _params(head)
        if quoted:
            value = quopri.decodestring(value.encode("latin-1", "replace")).decode("utf-8", "replace")
        value = value.strip()
        if name == "BEGIN" and value.upper() == "VCARD":
            cur, n = Record(source=source, id="", name=""), ""
        elif cur is None:
            continue
        elif name == "END":
            cur.name = cur.name or n
            cur.id = cur.id or f"{fallback_id}#{len(out)}"
            out.append(cur)
            cur = None
        elif name == "FN":
            cur.name = value.replace("\\,", ",")
        elif name == "N":
            family, given, *rest = (value.split(";") + ["", ""])[:5]
            middle = rest[0] if rest else ""
            n = " ".join(x for x in (given, middle, family) if x).replace("\\,", ",")
        elif name == "ORG":
            cur.org = value.split(";")[0]
        elif name == "UID" or name.startswith("X-KDECONNECT-ID-DEV"):
            cur.id = cur.id or value
        elif name == "TEL":
            v = phone(value[4:] if value.lower().startswith("tel:") else value)
            if v:
                personal = True if types & PERSONAL_TEL else False if types & PLACE_TEL else None
                _add(cur, Handle("tel", v, personal), value)
        elif name == "EMAIL":
            v = mailbox(value)
            if v:
                _add(cur, Handle("email", v, False if v.split("@")[0] in GENERIC_MAILBOX else None), value)
    return out


def _add(rec: Record, h: Handle, raw: str):
    if h.key not in rec.raw:
        rec.handles.append(h)
        rec.raw[h.key] = raw


def read_folder(folder: Path, source: str = "phone") -> list[Record]:
    out: list[Record] = []
    for f in sorted(Path(folder).rglob("*.vcf")):
        out += parse(f.read_text("utf-8", "replace"), source, f.stem)
    return out
