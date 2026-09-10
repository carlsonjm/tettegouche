# Changelog

## Unreleased

- Sequenced opening: card, expanding search outline with Browse entrance,
  search icon, then a deliberate “Just type” reveal with a one-shot light sweep.
- Matched the placeholder to Browse's text size while preserving typed-query size.
- Made Browse labels reliably clickable with delayed hover feedback and expanded
  the drawer gesture margin without moving the grabber's visual center.
- Prevented inside-card clicks from dismissing the launcher through its backdrop.
- Kept sorting compact, with centered labels, selected pill fill, hover outlines,
  a closing fade, and Escape dismissing the menu before the drawer.
- Added offscreen Browse/Sort interaction coverage for standalone and Card Line
  modes alongside the existing panel-applet and workspace-context tests.

User-tested freeze: September 9, 2026. These changes do not alter Kadunce or
Temperance and do not create a separate tagged release.
