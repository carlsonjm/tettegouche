# Expanded drawer header above search

Routing correction candidate 119ebd0f7b2880b345945083ff08a540ebff24364f0fcd0b76ab84ded2de44b6:
J reported bottom App pull opening Files. Closed drawers preserve filesMode for
closing animation; drawerDrag incorrectly reused it for the next opening gesture.
Capture gesture mode on activation: closed bottom pull always Apps; expanded
header drag retains its current drawer. Tests now exercise Files pull, close,
then bottom touch pull and assert Apps. QML suite passed (15.52s).
Installer install-tette-files-routing-20260914.sh; no push. Its rollback is the
preceding spacing build, which retains this known routing bug.

Follow-up candidate: 27ce3026801ecda6df12200f405cc5f6aa95710ea00917408ee500e558babb1f.
J approved header direction and requested label insets, more search clearance,
and a divider under breadcrumbs. Expanded labels inset 18px left/14px right;
search starts at 64px, giving the 44px header 20px clearance. A 1px neutral
divider uses the existing 12px layout gaps above/below. Files pull now shares
App pull openingControls fade/translation and drawer-progress fade, replacing
its abrupt visibility cutoff. Compact label placement stays unchanged.
Installer: install-tette-files-header-spacing-20260914.sh; rollback fa53a70a.
Physical acceptance pending.

Candidate: fa53a70a0180747f40508ddbf1688c32b6159745bd7dcb67de9eca1328d92434.
App and Explore files expanded modes now share header at top, search below,
then content with a 16px gap. Compact labels/grabbers remain in their established
positions. Existing 260ms search motion and drawer progress drive transitions;
content follows the moving search field rather than the former header position.

Files action row remains below breadcrumbs. Pill backgrounds inset 5px at top
and bottom, with 16px horizontal padding; 42px input height retained.
Touch timing remains the 180ms trial. Dock/Active bounds untouched.

Build/QML controls suite passed (14.41s), including expanded header order,
return to compact view and existing touch/drag behavior. Render inspected.
Physical acceptance pending. No install/push performed.
Installer: install-tette-files-header-20260914.sh in workspace root; rollback is
the preceding b4bceaeb chrome candidate. Accepted drag build remains preserved.
