<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/readme/banner-dark.png">
    <img src="assets/readme/banner-light.png" alt="Tettegouche: touch-first Search, Apps and Files for KDE Plasma" width="100%">
  </picture>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/KDE_Plasma-6.7%2B-1d99f3?style=flat" alt="KDE Plasma 6.7+">
  <img src="https://img.shields.io/badge/session-Wayland-555?style=flat" alt="Wayland">
  <img src="https://img.shields.io/badge/input-touch%20%C2%B7%20pointer%20%C2%B7%20keys-555?style=flat" alt="Touch, pointer and keyboard">
  <img src="https://img.shields.io/badge/license-GPL--2.0--or--later-blue?style=flat" alt="GPL-2.0-or-later">
</p>

<p align="center">
  <a href="#install">Install</a> · <a href="#controls">Controls</a> · <a href="docs/README.md">Docs</a> · <a href="#used-by-shuffle">Used by Shuffle</a>
</p>

<p align="center">
Tettegouche is a touch-oriented Search and file launcher for KDE Plasma. One dot
in the panel opens search, applications and files in one place, and small
islands beside it show what is happening now. Search stays on this computer.
</p>



https://github.com/user-attachments/assets/bf570089-f795-42d4-8333-f2e6c63039b6



## What you get

<table>
<tr>
<td width="33%" valign="top"><b>Private search</b><br>Applications, files, notes, settings, sums and conversions as you type. It all stays on this computer.</td>
<td width="33%" valign="top"><b>Apps</b><br>Every application A to Z, by most used or by newest installed, with folders you make by dragging one onto another.</td>
<td width="33%" valign="top"><b>Files</b><br>A file browser with tabs, Places, drives and phones, that keeps copying safely after you close it.</td>
</tr>
<tr>
<td width="33%" valign="top"><b>Live activity</b><br>Islands in the panel for music, transfers, new downloads, drives, a shared screen and an application waiting on you.</td>
<td width="33%" valign="top"><b>Any input</b><br>Works with touch, a pointer or a keyboard, and follows your light or dark colour scheme.</td>
<td width="33%" valign="top"><b>Works on its own</b><br>Fully functional on a plain Plasma desktop, without Shuffle or its dock. Kadunce, Gooseberry or Split Rock add to it where they are installed.</td>
</tr>
</table>

## Controls

| Task | Touch | Keyboard |
| --- | --- | --- |
| Search | Tap the dot | `Meta` |
| Apps | Tap Apps in Search | `Meta+G` |
| Files | Tap Files in Search | `Meta+E` |
| Ambient | Tap the island | — |

Every other input is in [docs/INPUT.md](docs/INPUT.md).

<details>
<summary>Changing the keys</summary>

`Meta+G` and `Meta+E` are listed under Tettegouche, or Search where Shuffle is
installed, in System Settings' Shortcuts, where you can change them. Dolphin
takes `Meta+E` when it is installed; give the key to Tettegouche there. `Meta`
works with nothing to set: Tettegouche is Plasma's application launcher, as
Kickoff is.

</details>

## Search

Tap the dot in the panel, or press `Meta`. Before you type, Search offers Apps
and Files, Notes where Gooseberry is installed, Helpers where Split Rock is
installed, and below them what you used lately: files, and applications that
are not already open or pinned in the dock. To go straight to one of them,
press the dot and slide toward the islands. Search stays ready after you close
it, so it opens at once next time, and Tettegouche adds no background service
to do it.

Search stays on this computer. Files come from Baloo, KDE's built-in file
index that Dolphin also uses, so Tettegouche keeps no index of its own. Only
**Search the web** hands your words to your browser.

<details>
<summary>What Search finds</summary>

- Installed applications
- Files from KDE's file index, and recent documents. A file named for what
  you type comes first; one that only holds the words inside follows.
- Notes, while Gooseberry is running
- KDE settings
- Calculator results
- Unit conversions
- The time in another zone, such as "time in London"
- Split Rock's upkeep cards and facts, such as "update" or "storage", where
  Split Rock is installed

Local results come first. If nothing local matches, submitting the search can
open it in your web browser. Results are not ranked by what you used before.
Touch and hold an application, or right-click it, to uninstall it.

</details>

<details>
<summary>Apps</summary>

**Apps** shows installed applications when you would rather look than search.
A to Z is one run by name. Most used and Newest installed are divided into
sections by when each was last used or arrived. Apps remembers your choice.

Drag one application onto another to make a folder: a single tile at its
name's place A to Z, or at the head of its section. It opens and closes in
place. Touch and hold an application for its sheet: its own actions, folders,
Hide, Edit Application… to change its name, icon or command in KDE's menu
editor, and Uninstall…. Apps also has a launcher of its own, with its own
icon, to pin to a dock.

</details>

<details>
<summary>Files</summary>

**Files** is a local file browser inside Tettegouche. It includes Places, tabs,
history, breadcrumbs, filtering, sorting, selection, and hidden-file display.
It can pop out into a window of its own.

You can open, copy, move, rename, and delete files; create folders; drag files
between folders and to or from other applications; open drives and phones, and
eject drives; and open Trash to restore items or delete them for good. A
running file operation carries on safely if you close Search or the panel
restarts. Files browses local folders, drives and phones; network shares open
in Dolphin.

</details>

## Live activity

The islands beside the dot show what is happening now:

- Music and other media sessions
- Plasma file and desktop jobs
- Copy and move operations started in Tettegouche
- New files arriving in Downloads
- A drive or memory card plugged in: one tap opens it in Files
- A screen shared or recorded through Plasma's portal, with Stop
- An application waiting on you: one tap brings it and its dialog forward
- Where Split Rock is installed, a fact that needs attention, such as a disk
  filling up

<details>
<summary>How the islands behave</summary>

Each island's controls come from the application or service behind it. When
that source goes away, Tettegouche removes the item without guessing whether it
succeeded.

Each kind of activity is its own island, side by side beside the dot, taking
only the room it needs, clear so the panel shows through. When they share the
room, each gives up names first and keeps its buttons at its end. A tap opens
an island in place, larger, with the media's art, position and controls or each
transfer's own actions; a sideways flick sets one aside. The widget's setting
"Show islands beside the launcher" turns them off.

</details>

<details>
<summary>Related settings</summary>

Search can include useful information from supported Bluetooth, sound, network,
display, power, printer, storage, KDE Connect, default-application, and Night
Light settings.

These results open the matching KDE settings page, where you make any change
yourself.

</details>

<details>
<summary>On its own, or with Kadunce and Shuffle</summary>

Tettegouche works on its own. Choosing an application that is already open
brings its window forward instead of opening another: through Kadunce, which
shows the card that holds it, or through Plasma's own window list where
Kadunce is not running. Expanded Apps and Files views can also use the space
Kadunce provides.

Without Kadunce, or with a version it cannot use, Tettegouche opens in its own
window. Without Shuffle and its dock it is fully functional: that is a
supported setup, not a reduced one. Pin to dock, and the room Search leaves for
Shuffle's bars, appear only where Shuffle is installed.

</details>

## Install

These steps are for Arch Linux or CachyOS running KDE Plasma 6.7 or newer in a
Wayland session, the default on both. Tettegouche is built on your computer
from this page's code, so you type a few commands into **Konsole**, Plasma's
terminal. Open it from the application launcher.

### 1. What you need

Check your Plasma version. It must say 6.7 or higher:

```bash
plasmashell --version
```

Bring the computer up to date. If you just did this for another part of the
suite, skip it:

```bash
sudo pacman -Syu
```

Restart the computer only if that update installed a new `kwin`,
`plasma-workspace` or kernel (`linux`, or `linux-cachyos` on CachyOS): Tettegouche is built against what is
installed, so that has to be what is running.

Then install what the build needs. Type your password when asked, and answer
`Y`:

```bash
sudo pacman -S --needed base-devel git cmake ninja extra-cmake-modules python ripgrep gettext qt6-base qt6-declarative qt6-svg qt6-tools kbookmarks kcoreaddons kfilemetadata kglobalaccel ki18n kio krunner kservice bluez-qt solid kirigami kpackage layer-shell-qt libplasma plasma-workspace plasma-activities-stats kactivitymanagerd appstream-qt kate okular ffmpegthumbs kdegraphics-thumbnailers
```

If pacman says a package **is up to date -- skipping**, or **there is nothing
to do**, that is normal: it is already installed.

Kate, Okular and the thumbnailers are there because the installer's checks
open real files with them. `kdeplasma-addons`, if you add it, lets Search
answer sums, unit conversions and times in other zones.

### 2. Download

This puts the code in a folder called `tettegouche` in your home folder. Use
`git` rather than GitHub's Download ZIP, so a later update is one command:

```bash
cd ~
git clone https://github.com/carlsonjm/tettegouche.git
cd tettegouche
```

### 3. Install

```bash
./install.sh
```

The installer checks the code, builds it and runs its tests. Then it asks for your password in Konsole (nothing shows as you type)
to install Tettegouche for the whole computer, and restarts the panel. The
panel blinks out for a moment; your windows stay open. It ends with
**Tettegouche installed**.

### 4. Put it on the panel

1. Right-click an empty part of the panel and choose **Add Widgets…**.
2. Search for **Tettegouche** and drag it onto the panel, at its left end.
3. Plasma gives the launcher key to the first launcher it finds on the panel.
   For `Meta` to open Search, remove Plasma's own **Application Launcher**:
   right-click it and choose **Remove**, or remove it in the panel's edit mode.

On Plasma's standard bottom panel the dot then sits at the left end. Live
activity, such as the song playing, shows as an island a good way to the dot's
right, and Plasma's task icons move to the middle of the panel. That is how it
lays out on a panel without Shuffle.

### 5. Check it worked

- Tap the dot on the panel, or press `Meta`. Search opens, ready to type.
  Type the name of an application and press `Enter` to open it.
- `Meta+G` opens Apps. `Meta+E` opens Files, unless Dolphin already has that
  key; System Settings' **Shortcuts** page, under Dolphin and Tettegouche,
  moves it.

Without Kadunce, Search opens in its own window. That is a full setup, not a
reduced one.

### 6. Update

After every Plasma update, and to get a newer Tettegouche:

```bash
cd ~/tettegouche
git pull
./install.sh
```

Until it is built again after a Plasma update, Ambient leaves out waiting
applications and Plasma's own transfers.

### 7. Uninstall

```bash
cd ~/tettegouche
./uninstall.sh
```

It asks for your password, takes the dot off the panel and puts Plasma's own
**Application Launcher** back where the dot was, and ends with **Tettegouche
removed**. The panel blinks out for a moment; your windows stay open.

To delete the download too, run `rm -rf ~/tettegouche`.

<details>
<summary>If the install stops</summary>

The installer changes nothing until every check has passed, so you can fix
the cause and run `./install.sh` again.

- **A package is missing:** run the `pacman` line in step 1 again.
- **It stops at `words-test`:** the checks need the English (US) language
  files, which some systems don't generate. Add them, then run the installer
  again:

  ```bash
  sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  sudo locale-gen
  ```

- **It says the panel still holds the previous widget:** sign out and back in.

Some related-setting results come from optional system tools and appear only
when the tool is installed. Bluetooth hardware is optional.

</details>

## For developers

<details>
<summary>Folder map and checks</summary>

Read `AGENTS.md` before working in this repository. The documentation index is
in `docs/README.md`.

```text
src/          launcher, Search, Files, integration, and activity providers
qml/          Search and Files presentation
applet/       panel entry, Ambient island, and configuration
tests/        native, QML, private-session, packaging, and source checks
docs/         current contracts and architecture
```

Run the repository checks before opening a pull request:

```bash
./verify.sh
```

GitHub runs the same checks on every pull request and on `main`, against the
Qt and KDE packages Arch Linux ships at the time.

</details>

## Used by Shuffle

Tettegouche is a project of its own. [Shuffle](https://shuffleplasma.com), a
touch-first desktop built on KDE Plasma, includes it, and there it is called
Search. Shuffle also includes these related projects, each usable on its own:
[Kadunce](https://github.com/carlsonjm/kadunce),
[Temperance](https://github.com/carlsonjm/temperance),
[Gooseberry](https://github.com/carlsonjm/gooseberry) and
[Split Rock](https://github.com/carlsonjm/split-rock).

## License

Tettegouche is licensed under GPL-2.0-or-later.

The project names and marks are not covered by that licence. See
[TRADEMARKS.md](TRADEMARKS.md).

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="assets/readme/good-input-white.png"><img src="assets/readme/good-input-ink.png" alt="Good Input" width="140"></picture></p>
