# Input

Every touch, mouse and keyboard input Tettegouche handles, destination by
destination, with what you see happen. Other documents cite this list rather
than repeat it.

| Task | Touch | Keyboard |
| --- | --- | --- |
| Search | Tap the dot | `Meta`, once set in Plasma |
| Browse everything | Tap "browse everything" in Search | `Meta+G` |
| Files | Tap "explore files" in Search | `Meta+E` |
| Ambient | Tap the island | — |

## Search

| Input | What happens |
| --- | --- |
| Type | The letters go into the search wherever the focus is, and results follow each keystroke. Nothing is sent online. |
| Tap the search field or its magnifier | Raises the on-screen keys. |
| Touch the on-screen keys | Types into the search. It never closes Search. |
| Tap or click the × at the field's end | Clears the search and raises the on-screen keys. |
| Down or Up | Moves the highlight through the results, passing through a setting's detail rows on the way. |
| Enter | Opens the highlighted result. With results still arriving, it opens the best once they settle; with no local result, it searches the web in the browser. |
| Tap or click a result | Opens it. An application marked OPEN comes forward instead of opening again. |
| Tap or click "Search the web for …" | Searches the web in the browser. |
| Tap or click "Everyday search ⇄" or "All files ⇄" | Switches between everyday results and every indexed file. |
| Tap or click "Quiet folders…" | Opens the list of folders everyday search leaves out, one path per line. Save keeps it; Cancel, Esc or a tap outside leaves it as it was. |
| Esc | Closes an open menu, then an open drawer, then Search. |
| Tap or click outside Search | Closes it. Inside Kadunce's Spread, the space round Search belongs to Spread. |
| Drag Search sideways inside Kadunce's Spread | Search follows and tells Spread how far it has moved. Let go: if Spread moves on, Search slides away to that side and closes; if not, it springs back. |
| With the on-screen keys up | Search rises only as far as it must to stay above them, then shortens, so the search field and its results, or an open drawer, stay in view. Inside Kadunce's Spread it keeps its place and shortens instead. It returns as the keys go down. |

### The dot

| Input | What happens |
| --- | --- |
| Tap or click the dot | Opens Search, and a ring round the dot shows it is open. Again closes it. |
| With the dot focused, Enter or Space | Opens or closes Search. |
| Meta, once set as the widget's shortcut in Plasma | Opens or closes Search. Tettegouche does not set it; Plasma's own default for Meta opens Kickoff, Plasma's application menu. |
| Point at the dot | The dot grows slightly, and a tooltip says whether Search is open. |
| Right-click the dot or the Ambient island | Plasma's own widget menu, which leads to the widget's settings. |
| Setting "Open inside Spread when available", off | Search always opens on its own, never inside Kadunce's Spread. |
| Setting "Animate the launcher indicator", off | The ring appears without its ripple, and the dot's hover change is instant. |

### Related settings

| Input | What happens |
| --- | --- |
| Down or Up in the search results | Steps from a setting into its detail rows, such as connected Bluetooth devices, and on to the next result. |
| Enter on a detail row | Opens that setting's page in System Settings. |
| Tap or click a detail row | Opens that setting's page in System Settings. It never connects, pairs, mounts or switches anything. If the page cannot open, the row says so. |

## Browse everything

| Input | What happens |
| --- | --- |
| Tap or click "browse everything" in Search | Opens Browse everything. |
| Pull up the handle under "browse everything" | The drawer follows your finger or the pointer. Let go and it opens if pulled far enough, or falls back. |
| Type | Narrows the applications to those whose names match. What is typed shows in the search field, in the middle of the drawer's header. |
| Arrow keys, typed into or not | The first press shows, lifted, the application Enter would open; then Left and Right move one, Up and Down a row, keeping it in view. |
| Enter | Opens the chosen application: the first one, unless the arrow keys moved it. |
| Tap or click an application | Opens it, or brings it forward if it is already open. |
| Touch and hold an application, or right-click it | Opens its sheet: the application's own actions, such as a new window, each starting afresh; Hide, which takes it out of Browse everything while Search still finds it; and Uninstall…, where the software centre lists it, which opens it there. |
| Tap or click the sort button | Offers A to Z or Z to A. |
| Tap or click Back, at the header's left | Returns to search, with what is typed. |
| Drag the drawer's top edge down | The drawer follows. Let go and it closes if pulled far enough, or stays open. |
| Esc | Closes the sort menu if it is open, otherwise the drawer. |
| Meta+G | Opens Search on Browse everything; pressed there again, closes it. It is listed under Tettegouche in System Settings' Shortcuts, where it can be changed. While another application holds Meta+G, such as KDE's Overview, KDE gives it to whichever had it first. |

## Files

| Input | What happens |
| --- | --- |
| Tap or click "explore files" in Search, or pull down from it | Opens Files. |
| Type | Narrows what is shown to names that match: the folder, Recent or a search's results. Subfolders are not searched. What is typed shows in the search field, in the middle of the drawer's header. |
| Down, from what is typed | Moves the keys into the files, on the first one. |
| With text typed and nothing chosen, tap or click "Search inside folders", or press Enter | Looks through this folder and every folder inside it for names containing the text as typed. Results arrive while it runs, each with the folder it is in. Back returns to the folder; Stop searching keeps what it has found. Hidden files are searched only while shown. |
| Tap or click a place | Opens that folder. |
| Tap or click Recent | Shows the 30 files and folders used most recently, newest first, each with the folder it is in. The sort stays the order of use. |
| Tap a folder in Recent or in a search's results | Opens it in place and clears the typed text. |
| Tap or click a part of the path | Opens that folder. |
| Tap or click Back or Forward, or Alt+Left or Alt+Right | Goes back or forward in this tab's history. |
| Alt+Up | Opens the folder that holds this one. |
| Tap or click Path, or Ctrl+L | Shows a field for a folder's full path. Enter goes there; Esc hides the field. |
| Tap or click Refresh | Reloads the folder. |
| Tap or click +, or Ctrl+T | Opens a new tab on the current folder. |
| Open in new tab, from a folder's menu | Opens that folder in a tab of its own. |
| Show in folder, from a file's menu in Recent or a search | Opens the folder that holds it, with the file chosen. |
| Drag the handle at the right edge of a long folder | Scrolls through it at once. |
| Tap or click a tab | Switches to it. |
| Ctrl+Tab | Switches to the next tab. |
| Tap or click × on a tab, or Ctrl+W | Closes that tab, or the current one for Ctrl+W. The last tab stays. |
| Tap or click the sort button | Offers name A–Z, name Z–A, newest first, largest first, and showing hidden files. |
| Click a file | Selects it. |
| Double-click a file | Opens it in its usual application and closes Search. A folder opens in place. |
| Ctrl+click a file | Adds it to the selection, or removes it. |
| Shift+click a file | Selects everything from the last selected file to this one. |
| Ctrl+Shift+click a file | Adds that range to the selection. |
| Click empty space | Clears the selection. |
| Drag across empty space with the mouse | Draws a box that selects what it touches. With Ctrl it flips those files; with Shift it adds them. |
| Tap a file | Opens it in its usual application and closes Search; a folder opens in place. A file no application claims offers Open with instead. While choosing several, adds or removes it. |
| Touch and hold a file | Selects it and starts choosing several, with a circle on each file. The bar above the files offers what to do with them. |
| Tap empty space | Clears the selection. |
| Touch and hold empty space | Opens the folder's action menu beside the finger. |
| Tap or click "Done selecting" | Stops choosing several and clears the selection. |
| Tap or click Copy, Cut, Rename or Move to Trash in the bar | Acts on the chosen files, as the keys and the action menu do. Rename shows for one file. |
| Arrow keys, Home or End | Move the selection one file, one row, or to the first or last file. |
| Shift with an arrow, Home or End | Extends the selection. |
| Ctrl with an arrow | Moves the focus outline without changing the selection. |
| Ctrl+Shift with an arrow | Adds the range to the selection. |
| Enter, or tap or click Open | Opens the selected file, as a double-click does. With nothing selected and text typed, Enter searches inside folders. |
| Right-click a file, or tap or click ⋯ with files chosen | Their action menu: Open, Open with, Copy, Cut, Rename, Move to Trash, Compress, Extract here for archives, Restore last trashed item, Select all, Properties, and for a folder, Paste into it. |
| Choose Open with | Lists the applications for the file's kind, the default first; Show all applications lists every one, with a filter. "Always use it" makes the pick KDE's default for that kind. A tap opens the file and closes Search. |
| Choose Compress | Ark makes a zip beside the first: one item keeps its name, several make Archive.zip. Its progress shows in Ambient. |
| Choose Extract here | Ark unpacks each archive beside itself, in a folder of its own when it holds several items. Its progress shows in Ambient. |
| With one file or folder chosen, tap or click Properties in the bar or the menu, or press Alt+Enter | Shows its kind, size, folder and dates. A folder's total size and what it holds follow once counted; a photo adds its dimensions, date taken and camera, a song its title, artist, album and length, a video its dimensions and length. Close or Esc puts it away. |
| Right-click empty space, or tap or click ⋯ with nothing chosen | The folder's action menu: Paste here, Select all, New folder, Restore last trashed item, Empty Trash. Recent, a search and a folder that cannot be written offer no Paste here or New folder. |
| Choose Empty Trash | Asks first, giving how many items and how much space; Empty Trash removes everything in Trash for good. |
| Ctrl+C, or tap or click Copy | Copies the selection. |
| Ctrl+X, or Cut | Cuts the selection. |
| Ctrl+V, or Paste here or Paste in the bar | Pastes a copy, or moves what was cut. |
| Paste or drop onto a name already taken | Asks: Replace, Skip, Keep both or Stop; a folder offers Merge instead of Replace. With several arriving, "Do the same for the rest" answers once for all. Esc stops. Nothing is replaced without Replace. |
| Ctrl+A, or Select all | Selects everything in the folder. |
| F2, or Rename | Shows a field to rename the one selected item, its name selected and its extension left. Enter or Rename renames it; Esc or Cancel leaves it. |
| Delete, or Move to Trash | Asks first, naming the file or how many; Move to Trash moves them. Nothing is deleted permanently. |
| Restore last trashed item | Brings back the last item Tettegouche moved to Trash. |
| Tap or click New folder | Shows a name field. Enter or Create makes the folder; Esc or Cancel leaves it. |
| Drag a file with the mouse, or touch and hold it and then drag | Carries the selection, labelled with the folder under it; dropped on a folder, it is copied there. Near the top or bottom edge the list scrolls. Dropped anywhere else inside Files, nothing happens. |
| Carry files past the edge of Files | They leave Files and go on as the system's own drag, for any application, on this display or another. Dropped on one, it receives a copy; the originals stay. Dropped on nothing, nothing happens. |
| Drag files from another application over Files, and let go | Labelled with where they would land: the folder tile under them, else the folder shown. Near the top or bottom edge the list scrolls. Let go and they are copied there, never moved. In Recent or a search only a folder tile takes them; outside the list, nothing happens. Only a window on another display can start this, since a press beside Files closes it. |
| Tap or click a drive under the places | Opens it, mounted first if it is not; its row says Opening… meanwhile. A drive that cannot be opened says why. |
| Tap or click ⏏ beside a plugged-in drive | Makes it safe to pull out: its row says Ejecting…, then Files says it can be unplugged, and a drive powered off leaves the list. While Files copies or moves to or from it, the row says Ejects when done, and it ejects after. |
| Plug in or pull out a drive while Files is open | It appears under the places, or leaves them. A tab showing a drive that leaves or is ejected goes Home. |
| Another application opens a folder or asks to show files, as it would a file manager: Plasma's Open with File Manager for a drive, or Show in folder in a browser's downloads | Once Files is the file manager, it opens at the folder, or with the files chosen in theirs, or with a file's Properties when those are asked for. A plugged-in phone opens in Files; Trash and network shares open in Dolphin. |
| Tap or click Back, at the header's left | Returns to search, with what is typed. |
| Pinch, Ctrl with + or −, or Ctrl and the scroll wheel | Makes the tiles larger or smaller, in four sizes. Ctrl+0 returns them to the usual size. The size is kept. |
| Tap or click Pause, Resume or × on a running copy or move | Pauses, resumes or cancels that one alone. Other file actions stay available while it runs. |
| Drag the drawer's top edge down | The drawer follows. Let go and it closes if pulled far enough, or stays open. |
| Esc | Cancels a drag; otherwise clears the selection; otherwise closes Files. |
| Meta+E | Opens Search on Files; pressed there again, closes it. It is listed and changed as Meta+G is. Dolphin holds Meta+E from its own install, so it opens Dolphin until Meta+E is taken from Dolphin in System Settings. |
| With the on-screen keys up | The current folder, its path and its actions stay above them: the actions join the path's row, and the tabs and the Open row step aside until the keys go down. Menus open above the keys. |

## Ambient

| Input | What happens |
| --- | --- |
| Tap or click play or pause, previous or next on the media island | Plays, pauses or skips the media. Previous and next show when the island has room. |
| Tap or click × on the transfer island | Cancels the transfer. It shows only for a single transfer its source can cancel. |
| Tap or click the folder on an arrival's island | Opens Files at the file, selected. |
| Tap or click a drive's island, or its Open | Files opens the drive, mounting it first. |
| Tap or click another island away from its controls | Opens it in place, larger. |
| Drag an island sideways, by finger or mouse, from anywhere on it | It follows and sheds its details in its own order, down to its first piece; its neighbours hold their places. Let go early and it springs back whole. |
| Flick an island sideways, or drag it past its first piece | Sets aside what it shows, and its neighbours take the room: media until it plays again; transfers until they end, each then filed in the notification history; an ended transfer or a drive, filed now. |
| With an island focused, Delete | Sets it aside. |
| Tap or click the bubble after the islands | Opens the island on what the bubble holds. |
| With an island or the bubble focused, Enter or Space | Opens it. |
| In the open island, drag or tap along the track | Moves the media to that point, when the player allows it. |
| In the open island, tap or click previous, play or pause, or next | Acts on the media. Each shows only when the player supports it. |
| In the open island, tap or click another player | Shows that player in the island. |
| In the open island, tap or click Show and the player's name | Brings the player forward and closes the island. It shows only when the player can be raised. |
| In the open island, tap or click a mark along its top | Moves between the media and the transfers. |
| In the open island, tap or click Pause transfer, Resume or × on a transfer | Acts on that transfer alone. Each shows only when its source supports it. |
| In the open island, tap or click Show in Files | Opens Files at the new download, selected, and closes the island. |
| Esc, or a tap or click outside the open island | Closes it back into the band, not to search. |
