# Explore files interaction pass

Status: mouse/keyboard and touch correction accepted by J; frozen for main.
Installed /usr/bin/tettegouche matches the accepted candidate SHA256 below.

Previous selection/copy corrections passed J's checks (997b6ff binary). This
pass supersedes the auto-enter-on-create behavior in FILES-COPY-20260914.md.

## Interaction contract implemented

- Current folder, selection, keyboard focus and clipboard are separate state.
- Mouse click selects; double-click opens. Ctrl toggles and Shift selects ranges.
- Empty-space click clears selection, retaining copied files on the clipboard.
- Right-click preserves a selected group or selects the targeted item. Folder
  context offers explicit Paste into; background Paste here and Ctrl+V use the
  current folder. Pasting into a child does not navigate into it.
- Arrow/Home/End navigation, Shift ranges, Ctrl focus movement, Ctrl+A/C/V,
  Alt+Left/Right/Up, Ctrl+L and selection Escape are available.
- Touch tap selects folders and files; double-tap opens either. A 500ms hold
  reveals selection/context actions. Controls
  are contextual rather than requiring mouse users to enter touch Select mode.
- New folder creates and selects in the current folder, without entering it.
- Copy remains asynchronous, local-only, never silently overwrites, and does
  not reinterpret external cut clipboard contents as a move.

## Verification and bounds

Native temporary-folder tests cover create/select, clipboard survival after
deselection, paste into a child without navigation, and collision protection.
QML tests cover mouse selection, blank click, context paste and Escape. Build
and source checks pass. Large-copy physical testing remains deferred.

Rectangle selection, drag/drop, rename/trash/recovery and broader keyboard
accessibility remain subsequent work; this is not the full desktop contract.

Installer: ../install-tette-files-interaction-20260914.sh (workspace root).
Candidate SHA256: 23b11dcc64d970c3f02e6f111f30632fb4efdd0f99c655c26efccdd1f60ac693.
Rollback SHA256: 997b6ff1ef8baadee914dcca36d9f2d6d77129b72901fea7ce40794959aa4462.

## Touch correction

J reported every tap opening the context menu. The right-button TapHandlers
still accepted touchscreen input; restrict those handlers to mouse/touchpad.
Touch now selects folders instead of entering immediately. Hold-to-drag range
selection is deferred rather than sharing the context-menu hold gesture.

Synthetic touch tests pass for folder selection, double-tap open, file selection,
500ms hold menu, release without opening, and empty-space deselection without a
menu. Existing mouse/keyboard controls tests pass (12.55s complete QML suite).

Installer: install-tette-files-touch-20260914.sh in workspace root.
Candidate: 0457a9321436cee052742e250f5f5d7a21c65da3012afb14edd36f353b96e303.
Previous-build rollback is interaction binary 23b11dcc (mouse/keyboard passed, touch
not accepted); earlier selection rollback remains separately preserved.
