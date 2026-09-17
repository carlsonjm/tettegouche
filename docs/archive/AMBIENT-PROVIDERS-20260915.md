# Ambient production-provider candidate — September 15

Source-only A2 candidate based on the accepted B1 main at `8cc4531`.
Not installed, pushed or physically accepted. The accepted compositor, panel
order, mirrored geometry, stock clock and per-activity popups are preserved.

## Behavior and ownership

Normal applet startup uses real providers, shared once per plasmashell process.
`TETTE_AMBIENT_FIXTURE=transfer-media` and `paused` remain explicit demo/test
overrides. With no relevant source, normal Ambient is empty.

- MPRIS: one initial discovery/snapshot followed by owner, property and seek
  events. Session owner generations reject stale actions. Paused resumable
  sessions remain visible. Optional title/artist/duration stay absent when not
  supplied. The accepted local presentation clock uses source position/rate
  samples and freezes on pause. The popup's seek action is explicitly Forward
  10 s. Controls require current source capabilities and owner validation.
- Desktop jobs: consume Plasma's shared `NotificationManager::JobsModel` in
  process. Never register a competing JobViewServer. Running/suspended jobs
  supply progress, counts, descriptions, identity and supported controls.
  Default zero percent without totals is unknown. Stopped/lost jobs leave.
- Incoming files: one nonblocking inotify descriptor and QSocketNotifier watch
  the configured Downloads directory and its parent for directory recovery.
  Direct writes, temporary names, witnessed renames, preallocation, atomic
  arrivals and disappearance are handled as filesystem evidence. Show in Files
  revalidates the actual file identity and opens Tette's existing Files drawer.
  No source identity, percentage, ETA, Cancel or Open is inferred.
- Tette transfers: FileBrowser/KIO still owns the operation. The existing
  launcher process publishes revisioned snapshots/events and UUID-checked Cancel
  on `/Activities`, interface `io.github.carlsonjm.Tettegouche.Activities1`.
  The applet validates the source owner generation before dispatch. Closing or
  hiding the launcher releases its presentation; outstanding work keeps its
  event loop alive. Reopening uses the existing process. KJob `finished` also
  clears quietly canceled work. This selectively reuses the earlier candidate's
  lifecycle approach without importing its Files collision UI or Ambient state.

Authoritative rows absorb filesystem evidence only for exact destination and
matching current file identity. Concrete destinations witnessed during a
multi-file job remain aliases for that job's lifetime. Source fields/actions
win; enrichment retains the visible row ID and replaces its action token.
Consumed file bursts do not reappear after job removal. Directory-only,
ambiguous or unreported temporary destinations cannot be safely merged; these
remain separate until exact source evidence exists. No suffix guessing.

## Filesystem limits

Observed size is logical file length, not bytes transferred; preallocation never
becomes progress. Close/move-in starts a 2-second quiet deadline, other write
bursts use 5 seconds. Expiry checks identity/metadata and permits at most one
additional check if metadata changed without a delivered event. New events rearm
observation. Quiet rows retire without a completion claim or history.

Only ordinary local direct children are covered. No recursion, browser scraping,
notification parsing or polling fallback. mmap writes and remotely performed
network-filesystem changes may not be observed. Watch invalidation/overflow
clears uncertain state and re-arms when possible without inventing missed jobs.
An existing file is not admitted merely because the applet starts.

Zen currently supplies no verified Plasma job. Its local Downloads writes may
appear only as Incoming file, with actual name, observed size, unknown progress
and Show in Files. Completion cannot be proved by quiet time; Open stays absent.

## Validation

Build: RelWithDebInfo with the existing /usr install prefix, source-only output.
Build and all 11 CTest targets pass, including the corrected focused provider
rerun. Source/package checks and whitespace validation pass. A sandbox-denied
private-bus startup was rerun successfully with test permission; it was not a
provider failure.
Focused private-bus tests cover MPRIS metadata/capabilities, paused clock, seek,
owner replacement/stale actions; real shared JobsModel unknown/known progress,
suspend/resume/cancel and producer death; Tette's actual KIO operation bridge,
navigation independence, source-name loss/reacquisition and stale Cancel.

Disposable file tests cover initial emptiness, write/rename identity,
preallocation, quiet retirement, later writes, deletion, atomic arrival and
Downloads directory recreation. Projection tests cover exact merge, authority
token replacement, consumed burst suppression, stale file actions and an
unmergeable directory destination.

The existing panel, Ambient, launcher, Files and application-context suites are
run along with source/package checks. A separate compiled-applet fixture test
checks the explicit demo override. The existing Trash fixture remains subject to
its isolated-data-directory skip; this packet does not broaden Files acceptance.
Actual launcher surface close/reopen, installed apps and physical centering
remain J's acceptance checks, not a claimed automated physical pass.

## Install and physical gate

Install this candidate worktree using the existing `./install.sh` only when J
requests installation. Clear `TETTE_AMBIENT_FIXTURE` from the Plasma launch
environment for normal-source acceptance, then restart Plasma once through the
existing installation workflow. Preserve the panel arrangement and clock.

Check:

1. Real media play/pause, paused retention, next/previous where supported, and
   compact popup actions; verify missing metadata does not show invented text.
2. Real Tette copy/move: close/reopen the launcher during work, see progress and
   Cancel, and verify the underlying operation and final file state.
3. Zen writing into Downloads: Incoming file, unknown progress, observed file
   size and Show in Files; no percent, browser controls or uncertain Open.
4. Concurrent media + transfer compression at narrow/wide sizes and grouped
   activity access; keep essential controls reachable.
5. Source exit, cancellation and completion remove activity without duplicate
   outcomes. Check touch/mouse/keyboard and dock centering on tablet and monitor.

Do not push or mark accepted before J reports the physical pass.
