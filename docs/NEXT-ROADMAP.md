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

A further source follows the validation (suite plan, Block 6): an application
whose dialog is waiting for the person. Kadunce keeps such a dialog hidden with
its application and raises Plasma's standard attention flag on the
application, so Ambient reads that flag from Plasma's task model and depends on
nothing in Kadunce. The row names the application, leaves when the flag drops,
and its one action asks Plasma to activate the application, which brings it
forward with its dialog. Whether an application's own attention request, with
no dialog behind it, also earns a row is decided with J first; the admission
rule in [AMBIENT-CONTRACT.md](AMBIENT-CONTRACT.md) changes when the row is
built.

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
