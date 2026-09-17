# Explore files — slice 3: selection, copy and folders

Historical slice notes below. Final accepted behavior is recorded in
[Files interaction](FILES-INTERACTION-20260914.md): tap selects, double-tap opens,
and new-folder creation selects in the parent rather than entering it. The final
0457a932 binary is installed and accepted. Large-copy physical checks stay deferred.

bc4a23d installed: J passed touch controls/snappiness, reported create/path issue
and missing direct mouse multi-selection. Large-copy lifecycle test deferred.
Corrective candidate 997b6ff, not installed/accepted/pushed. Accepted opening checkpoint:
cdcf5c1 (binary 7ef47e2), preserved as rollback.

Select mode toggles file/folder membership, with checkmarks and count. Done
selecting clears selection. Normal folder taps still navigate; single-file Open
is preserved. A selected folder's Open navigates instead of launching an app.
Selection lives per tab; entering a new folder clears it. Copy validates selected
URLs against the current listing and publishes native URL clipboard data. Paste
always COPIES even if another application marked clipboard items as cut. Local
URLs only; no shell quoting/execution. Copy/ Paste shortcuts are scoped to grid
focus so text editors retain their own clipboard behavior.

Correction: Ctrl-click toggles directly without touch mode; Shift-click selects
the visible sorted range from the anchor; Ctrl+Shift adds that range. Separate
modifier-specific pointer handlers avoid ambiguous modifier inspection or folder
navigation. Successful mkdir enters the new folder and updates crumbs immediately,
unless navigation/tab state changed while it was pending. The launcher catch-all
typing handler excludes Return/Enter, preventing a closing name editor from
injecting an invisible search filter; successful folder entry clears search.
Tests cover mouse modifier dispatch, range membership, Enter without filter
contamination, and new folder path/crumb agreement. Large copy remains untested
physically, not silently promoted to pass.

KIO copy and mkdir jobs are asynchronous. No Overwrite flag and no conflict UI
delegate; a collision stops with a visible error, never silently overwrites.
Already-copied items may remain after a partial failure (explicit status warning).
Folder names reject empty, dot/dotdot, slash and NUL. No move, rename, deletion,
auto-rename, merge prompt, undo or cancellation control in this slice.

One write job at a time. Closing/handoff hides Tette and releases its guest lease
immediately, but process quit is deferred until the job finishes. Reopening
cancels deferred quit and shows progress/status. Late errors are stored for next
process opening. Forced termination is not protected; a partly copied item may
remain. This is not a persistent background service. Open-file launch is blocked
during a write job; unrelated app launches still follow normal dismissal with
the same deferred-quit guard. Navigation remains independent of job destination.

Verification: build, source guards, diff check; QML controls including folder form
show/cancel; private-bus actual temporary-file copy of two files and nested folder,
duplicate request guard, collision leaving destination bytes unchanged, invalid
folder name and existing-folder refusal. No user-file writes in testing. Live
close/reopen during copy is a J acceptance check, not claimed automated coverage.

Installer ../../install-tette-files-copy-20260914.sh; restart Tette. J checks:
create a throwaway folder; select two disposable files, Copy, navigate to the new
folder and Paste; confirm both and original files remain. Repeat Paste to see
conflict refusal. If copying a larger disposable file, close/reopen Tette while
it runs and confirm completion. Rollback uses --rollback. Nothing pushed.
