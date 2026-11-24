"""What a desktop search asks about people, answered as JSON on one line.

    people [WORDS]      everyone, or those whose name or handles fit the words
    person ID           one person: every handle, and a likely match if any
    join ID OTHER       these two are one person from now on
    not-same ID OTHER   they are not, and it is not asked again
    separate ID         take a joined person apart again
    choices             how many contacts, and what the user has decided
    start-over          forget every decision; people are as the cards say

The contact cards are read from KDE Connect's folder each time, and what the
user decided is kept beside them in decisions.json, by handle, so the people
can always be rebuilt from the cards.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from .model import Decisions, Result, agree, resolve, tokens
from .vcard import read_folder


def data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def cards_folder() -> Path:
    return Path(os.environ.get("GOOD_INPUT_PEOPLE_CARDS") or data_home() / "kpeoplevcard")


def decisions_file() -> Path:
    return data_home() / "good-input-people" / "decisions.json"


def load() -> Decisions:
    try:
        d = json.loads(decisions_file().read_text("utf-8"))
    except (OSError, ValueError):
        return Decisions()
    pairs = lambda k: [tuple(p) for p in d.get(k, []) if isinstance(p, list) and len(p) == 2]
    return Decisions(pairs("joins"), pairs("splits"), pairs("apart"))


def save(d: Decisions):
    f = decisions_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".tmp")
    tmp.write_text(json.dumps({"joins": d.joins, "splits": d.splits, "apart": d.apart}, indent=1), "utf-8")
    tmp.replace(f)


def pid(res: Result, n: int) -> str:
    """A person is named by its first card, which the phone numbers."""
    return res.records[res.people[n].records[0]].id


def find(res: Result, ident: str) -> int:
    for n, p in enumerate(res.people):
        if any(res.records[i].id == ident for i in p.records):
            return n
    return -1


def shown(value: str) -> str:
    if value.startswith("+1") and len(value) == 12:
        return f"({value[2:5]}) {value[5:8]}-{value[8:]}"
    return value[6:] if value.startswith("local:") else value


def summary(p) -> str:
    tel = sum(1 for h in p.handles if h.kind == "tel")
    mail = len(p.handles) - tel
    parts = []
    if tel:
        parts.append("1 number" if tel == 1 else f"{tel} numbers")
    if mail:
        parts.append("1 address" if mail == 1 else f"{mail} addresses")
    return " · ".join(parts) or "No number or address"


def initials(name: str) -> str:
    words = [w for w in name.split() if w[:1].isalnum()]
    return "".join(w[0] for w in words[:2]).upper() or "?"


def row(res: Result, n: int) -> dict:
    p = res.people[n]
    return {"id": pid(res, n), "name": p.name or shown(p.handles[0].value) if p.handles or p.name else "No name",
            "initials": initials(p.name), "summary": summary(p)}


def people(res: Result, words: str) -> dict:
    """Everyone the words find, by name; with no words, everyone. Never cut short:
    the list is the whole address book, and a person missing from it is lost."""
    want = tokens(words)
    digits = "".join(c for c in words if c.isdigit())
    found = []
    for n, p in enumerate(res.people):
        if not p.name and not p.handles:
            continue
        names = [t for i in p.records for t in tokens(res.records[i].name)]
        if want:
            by_name = all(any(t.startswith(w) for t in names) for w in want)
            by_handle = (len(digits) >= 3 and any(digits in h.value for h in p.handles if h.kind == "tel")) \
                or ("@" in words and any(words.strip().lower() in h.value for h in p.handles if h.kind == "email"))
            if not (by_name or by_handle):
                continue
            first = 0 if names and names[0].startswith(want[0]) else 1
        else:
            first = 0
        found.append((first, (p.name or "￿").casefold(), n))
    found.sort()
    return {"count": len(res.people), "found": len(found), "people": [row(res, n) for _, _, n in found]}


def person(res: Result, ident: str) -> dict:
    n = find(res, ident)
    if n < 0:
        return {"error": "gone"}
    p = res.people[n]
    recs = [res.records[i] for i in p.records]
    labels = {True: "Mobile", False: "Home or work", None: "Phone"}
    out = row(res, n)
    out["handles"] = [{"kind": h.kind, "value": h.value.replace("local:", ""), "shown": shown(h.value),
                       "label": labels[h.personal] if h.kind == "tel" else "Email"} for h in p.handles]
    out["cards"] = len(recs)
    by_hand = any(j.reason == "hand" for j in p.joins)
    out["joined"] = "" if len(recs) < 2 else "hand" if by_hand else "same"
    out["match"] = None
    for s in res.suggestions:
        if n in s.people and s.reason != "shared-handle":
            other = s.people[0] if s.people[1] == n else s.people[1]
            m = row(res, other)
            m["why"] = "name" if s.strength == "strong" else "first-name"
            out["match"] = m
            break
    return out


def decide(res: Result, d: Decisions, verb: str, ident: str, other: str = "") -> dict:
    a = find(res, ident)
    if a < 0:
        return {"error": "gone"}
    pa = res.people[a]
    if verb == "separate":
        mine = {h.key for h in pa.handles}
        d.joins = [j for j in d.joins if not (j[0] in mine and j[1] in mine)]
        ids = [res.records[i].id for i in pa.records]
        for i, x in enumerate(ids):
            for y in ids[i + 1:]:
                if not any(agree_pair(x, y, p) for p in d.apart):
                    d.apart.append((x, y))
    else:
        b = find(res, other)
        if b < 0 or a == b or not pa.handles or not res.people[b].handles:
            return {"error": "gone"}
        pair = (pa.handles[0].key, res.people[b].handles[0].key)
        ha, hb = {h.key for h in pa.handles}, {h.key for h in res.people[b].handles}
        across = lambda p: (p[0] in ha and p[1] in hb) or (p[0] in hb and p[1] in ha)
        ia = {res.records[i].id for i in pa.records}
        ib = {res.records[i].id for i in res.people[b].records}
        if verb == "join":
            d.splits = [p for p in d.splits if not across(p)]
            d.apart = [p for p in d.apart if not ((p[0] in ia and p[1] in ib) or (p[0] in ib and p[1] in ia))]
            d.joins.append(pair)
        else:
            d.joins = [p for p in d.joins if not across(p)]
            d.splits.append(pair)
    save(d)
    again = resolve(res.records, d)
    return person(again, ident)


def choices(res: Result, d: Decisions) -> dict:
    """For a settings page: the contacts read, and how many decisions are kept."""
    return {"cards": len(res.records), "people": len(res.people),
            "joined": len(d.joins), "apart": len(d.splits) + len(d.apart)}


def start_over() -> dict:
    """Every join, "not the same" and separation forgotten, so the people
    are rebuilt from the cards alone."""
    d = Decisions()
    save(d)
    return choices(resolve(read_folder(cards_folder()), d), d)


def agree_pair(x: str, y: str, p: tuple[str, str]) -> bool:
    return (p[0] == x and p[1] == y) or (p[0] == y and p[1] == x)


def answer(args: list[str]) -> dict:
    verb = args[0] if args else "people"
    if verb == "start-over" and len(args) == 1:
        return start_over()
    d = load()
    res = resolve(read_folder(cards_folder()), d)
    if verb == "people":
        return people(res, " ".join(args[1:]))
    if verb == "person" and len(args) == 2:
        return person(res, args[1])
    if verb in ("join", "not-same") and len(args) == 3:
        return decide(res, d, verb, args[1], args[2])
    if verb == "separate" and len(args) == 2:
        return decide(res, d, verb, args[1])
    if verb == "choices" and len(args) == 1:
        return choices(res, d)
    return {"error": "usage"}


def main():
    print(json.dumps(answer(sys.argv[1:]), ensure_ascii=False))


if __name__ == "__main__":
    main()
