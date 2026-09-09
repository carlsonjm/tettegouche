# Architecture

Tettegouche is an on-demand launcher, not a desktop service. One process owns
one temporary layer-shell surface and exits as soon as the user launches an
application or dismisses the surface.

## Ownership boundary

Tettegouche owns:

- invocation and launcher presentation;
- installed-application queries through Plasma's application runner;
- result selection and normal application launch actions;
- interpretation of the published workspace-context schema.

Kadunce owns:

- KWin window discovery and identity;
- cards, stacks, focus, and output state;
- any future command that focuses an existing card.

At open time, Tettegouche requests one `workspaceContext` snapshot from
Kadunce. There is no timer, heartbeat, raw KWin discovery, or reverse surface
state publication. If the endpoint is absent, malformed, or has an unsupported
version, the context is discarded and application search continues normally.

## Launch behavior

The first seed labels results that correspond to an open application, then
invokes Plasma's ordinary action for the selected result. It does not pretend
that launching and focusing are equivalent. Exact focus-or-launch behavior is
blocked on a separately designed Kadunce command with deterministic handling
for multiple windows, stacks, minimized windows, and different outputs.

## Surface behavior

The launcher uses one full-display input surface with a centered responsive
sheet. It does not reserve workspace, render a permanent trigger, follow card
geometry, or assume a particular built-in display size. A second invocation is
forwarded to the existing process through a small single-instance D-Bus entry
point.
