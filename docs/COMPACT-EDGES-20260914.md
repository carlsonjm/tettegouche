# Compact edge hierarchy

Accepted by J and frozen after accepted file operations. Compact view only:

- Resting search is centered between the mirrored edge affordances, with equal gaps.
- Both compact and expanded drawer labels are lowercase.
- Handle centers sit 12 logical pixels from top/bottom sheet edges. Labels face
  inward, with their nearest edge 30 pixels from the corresponding sheet edge.
- Labels use 12px type and reduced alpha; independent hover brightens them.
- 48px edge interaction groups retain touch pulls. Bottom handle interpolates
  into the unchanged expanded close control; Files opening fade remains intact.

Launcher QML suite passed, including geometry, independent hover, drawer routing,
and existing file interactions. Compact rendered preview inspected. Physical
acceptance passed. Nothing installed or pushed automatically by the agent.

Installer: workspace install-tette-compact-20260914.sh.
SHA256: 6adb24d71f7ebf6451c2bddbdec60ad92d356bf3a9e41c53c07c94eebd3ffb82.
Rollback: accepted d11db35a file-operations build.
