# Related settings contract

Related setting rows add read-only local details under a KDE settings result.
Tettegouche picks each provider by the setting's stable ID, not by its
translated name.

## Supported context

- Bluetooth: connected device names with event-driven BluezQt updates.
- Sound: output and microphone devices and muted/in-use status; monitor sources
  are omitted.
- Networking: active named connections, including VPNs; loopback and bridges are
  omitted.
- Displays: connected outputs, active mode/scale, and disabled state.
- Power: battery charge state and the standard system power profile when exposed.
- Printers: configured printer names and idle/printing/disabled state, without job
  names.
- KDE Connect: paired and reachable devices when its provider is installed.
- Removable storage: present removable/hotplug volumes and mounted state from
  Solid metadata only.
- Default applications: browser, mail, and file-manager associations.
- Night Light: enabled/active state and current temperature when available.

Bluetooth is event-driven. Other providers are lazy snapshots taken once per
launcher process when their parent setting appears. Reopening refreshes them.
If a service is missing, returns malformed output or times out, the parent
still works and shows no children.

Local helper processes run with fixed arguments and no shell, time out after two
seconds, and stop at one MiB of output. D-Bus property reads do not start the
service and time out after 1.5 seconds.

## Presentation and activation

Groups show at most three details plus a remaining-count row when more than four
records exist. Children are separate selectable rows after their parent in
keyboard order; [INPUT.md](INPUT.md) lists how they are reached. Selecting a
child keeps the parent destination pinned, and Tettegouche checks the child is
still there before opening it.

A child opens the matching settings page and acts on nothing itself: it does not
disconnect, pair, mount, switch audio or outputs, manage print jobs, change
profiles or take any other device action. Adding such controls first needs
stable device identities and verified APIs for making the change.

## Current limits

Input-device classification and enabled state, printer defaults/queue counts,
KDE Connect remote battery/offline details, default-terminal detection, richer
Night Light schedules, and continuous refresh for every provider are absent.
Custom performance profiles are not assumed to equal the standard system power
profile. Storage opens KDE Device Actions, not a disk manager.
