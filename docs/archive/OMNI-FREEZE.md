# Omni search freeze — 2026-09-10

User-approved freeze of confidence-based ranking, Everyday/All files scope,
editable quiet folders, canonical destination deduplication, stable selection,
related settings information, and independently selectable child rows.

User testing passed search basics, duplicate/stable-selection tests without
noticeable arrow-navigation lag, child paging/visuals, and direct settings launch.
The final Wi-Fi child launch was explicitly confirmed clean and fast. These
passes do not claim exhaustive hardware or provider coverage.

Final verification: all seven CTest tests, source checks, and diff whitespace
checks pass. Installed and build binaries both have SHA-256:

`b04303a7bca9da83d17770c0d0c22e415d0dbf7aac6b4c044d9b9d09dad95b05`

Search policy authority: SEARCH-CONTRACT.md. Earlier candidate notes in
OMNI-SEARCH.md and RELATED-SETTINGS.md record incremental verification; this
freeze records the subsequent user acceptance.

Known boundaries: children open the relevant settings page, not device-specific
controls. Most related providers are lazy per-process snapshots. Storage opens
Device Actions. Broader task-family grouping, stable device action identities,
and personalization remain future work. Web fallback's search-engine choice and
new-tab behavior across all default browsers are not fully user-validated.

No Kadunce or Temperance changes are included in this freeze.
