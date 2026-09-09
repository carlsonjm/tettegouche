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

Kadunce owns:

- KWin window discovery and identity;
- cards, stacks, focus, and output state;
- activation behavior for existing windows and cards.

At open time, Tettegouche requests one `workspaceContext` snapshot from
Kadunce. There is no timer, heartbeat, raw KWin discovery, or reverse surface
state publication. If the endpoint is absent, malformed, or has an unsupported
version, the context is discarded and application search continues normally.

## Launch behavior

Results that correspond to an open application carry its live `windowId`.
Tettegouche asks Kadunce to activate that exact window; Kadunce restores it if
minimized and routes card-backed windows through its existing card selection.
When several windows belong to one application, the focused window wins,
followed by the selected card and then the frontmost matching window. Results
without a live match use Plasma's ordinary launch action.

## Surface behavior

The launcher uses one full-display input surface with a centered responsive
sheet. It does not reserve workspace, render a permanent trigger, follow card
geometry, or assume a particular built-in display size. A second invocation is
forwarded to the existing process through a small single-instance D-Bus entry
point.
