# Related settings contract

Related setting rows add read-only local context to a canonical KDE settings
destination. Stable setting IDs select providers; translated display names are
never routing keys.

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
Missing services, malformed output, and timeouts leave the parent functional
without children.

Local helper processes use fixed arguments without a shell, a two-second timeout,
and a one-MiB output guard. D-Bus property reads disable service autostart and
time out after 1.5 seconds.

## Presentation and activation

Groups show at most three details plus a remaining-count row when more than four
records exist. Children are separate selectable rows after their parent in
keyboard order. Selection retains the pinned parent destination and revalidates
the child before activation.

A child opens the relevant existing settings page. It never disconnects, pairs,
mounts, switches audio/output, manages printer jobs, changes profiles, or performs
another device-specific action. Such controls require stable device identities
and verified mutation APIs before they can enter this contract.

## Current limits

Input-device classification and enabled state, printer defaults/queue counts,
KDE Connect remote battery/offline details, default-terminal detection, richer
Night Light schedules, and continuous refresh for every provider are absent.
Custom performance profiles are not assumed to equal the standard system power
profile. Storage opens KDE Device Actions; it is not a disk-management surface.
