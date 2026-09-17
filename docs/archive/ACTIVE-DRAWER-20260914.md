# Accepted tablet Active drawer freeze

J passed the final compact hierarchy and authorized freeze/push September14.
Installed Tette b681ec7ee486bfd085144b138e354b1c015d8f4336ed87e7ed3a3bbf24b6350d
and Kadunce bec4d8a60dc4129510efef936cefbe06dc7b92990f42c3ea3a34e5eed5959277
verified; live safety switch passes. All drawer motion/card movement, dock-safe
bounds, header layout and compact tab hierarchy are J-accepted. Monitor-specific
expanded bounds remain deferred. Local pinned installers preserve rollback;
fresh clones build through normal install.sh. Earlier candidate notes below are
historical provenance, not current installation status. Files is the next slice.

## Historical implementation and test notes

Compact hierarchy followup: J accepted installed header d509f7. Candidate b681ec
moves Browse everything below the compact pull tab. Tab bounds interpolate on
drawerProgress instead of switching at drawerOpen; bar/label fade out before the
expanded close pill fades in. Reverse and partial pulls use the same clock.
QML hierarchy, intermediate bounds, open/close and spacing tests pass. Not installed
or pushed. ../../install-tette-tab-20260914.sh updates only Tette; rollback d509f7.

Latest: J passed all drawer motion/card movement on installed bfe821 Tette and
bec4d8 Kadunce. Header-only followup d509f7 centers the Close drawer pill on the
header axis, removes its chevron, and uses equal28px gaps between search/header
and header/grid. QML alignment/spacing/click checks pass. Not installed or pushed.
Install ../../install-tette-header-20260914.sh; one launcher binary only, rollback
to bfe821. Kadunce and all passed motion/ownership behavior remain unchanged.

September14: first candidate installed; followup below awaits physical acceptance. Bases: Tette bdf4523,
Kadunce a6ce03e. Compact search, panel toggle/dock focus and monitor behavior stay.

Committed Apps opening requests expanded presentation asynchronously. Protocol3
remains unchanged; beginLauncherGuest advertises presentationCapability1. Kadunce
validates caller against the live lease owner, uses canonical Active hit bounds,
resets horizontal offset and suppresses guest navigation while expanded. The guest
does not become an app card or Bento member; real card geometry is not modified.
Closing returns to compact;220ms visual bounds transition precedes mask contraction
and compact bridge request at260ms. Generation guards reject superseded callbacks.
Meta still dismisses; Escape closes sort menu, drawer, then launcher.

Tette applies accepted Active bounds to its input envelope before expanding.
Failed/old capability ends the guest lease and uses standalone tablet expansion.
Standalone eDP uses work area minus10px gutters. External-screen standalone sizing
is unchanged. Bridge loss preserves drawer intent; screen bounds change ends the
lease and safely falls back. No per-frame bus messages or manual resizing.

Drawer drag reference distance is frozen at pickup; only committed open expands.
The outer horizontal guest drag is disabled while a drawer is open. Tablet expanded
icons52px versus42px and tile height112px versus94px; other sizing unchanged.
Search query and sort model are not reset by bounds changes; physical scrolling,
focus and transition feel still require J acceptance. No Files/ambient feature.

## Evidence and limits

Production builds, Tette source/package guards, launcher-controls and workspace
context tests passed. QML tests cover existing controls and expansion/collapse.
An initial test failure caught overlapping center/size animation; standalone now
derives center directly from animated size. Private guest protocol fixture with
Virtual-0 tablet: /tmp/kadunce-unload-test.z7ivQr passes owner validation, Active
bounds, expansion/collapse, navigation suppression, closed lease and owner loss.
Initial private attempt M4znwo had no test window and was not a passing test.
Fixture change reverted and production rebuilt. Kadunce control gate and read-only
live safety pass. Mixed-version fallback/stale replies are code-reviewed, not a
full two-app private integration test. J owns physical touch/launch acceptance.

## Pinned install and rollback

../install-tette-active-drawer-20260914.sh installs TWO binaries only, with preflight
hashes and backup; --rollback restores both. No applet/Temperance changes.
Save then log out/in afterward to load the guest bridge. No automatic restart.

Tette candidate: b61483f5d4e9c7b1119d27b79be828c242c101a6f23207b0b9a8a950da6b8eb1
Tette rollback: a947545e571bc3e333301ebf3a80d3c2847424caf8b7fe5597e02ead37f0902e
Kadunce candidate: 3220b821f4c0d0fc22183e35de58537617d88fa11d01134b1bb3bb26a0cb848e
Kadunce rollback: e59f5b62ecb8f9d1c122ece2db03e1d9d62a3267584eb15be73e28a440ef29b9

J checks: pull/tap Apps opens Active with comfortable icons and working scroll;
close/cancel returns compact without jumping; launch, Meta toggle and Kadunce
disable still clean up. No monitor expansion acceptance claimed. Freeze only
after J's pass; Files UI reference still needs locating before that next slice.

## Followup: dock, dismissal, neighbor motion and center ownership

J confirmed first-candidate open/close, but reported exposed neighbors, dock
overlap, unclear dismissal and a real center card above Tette on return.
Followup is built, NOT installed or pushed. Expanded bounds intersect Kadunce's
visible-dock safe area with10px clearance; expanded input mask matches exactly.
Close drawer is a labeled chevron pill, retaining downward drag and Escape.
Neighbor presentation uses220ms outward slide/fade and reverses after the drawer
collapses. It changes no native geometry, selection or order. Stack elevation
and stack raising are suspended throughout the guest lease, including compact
return, and restored only when Tette leaves. This addresses a code-level layering
conflict; J's exact stuck-center reproduction remains a physical acceptance test.

QML controls/workspace-context, floating-dock model and control/live safety pass.
Private /tmp/kadunce-unload-test.xvnGsl passes finite opacity departure/return,
owner validation, closed lease, owner loss and unload. Earlier64NSdT failed because
the diagnostic field was inserted in the trace instead of the state reply; corrected
before the passing run. Private fixture removed; production rebuilt. No full
two-app visual test or monitor acceptance claimed.

Installer: ../../install-tette-drawer-polish-20260914.sh (two binaries; --rollback
restores the installed first drawer candidate). Original installer retains the
pre-drawer accepted rollback. No automatic restart. Save then log out/in.

Tette followup: bfe821ba7d18882ab010728d7c687661b19f7868604ab059efdc5148cce656a8
Kadunce followup: bec4d8a60dc4129510efef936cefbe06dc7b92990f42c3ea3a34e5eed5959277

J checks: open above dock with neighbors departing; close by pill/drag with
neighbors returning and no center card covering Tette; repeat with a selected
stack, then dismiss Tette and check normal stack order/interaction.
