/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

Item {
    id: root
    // Its words come from the launcher's catalog.
    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }

    required property var launcherController
    required property var searchResults
    required property var applicationCatalog
    property var fileBrowser: null
    // What was used lately, offered before anything is typed.
    property var recentUse: null
    // Gooseberry's quick note, offered while it is installed; null when the
    // setting is off.
    property var notesDoor: null
    property bool notesPillShown: true
    // The quick note Search writes in its own window; null when the setting is
    // off. Notes is one of Search's modes while the notes application speaks
    // its interface, and opens that application's own card otherwise.
    property var quickNote: null
    // Search's mode, Notes: it opens in this window with the drawer's motion
    // and grows into its application's own window. The shown mode stays while
    // it closes, until its motion ends.
    property string modeShown: ""
    property bool modeOpen: false
    property real modeProgress: 0
    property bool modeGrowing: false
    property bool modeHandoff: false
    property string modeToken: ""
    // Whether Search filled the screen before a mode grew into its
    // application's window, to come back to if that window never shows.
    property bool modeExpandedBefore: false
    // Files' own window, which Pop out opens: offered where the launcher
    // can open it, and awaited in Spread as a launch is.
    readonly property bool filesWindowOffered: !!root.fileBrowser && !!root.launcherController.filesWindowOffered
    property bool filesHandoff: false
    readonly property bool notesOpen: modeOpen && modeShown === "notes"
    readonly property real notesProgress: modeShown === "notes" ? modeProgress : 0
    readonly property bool notesGrowing: modeGrowing && modeShown === "notes"
    readonly property bool notesHandoff: modeHandoff && modeShown === "notes"
    property bool filesMode: false
    // Plasma's animation speed, read through Kirigami's durations: 1 at the
    // default, smaller when faster, 0 for instant. Search's travel, the sheet,
    // its drawers, modes and presses, passes through ms(), so it keeps step
    // with the rest of the desktop. The first screen's arrival keeps its own
    // pace through own(), as a moment meant to be seen; with animations set
    // to instant it only fades, and the progress sweep keeps its rate.
    readonly property real motionFactor: Math.max(0, Kirigami.Units.longDuration / 200)
    readonly property bool reducedMotion: Kirigami.Units.longDuration <= 1
    function ms(base) { return root.motionFactor > 0 ? Math.max(1, Math.round(base * root.motionFactor)) : 1 }
    function own(base) { return root.reducedMotion ? 1 : base }
    focus: true
    // Search follows the window's colour scheme: the suite's dark look on a
    // dark one, the scheme's own ground and ink on a light one.
    SearchColors {
        id: tone
        theme: root.Kirigami.Theme
    }
    readonly property color primaryText: tone.primaryText
    readonly property color secondaryText: tone.secondaryText
    readonly property color edgeText: tone.edgeText
    readonly property color surfaceColor: tone.surface
    readonly property color surfaceOutline: tone.outline
    readonly property color controlColor: tone.control
    // Shuffle's corner tiers: paper for the sheet and all laid in it, notes for
    // what floats above and closes; anything pressed is a pill.
    readonly property int paperRadius: 8
    readonly property int noteRadius: 12
    readonly property int contentInset: 24
    // The room the row of modes takes above the rest: its 40 pills and 16
    // below them (Comfortable), within the 24 the sheet keeps all round.
    // With the on-screen keys up over a search, the row gives its room to
    // the results.
    readonly property bool modeRowShown: !(keysUp && query.text.length > 0 && !drawerOpen && !modeOpen)
    readonly property int modeRowReach: modeRowShown ? 56 : 0
    // Search's field, the same on every screen: 44, the height it first had
    // in use, and the touch target's.
    readonly property int fieldHeight: 44
    // The field's words and what was found for them, read across the sheet.
    readonly property TextInput query: searchField.query
    readonly property ListView resultList: resultsArea.resultList
    // Which sections of what was used lately the first screen shows, each by
    // its setting: the applications, the files, or both.
    property bool recentApps: true
    property bool recentFiles: true
    // When something was used, as a recent file says it: minutes or hours
    // ago, yesterday, a day this week, or its date.
    function usedWhen(when) {
        if (!when || isNaN(when.getTime())) return ""
        const minutes = Math.max(0, Math.floor((Date.now() - when.getTime()) / 60000))
        if (minutes < 1) return words.i18n("just now")
        if (minutes < 60) return words.i18np("%1 min ago", "%1 min ago", minutes)
        const midnight = new Date()
        midnight.setHours(0, 0, 0, 0)
        if (when >= midnight) return words.i18np("%1 h ago", "%1 h ago", Math.floor(minutes / 60))
        const day = 24 * 60 * 60 * 1000
        if (when.getTime() >= midnight.getTime() - day) return words.i18n("yesterday")
        if (when.getTime() >= midnight.getTime() - 6 * day) return Qt.locale().dayName(when.getDay(), Locale.LongFormat)
        return when.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }
    function usedWhere(where, when) {
        const said = root.usedWhen(when)
        return where && said ? words.i18nc("a recent file's folder and when it was used", "%1 · %2", where, said)
            : where || said
    }
    property bool pendingLaunch: false
    property string selectedChildKey: ""
    property bool childLaunchFailed: false

    function childKey(child) { return JSON.stringify([child.label, child.status || ""]) }
    function currentChildren() {
        const row = root.searchResults.selectionPinned()
            ? root.searchResults.selectedRow() : resultList.currentIndex
        return row < 0 ? [] : root.launcherController.relatedItems(row)
    }
    function moveResultSelection(direction) {
        const children = currentChildren()
        let child = children.findIndex(function(item) { return root.childKey(item) === root.selectedChildKey })
        if (direction > 0 && child + 1 < children.length) {
            root.selectedChildKey = root.childKey(children[child + 1])
        } else if (direction < 0 && root.selectedChildKey !== "") {
            root.selectedChildKey = child > 0 ? root.childKey(children[child - 1]) : ""
        } else {
            if ((direction < 0 && resultList.currentIndex <= 0)
                || (direction > 0 && resultList.currentIndex >= resultList.count - 1)) return
            resultList.currentIndex = Math.max(0, Math.min(resultList.count - 1, resultList.currentIndex + direction))
            root.selectedChildKey = ""
            if (direction < 0) {
                const previous = root.launcherController.relatedItems(resultList.currentIndex)
                if (previous.length) root.selectedChildKey = root.childKey(previous[previous.length - 1])
            }
        }
        root.searchResults.pinSelection(resultList.currentIndex)
        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
    }
    function openChildSettings() {
        const child = currentChildren().find(function(item) { return root.childKey(item) === root.selectedChildKey })
        if (!child) return
        const row = root.searchResults.selectedRow()
        root.childLaunchFailed = !root.runResult(row)
    }
    property bool applicationLaunchPending: false
    property string launchingApplication: ""
    property real guestDrag: 0
    property bool guestExiting: false
    property bool guestDragged: false
    property bool searchEngaged: false
    property bool drawerOpen: false
    property real drawerProgress: 0
    property bool sortMenuOpen: false
    property real openingText: 0
    property real openingControls: 0
    property real openingIcon: 0
    property real openingShine: 0
    // Where the on-screen keys lie over this window, as the compositor reports
    // them; empty while they are down. The keys hold no room of their own, so
    // the sheet keeps above them itself.
    property rect keysRect: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle : Qt.rect(0, 0, 0, 0)
    readonly property bool keysUp: keysRect.width > 0 && keysRect.height > 0 && keysRect.y < height
    // Opened to type, the field takes the keys again once the window is
    // active: started cold, the cursor can show before the window has the
    // keys, so nothing typed would reach it.
    property bool typingAwaitsWindow: false
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (!root.Window.window.active || !root.typingAwaitsWindow) return
            root.typingAwaitsWindow = false
            if (!root.searchEngaged) return
            query.forceActiveFocus()
            Qt.inputMethod.update(Qt.ImQueryInput)
        }
    }
    // Whether Notes filled the screen when its note went to the notes
    // application's card, so Back returns to that size.
    property bool notesLeftExpanded: false
    // False while Search opens, so the sheet takes its place at once.
    property bool sheetSettled: true
    // How far up from the window's bottom the sheet must keep clear, eased as
    // the keys come and go.
    property real keysReach: keysUp ? height - keysRect.y + 10 : 0
    Behavior on keysReach {
        NumberAnimation { id: keysMotion; duration: root.ms(220); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: openingSequence
        ScriptAction { script: { root.openingText = 0; root.openingControls = 0; root.openingIcon = 0; root.openingShine = 0 } }
        PauseAnimation { duration: root.own(60) }
        NumberAnimation { target: root; property: "openingControls"; to: 1; duration: root.own(240); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "openingIcon"; to: 1; duration: root.own(120); easing.type: Easing.OutCubic }
        PauseAnimation { duration: root.own(140) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "openingText"; to: 1; duration: root.own(280); easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: root.own(180) }
                NumberAnimation { target: root; property: "openingShine"; to: 1; duration: root.own(460); easing.type: Easing.InOutSine }
            }
        }
    }

    function setDrawerOpen(open, mode, keepSize) {
        // Files windows of their own stay as they are; Files opens here too.
        if (open) root.filesMode = mode === "files"
        root.guestDrag = 0
        // Every drawer opens at Search's own size, a card in Spread; Expand
        // fills the screen. Moving between drawers and Notes keeps the size
        // chosen.
        const wasOpen = root.drawerOpen
        root.drawerOpen = open
        if (!keepSize && (!open || !wasOpen)) root.launcherController.setDrawerExpanded(false)
        if (!open) {
            root.sortMenuOpen = false
            root.renamingFolder = ""
        }
        root.applicationCatalog.filterText = open && !root.filesMode ? query.text : ""
        if (root.fileBrowser) root.fileBrowser.filter = root.filesMode ? query.text : ""
        root.searchResults.queryString = open ? "" : query.text
        drawerSettle.to = open ? 1 : 0
        drawerSettle.restart()
        if (open) {
            root.searchEngaged = false
            root.forceActiveFocus()
            if (!root.filesMode) {
                root.applicationCatalog.refreshUse()
                // An application installed a moment ago shows as Apps opens.
                root.applicationCatalog.checkInstalled()
            }
            // Request the shared presentation first; listing must not precede
            // the drawer handshake or run at launcher construction time.
            if (root.filesMode && root.fileBrowser) Qt.callLater(function() {
                if (root.drawerOpen && root.filesMode) root.fileBrowser.open()
            })
        }
    }

    onGuestDragChanged: {
        if (root.launcherController.guestMode && !root.guestExiting) {
            root.launcherController.updateGuestDrag(root.guestDrag)
        }
    }

    function runResult(index) {
        if (index < 0 || index >= resultList.count) {
            return false
        }
        const activation = root.launcherController.activateIfOpen(index)
        if (activation < 0) return false
        if (activation > 0) {
            root.launcherController.finishLaunch()
            return true
        }
        const applicationName = String(
            root.searchResults.data(
                root.searchResults.index(index, 0), Qt.DisplayRole))
        const waitsForWindow =
            root.launcherController.beginGuestApplicationLaunch(index, false)
        if (waitsForWindow) {
            root.applicationLaunchPending = true
            root.launchingApplication = applicationName
            launchTimeout.restart()
        }
        if (root.searchResults.run(root.searchResults.index(index, 0))) {
            if (!waitsForWindow) {
                root.launcherController.finishLaunch()
            }
            return true
        }
        if (waitsForWindow) {
            launchTimeout.stop()
            root.launcherController.cancelGuestApplicationLaunch()
            root.applicationLaunchPending = false
            root.launchingApplication = ""
        }
        return false
    }

    // One of an application's own actions, such as a new private window: a
    // fresh start, never its open window brought forward.
    function runCatalogAction(index, action) {
        if (!root.applicationCatalog.runAction(index, action)) return false
        root.launcherController.finishLaunch()
        return true
    }

    // An application carried from its tile leaves Search as a drag, which
    // Shuffle's dock takes as a pin, or any other launcher as its own.
    function carryApplication(index) {
        applicationSheet.close()
        const at = sheet.mapToItem(null, 0, 0)
        root.launcherController.carryApplication(index, Qt.rect(at.x, at.y, sheet.width, sheet.height))
    }

    // A folder carried from its tile leaves Search as a drag of its
    // applications, which Shuffle's dock takes as a folder.
    function carryFolder(index) {
        folderSheet.close()
        const at = sheet.mapToItem(null, 0, 0)
        root.launcherController.carryFolder(index, Qt.rect(at.x, at.y, sheet.width, sheet.height))
    }

    // Apps' folders open and close in place, and the choice stays on the
    // folder's row.
    function toggleFolder(index) {
        const folder = root.applicationCatalog.folderId(index)
        if (!folder) return
        root.applicationCatalog.setFolderOpen(folder, !root.applicationCatalog.isOpen(index))
        const row = root.applicationCatalog.folderRow(folder)
        if (row >= 0) applicationGrid.currentIndex = row
    }
    // The folder whose name is being changed, on its own row.
    property string renamingFolder: ""
    function renameFolder(folder) {
        query.text = ""
        root.renamingFolder = folder
        const row = root.applicationCatalog.folderRow(folder)
        if (row >= 0) Qt.callLater(() => {
            if (applicationGrid.lineOf[row] !== undefined)
                applicationGrid.applicationLines.positionViewAtIndex(applicationGrid.lineOf[row], ListView.Contain)
        })
    }
    function goBack() {
        if (root.choosingFolder) root.cancelFolder()
        else {
            root.setDrawerOpen(false)
            if (root.modeOpen) root.closeMode()
        }
    }

    // New folder in Apps: the applications tapped are chosen, and Make
    // folder gathers them, two or more, into a folder of their own, which
    // opens in place with its name ready to change.
    property bool choosingFolder: false
    property var folderPicks: []
    onDrawerOpenChanged: if (!root.drawerOpen) root.cancelFolder()
    onFilesModeChanged: if (root.filesMode) root.cancelFolder()
    function startFolder() {
        root.renamingFolder = ""
        root.sortMenuOpen = false
        root.folderPicks = []
        root.choosingFolder = true
    }
    function cancelFolder() {
        root.choosingFolder = false
        root.folderPicks = []
    }
    function pickForFolder(applicationId) {
        if (!applicationId) return
        const picks = root.folderPicks.slice()
        const at = picks.indexOf(applicationId)
        if (at >= 0) picks.splice(at, 1)
        else picks.push(applicationId)
        root.folderPicks = picks
    }
    function makeFolder() {
        const folder = root.applicationCatalog.makeFolder(root.folderPicks)
        root.cancelFolder()
        if (!folder) return
        root.renameFolder(folder)
    }

    // A folder's sheet: Rename and Remove folder.
    function showFolderSheet(index, tile, point) {
        folderSheet.row = index
        folderSheet.folder = root.applicationCatalog.folderId(index)
        const at = tile.mapToItem(sheet, point.x, point.y)
        folderSheet.openNear(at.x, at.y)
    }

    // An application's sheet, opened from its tile at a point on it.
    function showApplicationSheet(index, tile, point) {
        root.applicationCatalog.prepareSoftware()
        applicationSheet.row = index
        applicationSheet.applicationId = root.applicationCatalog.applicationId(index)
        applicationSheet.actions = root.applicationCatalog.actions(index)
        applicationSheet.hidden = root.applicationCatalog.isHidden(index)
        applicationSheet.pinned = root.launcherController.dockPresent
            && root.launcherController.catalogPinned(index)
        applicationSheet.inFolder = root.applicationCatalog.folderOf(index)
        applicationSheet.folders = root.applicationCatalog.folderList()
            .filter(folder => folder.id !== applicationSheet.inFolder)
        const at = tile.mapToItem(sheet, point.x, point.y)
        applicationSheet.openNear(at.x, at.y)
    }

    // A found application's sheet, where it can be uninstalled; other
    // results have none.
    function showResultSheet(index, target, point) {
        root.applicationCatalog.prepareSoftware()
        const id = root.launcherController.resultApplicationId(index)
        if (id === "" || !root.applicationCatalog.canUninstallApplication(id)) return
        resultSheet.applicationId = id
        const at = target.mapToItem(sheet, point.x, point.y)
        resultSheet.openNear(at.x, at.y)
    }

    function runCatalogApplication(index, applicationName) {
        // Choosing for a new folder, a tap or Enter chooses instead.
        if (root.choosingFolder) {
            if (!root.applicationCatalog.isFolder(index))
                root.pickForFolder(root.applicationCatalog.applicationId(index))
            return true
        }
        if (root.applicationCatalog.isFolder(index)) {
            root.toggleFolder(index)
            return true
        }
        const activation = root.launcherController.activateCatalogIfOpen(index)
        if (activation < 0) return false
        if (activation > 0) {
            root.launcherController.finishLaunch()
            return true
        }
        const waitsForWindow =
            root.launcherController.beginGuestApplicationLaunch(index, true)
        if (waitsForWindow) {
            root.applicationLaunchPending = true
            root.launchingApplication = applicationName
            launchTimeout.restart()
        }
        if (root.applicationCatalog.launch(index)) {
            if (!waitsForWindow) {
                root.launcherController.finishLaunch()
            }
            return true
        }
        if (waitsForWindow) {
            launchTimeout.stop()
            root.launcherController.cancelGuestApplicationLaunch()
            root.applicationLaunchPending = false
            root.launchingApplication = ""
        }
        return false
    }

    // Expand, in the corner of each drawer and mode: Search fills the screen,
    // and again comes back to its size.
    function toggleExpanded() {
        root.launcherController.setDrawerExpanded(!root.launcherController.drawerExpanded, true)
    }
    // Pop out, in Files: Files moves into a window of its own with its tabs
    // and folder as they are, and Search closes. In Spread the window takes
    // Search's card, as an application started from Search does.
    function popOutFiles() {
        if (!root.drawerOpen || !root.filesMode || root.filesHandoff || !root.filesWindowOffered) return
        root.filesHandoff = root.launcherController.guestMode
            && root.launcherController.beginGuestFilesLaunch()
        if (!root.launcherController.popOutFilesWindow()) {
            if (root.filesHandoff) root.launcherController.cancelGuestApplicationLaunch()
            root.filesHandoff = false
            return
        }
        if (root.filesHandoff) filesHandoffTimeout.restart()
        else root.launcherController.close()
    }

    // A mode opens in Search's window with the drawer's motion and the
    // window keeps its size: Notes turns the field into the board's find
    // field, or into the page of the note Start begins or resumes.
    function openMode(name, view) {
        const client = name === "notes" ? root.quickNote : null
        if (!client || !client.available || root.modeGrowing) return false
        if (view === "page") client.start()
        root.modeShown = name
        root.modeOpen = true
        root.sortMenuOpen = false
        modeSettle.to = 1
        modeSettle.restart()
        root.showNotesView(view)
        return true
    }
    // The board; "page", the quick note Start resumes; "new", a new quick
    // note; "note:" and an id, that note. The last two open alone, as the
    // panel's dot and pinned note ask, with no Back to the board.
    function showNotesView(view) {
        if (view === "new") notesPane.startNote("", true)
        else if (view && view.startsWith("note:")) notesPane.openNote(view.slice(5), true)
        else notesPane.enter(view === "page" ? "page" : "board")
    }
    // Notes opens on the board, or on the view showNotesView names. An older
    // notes application without the interface gets its own card, and Search
    // closes.
    function openNotes(view) {
        if (root.openMode("notes", view)) return true
        if (!root.notesDoor || !root.notesDoor.open()) return false
        root.launcherController.finishLaunch()
        return true
    }
    // Notes asked for from outside Search, as the dot's slide asks: it opens,
    // or Search closes when it is the mode already open. Search may have only
    // just opened, before Notes has answered whether it is there; the mode
    // then waits for the answer, and falls back to its own sheet if
    // Gooseberry's interface never answers.
    function openModeDirectly(name, view) {
        modeWait.stop()
        root.modeAwaited = ""
        if (root.modeOpen && root.modeShown === name) {
            // A note asked for while Notes is open is shown there.
            if (view) root.showNotesView(view)
            else root.launcherController.close()
            return
        }
        if (root.drawerOpen) root.setDrawerOpen(false)
        if (root.modeOpen) return
        if (name !== "notes" || !root.notesDoor) return
        const client = root.quickNote
        if (client && client.available) {
            root.openNotes(view)
            return
        }
        root.modeAwaitedView = view || ""
        root.modeAwaited = name
        modeWait.restart()
    }
    function settleAwaitedMode(late) {
        const name = root.modeAwaited
        if (!name) return
        const client = root.quickNote
        if (!late && !(client && client.available)) return
        modeWait.stop()
        root.modeAwaited = ""
        root.openNotes(root.modeAwaitedView)
    }
    property string modeAwaited: ""
    property string modeAwaitedView: ""
    Timer {
        id: modeWait
        interval: 1500
        onTriggered: root.settleAwaitedMode(true)
    }
    Connections {
        target: root.modeAwaited === "notes" ? root.quickNote : null
        ignoreUnknownSignals: true
        function onAvailableChanged() { root.settleAwaitedMode(false) }
    }
    function closeMode(keepSize) {
        if (!root.modeOpen || root.modeGrowing) return
        if (root.modeShown === "notes") root.quickNote.flush()
        root.modeOpen = false
        // Search goes back to the size it had before Expand, unless a drawer
        // takes the mode's place.
        if (!keepSize && root.launcherController.drawerExpanded) root.launcherController.setDrawerExpanded(false)
        modeSettle.to = 0
        modeSettle.restart()
        root.forceActiveFocus()
    }
    function closeNotes() { root.closeMode() }
    // Pop out grows the window as Apps does, and the application's own window
    // takes its place: in Spread through Kadunce's launch, over an Active card
    // once it has drawn, since Kadunce puts it in the card's place.
    function growMode() {
        if (!root.modeOpen || root.modeGrowing) return
        root.modeExpandedBefore = root.launcherController.drawerExpanded
        root.modeGrowing = true
        root.modeToken = Math.random().toString(36).slice(2) + Date.now().toString(36)
        root.launcherController.setDrawerExpanded(true)
        root.modeHandoff = root.launcherController.guestMode
            && root.launcherController.beginGuestNotesLaunch()
        const opened = root.quickNote.openBoard(root.modeToken)
        if (!opened) {
            root.stopGrowingMode()
            return
        }
        modeTimeout.restart()
    }
    function growNotes() { root.growMode() }
    function stopGrowingMode() {
        modeTimeout.stop()
        if (root.modeHandoff) root.launcherController.cancelGuestApplicationLaunch()
        root.modeHandoff = false
        root.modeGrowing = false
        root.modeToken = ""
        root.launcherController.setDrawerExpanded(root.modeExpandedBefore, true)
    }
    function modeWindowShown(requestToken) {
        if (!root.modeGrowing || root.modeHandoff || requestToken !== root.modeToken) return
        modeTimeout.stop()
        modeExit.restart()
    }

    // Something used lately opens: an application, or a file in its usual one,
    // awaited as a card as any launch from Search is.
    function runRecent(index, name) {
        if (!root.recentUse || index < 0 || index >= root.recentUse.count) return false
        const waitsForWindow = root.launcherController.beginGuestRecentLaunch(index)
        if (waitsForWindow) {
            root.applicationLaunchPending = true
            root.launchingApplication = name
            launchTimeout.restart()
        }
        if (root.recentUse.open(index)) {
            if (!waitsForWindow) root.launcherController.finishLaunch()
            return true
        }
        if (waitsForWindow) {
            launchTimeout.stop()
            root.launcherController.cancelGuestApplicationLaunch()
            root.applicationLaunchPending = false
            root.launchingApplication = ""
        }
        return false
    }

    function submit() {
        if (root.drawerOpen && root.filesMode) {
            // With nothing chosen, Enter searches inside the folder as its
            // pill does; otherwise it opens what is chosen.
            if (!root.fileBrowser) return
            if (root.fileBrowser.searchOffered && root.fileBrowser.selectedPaths.length === 0)
                root.fileBrowser.searchInside(root.fileBrowser.filter)
            else
                root.fileBrowser.openSelected()
            return
        }
        if (!root.drawerOpen && root.selectedChildKey !== "") {
            root.openChildSettings()
        } else if (!root.drawerOpen && root.searchResults.querying) {
            pendingLaunch = true
        } else if (root.drawerOpen && applicationGrid.choices.length > 0) {
            const row = applicationGrid.currentIndex >= 0 ? applicationGrid.currentIndex : applicationGrid.choices[0]
            runCatalogApplication(row,
                root.applicationCatalog.applicationName(row))
        } else if (root.searchResults.selectionPinned()) {
            // A vanished destination must not silently turn Enter into a
            // different app launch (or a web search).
            runResult(root.searchResults.selectedRow())
        } else if (resultList.count > 0) {
            runResult(Math.max(0, resultList.currentIndex))
        } else if (root.searchResults.querying) {
            pendingLaunch = true
        } else if (!root.drawerOpen && query.text.trim().length > 0) {
            const waiting = root.launcherController.beginGuestWebLaunch()
            if (waiting) {
                root.applicationLaunchPending = true
                root.launchingApplication = words.i18n("Web search")
                launchTimeout.restart()
            }
            if (!root.launcherController.searchWeb(query.text) && waiting) {
                root.launcherController.cancelGuestApplicationLaunch()
                launchTimeout.stop()
                root.applicationLaunchPending = false
            }
        }
    }

    Connections {
        target: root.fileBrowser
        ignoreUnknownSignals: true
        function onFolderCreated() { query.text="" }
        function onFilterCleared() { query.text="" }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.sortMenuOpen) {
                root.sortMenuOpen = false
                event.accepted = true
                return
            }
            if (root.choosingFolder) {
                root.cancelFolder()
                event.accepted = true
                return
            }
            if (root.modeOpen) {
                root.closeMode()
                event.accepted = true
                return
            }
            if (root.drawerProgress > 0.01) {
                root.setDrawerOpen(false)
                event.accepted = true
                return
            }
            root.launcherController.close()
            event.accepted = true
            return
        }
        // Apps with nothing typed: the arrow keys choose an
        // application, as they do once something is typed, and Enter opens it.
        if (root.drawerOpen && !root.filesMode && !query.activeFocus && applicationGrid.choices.length > 0) {
            const steps = { [Qt.Key_Left]: [-1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_Up]: [0, -1], [Qt.Key_Down]: [0, 1] }
            const move = steps[event.key]
            if (move && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                applicationGrid.step(move[0], move[1])
                event.accepted = true
                return
            }
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && applicationGrid.keyChosen) {
                root.submit()
                event.accepted = true
                return
            }
        }
        // Tab moves between the controls; anything else typed goes into
        // search.
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
                && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab
                && !query.activeFocus && !root.modeOpen && event.text.length > 0
                && !(event.modifiers & (Qt.ControlModifier
                    | Qt.AltModifier | Qt.MetaModifier))) {
            root.searchEngaged = true
            query.forceActiveFocus()
            query.insert(query.cursorPosition, event.text)
            event.accepted = true
        }
    }

    Connections {
        target: root.launcherController
        function onGuestBridgeLost() {
            launchTimeout.stop()
            launchReadyExit.stop()
            guestExit.stop()
            root.applicationLaunchPending = false
            root.launchingApplication = ""
            root.guestExiting = false
            root.guestDrag = 0
            sheet.opacity = 1
            sheet.scale = 1
            query.forceActiveFocus()
        }
        function onOpened() {
            // Search opens where it rests, at its resting size: nothing slides
            // or shrinks in from where it last closed.
            root.sheetSettled = false
            Qt.callLater(() => { root.sheetSettled = true })
            launchTimeout.stop()
            query.text = ""
            root.pendingLaunch = false
            root.applicationLaunchPending = false
            root.launchingApplication = ""
            root.searchEngaged = false
            root.drawerOpen = false
            root.drawerProgress = 0
            root.sortMenuOpen = false
            modeSettle.stop()
            modeTimeout.stop()
            modeExit.stop()
            modeWait.stop()
            root.modeAwaited = ""
            root.modeOpen = false
            root.modeShown = ""
            root.modeProgress = 0
            root.modeGrowing = false
            root.modeHandoff = false
            root.modeToken = ""
            filesHandoffTimeout.stop()
            root.filesHandoff = false
            if (root.quickNote) root.quickNote.refresh()
            root.forceActiveFocus()
            // Opened by its key, Search is ready to type: the cursor waits in
            // the field, and keys on screen stay up. Its button leaves the
            // field alone, so a tap raises no keys.
            if (root.launcherController.openedToType()) {
                root.searchEngaged = true
                query.forceActiveFocus()
            }
            root.typingAwaitsWindow = root.searchEngaged && !(root.Window.window && root.Window.window.active)
            root.guestDrag = 0
            root.guestExiting = false
            root.guestDragged = false
            sheet.opacity = 1
            sheet.scale = 1
            openingSequence.restart()
            // The doors follow the field's outline in.
            firstRow.arrive(root.own(140), true)
        }
        function onFilesRequested() { root.setDrawerOpen(true, "files") }
        // Meta+G, Meta+E or the dot's slide: that drawer opens filling the
        // screen, a single step to the whole view, or the launcher closes when
        // it is the one already open. Pills inside Search open at its size.
        // Another drawer or mode already open gives way, so the slide moves
        // straight from one to the next and Back leads to search.
        function onDrawerRequested(mode) {
            // The panel's dot asks for "note", a new quick note, and its
            // pinned note for "note:" and the note's id. Each opens at
            // Search's size.
            if (mode === "note" || mode.startsWith("note:")) {
                if (root.modeOpen && root.modeShown !== "notes") root.closeMode()
                root.openModeDirectly("notes", mode === "note" ? "new" : mode)
                return
            }
            // Back from a note handed to the notes application's card: Notes
            // again, at the size it had when the note left.
            if (mode === "notes-back") {
                if (root.modeOpen && root.modeShown !== "notes") root.closeMode()
                root.openModeDirectly("notes")
                if (root.notesLeftExpanded) root.launcherController.setDrawerExpanded(true, true)
                return
            }
            if (root.modeOpen && root.modeShown !== mode) root.closeMode()
            if (mode === "notes") {
                const shown = root.modeOpen && root.modeShown === mode
                root.openModeDirectly(mode)
                const coming = (root.modeOpen && root.modeShown === mode) || root.modeAwaited === mode
                if (!shown && coming) root.launcherController.setDrawerExpanded(true, true)
                return
            }
            const files = mode === "files"
            if (files && !root.fileBrowser) return
            if (root.drawerOpen && root.filesMode === files) root.launcherController.close()
            else {
                root.setDrawerOpen(true, files ? "files" : "apps")
                root.launcherController.setDrawerExpanded(true, true)
            }
        }
        function onGuestLaunchReady() {
            if (root.filesHandoff) {
                filesHandoffTimeout.stop()
                root.filesHandoff = false
                root.guestExiting = true
                launchReadyExit.restart()
                return
            }
            if (root.modeHandoff) {
                modeTimeout.stop()
                root.modeHandoff = false
                root.guestExiting = true
                launchReadyExit.restart()
                return
            }
            if (!root.applicationLaunchPending) {
                return
            }
            launchTimeout.stop()
            root.guestExiting = true
            launchReadyExit.restart()
        }
        function onGuestNavigationReady(slot) {
            if (root.guestExiting) {
                return
            }
            root.guestExiting = true
            root.guestDragged = true
            guestExit.to = slot < 0
                ? sheet.width * 1.25 : -sheet.width * 1.25
            guestExit.restart()
        }
    }

    Connections {
        target: root.searchResults
        function onQueryingChanged() {
            if (!root.searchResults.querying && root.pendingLaunch) {
                root.pendingLaunch = false
                root.submit()
            }
        }
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "transparent"
        visible: !root.launcherController.guestMode

        TapHandler {
            onTapped: event => {
                const point = sheet.mapFromItem(backdrop, event.position.x, event.position.y)
                if (!sheet.contains(point)) root.launcherController.close()
            }
        }
    }

    Rectangle {
        id: sheet
        objectName: "launcher-sheet"
        // Resting, the sheet is as tall as what its first screen shows: the
        // field alone, one section of what was used lately, or both, as far
        // as the screen allows. Typing, a drawer or a mode gives it its
        // working height. Whatever its height, it stays centred.
        readonly property real restingHeight: Math.min(root.launcherController.availableArea.height - 40,
            2 * root.contentInset + root.modeRowReach + root.fieldHeight
                + (firstRow.sections > 0 ? firstRow.gap + firstRow.naturalHeight : 0))
        readonly property real fullHeight: Math.max(restingHeight,
            Math.min(root.launcherController.availableArea.height - 40, universalHeight))
        readonly property bool resting: query.text.length === 0 && !root.drawerOpen && root.modeShown === ""
        readonly property real restHeight: root.launcherController.guestMode
            ? root.launcherController.guestHeight
            : root.launcherController.drawerExpanded
                ? Math.max(1, root.launcherController.availableArea.height - 20)
                : resting ? restingHeight : fullHeight
        // Floating, Search is one size on every display, as tall as both
        // sections and as wide as eight applications want, never scaled up
        // with a large display; only a smaller screen trims it.
        readonly property real universalWidth: 840
        readonly property real universalHeight: 2 * root.contentInset + 56 + root.fieldHeight
            + firstRow.gap + firstRow.headHeight + firstRow.appHeight
            + firstRow.gap + firstRow.headHeight + 2 * firstRow.cardHeight + firstRow.cardGap
        // With nothing under the field, the sheet is only as wide as the
        // field needs: 592 and the 24 on each side.
        readonly property real smallWidth: 640
        readonly property bool small: resting && firstRow.sections === 0
        // With the keys up the sheet rises only as far as it must, never
        // leaving the room Kadunce gave a guest, then shortens to fit.
        readonly property real keysLine: root.height - root.keysReach
        // The room it is centred in: the work area, above the keys while
        // they are up.
        readonly property real room: Math.min(root.launcherController.availableArea.y
            + root.launcherController.availableArea.height, keysLine) - root.launcherController.availableArea.y
        readonly property real highest: root.launcherController.guestMode
            ? root.launcherController.guestY
            : root.launcherController.availableArea.y
                + Math.min(10, Math.round((root.launcherController.availableArea.height - restHeight) / 2))
        x: root.launcherController.guestMode
            ? root.launcherController.guestX
            : root.launcherController.availableArea.x
                + (root.launcherController.availableArea.width - width) / 2
        y: Math.max(highest, Math.min(keysLine - height, root.launcherController.guestMode
            ? root.launcherController.guestY
            : root.launcherController.availableArea.y
                + (root.launcherController.drawerExpanded ? 10
                    : Math.max(0, Math.min(Math.round((room - height) / 2), room - height - 10)))))
        width: root.launcherController.guestMode
            ? root.launcherController.guestWidth
            : root.launcherController.drawerExpanded
                ? Math.max(1, root.launcherController.availableArea.width - 20)
                : Math.min(small ? smallWidth : universalWidth, root.launcherController.availableArea.width - 40)
        height: Math.max(Math.min(restHeight, 160), Math.min(restHeight, keysLine - highest))
        Behavior on x { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        // Centred on its height as that moves, so it grows up and down
        // evenly with no motion of its own.
        Behavior on y { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        Behavior on width { enabled: root.sheetSettled; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        // The keys' own easing already moves the sheet; chasing it would lag.
        Behavior on height { enabled: root.sheetSettled && !keysMotion.running; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        // Floating, it is a note that closes; in Spread, a card's paper.
        radius: root.launcherController.guestMode ? root.paperRadius : root.noteRadius
        color: root.surfaceColor
        border.width: 1
        border.color: root.surfaceOutline
        clip: true
        transform: Translate { x: root.guestDrag }

        DragHandler {
            id: guestDragHandler
            enabled: root.launcherController.guestMode
                && !root.drawerOpen
                && !root.guestExiting
                && !root.applicationLaunchPending
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            acceptedDevices: PointerDevice.Mouse
                | PointerDevice.TouchPad
                | PointerDevice.TouchScreen

            onTranslationChanged: {
                if (active) {
                    root.guestDrag = translation.x
                    if (Math.abs(translation.x) > 8) {
                        root.guestDragged = true
                    }
                }
            }
            onActiveChanged: {
                if (active || !root.launcherController.guestMode) {
                    return
                }
                const projected = translation.x + Math.max(-140,
                    Math.min(140, centroid.velocity.x * 0.09))
                if (root.launcherController.finishGuestDrag(projected)) {
                    root.guestExiting = true
                    guestExit.to = projected < 0
                        ? -sheet.width * 1.25 : sheet.width * 1.25
                    guestExit.restart()
                } else {
                    guestReturn.restart()
                }
            }
        }

        TapHandler {
            onTapped: event => event.accepted = true
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.contentInset
            anchors.topMargin: root.contentInset + root.modeRowReach

            SearchField {
                id: searchField
                launcher: root
                tone: tone
                words: words
                applicationGrid: applicationGrid
                filesLoader: filesLoader
                firstRow: firstRow
                resultList: root.resultList
            }

            ModeRow {
                id: modeRow
                launcher: root
                tone: tone
                words: words
                drawerSettle: drawerSettle
            }

            RecentRow {
                id: firstRow
                launcher: root
                tone: tone
                words: words
                modeRow: modeRow
                searchField: searchField
                sheet: sheet
            }

            SearchResults {
                id: resultsArea
                launcher: root
                tone: tone
                words: words
                query: root.query
                searchField: searchField
            }

            Item {
                id: drawerHandle
                objectName: "drawer-header"
                readonly property real sectionGap: 16
                readonly property real openHeight: root.fieldHeight
                // Open, the header is search's own row: the field stays where
                // it is on every screen, with the eye inside it beside Clear.
                readonly property real controlsOpacity: Math.max(0, (root.drawerProgress - 0.72) / 0.28)
                readonly property real restingY: parent.height + root.contentInset - 48
                readonly property real revealDistance: Math.max(1,
                    restingY)
                property real dragStartProgress: 0
                property real dragReferenceDistance: 1
                x: 0
                y: root.filesMode && root.drawerProgress > 0
                    ? 0
                    : Math.round(restingY
                        - root.drawerProgress * revealDistance)
                width: parent.width
                height: 48 - (48 - openHeight) * root.drawerProgress
                opacity: (query.text.length === 0 || root.drawerOpen)
                    && !root.applicationLaunchPending
                    ? root.openingControls * (1 - root.modeProgress) : 0
                transform: Translate { y: (1 - root.openingControls) * 10 }
                enabled: opacity > 0.5
                z: 4

                // The eye shows what is hidden: hidden applications in Browse
                // everything, hidden files in Files. Again, it hides them. It
                // sits inside search, just left of its search icon.
                Item {
                    id: hiddenButton
                    objectName: "hidden-button"
                    readonly property bool showing: root.filesMode
                        ? !!root.fileBrowser && root.fileBrowser.hidden
                        : root.applicationCatalog.showHidden
                    function toggle() {
                        if (root.filesMode) {
                            if (root.fileBrowser) root.fileBrowser.hidden = !root.fileBrowser.hidden
                        } else {
                            root.applicationCatalog.showHidden = !root.applicationCatalog.showHidden
                        }
                    }
                    x: searchField.x + searchField.width - 12 - (searchField.trailingAction.visible ? 36 : 0) - width
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42
                    opacity: drawerHandle.controlsOpacity
                    enabled: root.drawerOpen && opacity > 0.9
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: root.filesMode ? words.i18n("Show hidden files")
                        : words.i18n("Show hidden applications")
                    Accessible.checked: showing
                    Accessible.onPressAction: toggle()
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: height / 2
                        color: hiddenPress.pressed ? tone.controlPressed
                            : hiddenButton.showing ? tone.controlHover
                            : hiddenHover.hovered ? root.controlColor : "transparent"
                        Behavior on color { ColorAnimation { duration: root.ms(90) } }
                    }
                    SuiteIcon {
                        anchors.centerIn: parent
                        glyph: hiddenButton.showing ? "eye" : "eye-off"
                        width: 18
                        height: 18
                    }
                    HoverHandler {
                        id: hiddenHover
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                    }
                    MouseArea {
                        id: hiddenPress
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hiddenButton.toggle()
                    }
                }

                // The open drawer's header pulled down closes it.
                DragHandler {
                    id: drawerDrag
                    property string gestureMode: "apps"
                    enabled: root.drawerOpen
                    margin: 4
                    target: null
                    xAxis.enabled: false
                    yAxis.enabled: true
                    acceptedDevices: PointerDevice.Mouse
                        | PointerDevice.TouchPad
                        | PointerDevice.TouchScreen
                    onActiveChanged: {
                        if (active) {
                            // The compact bottom pull always opens Apps, even
                            // when the last drawer closed was Files. Keep mode
                            // stable for this gesture, not inherited from history.
                            gestureMode=root.drawerOpen && root.filesMode ? "files" : "apps"
                            if(!root.drawerOpen)root.filesMode=false
                            root.sortMenuOpen = false
                            drawerHandle.dragStartProgress =
                                root.drawerProgress
                            drawerHandle.dragReferenceDistance = drawerHandle.revealDistance
                            drawerSettle.stop()
                        } else {
                            root.setDrawerOpen(root.drawerProgress > 0.34, gestureMode)
                        }
                    }
                    onTranslationChanged: {
                        if (active) {
                            root.drawerProgress = Math.max(0, Math.min(1,
                                drawerHandle.dragStartProgress
                                - translation.y
                                    / drawerHandle.dragReferenceDistance))
                        }
                    }
                }
            }

            NotesPane {
                id: notesPane
                objectName: "notes-pane"
                anchors.fill: parent
                z: 5
                quickNote: root.quickNote
                progress: root.notesProgress
                fieldRest: Qt.rect(searchField.x, searchField.y, searchField.width, searchField.height)
                growing: root.modeGrowing
                expanded: root.launcherController.drawerExpanded
                surfaceColor: root.surfaceColor
                surfaceOutline: root.surfaceOutline
                controlColor: root.controlColor
                primaryText: root.primaryText
                onExpand: root.toggleExpanded()
                onDismiss: root.launcherController.close()
                onGrow: root.growNotes()
                onFinished: {
                    root.notesLeftExpanded = root.launcherController.drawerExpanded
                    root.launcherController.close()
                }
            }

            Loader {
                id: filesLoader
                active: false
                asynchronous: true
                sourceComponent: FilesPane {
                    objectName: "files-pane"
                    browser: root.fileBrowser
                    compact: root.keysUp
                    card: !root.launcherController.drawerExpanded
                    keysReach: root.keysReach
                    carryArea: sheet
                    onCarryOut: paths => {
                        const at = sheet.mapToItem(null, 0, 0)
                        root.launcherController.carryOut(paths, Qt.rect(at.x, at.y, sheet.width, sheet.height))
                    }
                }
                Connections {
                    target: root
                    function onFilesModeChanged() { if (root.filesMode) filesLoader.active = true }
                }
                x: 0; y: searchField.y + searchField.height + drawerHandle.sectionGap
                width: parent.width; height: Math.max(0,parent.height-y)
                visible: root.filesMode && root.drawerProgress>0.01
                opacity: root.drawerProgress
            }
            // Apps' row over its applications, the same cluster Files has at
            // the right of its own: New folder, the order, then the size.
            SizePill {
                id: appsSize
                objectName: "apps-size"
                x: parent.width - width
                y: sortButton.y
                width: 72; height: 42
                visible: sortButton.visible
                opacity: sortButton.opacity
                enabled: sortButton.enabled
                z: 5
                level: root.applicationCatalog ? root.applicationCatalog.tileSize : 1
                onResize: step => applicationGrid.resizeTiles(step)
            }
            Item {
                id: sortButton
                objectName: "sort-button"
                // By the catalog's numbers for them; 1 is no longer one.
                readonly property var orderNames: [words.i18n("A to Z"), words.i18n("A to Z"),
                    words.i18n("Most used"), words.i18n("Newest installed")]
                Accessible.role: Accessible.ButtonMenu
                Accessible.name: words.i18n("Sort: %1", sortLabel.text)
                Accessible.onPressAction: root.sortMenuOpen = !root.sortMenuOpen
                x: appsSize.x - 8 - width
                y: searchField.y + searchField.height + drawerHandle.sectionGap
                width: sortLabel.implicitWidth + 46
                height: 42
                visible: !root.filesMode && !root.choosingFolder && opacity > 0
                opacity: drawerHandle.controlsOpacity
                enabled: root.drawerOpen && !root.filesMode && opacity > 0.9
                z: 5
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 30
                    radius: height / 2
                    color: sortPress.pressed || root.sortMenuOpen ? tone.controlPressed
                        : sortHover.hovered ? tone.controlHover : root.controlColor
                    Behavior on color { ColorAnimation { duration: root.ms(90) } }
                    Text {
                        id: sortLabel
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        text: sortButton.orderNames[Math.max(0, Math.min(3, root.applicationCatalog.sortOrder))]
                        color: root.primaryText
                        font.pixelSize: 13
                    }
                    SuiteIcon {
                        glyph: "chevron-down"
                        width: 14; height: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                HoverHandler {
                    id: sortHover
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                }
                MouseArea {
                    id: sortPress
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortMenuOpen = !root.sortMenuOpen
                }
            }

            // New folder, beside the order, as Files has it.
            ModePill {
                id: newAppsFolder
                objectName: "apps-new-folder"
                label: words.i18n("New folder")
                primaryText: root.primaryText
                controlColor: root.controlColor
                x: sortButton.x - 8 - width
                y: sortButton.y
                visible: sortButton.visible && !root.choosingFolder
                opacity: sortButton.opacity
                enabled: sortButton.enabled
                z: 5
                onActivated: root.startFolder()
            }
            // Choosing for a new folder: what to do, Cancel, and Make folder
            // once two are chosen.
            Item {
                id: folderChoosing
                objectName: "apps-folder-choosing"
                x: 0
                y: sortButton.y
                width: parent.width
                height: 42
                visible: root.choosingFolder && !root.filesMode
                z: 6
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.right: cancelFolderPill.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.folderPicks.length === 0
                        ? words.i18n("Choose applications for the new folder")
                        : words.i18np("%1 chosen", "%1 chosen", root.folderPicks.length)
                    color: root.secondaryText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                ModePill {
                    id: cancelFolderPill
                    objectName: "apps-folder-cancel"
                    label: words.i18n("Cancel")
                    primaryText: root.primaryText
                    controlColor: root.controlColor
                    anchors.right: makeFolderPill.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: root.cancelFolder()
                }
                ModePill {
                    id: makeFolderPill
                    objectName: "apps-folder-make"
                    label: words.i18n("Make folder")
                    light: true
                    dimmed: root.folderPicks.length < 2
                    enabled: root.folderPicks.length >= 2
                    primaryText: root.primaryText
                    controlColor: root.controlColor
                    surfaceColor: root.surfaceColor
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onActivated: root.makeFolder()
                }
            }

            AppsGrid {
                id: applicationGrid
                launcher: root
                tone: tone
                words: words
                applicationSheet: applicationSheet
                drawerHandle: drawerHandle
                folderSheet: folderSheet
                searchField: searchField
                sheet: sheet
                sortButton: sortButton
            }

            // An application's sheet: its own actions, then Pin to dock or
            // Unpin from dock where Shuffle's dock is there, Hide or Unhide,
            // Edit Application… where KDE's menu editor is installed, and
            // Uninstall where the software centre can show it.
            SheetMenu {
                id: applicationSheet
                objectName: "application-sheet"
                bounds: sheet
                bottomMargin: root.keysReach
                keysReach: root.keysReach
                property int row: -1
                // The application the sheet is for, which keeps its row
                // when Apps is read again.
                property string applicationId: ""
                property var actions: []
                property bool hidden: false
                property bool pinned: false
                property string inFolder: ""
                property var folders: []
                Repeater {
                    model: applicationSheet.actions
                    // Made after the menu, so each line is given its menu here.
                    delegate: SheetMenuItem {
                        required property var modelData
                        menu: applicationSheet
                        width: parent ? parent.width : implicitWidth
                        text: modelData.name
                        onTriggered: root.runCatalogAction(applicationSheet.row, modelData.index)
                    }
                }
                SheetMenuItem {
                    objectName: "application-sheet-pin"
                    text: applicationSheet.pinned ? words.i18n("Unpin from dock") : words.i18n("Pin to dock")
                    visible: root.launcherController.dockPresent
                    onTriggered: root.launcherController.pinCatalog(applicationSheet.row, !applicationSheet.pinned)
                }
                // Into another folder, or out of the one it is in.
                Repeater {
                    model: applicationSheet.folders
                    delegate: SheetMenuItem {
                        required property var modelData
                        menu: applicationSheet
                        width: parent ? parent.width : implicitWidth
                        text: words.i18n("Put in “%1”", modelData.name)
                        onTriggered: root.applicationCatalog.putInFolder(applicationSheet.row, modelData.id)
                    }
                }
                SheetMenuItem {
                    objectName: "application-sheet-take-out"
                    text: words.i18n("Take out of folder")
                    visible: applicationSheet.inFolder !== ""
                    onTriggered: root.applicationCatalog.takeOut(applicationSheet.row)
                }
                SheetMenuItem {
                    objectName: "application-sheet-hide"
                    text: applicationSheet.hidden ? words.i18n("Unhide") : words.i18n("Hide")
                    onTriggered: root.applicationCatalog.setHidden(applicationSheet.row, !applicationSheet.hidden)
                }
                SheetMenuItem {
                    objectName: "application-sheet-edit"
                    text: words.i18n("Edit Application…")
                    visible: root.applicationCatalog.canEdit(applicationSheet.row)
                    onTriggered: {
                        if (root.applicationCatalog.edit(applicationSheet.row))
                            root.launcherController.finishLaunch()
                    }
                }
                SheetMenuItem {
                    objectName: "application-sheet-uninstall"
                    text: words.i18n("Uninstall…")
                    visible: {
                        root.applicationCatalog.softwareReady
                        return root.applicationCatalog.canUninstall(applicationSheet.row)
                    }
                    onTriggered: {
                        if (root.applicationCatalog.uninstall(applicationSheet.row))
                            root.launcherController.finishLaunch()
                    }
                }
            }

            // A found application's sheet: Uninstall…, as from Apps.
            SheetMenu {
                id: resultSheet
                objectName: "result-sheet"
                bounds: sheet
                bottomMargin: root.keysReach
                keysReach: root.keysReach
                property string applicationId: ""
                SheetMenuItem {
                    objectName: "result-sheet-uninstall"
                    text: words.i18n("Uninstall…")
                    onTriggered: {
                        if (root.applicationCatalog.uninstallApplication(resultSheet.applicationId))
                            root.launcherController.finishLaunch()
                    }
                }
            }

            // A folder's sheet. Rename readies its name to change on its row;
            // Remove folder puts its applications back in Apps.
            SheetMenu {
                id: folderSheet
                objectName: "apps-folder-sheet"
                bounds: sheet
                bottomMargin: root.keysReach
                keysReach: root.keysReach
                property int row: -1
                property string folder: ""
                SheetMenuItem {
                    objectName: "apps-folder-sheet-rename"
                    text: words.i18n("Rename")
                    // Once the sheet has closed and let the keys go.
                    onTriggered: Qt.callLater(() => root.renameFolder(folderSheet.folder))
                }
                SheetMenuItem {
                    objectName: "apps-folder-sheet-remove"
                    text: words.i18n("Remove folder")
                    onTriggered: root.applicationCatalog.removeFolder(folderSheet.folder)
                }
            }

            Text {
                anchors.centerIn: applicationGrid
                visible: root.drawerOpen && !root.filesMode && query.text.length > 0
                    && applicationGrid.choices.length === 0
                text: words.i18n("No applications found")
                color: root.secondaryText
                font.pixelSize: 15
                z: 4
            }

            Rectangle {
                id: sortMenu
                objectName: "sort-menu"
                // Under the sort button, its right edge level with the button's.
                x: sortButton.x + sortButton.width - width
                y: sortButton.y + sortButton.height + 4
                width: 160
                height: sortChoices.implicitHeight + 12
                radius: root.noteRadius
                color: root.surfaceColor
                border.width: 1
                border.color: root.surfaceOutline
                visible: opacity > 0
                enabled: root.sortMenuOpen && root.drawerOpen
                opacity: root.sortMenuOpen && root.drawerOpen ? 1 : 0
                z: 8

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.ms(120)
                        easing.type: Easing.OutCubic
                    }
                }

                Column {
                    id: sortChoices
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    // Each order's number is the catalog's own.
                    Repeater {
                        model: [
                            { "label": words.i18n("A to Z"), "order": 0 },
                            { "label": words.i18n("Most used"), "order": 2 },
                            { "label": words.i18n("Newest installed"), "order": 3 }
                        ]

                        delegate: Rectangle {
                            id: sortChoice
                            required property var modelData
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.label
                            Accessible.checked: selected
                            width: parent.width
                            height: 38
                            radius: height / 2
                            readonly property bool selected: root.applicationCatalog.sortOrder
                                === sortChoice.modelData.order
                            color: selected ? root.controlColor : "transparent"
                            border.width: !selected && choiceHover.hovered ? 1 : 0
                            border.color: root.surfaceOutline
                            Behavior on color { ColorAnimation { duration: root.ms(100) } }

                            Text {
                                anchors.centerIn: parent
                                text: sortChoice.modelData.label
                                color: root.primaryText
                                font.pixelSize: 13
                            }

                            HoverHandler { id: choiceHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.applicationCatalog.sortOrder =
                                        sortChoice.modelData.order
                                    applicationGrid.reset()
                                    root.sortMenuOpen = false
                                }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 14
                visible: root.applicationLaunchPending
                opacity: root.applicationLaunchPending ? 1 : 0
                z: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: words.i18n("Opening")
                    color: root.secondaryText
                    font.pixelSize: 14
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(content.width * 0.72, 620)
                    horizontalAlignment: Text.AlignHCenter
                    text: root.launchingApplication
                    color: root.primaryText
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 3
                    radius: height / 2
                    color: tone.track

                    Rectangle {
                        id: launchProgress
                        width: 28
                        height: parent.height
                        radius: height / 2
                        color: tone.progress

                        SequentialAnimation on x {
                            running: root.applicationLaunchPending
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 0
                                to: 56
                                duration: 560
                                easing.type: Easing.InOutCubic
                            }
                            NumberAnimation {
                                from: 56
                                to: 0
                                duration: 560
                                easing.type: Easing.InOutCubic
                            }
                        }
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: modeSettle
        target: root
        property: "modeProgress"
        duration: root.ms(260)
        easing.type: Easing.OutCubic
        onFinished: if (!root.modeOpen && root.modeProgress <= 0) root.modeShown = ""
    }

    // The application's window never arrived: back to the mode.
    Timer {
        id: modeTimeout
        interval: 10000
        repeat: false
        onTriggered: root.stopGrowingMode()
    }

    // Files' window is already open; Search leaves if Kadunce does not take
    // it as Search's card.
    Timer {
        id: filesHandoffTimeout
        interval: 3000
        onTriggered: {
            root.filesHandoff = false
            root.launcherController.cancelGuestApplicationLaunch()
            root.launcherController.close()
        }
    }

    // Over an Active card the application's window has taken the card's
    // place under the grown window, which fades to show it.
    NumberAnimation {
        id: modeExit
        target: sheet
        property: "opacity"
        to: 0
        duration: root.ms(140)
        easing.type: Easing.OutCubic
        onFinished: root.launcherController.finishLaunch()
    }

    Connections {
        target: root.quickNote
        ignoreUnknownSignals: true
        function onBoardShown(requestToken) { root.modeWindowShown(requestToken) }
    }

    Timer {
        id: launchTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            root.launcherController.cancelGuestApplicationLaunch()
            root.applicationLaunchPending = false
            root.launchingApplication = ""
            root.guestExiting = false
            query.forceActiveFocus()
        }
    }

    NumberAnimation {
        id: drawerSettle
        target: root
        property: "drawerProgress"
        duration: root.ms(260)
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: guestReturn
        target: root
        property: "guestDrag"
        to: 0
        duration: root.ms(210)
        easing.type: Easing.OutBack
        onFinished: root.guestDragged = false
    }

    ParallelAnimation {
        id: launchReadyExit
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 0.96
            duration: root.ms(190)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 0
            duration: root.ms(190)
            easing.type: Easing.OutCubic
        }
        onFinished: root.launcherController.completeGuestHandoff()
    }

    ParallelAnimation {
        id: guestExit
        property real to: 0
        NumberAnimation {
            target: root
            property: "guestDrag"
            to: guestExit.to
            duration: root.ms(220)
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 0.72
            duration: root.ms(220)
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 0
            duration: root.ms(220)
            easing.type: Easing.InCubic
        }
        onFinished: root.launcherController.completeGuestHandoff()
    }
}
