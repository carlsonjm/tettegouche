"""The person model: source records in, people out, every join with its reason.

It knows nothing of where records come from. Three layers: a handle is one way
to reach someone, a record is what one source says, a person owns handles.

Joining goes by evidence, strongest first:
  1. the user's own joins and splits, kept by handle so they survive a rebuild;
  2. one record listing several handles (the source already says so);
  3. the same handle in two records, unless that handle looks shared;
  4. the same name: a suggestion only, never a join.

A handle looks shared when the records that carry it disagree on the name and
the handle is not marked as one person's own (a mobile number). A family
landline or an office address joins nobody; it is offered as a suggestion.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from .vcard import Handle, Record


@dataclass
class Decisions:
    """What the user decided by hand, as pairs of handle keys."""
    joins: list[tuple[str, str]] = field(default_factory=list)
    splits: list[tuple[str, str]] = field(default_factory=list)
    # Two cards the user took apart although they share a number or address,
    # as pairs of record ids.
    apart: list[tuple[str, str]] = field(default_factory=list)


@dataclass
class Join:
    reason: str             # "hand", "same-handle"
    a: int                  # record indexes
    b: int
    handle: str = ""


@dataclass
class Suggestion:
    reason: str             # "shared-handle", "same-name", "same-first-name"
    strength: str           # "strong" or "weak"
    people: tuple[int, int]  # person indexes
    detail: str = ""


@dataclass
class Person:
    name: str
    records: list[int]
    handles: list[Handle]
    joins: list[Join]


@dataclass
class Result:
    records: list[Record]
    people: list[Person]
    suggestions: list[Suggestion]
    shared: dict[str, list[int]]        # handle key -> records, not joined
    blocked: list[Join]                 # joins a split by hand stopped


def tokens(name: str) -> tuple[str, ...]:
    """A name's words, folded: no case, accents, punctuation or emoji."""
    text = unicodedata.normalize("NFKD", name)
    text = "".join(c for c in text if not unicodedata.combining(c)).casefold()
    text = re.sub(r"\([^)]*\)", " ", text)
    return tuple(t for t in re.split(r"[^\w]+", text) if t)


def agree(a: str, b: str) -> bool:
    """Could these be one person's name? Equal, or one inside the other
    ("Ana" and "Ana Reyes"). A missing name agrees with anything."""
    ta, tb = set(tokens(a)), set(tokens(b))
    return not ta or not tb or ta <= tb or tb <= ta


class _Sets:
    def __init__(self, n: int):
        self.parent = list(range(n))

    def find(self, i: int) -> int:
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def members(self, i: int) -> list[int]:
        r = self.find(i)
        return [j for j in range(len(self.parent)) if self.find(j) == r]

    def union(self, a: int, b: int):
        self.parent[self.find(b)] = self.find(a)


def resolve(records: list[Record], decisions: Decisions | None = None) -> Result:
    decisions = decisions or Decisions()
    sets = _Sets(len(records))
    by_handle: dict[str, list[int]] = {}
    for i, r in enumerate(records):
        for h in r.handles:
            by_handle.setdefault(h.key, []).append(i)
    kept: list[Join] = []
    blocked: list[Join] = []

    def apart(a: int, b: int) -> bool:
        """Would joining these put two handles together the user split?"""
        ha = {h.key for i in sets.members(a) for h in records[i].handles}
        hb = {h.key for i in sets.members(b) for h in records[i].handles}
        if any((x in ha and y in hb) or (x in hb and y in ha) for x, y in decisions.splits):
            return True
        ia = {records[i].id for i in sets.members(a)}
        ib = {records[i].id for i in sets.members(b)}
        return any((x in ia and y in ib) or (x in ib and y in ia) for x, y in decisions.apart)

    def join(j: Join, by_hand: bool = False):
        if sets.find(j.a) == sets.find(j.b):
            return
        if not by_hand and apart(j.a, j.b):
            blocked.append(j)
            return
        sets.union(j.a, j.b)
        kept.append(j)

    for x, y in decisions.joins:                       # 1. by hand
        for a in by_handle.get(x, [])[:1]:
            for b in by_handle.get(y, [])[:1]:
                join(Join("hand", a, b, f"{x} = {y}"), by_hand=True)

    shared: dict[str, list[int]] = {}
    for key, recs in by_handle.items():                # 3. same handle
        recs = sorted(set(recs))
        if len(recs) < 2:
            continue
        personal = _personal(records, recs, key)
        names_agree = all(agree(records[a].name, records[b].name) for a in recs for b in recs if a < b)
        if names_agree or (personal is True and len(recs) == 2):
            for b in recs[1:]:
                join(Join("same-handle", recs[0], b, key))
        else:
            shared[key] = recs

    roots = sorted({sets.find(i) for i in range(len(records))})
    index = {r: n for n, r in enumerate(roots)}
    people: list[Person] = []
    for r in roots:
        members = sets.members(r)
        handles: dict[str, Handle] = {}
        for i in members:
            for h in records[i].handles:
                handles.setdefault(h.key, h)
        name = max((records[i].name for i in members), key=lambda n: (len(tokens(n)), len(n)), default="")
        people.append(Person(name, members, list(handles.values()),
                             [j for j in kept if sets.find(j.a) == r]))

    suggestions: list[Suggestion] = []
    seen: set[tuple[int, int, str]] = set()

    def suggest(reason: str, strength: str, a: int, b: int, detail: str):
        pa, pb = sorted((index[sets.find(a)], index[sets.find(b)]))
        if pa == pb or (pa, pb, reason) in seen:
            return
        if any(s.people == (pa, pb) for s in suggestions):
            return
        ha = {h.key for h in people[pa].handles}
        hb = {h.key for h in people[pb].handles}
        if any((x in ha and y in hb) or (x in hb and y in ha) for x, y in decisions.splits):
            return                                      # the user already said no
        seen.add((pa, pb, reason))
        suggestions.append(Suggestion(reason, strength, (pa, pb), detail))

    by_name: dict[tuple[str, ...], list[int]] = {}
    for i, r in enumerate(records):
        t = tokens(r.name)
        if t:
            by_name.setdefault(tuple(sorted(t)), []).append(i)
    for t, recs in by_name.items():                    # 4. same name
        for b in recs[1:]:
            if len(t) >= 2:
                suggest("same-name", "strong", recs[0], b, records[recs[0]].name)
            else:
                suggest("same-first-name", "weak", recs[0], b, records[recs[0]].name)
    for key, recs in shared.items():
        for b in recs[1:]:
            suggest("shared-handle", "weak", recs[0], b, key)
    suggestions.sort(key=lambda s: (s.strength != "strong", s.reason))
    return Result(records, people, suggestions, shared, blocked)


def _personal(records: list[Record], recs: list[int], key: str) -> bool | None:
    marks = {h.personal for i in recs for h in records[i].handles if h.key == key}
    if False in marks:
        return False
    return True if marks == {True} else None
