# Production-readiness backlog

## Next priority: shared Active bounds and pop-out docks

J reported 2026-09-14 while testing Files drag/drop: all Active card sizing in
Tettegouche and Kadunce must allow clearance for pop-out docks. Bento already
respects this according to J and is the behavioral reference.

Promoted by J after accepting compact Files UI. Scope for the next slice:

- Audit Kadunce Active cards and Tette expanded App/Explore files drawers against
  the same dock-aware available bounds used by Bento.
- Preserve consistent margins and access to revealed/floating dock surfaces.
- Verify dock hidden/revealed transitions, tablet-only and monitor configurations.
- Preserve Active ownership, drawer/card transitions and bottom-edge gestures;
  do not reintroduce ordinary-window resizing or snapping regressions.
- Decide from the audit whether stable reserved clearance or dynamic adjustment
  is appropriate; avoid visible size oscillation on dock reveal.

Evidence: J's three screenshots in this task, 2026-09-14 at approximately 15:09.
They compare Bento clearance with a single Active window. This is a reported
requirement, not a confirmed implementation diagnosis. No code changes yet.

Additional Tette Explore files screenshot supplied at approximately 15:20
(codex-clipboard-439e79e2-528b-465d-a8d5-d6a582adcbbe.png) confirms this requirement
also covers the expanded Files drawer. Still deferred, not part of chrome polish.

## Same pass: Tette launcher touch target

J requests a full square hit area around the circular launcher icon, with enough
edge clearance. Current applet is 26x42 (42x26 vertically); keep the circular
artwork centered while expanding its layout/hit area to a square. Verify panel
edges, vertical orientation, Meta toggle and focus return. No implementation yet.
