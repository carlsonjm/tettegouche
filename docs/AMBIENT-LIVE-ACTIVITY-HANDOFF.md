# Ambient Tette — live activity handoff

Status: B1 compositor implemented and physically accepted by J on September 15,
2026. The accepted source is frozen on main by contract commit `715626c` and
integrated implementation commits `4317116` and `5ad0ca6` (accepted candidate
commits `7ea93ec` and `e8f9ab3`). Production activity providers remain A2.

## Accepted B1 freeze

The final right-side panel order is:

```text
Tette launcher → responsive Ambient strip → task dock
```

Temperance mirrors the responsive geometry on the left side. The application
dock remains physically centered between the two allocations. Each activity
opens its own compact, Temperance-style popup anchored to that activity. The
earlier combined full-screen activity view was removed before acceptance.

B1 remains a fixture-backed compositor. `TETTE_AMBIENT_FIXTURE=transfer-media`
exposes the acceptance transfer and media models; it is not a production data
provider. Real Tette file-operation, MPRIS, and supported desktop-job providers
and their action routing remain exclusively in A2.

## Product role

Ambient Tette answers **what matters now**. It presents ongoing context whose
continued state remains relevant: media playback, a file transfer, a recording,
a timer, or another live activity.

This is distinct from Temperance, which answers **what changed**. Temperance
currently presents notifications in the left-side ticker; broader system events
and state-change summaries are a future Temperance slice, not current behavior.
Ambient Tette owns the right-side dock surface. The centered application dock
remains stable between them.

There is no fourth Live Rail product. Tette and Temperance retain separate
ownership:

- Tette owns relevance, activity ranking, responsive density, right-side
  presentation, and local expansion.
- Temperance owns notification presentation today and the future transient-event
  surface on the left.
- Source applications and services own activity truth, lifecycle, and actions.

The system should infer the obvious next state instead of requiring another
mode. Ambient stays local and directly actionable; it does not become a dashboard.

## Admission contract

An item may enter Ambient only while it has meaningful current state, continued
presence is useful, a source owner is identifiable, and actions can be routed
truthfully to that owner.

Initial V1 source classes:

1. Tette-owned file copy/move operations.
2. Desktop download/file-operation jobs exposed by supported KDE infrastructure.
3. MPRIS media sessions.

Next candidates after the contract proves sound: screen recording and timers,
then installs/updates, rendering/export, compression and synchronization where a
reliable source interface exists.

Static battery percentage, Wi-Fi state, Bluetooth state, device connections,
completed work and ordinary notifications do not remain in Ambient. Their value
is in a transition or system control and therefore belongs to Temperance's future
event slice or an existing source notification.

## Lifecycle

An activity appears when its authoritative source starts or becomes relevant,
updates in place, and leaves when the source finishes or ceases to be relevant.
Ambient may animate it out but does not retain completion history. Until the
Temperance event slice exists, completion/failure/cancellation continues through
the source's existing notification behavior; Ambient must not fake that handoff.

Ambient survives ordinary Tette search and Files drawer presentation changes.
Closing the launcher must not cancel source-owned activity. Loss of a source
removes its activity safely; it must not invent a successful completion.

## Responsive activity compositor

Ambient packs concurrent activity rather than selecting one winner. Every active
item receives its minimum useful **core** before any item receives descriptive
**context**.

Core contains recognizable state and an essential direct action. Context contains
names, artist, filename, transferred size, duration and ETA. Importance determines
which context compresses first, not which activity disappears.

Examples for a download plus media:

```text
very narrow   ↓ 68%   ⏯
narrow        ↓ Fedora · 68%   ⏮ ⏯ ⏭
medium        ↓ Fedora.iso · 68%   ⏮ ⏯ ⏭ · Houdini
wide          ↓ Fedora.iso · 3.2/4.7 GB · 68%   ⏮ ⏯ ⏭ · Houdini · Dua Lipa · 2:41
```

Width reveals information, not capability. A compact item exposes the same
actions through its tap target/local expansion as a wide item.

| Activity | Core | Context as width increases |
| --- | --- | --- |
| Download/transfer | activity glyph + progress; Cancel when supported | name, bytes, ETA |
| Media | play/pause | title, artist, elapsed/duration |
| Recording | live indicator + Stop | elapsed time, source/window |
| Timer | remaining time | label, pause/reset |

When distinct activity cores cannot fit, group similar activities rather than
silently removing a class: `↓ 3 transfers · 68%   ⏯ Houdini`. A local expansion
reveals individual jobs and truthful source actions.

Use determinate progress only when the source provides it. Unknown progress stays
indeterminate. Do not invent ETA or infer live state from notification text.

## Dock geometry

Temperance flexes inside the left allocation. Ambient Tette flexes inside the
right allocation. Neither may move the center application dock away from the
physical display center.

Engineering must inspect the current Plasma panel layout before selecting the
mechanism. Independent anchors, symmetric allocation or another verified layout
are acceptable; changing the accepted task-dock center position is not.

The Tette launcher forms the left edge of the right-side composition. Ambient
fills the responsive strip between that launcher and the task dock. It must
remain usable at tablet and monitor widths, supported scaling, and supported
panel sizes.

## Interaction

- Tap an activity to reveal that activity's compact local popup and
  source-supported actions.
- Keep concurrent activity cores visible while space permits.
- Group counts open a compact local list of grouped activities.
- Close returns directly to Ambient without opening full search or another mode.
- Mouse hover may reveal controls, but touch and keyboard have equivalent access.
- Actions appear only when the authoritative source exposes them.

## Engineering packets

### A0 — source and geometry feasibility

Owner: A-Team/Astra. Read-only first.

Inspect installed Plasma/KDE APIs and current Tette/Temperance panel code.
Identify authoritative interfaces for KIO/desktop jobs, Tette file operations and
MPRIS. Prove whether progress, identity, lifecycle, grouping and actions are
available without polling or a new always-on daemon. Measure the current dock
layout and identify the smallest way to preserve its physical center.

Deliver an exact provider contract, ownership map, unavailable fields, proposed
files, focused tests and estimated packet split. A notification is not proof of
a live job. Stop before implementation if browser download progress is not
reliably observable.

### B1 — responsive compositor

Owner: B-Team/Sol after A0 fixes the provider interface.

Build the right-side Tette surface against a bounded activity model. Prove the
core/context density ladder, concurrent transfer plus media, grouping, local
expansion and center invariance. Use fixtures only for fields A0 proves available.
Do not add a provider, daemon, history store, Temperance UI or launcher dashboard.

### A2 — production providers and integration

Owner: A-Team/Astra after J accepts B1's interaction.

Implement approved authoritative providers and action routing. Connect Tette file
operations first, then MPRIS and supported desktop jobs. Add lifecycle and
source-loss checks. Do not block this packet on future Temperance event expansion.

### B3 — Temperance event expansion

Owner: B-Team/Sol as a separate later Temperance slice.

Expand the existing notification-only left ticker to supported non-notification
system transitions and activity outcomes. Define authoritative event sources,
deduplicate existing notifications, and keep events transient. Do not retain live
progress or make Temperance a second activity owner.

## Acceptance

- Music and a transfer remain visible together. Narrowing width removes detail
  before controls or an activity core.
- Wider space reveals title/artist and transfer name/bytes/ETA without adding
  capability.
- Multiple transfers group truthfully and remain individually accessible.
- Actions affect only the authoritative source and never appear when unsupported.
- Completion removes the ongoing item without duplicate or invented outcomes.
- Empty Ambient leaves clean whitespace beside Tette.
- Temperance remains left, Tette remains right, and the center app dock does not
  move.
- Tablet/monitor, touch/mouse/keyboard, scaling and panel-size checks pass.

## Stop conditions

Stop after two failed approaches to the same provider or layout boundary. Escalate
before adding a daemon, polling loop, persistent history, replacement panel/task
manager, cross-product state owner or broad Plasma patch.
