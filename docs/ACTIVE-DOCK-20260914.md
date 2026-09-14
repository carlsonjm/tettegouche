# Active dock clearance and launcher target

Installed by J and accepted on connected displays and unplugged tablet-only.
Freeze/push authorized. Accepted Files freeze is 5de4c8d.

Kadunce Active uses the same additional 10px bottom allowance as Bento when
the output's MaximizeArea reserves bottom space. Default gutter remains 10px.
No bottom reservation means symmetric gutters, including a tablet whose dock
has moved to the external monitor. This is placement geometry, not a new dock
visibility observer or resize loop. Existing guest floating-dock clipping stays.
Tette standalone expanded drawers use matching 10px top/20px bottom margins
when availableArea reserves bottom space; otherwise 10px all around. Guest
drawers consume Kadunce's Active target as before. Compact geometry unchanged.

Applet layout is now 42x42 rather than 26x42/42x26; circle remains 16px centered.
Thin panels can still constrain the cross-axis. Meta/focus behavior unchanged.

Evidence: production builds pass; CardLineLayout/carry-paint pass; launcher QML
passes including dock-free drawer bounds. Isolated panel test passes horizontal,
vertical, constrained panel, pointer/touch outside glyph and activation routes.
Required verify-control passes. Live safety and pinned installer verified separately.

Read-only hardware audit: DP-1 primary 2560x1440@144, scale1, origin1463,0;
eDP-1 2560x1600@180, scale1.75, logical1463x915 at0,241. Panel164 configured
floating,52px thick,lastScreen0; ActiveCardGutter10. No settings changed.
Saved screen indices alone are not proof of live work-area geometry.

Installer: ../install-active-dock-20260914.sh (workspace root). Three artifacts:
Tette binary, Tette applet plugin, Kadunce plugin. No engine/repair/Temperance.
Rollback uses the exact installed files captured before this pass. Installer
checks hashes before writes. Save work and log out/in to load plugins.

J reports connected displays and unplugged tablet-only passed. Installed hashes
match all three pinned candidates; post-install live safety verified.
Ghostty retains a reported stray 1px line below its window that triggers the
flat dock. Track separately: cause unconfirmed, not fixed in this freeze.
Auto-hidden/no-strut Active docks remain a separate physical
check: the new allowance is based on reserved work area, not a cached dock size.
