# Shared drawer sizing — implementation plan

September 14, 2026. Sizing-first implementation is installed and J-accepted;
freeze/push authorized. See ACTIVE-DRAWER-20260914.md for completion/tests.
Tette base bdf4523; Kadunce
accepted base a6ce03e. Both are separate packages. Preserve unrelated roadmaps.

## Original rationale (pre-implementation)

Launcher.qml currently changes drawerOpen/drawerProgress inside an unchanged
sheet: standalone uses64% of available width/height; guest uses the negotiated
rectangle. main.cpp accepts guest protocol3 and sets the input mask once.
Kadunce already returns both card and active rectangles in beginLauncherGuest,
but Tette reads only card. Kadunce guest hit-testing still uses the compact
CardStageController::launcherGuestTarget. QML-only enlargement would therefore
leave geometry and input ownership inconsistent.

## Contract

J's scope clarification: no manual resizing or resize handles. The13-inch tablet
uses fixed canonical Active bounds for an open drawer and compact bounds when
closed. Monitor screen-bound design/expansion gets its own later pass; retain
existing monitor behavior for this tablet slice.

- Tette owns content mode: Search, Apps, later Files. One derived presentation
  request: compact for Search, expanded for either drawer. Files is not built yet.
- Tablet guest expansion uses Kadunce's canonical Active bounds, not a separate
  percentage. It remains a temporary guest lease, never a normal application
  card or Bento member; no real-window restore records are changed.
- Close drawer returns to compact Search. Meta closes the entire launcher.
  Escape retains current precedence: sort popup, drawer, launcher.
- Query, catalogue sort/selection and scroll survive resizing. New invocation
  may retain its current deliberate reset behavior. Expansion alone neither
  launches apps nor invokes the keyboard. Deliberate field focus still can.
- Leave accepted compact search, launch handoff, dock focus and guest cancellation
  behavior intact. Expanded interaction must not pass through to real cards.
- No Files backend, Ambient, global desktop rules, persistent service or redesign.
- Expanded tablet Apps: moderate52px icons (previous42px),112px tile height
  (previous94px). Compact search and monitor drawer retain existing sizes.

## Slice A — shared presentation boundary

Tette src/main.cpp owns requested/accepted presentation and exposes bounds to QML.
Kadunce owns accepted guest bounds and interaction eligibility. Add an independently
negotiated presentation capability to existing protocol3 rather than blindly bump
its version (current Tette rejects any version other than3). Authenticate updates
against the existing guest owner, bind replies to lease/request generation, reject
stale replies after close or replacement. Use asynchronous updates, not blocking
D-Bus calls on pointer motion. No per-frame D-Bus traffic.

Keep compact layout's real-card positions/model unchanged while expanded guest
covers them. Suspend guest horizontal navigation and neighbor selection while
expanded; restore on compact return. Do not resize adjacent real windows.
Input bounds must cover the visible transitioning surface and retire the old
region after completion/cancellation. Tette layer-shell mask and Kadunce guest
hit-tests must share the accepted target/transition envelope; bottom dock remains
outside work-area-based expansion. Cover lease loss, disable and output changes.

Compatibility: compact protocol3 remains functional across mixed installs.
If expansion capability is missing/rejected, use a safe standalone expanded
surface after ending the guest lease, never silently enlarge outside its mask.
Failure should preserve the user's drawer intent and query without duplicate
surfaces. This fallback must be tested before offering independent installs.

## Slice B — existing App drawer proves the contract

QML consumes shared presented bounds; Apps and future Files do not calculate
their own window sizes. Start with a shared interruptible220ms ease-out, reuse
existing drawer behavior and adjust only if J's visual pass warrants it.
For a drag, freeze its reference distance at pickup: revealDistance currently
depends on content.height, so expansion during a held drag would otherwise change
its denominator. Choose expansion on committed drawer-open for the first slice;
partial/canceled pulls stay compact. Closing animates back; a fresh grab interrupts.
Prevent outer guest horizontal DragHandler from stealing drawer/grid gestures.

Standalone/tablet-without-Kadunce uses local available work area and existing
visual gutters. No user-selected dimensions. Monitor-only sizing is explicitly
deferred: preserve its existing treatment, do not add a maximum-width policy,
manual resizing or automatic Bento enrollment in this slice.

## Focused evidence and stop point

Extend tests/tst_Launcher.qml for open/close/cancel, stable drag denominator,
focus/query preservation and content remaining scrollable after expansion.
Controller/protocol tests cover accepted/rejected/stale replies, owner loss,
old protocol3 peer, standalone fallback and synchronized mask cleanup.
Kadunce private checks cover guest hit-testing, neighbor suppression and disable;
run its mandatory control gate if changed. Do not repeat unrelated stack tests.

Then build both packages, preserve exact rollbacks, provide coordinated pinned
installer(s), and let J test tablet Apps expansion, scroll, collapse, Meta toggle,
launch and kill-switch fallback. No auto-install or push. Freeze after acceptance.
Only then begin Files UI/backend work on this same presentation contract.

## Reference handoff

Suite roadmap agrees: Apps and All Files expanded before Ambient. Retrieved recent
CashyOS, Pillow Talk context via task6aa0d9c1-df4c-83ea-a0f8-e0a661b765a3;
it confirms the drawer priority but not the precise Files render. Locate and inspect
that older attachment before Files UI design; no substitute mockup claimed here.
Future Files operations also need a job lifetime independent of the launcher's
current dismiss-and-exit lifetime. Resolve that in the Files backend slice, not
by expanding this sizing batch into a service refactor.
