# Next roadmap

This is Tettegouche's sole canonical execution plan. Current implementation facts
belong in [CURRENT_STATE.md](CURRENT_STATE.md); completed investigations and
physical records belong in [archive/](archive/README.md).

## 1. Ambient release validation

Validate the live providers and responsive compositor as one bounded release
packet:

- real MPRIS play/pause, source replacement, optional metadata, and supported
  previous/next/seek actions;
- Plasma desktop jobs with known and unknown progress, suspension, cancellation,
  producer loss, and concurrent jobs;
- Tette copy/move while the launcher closes and reopens, including progress,
  cancellation, final file state, and clean row retirement;
- direct Downloads arrivals without invented percentage, completion, Open, or
  browser ownership;
- concurrent media and transfer density at tablet and monitor widths, including
  popup access by touch, mouse, and keyboard and a physically centered task dock.

Exit when installed behavior matches [AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md)
and any discrepancy has either a fix with focused regression coverage or a
documented current limitation.

## 1b. The launcher closes when the keyboard is touched

Typing into Tette with the virtual keyboard dismisses the launcher. A touch on
the keyboard reads as a touch outside Tette's own surface, and the dismissal
that follows is correct for every other surface. The keyboard is the exception:
it exists to serve the window that has focus, so a touch on it is not a touch
away from that window.

Recorded from physical use on 21 September. Search is unusable by touch until
this is answered, which makes it a release matter rather than polish.

The input panel is a compositor fact and is identifiable without any downstream
surface, so the fix stays inside Tettegouche and holds on an ordinary Plasma
panel. Kadunce carries the same blind spot in its own form and is being fixed
separately; neither fix depends on the other.

Exit when a full search can be typed by touch without the launcher dismissing
itself, and a touch genuinely outside still dismisses it.

## 2. Transfer robustness

Add useful operation progress and cancellation inside Files, explicit conflict
choices that preserve the current no-silent-overwrite guarantee, and tests for
large copies, interruption, unavailable destinations, and partial success. Keep
KIO ownership, quit deferral, and truthful Ambient projection.

## 3. Desktop file integration

Add external application/file-manager drag and drop, Open With, and properties.
Preserve the existing internal drag-copy rule and never reinterpret an external
operation without an explicit action.

## 4. File discovery

Design bounded asynchronous thumbnails/previews, recursive search, and Recent.
Set resource budgets and cancellation behavior before implementation. The
current directory filter must remain distinct from recursive or indexed search.

## 5. Storage lifecycle

Handle removable mount, unmount, eject, stale/offline locations, and optional
network locations without blocking launcher startup. Preserve asynchronous
listing and avoid readiness/stat probes on saved mounts during construction.

## 6. Release hardening

Complete keyboard and accessibility audit, large-directory and live-change
coverage, stale Trash-record reconciliation, scaling/panel-size checks, and
tablet/monitor physical validation. Split view and a full Trash browser remain
separate power-user work.

## Execution rules

- Work in related packets of two or three capabilities, with one implementation
  owner per packet.
- Establish an authoritative data source and a narrow fixture before changing
  presentation or lifecycle behavior.
- Do not add a daemon, polling loop, persistent activity history, compositor
  ownership, replacement task manager, or cross-product state owner.
- Use disposable fixtures; never test destructive operations on user files.
- Move completed packet evidence to `docs/archive/` and update current contracts
  only when accepted behavior or an invariant changes.
