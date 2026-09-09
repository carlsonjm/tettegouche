# Architecture

Tettegouche is an on-demand launcher, not a desktop service. One process owns
one temporary layer-shell surface and exits as soon as the user launches an
application or dismisses the surface.

## Ownership boundary

Tettegouche owns:

- invocation and launcher presentation;
- installed-application queries through Plasma's application runner;
- result selection and normal application launch actions;
- interpretation of the published workspace-context schema;
- requesting activation of an exact live window from that snapshot.
- rendering and interacting with its own temporary guest-card surface.

Kadunce owns:

- KWin window discovery and identity;
- cards, stacks, focus, and output state;
- activation behavior for existing windows and cards.
- guest placement, adjacent real-card motion, and the final Card Line selection.

At open time, Tettegouche first checks Kadunce's independent launcher-guest
protocol. Guest mode is requested only when Kadunce reports the exact supported
version. It then requests one `workspaceContext` snapshot. There is no timer,
heartbeat, or raw KWin discovery. If either endpoint is absent, malformed, or
unsupported, Tettegouche keeps its standalone surface and application search
continues normally.

## Guest-card handoff

Protocol 2 reserves a centered Card Line guest footprint for Tettegouche
without inserting it into Kadunce's persistent card model. Kadunce derives a
slightly narrower geometry from its canonical card so both real neighbors keep
useful visible shoulders; Tettegouche does not infer or resize that footprint.
It renders an opaque `#141414` surface with a
one-pixel `#333333` outline, the Card Line corner radius, and a 22-pixel content
inset, then limits input to that card. Real application cards remain visible on
either side and continue to belong exclusively to Kadunce.

During a horizontal launcher drag, Tettegouche sends only the current delta.
Kadunce mirrors that motion onto the incoming real card and decides whether the
release commits. A canceled drag springs back. A committed drag lets the real
card reclaim center, then Tettegouche exits. A press on a visible neighboring
card is treated as navigation rather than app activation: Kadunce consumes the
full input sequence, animates Tettegouche away, selects that neighbor, and
remains in Card Line. Loss of Tettegouche's unique D-Bus owner safely ends the
lease.

For a new application launch, Tettegouche asks Kadunce to hold the guest and
shows a bounded `Opening` state. Kadunce completes the guest only after KWin
reports an activated application window, preventing the previously selected
card from flashing into Active during process startup. A ten-second timeout
returns the launcher to search if no window arrives.

## Launch behavior

Results that correspond to an open application carry its live `windowId`.
Tettegouche asks Kadunce to activate that exact window; Kadunce restores it if
minimized and routes card-backed windows through its existing card selection.
When several windows belong to one application, the focused window wins,
followed by the selected card and then the frontmost matching window. Results
without a live match use Plasma's ordinary launch action.

## Surface behavior

Standalone mode uses one full-display input surface with a centered responsive
sheet. Guest mode keeps that layer-shell surface but masks input to the geometry
negotiated with Kadunce. Neither mode reserves workspace or renders a permanent
trigger. A second invocation is forwarded to the existing process through a
small single-instance D-Bus entry point.

Both modes use the same centered card treatment: a one-pixel `#5a5a5a`
hairline, ten-pixel corners, and an undimmed desktop outside the surface. At
rest, the search control is transparent with the same hairline, `Just type` on
the left, and its action icon on the right. Physical typing engages it directly;
an intentional tap fills the control, focuses the field, and requests the
system input method when one is available.

A quiet `Browse everything` label and horizontal grabber rest at the bottom
edge. A tap or upward drag raises them beneath the search control while an
alphabetical grid of visible Plasma applications grows behind them. In the open
header, the centered label crossfades to a left-aligned copy, the grabber
remains centered, and an A-Z/Z-A sort menu appears at right. Typing filters this
grid in place; resting-card typing continues to use KRunner's ranked result
view. The catalogue comes
directly from `KApplicationTrader` and launches through
`KIO::ApplicationLauncherJob`; it contains no recency, recommendation, or
usage-ranking layer. Open-window matching still runs before catalogue launch,
preserving the same no-duplicates behavior as text search.
