# Ambient activity contract

Ambient Tette answers what matters now. It presents ongoing media and transfer
state in the right-side panel strip while Temperance remains responsible for
notifications and transient events.

## Admission and ownership

An item may enter Ambient only while it has meaningful current state, continued
presence is useful, a source owner is identifiable, and available actions can be
routed truthfully to that owner.

Current sources are:

- MPRIS media sessions;
- running or suspended jobs from Plasma's shared desktop-jobs model;
- Tette-owned KIO copy/move operations through the launcher's activity bridge;
- filesystem evidence for new direct children in the configured Downloads folder.

Static system status, completed work, ordinary notifications, and historical
activity do not remain in Ambient. Ambient owns composition and routing; it does
not own the source operation or retain a completion history.

## Lifecycle and truth

- An activity appears, updates in place, and leaves with its authoritative
  source. Owner generations reject stale actions after source replacement.
- Paused resumable media remains visible. Lost/stopped jobs leave. A hidden
  Tette launcher may remain alive to finish and publish an operation.
- Source fields and actions override filesystem enrichment. Filesystem evidence
  merges only on exact destination and current file identity; there is no suffix
  guessing.
- Determinate progress, transferred bytes, ETA, completion, and controls appear
  only when the source supplies evidence. Unknown progress stays indeterminate.
- Source loss, quiet filesystem state, cancellation, and disappearance must not
  be presented as successful completion.

## Provider behavior

### MPRIS

Discovery takes an initial snapshot and then follows owner, property, and seek
events. Missing title, artist, duration, or capabilities remain absent. The
presentation clock advances from source position/rate samples and freezes on
pause. Controls require current capabilities and owner validation.

### Plasma desktop jobs

Tettegouche consumes Plasma's shared jobs model in process; it never registers a
competing job-view server. Running and suspended jobs expose only the identity,
progress, counts, descriptions, and controls supplied by that model. Zero
percent without a total is unknown progress.

### Tette operations

`FileBrowser` and KIO keep ownership. The launcher publishes revisioned snapshots
and UUID-checked Cancel over its activity D-Bus interface. The applet validates
the source owner generation before dispatching an action.

### Incoming files

A nonblocking inotify descriptor observes the Downloads directory and its parent
for recovery. Direct writes, witnessed renames, atomic arrivals, preallocation,
and disappearance are filesystem evidence. Observed length is file size, not
bytes transferred. Rows retire after bounded quiet observation without claiming
completion.

Only ordinary local direct children are covered. There is no recursion, browser
scraping, notification parsing, or polling fallback. mmap writes and remote
filesystem changes may be missed. Overflow or watch invalidation clears uncertain
state and rearms without inventing missed work. Existing files are not admitted
merely because the applet starts.

## Responsive composition

Every activity receives its minimum useful core before any activity receives
descriptive context. Core contains recognizable state and an essential supported
action. Context may add name, title, artist, byte count, duration, and other
source-backed detail.

Width reveals information, not capability. Optional context compresses before a
core disappears. Similar transfers may group when all individual cores cannot
fit; the group opens a local list with truthful per-source actions. Each activity
opens its own compact popup rather than a combined dashboard.

The Tette launcher forms the left edge of the right-side composition. Ambient
uses the measured space between it and the centered application dock. Temperance
flexes independently on the left. Neither side may displace the application dock
from the physical display center.

## Interaction and safety

- Touch, mouse, and keyboard must reach equivalent source-supported actions.
- Popup actions affect only the identified source and disappear when unsupported.
- Closing a popup returns directly to Ambient; it does not open full search.
- Empty Ambient leaves clean panel space.
- Do not add a daemon, polling loop, persistent history, replacement task
  manager, notification-derived progress, or cross-product activity owner.
