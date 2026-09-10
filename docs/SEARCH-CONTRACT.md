# Just type: search contract

Search should reveal recognizable destinations, not reward incidental strings.
This contract is the authority for ranking changes; screenshot-specific fixes
must become a rule tested against unrelated examples before adoption.

## Current foundation

1. Scope decides eligibility, not authorship. Everyday search keeps quiet
   collections and internal files out; All files restores indexed filename matches.
2. Confidence precedes provider preference: exact names, named intent, prefixes,
   word matches, then descriptive context. Unrelated results are omitted.
3. Apps, files, and aids break ties within comparable confidence. A precise
   setting may beat an incidental app or file; an explicit filename stays strong.
4. Aliases describe destinations, not query-specific rank overrides. Two-letter
   aliases remain ambiguous. Longer alias prefixes express stronger intent.
5. Punctuation and case are not meaningful obstacles. Matching uses word
   boundaries, not arbitrary scattered letters inside unrelated names.
6. Equivalent KDE module results already collapse to their canonical module.
   Context children remain attached to that destination and are not extra results.
7. No browsing or settings changes occur merely because the user types.
   Empty eligible results retain the existing explicitly submitted web fallback.
8. No usage learning is required. History cannot overpower relevance because
   this foundation does not use history.

## Acceptance examples

| Query | Expected relationship |
| --- | --- |
| wi | Winetricks before Wi-Fi; Wi-Fi before Window Manager |
| so | Sound and other short prefixes stay ambiguous, not an unconditional boost |
| soun | Sound intent before Soundcloud asset prefixes |
| soundcloud | Soundcloud name beats Sound; no continuing Sound alias boost |
| sound.png | Explicit file beats unrelated settings |
| pow / prin / displ | Same intent rule applies without per-query exceptions |
| browser | Relevant descriptive context is allowed, not fuzzy unrelated apps |
| arbitrary unmatched text | No invented destination; explicit browser fallback |

## Destination and interaction follow-up

Equivalent normalized local paths collapse across file providers. Desktop app
identities collapse across application results; a `kcm_*.desktop` shortcut can
collapse with the same KDE module. Canonical module results win that equivalence
so related children remain attached. Otherwise the strongest eligible
representation wins. Same-named files at different paths remain separate; no
filesystem symlink resolution, file opening, or title-based merging is used.
Independent printer applications are still distinct tools, not falsely treated
as equivalent module entrances. Broader task-family grouping remains future work.

Keyboard navigation and pointer/touch press pin the destination identity and
snapshot the displayed destination order. Late arrivals follow that snapshot;
replacement provider rows for the same destination retain its position. The
selected row is resolved from identity after model changes, not trusted by its
old integer index. If the destination vanishes, submitting does nothing rather
than opening its neighbor or invoking web fallback. A new query or scope releases
the lock. Initial results still rank freely before interaction. Press/keyboard
behavior requires live user validation in addition to synthetic model tests.

Tests cover duplicate paths, distinct same-name files, KCM/app equivalence, late
strong arrivals, duplicate arrivals, selected-destination removal, scope release,
and prevention of web fallback for a missing pinned destination.

Provider retrieval remains bounded by KDE's index and provider output. A shared
ranking policy cannot rank a candidate that was never retrieved. Read-only live
probes accompany policy fixtures to catch that difference.
