# Omni search — first candidate

Current ranking authority: [Search contract](SEARCH-CONTRACT.md). The shared
`SearchPolicy.h` evidence model supersedes the historical ranking descriptions
below, including the former Wi-Fi-specific exception. All two-letter setting
aliases now use the same ambiguous-prefix rule. All files intentionally retains
broader indexed filename matching; Everyday uses the confidence policy as well
as its quiet-folder/internal-file scope.

Match quality comes first: exact title/basename, prefix, contained query words,
then metadata-only matches. Comparable matches prefer applications, then files,
then system aids. Files must match their filename; incidental content hits and
dependency/cache paths are excluded inside Tette, without changing KDE's index.
Source/configuration extensions require an explicit extension in the query
(for example `BluetoothContext.h`); ordinary partial queries do not expose
implementation files. Build/autogen directories and generated object/dependency
files are always excluded. Documents and pictures retain partial-name matching.
KDE relevance is preserved inside each quality/tier. `OmniResults` wraps the public
KRunner result model, preserving source-index mapping when actions execute.
The inner model is unlimited so a global relevance cap cannot discard apps
before the outer tier sort. The view remains scrollable.

Providers are explicitly allowlisted: services, Baloo, recent documents, system
settings, calculator and unit converter. File coverage follows the user's
existing KDE indexing and recent-document configuration; this change does not
enable indexing, scan new directories or create a usage database. Shell,
kill/session actions, browser history and online runners are not enabled.

Browse remains an application-only grid. The normal Just Type result list is
the omni-search surface. Submission waits for local providers to finish. Only
an empty completed result set offers a deliberate web search, by Enter or tap.
No query is sent online merely by typing. The first candidate uses DuckDuckGo;
the engine preference is awaiting user confirmation.

Web dispatch uses the registered HTTPS browser. Zen/Firefox-family executables
get an explicit `--new-tab` URL argument without a shell. Other browsers use
the desktop URL handler and its tab/window preference; universal new-tab
behavior across all browsers has not been verified. URLs are encoded as query
parameters, never interpreted as commands.

Only app results use existing-window activation. Files execute their provider
action rather than merely focusing their associated app. Where an associated
application is identifiable, the existing guest protocol handles its arrival.
Web handoff includes the browser executable identity for custom desktop entries.

Bluetooth settings include smaller, indented connected-device names. BluezQt
provides read-only, event-driven context; Tette never discovers, pairs, connects
or disconnects devices. No adapter or unavailable BlueZ yields no children.
Device rows open their parent setting rather than performing device actions.

Verification: tier sorting, denied-provider checks, QML submit-wait and web
fallback tests; read-only live provider queries. Still requires user acceptance
of file opening, calculator action, settings launch, and default browser with
both an existing window and a cold start. No browser or user document was
opened by the automated tests.
# Settings intent follow-up

Short-query follow-up: `wi` resolves Wi-Fi as a limited two-letter exception,
ranked after direct application prefixes (Winetricks) but before ordinary setting
prefixes (Window Manager). Full `wifi` retains canonical-setting priority. Fresh
queries/scope changes settle the results list at its origin after layout, avoiding
a retained scroll offset clipping the first row; lower selections are not reset.

## File scope

Everyday search hides file matches until three characters, files within Git
repositories, application bundles/dependency internals, and configurable quiet
folders (including descendants, with path-boundary matching). Ordinary personal
documents and downloaded files keep their existing name matching. This is scope,
not an authorship detector. Repository ancestry is cached for the launcher session.

Tap the scope label above results to include **All files** from the existing KDE
index. This bypasses Tette's quiet-folder, repository, technical-file and short-query
filters, but still requires a filename match. It does not widen indexing or scan
file contents. Apps and settings remain available. Scope starts at Everyday for
each new launcher process.

“Quiet folders…” edits newline-separated absolute paths (or `~/` paths), saved in
`~/.config/studio.warbler/tettegouche-search.conf`. If present, the standard Documents
directory's `Design Library` folder is the initial editable suggestion. No other
asset-library locations are guessed. Empty the list to remove it; Save persists,
Cancel does not. No files are deleted and KDE's index is unchanged.

Common setting aliases now resolve against installed KDE modules in both the
Quick and QWidget System Settings collections. Three or more characters of a
known alias promote the canonical setting above incidental file prefixes; spaces
and hyphens are normalized (`wifi` / `wi-fi`). Longer distinct searches such as
`soundcloud` and explicit filenames such as `sound.png` retain normal ranking.
Native runner duplicates of the same module are suppressed. With a recognized
setting intent, unrelated metadata-only app/setting matches are omitted.

Alias rows preserve installed module titles/icons and share the existing child
info routing. Selecting one explicitly starts `systemsettings` with the verified
module ID as a separate argument. Storage currently opens KDE's **Device Actions**
module and shows the existing removable-device children; it is not a new disk
management interface. No child actions, geometry, or provider polling changed.

Live read-only checks covered wifi, soun, power, prin, storage and nig. All led
with their canonical module. Visual interaction still requires user validation.
