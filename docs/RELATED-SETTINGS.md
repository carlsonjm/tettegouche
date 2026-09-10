# Related settings — first shared-provider candidate

`RelatedInfo` supplies label/status records to a single QML child renderer.
Stable setting IDs select providers; translated display names are not routing
keys. Children are informational and activate their parent setting, never
disconnect, pair, mount, switch output or invoke another state-changing action.

Supported:

- Bluetooth: connected device names, event-driven updates through BluezQt.
- Sound: output and microphone devices, muted/in-use status; monitor sources omitted.
- Networking: active named connections, including VPNs; loopback/bridges omitted.
- Displays: connected outputs, active mode and scale, disabled state.
- Power: battery level/charging state; standard system power profile when supported.
- Printers: configured printer names and idle/printing/disabled state, no job names.
- KDE Connect: paired and reachable devices when the provider is installed.
- Removable storage: present removable/hotplug volumes, mounted state. Solid
  metadata only: no mount, filesystem traversal, free-space query or drive wake.
- Default applications: browser, mail and file manager associations.
- Night Light: enabled/active state and current temperature when available.

Except Bluetooth, providers are lazy snapshots obtained once per launcher
process, only when their setting appears. Reopening the launcher refreshes
them; these are not continuous monitoring widgets. Queries do not spawn new
polling loops. Missing services, malformed data and timed-out reads leave the
parent functional with no children. Local helper processes use fixed arguments,
no shell, a two-second timeout and a one-MiB output guard. D-Bus property reads
disable service autostart and time out after 1.5 seconds.

Groups are capped at three details plus a remaining-count row when more than
four records exist. Bluetooth retains its previously accepted rendering/count
behavior. Parent geometry expands with rows and collapses when absent.

Deliberate detours deferred: reliable input-device classification and enabled
states; printer default/queue counts; KDE Connect remote battery/offline detail;
default terminal detection; richer Night Light schedule; system-wide live
refresh for every provider; actionable device controls. Custom Z13 performance
profiles are not assumed to equal the standard system power profile.

Verification: seven tests pass, including parser fixtures, stable-ID routing,
unavailable/malformed data, and grouped-row layout. Read-only probes on the test
machine returned sound, network, display, power, printer, storage, default-app
and Night Light rows; KDE Connect returned none. This is not a live user visual
pass or confirmation of every possible hardware/backend combination.
# Independent child presentation

Children now use indented dot indicators, separate 40px selectable pills, and
keyboard order parent → children → next result (Up reverses). The parent highlight
is always limited to its own 62px row. Child selection retains the pinned parent
destination and checks that the displayed child is still present before opening.

Selecting a child now opens the relevant existing settings page directly, using
the normal launcher handoff. The extra explanatory/confirmation card was removed
after user testing. Existing System Settings instances receive KDE's CommandLine
request with the module ID; a closed instance uses the normal process launch.
No device-specific deep links, connect/disconnect, audio
switching, mounting, printer jobs, or power changes are claimed or implemented.
The current providers mostly supply display/status rather than stable actionable
device identities; such actions need those identities and verified APIs first.
