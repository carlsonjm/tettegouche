# Durable decisions

This ledger records decisions that constrain future work. It is grouped by
subsystem; dates, candidate history, and acceptance transcripts live in Git and
`docs/archive/`.

## Product and lifecycle

- Tettegouche is an on-demand launcher plus a Plasma applet, not a desktop
  service. Outstanding file work may keep a hidden launcher process alive.
- The launcher remains fully useful without Kadunce, optional related-setting
  tools, Bluetooth hardware, or an active Ambient source.
- Meta and panel invocation share toggle semantics and normal guest cleanup.
- The launcher is a top-layer surface, not an overlay one. KWin keeps the
  on-screen keyboard in the overlay layer, and an overlay launcher mapped after
  it stacked above the keys, so its full-screen backdrop took every touch meant
  for them and closed the search. Opening activates the launcher, which keeps a
  full-screen window from covering it. Notification banners now draw over the
  launcher rather than under it.

## Ownership

- Kadunce is the sole owner of KWin discovery, window identity, cards, stacks,
  focus, output state, guest placement, and Card Line selection.
- Tettegouche owns search, catalogue, Files, launcher presentation, related
  context, and the right-side Ambient composition.
- Temperance owns notifications and transient event history. Authoritative source
  applications and services own activity lifecycle and actions.

## Kadunce contracts

- Only launcher-guest protocol 3 and workspace-context schema version 1 are
  accepted. Version mismatch or malformed data falls back to standalone mode.
- The guest never joins the persistent card model. Tettegouche sends requested
  intent and deltas; Kadunce decides geometry, navigation, and commit.
- Existing applications activate exact live windows. New launches may hold the
  guest until a matching window arrives, with a bounded recovery timeout.

## Search

- Eligibility scope and ranking confidence are separate. Confidence precedes
  provider preference; aliases describe destinations rather than query-specific
  exceptions.
- Interaction pins destination identity, not a mutable row number.
- Typing never sends a query online. Web fallback requires explicit submission
  of an empty eligible local result set.
- Search does not learn usage or modify KDE indexing.

## Files

- `FileBrowser` owns local state and KIO operations; QML presents that state.
- Storage and saved paths must not be synchronously probed during launcher
  startup. Listing, mutation, and error delivery stay asynchronous.
- No operation silently overwrites. Partial success is reported; cancellation
  and source loss must never be presented as successful completion.
- Internal drag is copy. An explicit cut clipboard marker makes paste a move.
  Trash has no permanent-delete fallback.
- Test fixtures use disposable isolated locations, never real user files or Trash.

## Ambient

- An activity is admitted only while it has meaningful current state, a useful
  continued presence, an identifiable source, and truthful action routing.
- Determinate progress, ETA, completion, and controls appear only when the source
  provides evidence. Filesystem quiet time is not completion.
- Width reveals context, not capability. Every activity receives its useful core
  before optional detail, and the center task dock remains physically centered.
- Ambient keeps no completion history. Source loss removes stale state without a
  false success transition.

## Panel and visual system

- The direct-content `PlasmoidItem` structure and explicit root size hints are a
  functional panel contract.
- Lucide is the suite action-icon family. Tette Dot and other protected suite
  identity work remain custom.
- The shared visual and motion rules are defined in
  [ITASCA-VISUAL-LANGUAGE.md](ITASCA-VISUAL-LANGUAGE.md).
