#!/usr/bin/env python3
"""Guard the live documentation set without interpreting archived evidence."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOC_INDEX = ROOT / "docs" / "README.md"
ARCHIVE_INDEX = ROOT / "docs" / "archive" / "README.md"
INPUT_DOC = ROOT / "docs" / "INPUT.md"
REQUIRED = [
    "AGENTS.md",
    "docs/README.md",
    "docs/ARCHITECTURE.md",
    "docs/INPUT.md",
    "docs/ROADMAP.md",
]
INPUT_HEADER = "| Input | What happens |"
errors: list[str] = []


def tracked_documents() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--", "*.md", "*.txt"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    documents = []
    root_docs = {
        "AGENTS.md",
        "CHANGELOG.md",
        "CLAUDE.md",
        "README.md",
        "THIRD_PARTY_NOTICES.md",
        "TRADEMARKS.md",
    }
    for path in result.stdout.splitlines():
        if Path(path).name == "CMakeLists.txt" or path.startswith("LICENSES/"):
            continue
        if path in root_docs or path.startswith("docs/"):
            documents.append(path)
        elif path.endswith("/README.md") and path.split("/", 1)[0] in {
            "packaging",
            "patches",
            "tests",
        }:
            documents.append(path)
        elif path.endswith("/THIRD_PARTY.md"):
            documents.append(path)
    return documents


def index_mentions(path: str, text: str) -> bool:
    candidates = {path, Path(path).name}
    if path.startswith("docs/"):
        candidates.add(path.removeprefix("docs/"))
    else:
        candidates.add(f"../{path}")
    if Path(path).name == "README.md" and "/" in path and not path.startswith("docs/"):
        candidates.discard("README.md")
    return any(candidate in text for candidate in candidates)


def check_index_coverage() -> None:
    main_index = DOC_INDEX.read_text()
    # Archived evidence is kept privately; a checkout may carry none.
    archive_index = ARCHIVE_INDEX.read_text() if ARCHIVE_INDEX.exists() else ""
    for path in tracked_documents():
        if path.startswith("docs/archive/") and path != "docs/archive/README.md":
            if not index_mentions(path, archive_index):
                errors.append(f"archive index does not cover {path}")
        elif not index_mentions(path, main_index):
            errors.append(f"documentation index does not cover {path}")


def check_archive_authority() -> None:
    evidence_link = re.compile(
        r"(?:docs/)?archive/(?!README\.md\b)[^\s)`\]]+\.(?:md|txt)", re.IGNORECASE
    )
    for path in tracked_documents():
        if path.startswith("docs/archive/") or path == "docs/README.md":
            continue
        text = (ROOT / path).read_text()
        for match in evidence_link.finditer(text):
            errors.append(
                f"{path} treats archived evidence as a live reference: {match.group(0)}"
            )


def check_required() -> None:
    for path in REQUIRED:
        if not (ROOT / path).is_file():
            errors.append(f"required document {path} is missing")


def check_current_facts() -> None:
    """Live documents state what is true now; history lives in Git."""
    for path in tracked_documents():
        if not path.startswith("docs/") or path.startswith("docs/archive/"):
            continue
        text = (ROOT / path).read_text()
        if re.search(r"\b(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b", text, flags=re.IGNORECASE):
            errors.append(f"{path} contains a commit hash")
        if re.search(r"\b20\d{2}-\d{2}-\d{2}\b", text):
            errors.append(f"{path} contains dated progress")
        if re.search(
            r"\b(?:today|yesterday|tomorrow|this morning|this afternoon|this evening)\b",
            text,
            flags=re.IGNORECASE,
        ):
            errors.append(f"{path} contains relative progress narration")


def check_input_shape() -> None:
    """INPUT.md opens with prose and its controls map, then one two-column table
    per destination and per subsection under it, each with an optional note
    after. tests/verify-public.py checks the map itself."""
    if not INPUT_DOC.is_file():
        return
    lines = INPUT_DOC.read_text().splitlines()
    headings = [i for i, line in enumerate(lines) if line.startswith(("## ", "### "))]
    if not headings or not lines[headings[0]].startswith("## "):
        errors.append("INPUT.md has no destination sections")
        return
    intro = [line for line in lines[1:headings[0]] if line.strip()]
    if not any(not line.startswith("|") for line in intro) or any(line.startswith("#") for line in intro):
        errors.append("INPUT.md must open with a short prose introduction")
    for number, start in enumerate(headings):
        stop = headings[number + 1] if number + 1 < len(headings) else len(lines)
        body = [line for line in lines[start + 1:stop] if line.strip()]
        name = lines[start].lstrip("#").strip()
        if not body and number + 1 < len(headings) and lines[stop].startswith("### "):
            continue
        if len(body) < 3 or body[0] != INPUT_HEADER or body[1] != "| --- | --- |":
            errors.append(f"INPUT.md section {name} must start with one '{INPUT_HEADER}' table")
            continue
        rows = [line for line in body[2:] if line.startswith("|")]
        note = body[2 + len(rows):]
        if body[2:2 + len(rows)] != rows or any(line.startswith(("|", "#")) for line in note):
            errors.append(f"INPUT.md section {name} has more than one table")
        for row in rows:
            cells = row.split("|")
            if not row.startswith("| ") or not row.endswith(" |") or len(cells) != 4:
                errors.append(f"INPUT.md section {name} has a row that is not two cells: {row}")
    for path in tracked_documents():
        if path == "docs/INPUT.md" or path.startswith("docs/archive/"):
            continue
        if INPUT_HEADER in (ROOT / path).read_text():
            errors.append(f"{path} carries an input table; inputs belong in docs/INPUT.md")


check_required()
check_index_coverage()
check_archive_authority()
check_current_facts()
check_input_shape()

if errors:
    for error in errors:
        print(f"documentation guard: {error}", file=sys.stderr)
    raise SystemExit(1)

print("Documentation hygiene checks passed.")
