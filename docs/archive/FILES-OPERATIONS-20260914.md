# Rename, clipboard move, and recoverable Trash

Accepted by J after UI checkpoint a230c82; not pushed by agent.

- Rename via F2 or context menu, reusing the inline name field. One listed item,
  valid single name, no overwrite. Name form checks its captured selection before
  submitting, so a changed selection cannot rename a different item accidentally.
- Cut via Ctrl+X/context menu publishes native local URLs and KDE cut marker.
  Clipboard Paste now honors that marker and MOVES; ordinary copy and file
  dragging stay COPY. This supersedes the earlier copy-only paste policy.
  Successful move clears only an unchanged matching cut clipboard. Failed batch
  moves retain clipboard and report possible partial completion; no automatic retry.
- Delete/context menu opens confirmation to move selection into platform Trash.
  No permanent-delete fallback. Unsupported Trash locations fail without deleting.
- Restore last trashed item is available in the actions menu, one item at a time.
  Tette's Trash URLs persist in QSettings across restarts. Successful recovery
  removes the entry; failed recovery preserves it. Existing destinations are not
  overwritten. This is not a full Trash browser or general undo system. Externally
  deleted/restored trash entries may need handling in a later reconciliation pass.

All writes use asynchronous KIO jobs with existing quit deferral. Full failure
details appear in the wrapping error area, not solely the elided status line.

Verification: isolated native suite passed all seven tests, including rename
collision, cut/move, Trash, restart-persistent recovery and restore collision.
Temporary /tmp mount could not provide Trash; test rerun on home filesystem with
isolated TMPDIR/XDG_DATA_HOME succeeded. The Trash test skips unless explicitly
given an isolated tette-trash-test.* data directory to avoid touching user Trash.
QML tests exercise F2, Ctrl+X and Trash cancellation along with prior interactions.

Install: install-tette-files-operations-20260914.sh in workspace root.
SHA256 d11db35a2162606b61946ecb5dd4bad9e431870bf74d5d8cb873af51d843aedb.
Rollback is accepted 119ebd0f UI. J reports all checks passed.
