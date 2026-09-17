# Search contract

Search reveals recognizable destinations rather than rewarding incidental
strings. Screenshot-specific changes must become general rules tested against
unrelated examples before adoption.

## Eligibility and confidence

1. Scope decides eligibility, not authorship. Everyday hides quiet collections,
   repositories, technical/internal files, and file matches shorter than three
   characters. All files relaxes those Tettegouche filters but does not widen
   KDE indexing or scan content.
2. Confidence precedes provider preference: exact name, named intent, prefix,
   query words, descriptive context, then unrelated. Unrelated rows are omitted.
3. Apps, files, and system aids break ties only within comparable confidence. A
   precise setting may beat an incidental app; an explicit filename stays strong.
4. Aliases describe destinations. Two-letter aliases remain ambiguous; longer
   alias prefixes express stronger intent without per-query exceptions.
5. Matching ignores punctuation and case and uses word boundaries rather than
   arbitrary scattered letters.
6. No browsing or settings change occurs merely because the user types. Web
   fallback appears only after explicit submission of an empty eligible result.
7. Ranking has no usage-learning requirement; history cannot overpower relevance.

## Providers and execution

Allowed local sources are applications/services, Baloo and recent documents,
KDE settings, calculator, and unit conversion. Shell, session/kill actions,
browser history, and online runners are excluded.

Application results may activate an exact existing Kadunce window. Files and
settings execute their provider or verified module action. Web dispatch sends an
encoded URL through the registered HTTPS browser; query text is never executed.

## Destination identity

- Equivalent normalized local paths collapse across file providers. Same-named
  files at different paths remain distinct; no symlink traversal or title-only
  merging is performed.
- Desktop application identities collapse across app rows. A `kcm_*.desktop`
  shortcut may collapse with the same KDE module; the canonical module wins so
  related children remain attached.
- Context children belong to the parent destination and are not extra ranked
  results. Selecting one opens the parent settings page after revalidating that
  the child is still present.
- Independent tools with similar names remain separate destinations.

## Stable interaction

Keyboard navigation and pointer/touch press pin the destination identity and a
snapshot of displayed order. Late arrivals follow that snapshot; a replacement
row for the same destination keeps its position. Execution resolves the pinned
identity rather than trusting an old row number. If it disappears, submission
does nothing. A new query or scope releases the lock.

## Reference examples

| Query | Expected relationship |
| --- | --- |
| `wi` | Winetricks before Wi-Fi; Wi-Fi before Window Manager |
| `so` | Sound and other short prefixes remain ambiguous |
| `soun` | Sound intent before a Soundcloud asset prefix |
| `soundcloud` | Exact Soundcloud name beats the Sound alias |
| `sound.png` | Explicit file beats unrelated settings |
| unmatched text | No invented destination; explicit browser fallback |

Provider retrieval remains a hard boundary: policy cannot rank a candidate that
KDE never returns.
