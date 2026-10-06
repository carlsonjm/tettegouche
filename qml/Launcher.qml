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
    // The quick note Search writes in its own window; null when the setting is
    // off. Notes is one of Search's modes while the notes application speaks
    // its interface, and opens that application's own card otherwise.
    property var quickNote: null
    // Genie's chat, kept by Split Rock; null when the setting is off.
    property var genie: null
    // Search's modes, Notes and Genie: each opens in this window with the
    // drawer's motion and grows into its application's own window. The shown
    // mode stays while it closes, until its motion ends.
    property string modeShown: ""
    property bool modeOpen: false
    property real modeProgress: 0
    property bool modeGrowing: false
    property bool modeHandoff: false
    property string modeToken: ""
    readonly property bool notesOpen: modeOpen && modeShown === "notes"
    readonly property real notesProgress: modeShown === "notes" ? modeProgress : 0
    readonly property bool notesGrowing: modeGrowing && modeShown === "notes"
    readonly property bool notesHandoff: modeHandoff && modeShown === "notes"
    readonly property bool genieOpen: modeOpen && modeShown === "genie"
    readonly property real genieProgress: modeShown === "genie" ? modeProgress : 0
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
    readonly property color primaryText: "#f2ffffff"
    readonly property color secondaryText: "#a8ffffff"
    readonly property color edgeText: "#88ffffff"
    readonly property color surfaceColor: "#141414"
    readonly property color surfaceOutline: "#5a5a5a"
    readonly property color controlColor: "#242424"
    // Shuffle's corner tiers: paper for the sheet and all laid in it, notes for
    // what floats above and closes; anything pressed is a pill.
    readonly property int paperRadius: 8
    readonly property int noteRadius: 12
    readonly property int contentInset: 22
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
    // How far up from the window's bottom the sheet must keep clear, eased as
    // the keys come and go.
    property real keysReach: keysUp ? height - keysRect.y + 10 : 0
    Behavior on keysReach {
        NumberAnimation { id: keysMotion; duration: root.ms(220); easing.type: Easing.OutCubic }
    }

    // Under the finger a piece lifts, as an object would: a little larger, a
    // step lighter, with a soft shadow beneath it.
    component LiftShadow: Item {
        id: shadow
        property bool lifted: false
        property real cornerRadius: root.paperRadius
        anchors.fill: parent
        z: -1
        opacity: lifted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
        Repeater {
            model: [{ grow: 6, drop: 7, alpha: 0.10 }, { grow: 3, drop: 4, alpha: 0.16 }, { grow: 1, drop: 2, alpha: 0.22 }]
            Rectangle {
                required property var modelData
                x: -modelData.grow
                y: -modelData.grow + modelData.drop
                width: shadow.width + 2 * modelData.grow
                height: shadow.height + 2 * modelData.grow
                radius: shadow.cornerRadius + modelData.grow
                color: Qt.rgba(0, 0, 0, modelData.alpha)
            }
        }
    }

    // A door on Search's first screen, Apps, Files or Notes: the suite's pill.
    component FirstPill: Item {
        id: pill
        property string label
        property string glyph
        // How far it has arrived, 0 to 1; it rises a little into place,
        // growing to its size. With animations set to instant it only fades.
        property real reveal: 1
        signal activated()
        width: pillContent.implicitWidth + 32
        height: 44
        opacity: reveal
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Keys.onReturnPressed: pill.activated()
        Keys.onEnterPressed: pill.activated()
        Keys.onSpacePressed: pill.activated()
        Rectangle {
            id: pillFace
            anchors.fill: parent
            radius: height / 2
            color: pillTap.pressed ? "#303030" : pillHover.hovered ? "#2a2a2a" : root.controlColor
            scale: pillTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.ms(90) } }
            transform: [
                Scale {
                    origin.x: pillFace.width / 2
                    origin.y: pillFace.height / 2
                    xScale: root.reducedMotion ? 1 : 0.9 + 0.1 * pill.reveal
                    yScale: root.reducedMotion ? 1 : 0.9 + 0.1 * pill.reveal
                },
                Translate { y: root.reducedMotion ? 0 : (1 - pill.reveal) * 10 }
            ]
            LiftShadow { lifted: pillTap.pressed; cornerRadius: pillFace.radius }
            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: 9
                // Apps: four squares, as a grid of applications.
                Grid {
                    visible: pill.glyph === "apps"
                    anchors.verticalCenter: parent.verticalCenter
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: 4
                        Rectangle { width: 6.5; height: 6.5; radius: 1.5; color: root.primaryText }
                    }
                }
                SuiteIcon {
                    visible: pill.glyph === "files" || pill.glyph === "notes" || pill.glyph === "genie"
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: pill.glyph === "notes" || pill.glyph === "genie" ? pill.glyph : "folder-open"
                    width: 18
                    height: 18
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.label
                    color: root.primaryText
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }
        }
        // Keyboard focus alone gets an outline.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: "#b0ffffff"
            visible: pill.activeFocus
        }
        HoverHandler {
            id: pillHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: pillTap
            enabled: !root.guestDragged
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: pill.activated()
        }
    }

    // Something used lately: an application's icon or a file's picture, and
    // its name.
    component RecentTile: Item {
        id: tile
        required property int index
        required property var model
        objectName: "recent-" + index
        height: 64
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: tile.model.name
        Keys.onReturnPressed: root.runRecent(tile.index, tile.model.name)
        Keys.onEnterPressed: root.runRecent(tile.index, tile.model.name)
        Keys.onSpacePressed: root.runRecent(tile.index, tile.model.name)
        Rectangle {
            id: tileFace
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 68)
            height: parent.height
            radius: root.paperRadius
            color: tileTap.pressed ? "#262626" : tileHover.hovered ? "#20ffffff" : "transparent"
            scale: tileTap.pressed ? 1.07 : 1
            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.ms(90) } }
            LiftShadow { lifted: tileTap.pressed }
            Item {
                x: (parent.width - 34) / 2
                y: 6
                width: 34
                height: 34
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: tile.model.thumbnail.length === 0
                    source: tile.model.icon
                }
                Rectangle {
                    anchors.fill: parent
                    visible: tile.model.thumbnail.length > 0
                    radius: 6
                    color: root.controlColor
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: tile.model.thumbnail
                        sourceSize: Qt.size(68, 68)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }
            Text {
                x: 3
                y: 44
                width: parent.width - 6
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.model.name
                color: root.secondaryText
                font.pixelSize: 11
            }
        }
        Rectangle {
            anchors.fill: tileFace
            anchors.margins: -2
            radius: root.paperRadius + 2
            color: "transparent"
            border.width: 1.5
            border.color: "#b0ffffff"
            visible: tile.activeFocus
        }
        HoverHandler {
            id: tileHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: tileTap
            enabled: !root.guestDragged && !root.applicationLaunchPending
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.runRecent(tile.index, tile.model.name)
        }
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

    function setDrawerOpen(open, mode) {
        if (open) root.filesMode = mode === "files"
        root.guestDrag = 0
        root.drawerOpen = open
        root.launcherController.setDrawerExpanded(open)
        if (!open) {
            root.sortMenuOpen = false
        }
        root.applicationCatalog.filterText = open && !root.filesMode ? query.text : ""
        if (root.fileBrowser) root.fileBrowser.filter = root.filesMode ? query.text : ""
        root.searchResults.queryString = open ? "" : query.text
        drawerSettle.to = open ? 1 : 0
        drawerSettle.restart()
        if (open) {
            root.searchEngaged = false
            root.forceActiveFocus()
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

    // An application's sheet, opened from its tile at a point on it.
    function showApplicationSheet(index, tile, point) {
        root.applicationCatalog.prepareSoftware()
        applicationSheet.row = index
        applicationSheet.actions = root.applicationCatalog.actions(index)
        applicationSheet.hidden = root.applicationCatalog.isHidden(index)
        const at = tile.mapToItem(sheet, point.x, point.y)
        applicationSheet.openNear(at.x, at.y)
    }

    function runCatalogApplication(index, applicationName) {
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

    // A mode opens in Search's window with the drawer's motion and the
    // window keeps its size: Notes turns the field into the note pad, Genie
    // carries it into the header with the question.
    function openMode(name) {
        const client = name === "notes" ? root.quickNote : root.genie
        if (!client || !client.available || root.modeGrowing) return false
        client.start()
        root.modeShown = name
        root.modeOpen = true
        root.sortMenuOpen = false
        modeSettle.to = 1
        modeSettle.restart()
        if (name === "notes") notesPane.focusPad()
        else geniePane.focusField()
        return true
    }
    // An older notes application without the interface gets its own card,
    // and Search closes.
    function openNotes() {
        if (root.openMode("notes")) return true
        if (!root.notesDoor || !root.notesDoor.open()) return false
        root.launcherController.finishLaunch()
        return true
    }
    function openGenie() { return root.openMode("genie") }
    function closeMode() {
        if (!root.modeOpen || root.modeGrowing) return
        if (root.modeShown === "notes") root.quickNote.flush()
        root.modeOpen = false
        modeSettle.to = 0
        modeSettle.restart()
        root.forceActiveFocus()
    }
    function closeNotes() { root.closeMode() }
    // All notes and Expand grow the window as Apps does, and the
    // application's own window takes its place: in Spread through Kadunce's
    // launch, over an Active card once it has drawn, since Kadunce puts it in
    // the card's place.
    function growMode() {
        if (!root.modeOpen || root.modeGrowing) return
        const notes = root.modeShown === "notes"
        root.modeGrowing = true
        root.modeToken = Math.random().toString(36).slice(2) + Date.now().toString(36)
        root.launcherController.setDrawerExpanded(true)
        root.modeHandoff = root.launcherController.guestMode
            && (notes ? root.launcherController.beginGuestNotesLaunch()
                      : root.launcherController.beginGuestGenieLaunch())
        const opened = notes ? root.quickNote.openBoard(root.modeToken)
                             : root.genie.openWindow(root.modeToken)
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
        root.launcherController.setDrawerExpanded(false)
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
        } else if (root.drawerOpen && applicationGrid.count > 0) {
            const row = Math.max(0, applicationGrid.currentIndex)
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
        if (root.drawerOpen && !root.filesMode && !query.activeFocus && applicationGrid.count > 0) {
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
            root.modeOpen = false
            root.modeShown = ""
            root.modeProgress = 0
            root.modeGrowing = false
            root.modeHandoff = false
            root.modeToken = ""
            if (root.quickNote) root.quickNote.refresh()
            if (root.genie) root.genie.refresh()
            root.forceActiveFocus()
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
        // Meta+G or Meta+E: that drawer opens, or closes the launcher when it
        // is the drawer already open.
        function onDrawerRequested(mode) {
            const files = mode === "files"
            if (files && !root.fileBrowser) return
            if (root.drawerOpen && root.filesMode === files) root.launcherController.close()
            else root.setDrawerOpen(true, files ? "files" : "apps")
        }
        function onGuestLaunchReady() {
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
        readonly property real restHeight: root.launcherController.guestMode
            ? root.launcherController.guestHeight
            : root.launcherController.drawerExpanded
                ? Math.max(1, root.launcherController.availableArea.height - 20
                    - (root.launcherController.availableArea.y
                        + root.launcherController.availableArea.height < root.height - 1 ? 10 : 0))
                : Math.round(root.launcherController.availableArea.height * 0.64)
        // With the keys up the sheet rises only as far as it must, never
        // leaving the room Kadunce gave a guest, then shortens to fit.
        readonly property real keysLine: root.height - root.keysReach
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
                    : Math.round((root.launcherController.availableArea.height - height) / 2))))
        width: root.launcherController.guestMode
            ? root.launcherController.guestWidth
            : root.launcherController.drawerExpanded
                ? Math.max(1, root.launcherController.availableArea.width - 20)
                : Math.round(root.launcherController.availableArea.width * 0.64)
        height: Math.max(Math.min(restHeight, 160), Math.min(restHeight, keysLine - highest))
        Behavior on x { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        Behavior on y { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        // The keys' own easing already moves the sheet; chasing it would lag.
        Behavior on height { enabled: !keysMotion.running; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        radius: root.paperRadius
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

            Rectangle {
                id: searchField
                objectName: "search-field"
                // Nothing typed and nothing found: search rests in the middle.
                readonly property bool idle:
                    query.text.length === 0
                    && resultList.count === 0
                    && !root.searchResults.querying
                    && !root.applicationLaunchPending
                // Where search sits with the drawers shut: with the first
                // row under it, the two centred together, and as wide as the
                // row needs.
                readonly property real compactWidth: idle ? Math.min(parent.width,
                    Math.max(360, parent.width * 0.72, firstRow.naturalWidth)) : parent.width
                readonly property real compactY: idle ? Math.max(0, Math.round(
                    (parent.height - 58 - (firstRow.fits ? firstRow.reach : 0)) / 2)) : 0
                // An open drawer holds search in its header, between Back and
                // the sort button; it travels there as the drawer opens.
                width: compactWidth + (drawerHandle.fieldWidth - compactWidth) * root.drawerProgress
                height: 58 + (drawerHandle.openHeight - 58) * root.drawerProgress
                x: (parent.width - width) / 2
                y: Math.round(compactY * (1 - root.drawerProgress))
                radius: height / 2
                color: root.searchEngaged || query.text.length > 0
                    ? root.controlColor : "transparent"
                opacity: (root.applicationLaunchPending ? 0 : 1)
                    * Math.max(0, 1 - root.modeProgress * 2)
                enabled: !root.applicationLaunchPending && !root.modeOpen
                border.width: 0
                border.color: root.surfaceOutline

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (0.6 + 0.4 * root.openingControls)
                    height: parent.height
                    radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.surfaceOutline
                    opacity: root.openingControls
                }

                // The drawer's own motion carries search between its places;
                // these ease only changes made while a drawer is shut or open.
                Behavior on width {
                    enabled: root.drawerProgress <= 0 || root.drawerProgress >= 1
                    NumberAnimation { duration: root.ms(240); easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: root.drawerProgress <= 0 || root.drawerProgress >= 1
                    NumberAnimation { duration: root.ms(260); easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    // The notes pad grows out of the field; its own motion
                    // carries the fade.
                    enabled: root.modeProgress <= 0 || root.modeProgress >= 1
                    NumberAnimation { duration: root.ms(140); easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: root.ms(150); easing.type: Easing.OutCubic }
                }

                Item {
                    id: trailingAction
                    Accessible.role: Accessible.Button
                    Accessible.name: query.text.length > 0 ? words.i18n("Clear search") : words.i18n("Search")
                    Accessible.onPressAction: { root.searchEngaged = true; query.text = ""; query.forceActiveFocus() }
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    opacity: root.openingIcon

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: query.text.length > 0
                            ? "edit-clear-symbolic" : "system-search"
                        color: root.primaryText
                    }

                    TapHandler {
                        onTapped: {
                            root.searchEngaged = true
                            if (query.text.length > 0) {
                                query.text = ""
                            }
                            query.forceActiveFocus()
                            root.launcherController.showInputMethod()
                        }
                    }
                }

                TextInput {
                    id: query
                    objectName: "search-query"
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: trailingAction.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.primaryText
                    selectionColor: "#6da9ddff"
                    selectedTextColor: "#ffffffff"
                    font.pixelSize: 18
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText

                    onTextChanged: {
                        root.selectedChildKey = ""
                        root.childLaunchFailed = false
                        if (text.length > 0) {
                            root.searchEngaged = true
                        }
                        root.pendingLaunch = false
                        root.applicationCatalog.filterText = root.drawerOpen && !root.filesMode
                            ? text : ""
                        if (root.fileBrowser && root.filesMode) root.fileBrowser.filter = text
                        root.searchResults.queryString = root.drawerOpen
                            ? "" : text
                        resultList.currentIndex = resultList.count > 0 ? 0 : -1
                        resultList.settleAtBeginning()
                        applicationGrid.currentIndex =
                            applicationGrid.count > 0 ? 0 : -1
                        applicationGrid.keyChosen = false
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.searchEngaged = true
                        }
                    }

                    Keys.onPressed: event => {
                        if (root.drawerOpen && !root.filesMode && event.key === Qt.Key_Down
                                && applicationGrid.count > 0) {
                            applicationGrid.step(0, 1)
                            event.accepted = true
                        } else if (root.drawerOpen && !root.filesMode && event.key === Qt.Key_Up
                                   && applicationGrid.count > 0) {
                            applicationGrid.step(0, -1)
                            event.accepted = true
                        } else if (root.drawerOpen && root.filesMode && event.key === Qt.Key_Down
                                   && filesLoader.item) {
                            // From the filter into the files: the keys move there.
                            filesLoader.item.focusFiles()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down
                                   && resultList.count > 0) {
                            root.moveResultSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up
                                   && resultList.count > 0) {
                            root.moveResultSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return
                                   || event.key === Qt.Key_Enter) {
                            root.submit()
                            event.accepted = true
                        }
                    }

                    Text {
                        id: placeholder
                        objectName: "just-type-placeholder"
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: query.text.length === 0
                        text: words.i18n("Just type")
                        color: "#86ffffff"
                        font.pixelSize: 12
                        opacity: root.openingText
                        transform: Translate { y: (1 - root.openingText) * 3 }

                        // A single soft light pass, clipped to copies of the
                        // glyphs rather than a rectangle crossing the field.
                        Repeater {
                            model: 7
                            delegate: Item {
                                required property int index
                                x: root.openingShine * (placeholder.implicitWidth + 35)
                                    - 35 + index * 5
                                width: 5
                                height: placeholder.height
                                clip: true
                                visible: root.openingShine > 0 && root.openingShine < 1
                                opacity: [0.08, 0.18, 0.34, 0.5, 0.34, 0.18, 0.08][index]
                                Text {
                                    x: -parent.x
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    text: placeholder.text
                                    font: placeholder.font
                                    color: "#ffffff"
                                }
                            }
                        }
                    }
                }

                TapHandler {
                    enabled: !root.guestDragged
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        root.searchEngaged = true
                        query.forceActiveFocus()
                        root.launcherController.showInputMethod()
                    }
                }
            }

            // Before anything is typed: Apps, Files and, where Gooseberry is
            // installed, Notes; then what was used lately and is neither
            // pinned, open nor hidden, spaced evenly across the field's width.
            // A narrow sheet keeps the doors and as many of the rest as fit;
            // with none of the rest, the doors are centred.
            Item {
                id: firstRow
                objectName: "first-row"
                readonly property real gap: 18
                readonly property real pillGap: 10
                readonly property real tileWidth: 72
                readonly property int most: 6
                // The line between the doors and the rest, with its room.
                readonly property real divide: 25
                readonly property int offered: root.recentUse ? root.recentUse.count : 0
                readonly property real pillsWidth: appsPill.width
                    + (filesPill.visible ? pillGap + filesPill.width : 0)
                    + (notesPill.visible ? pillGap + notesPill.width : 0)
                    + (geniePill.visible ? pillGap + geniePill.width : 0)
                readonly property real naturalWidth: pillsWidth
                    + (offered > 0 ? divide + Math.min(offered, most) * tileWidth : 0)
                readonly property int shownCount: offered > 0 ? Math.max(0, Math.min(offered, most,
                    Math.floor((width - pillsWidth - divide) / tileWidth))) : 0
                readonly property real cellWidth: shownCount > 0
                    ? (width - pillsWidth - divide) / shownCount : 0
                readonly property real reach: gap + height
                readonly property bool fits: parent.height >= 58 + reach
                // The row arrives a piece at a time: each door in turn, left
                // to right, then what was used lately as one group. Typing
                // sends the row away whole, sinking a little, and clearing
                // the field brings it back the same way it first came.
                readonly property int doors: 1 + (filesPill.visible ? 1 : 0)
                    + (notesPill.visible ? 1 : 0) + (geniePill.visible ? 1 : 0)
                readonly property int step: 260
                readonly property int stagger: 45
                readonly property int span: step + doors * stagger
                // 1 while the first screen rests under the field.
                property real rest: 1
                // How far the arrival has come, across every piece.
                property real arrival: 1
                function reveal(order) {
                    if (root.reducedMotion) return arrival
                    const t = Math.max(0, Math.min(1, (arrival * span - order * stagger) / step))
                    return 1 - Math.pow(1 - t, 3)
                }
                function arrive(delay, again) {
                    leaving.stop()
                    // Caught on its way out, it comes straight back.
                    if (!again && rest > 0 && arrival >= 1) {
                        returning.restart()
                        return
                    }
                    arriving.stop()
                    returning.stop()
                    arrival = 0
                    rest = 1
                    arriving.delay = Math.max(1, delay)
                    arriving.start()
                }
                function leave() {
                    arriving.stop()
                    returning.stop()
                    leaving.restart()
                }
                SequentialAnimation {
                    id: arriving
                    property int delay: 1
                    PauseAnimation { duration: arriving.delay }
                    NumberAnimation {
                        target: firstRow
                        property: "arrival"
                        to: 1
                        duration: root.reducedMotion ? 120 : firstRow.span
                    }
                }
                NumberAnimation {
                    id: returning
                    target: firstRow
                    property: "rest"
                    to: 1
                    duration: root.own(140)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    id: leaving
                    target: firstRow
                    property: "rest"
                    to: 0
                    duration: root.reducedMotion ? 90 : 150
                    easing.type: Easing.InCubic
                }
                readonly property bool resting: searchField.idle
                onRestingChanged: resting ? arrive(1) : leave()
                x: (parent.width - width) / 2
                y: searchField.y + searchField.height + gap
                width: searchField.compactWidth
                height: 64
                opacity: fits && !root.applicationLaunchPending
                    ? rest * Math.max(0, 1 - root.drawerProgress * 3)
                        * Math.max(0, 1 - root.modeProgress * 3) : 0
                visible: opacity > 0
                enabled: resting && opacity > 0.5 && !root.drawerOpen && !root.modeOpen
                transform: Translate { y: root.reducedMotion ? 0 : (1 - firstRow.rest) * 6 }

                Row {
                    x: firstRow.shownCount > 0 ? 0 : (firstRow.width - firstRow.pillsWidth) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: firstRow.pillGap
                    FirstPill {
                        id: appsPill
                        reveal: firstRow.reveal(0)
                        objectName: "apps-pill"
                        label: words.i18n("Apps")
                        glyph: "apps"
                        onActivated: root.setDrawerOpen(true, "apps")
                    }
                    FirstPill {
                        id: filesPill
                        reveal: firstRow.reveal(1)
                        objectName: "files-pill"
                        label: words.i18n("Files")
                        glyph: "files"
                        visible: root.fileBrowser !== null
                        onActivated: root.setDrawerOpen(true, "files")
                    }
                    FirstPill {
                        id: notesPill
                        reveal: firstRow.reveal(1 + (filesPill.visible ? 1 : 0))
                        objectName: "notes-pill"
                        label: words.i18n("Notes")
                        glyph: "notes"
                        visible: root.notesDoor !== null && root.notesDoor.available
                        onActivated: root.openNotes()
                    }
                    FirstPill {
                        id: geniePill
                        reveal: firstRow.reveal(1 + (filesPill.visible ? 1 : 0) + (notesPill.visible ? 1 : 0))
                        objectName: "genie-pill"
                        label: words.i18n("Ask")
                        glyph: "genie"
                        visible: root.genie !== null && root.genie.available
                        onActivated: root.openGenie()
                    }
                }
                Rectangle {
                    visible: firstRow.shownCount > 0
                    opacity: firstRow.reveal(firstRow.doors)
                    x: firstRow.pillsWidth + Math.floor(firstRow.divide / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 36
                    color: "#2c2c2c"
                }
                Repeater {
                    model: root.recentUse
                    delegate: RecentTile {
                        id: recentTile
                        readonly property real reveal: firstRow.reveal(firstRow.doors)
                        x: firstRow.pillsWidth + firstRow.divide + index * firstRow.cellWidth
                        y: (firstRow.height - height) / 2
                        width: firstRow.cellWidth
                        visible: index < firstRow.shownCount
                        opacity: reveal
                        transform: Translate { y: root.reducedMotion ? 0 : (1 - recentTile.reveal) * 10 }
                    }
                }
            }

            Item {
                id: resultsArea
                y: searchField.y + searchField.height + 16
                width: parent.width
                height: parent.height - y
                opacity: root.applicationLaunchPending ? 0 : 1
                visible: query.text.length > 0 && !root.drawerOpen

                Row {
                    spacing: 20
                    Text {
                        objectName: "file-scope-toggle"
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        text: root.searchResults.allFiles ? words.i18n("All files ⇄") : words.i18n("Everyday search ⇄")
                        color: root.primaryText
                        font.pixelSize: 12
                        height: 34
                        verticalAlignment: Text.AlignVCenter
                        TapHandler {
                            onTapped: {
                                root.searchResults.allFiles = !root.searchResults.allFiles
                                root.selectedChildKey = ""
                                root.childLaunchFailed = false
                                resultList.currentIndex = resultList.count > 0 ? 0 : -1
                                resultList.settleAtBeginning()
                            }
                        }
                    }
                    Text {
                        objectName: "quiet-folders-button"
                        Accessible.role: Accessible.Button
                        Accessible.name: text
                        Accessible.onPressAction: { quietPaths.text = root.searchResults.quietFolders || ""; quietPopup.open() }
                        text: words.i18n("Quiet folders…")
                        color: root.secondaryText
                        font.pixelSize: 12
                        height: 34
                        verticalAlignment: Text.AlignVCenter
                        TapHandler { onTapped: { quietPaths.text = root.searchResults.quietFolders || ""; quietPopup.open() } }
                    }
                }

                QQC2.Popup {
                    id: quietPopup
                    width: Math.min(480, resultsArea.width)
                    height: 250
                    x: (resultsArea.width - width) / 2
                    y: 38
                    padding: 16
                    bottomMargin: root.keysReach
                    modal: true
                    background: Rectangle { color: root.surfaceColor; radius: root.paperRadius; border.color: root.surfaceOutline }
                    contentItem: Column {
                        spacing: 10
                        Text { text: words.i18n("Quiet folders"); color: root.primaryText; font.pixelSize: 16 }
                        Text {
                            text: words.i18n("One full folder path per line. All files includes these again.")
                            color: root.secondaryText
                            width: parent.width
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                        QQC2.ScrollView {
                            width: parent.width
                            height: 110
                            QQC2.TextArea { id: quietPaths; color: root.primaryText; wrapMode: TextEdit.NoWrap }
                        }
                        Row {
                            spacing: 16
                            QQC2.Button { text: words.i18n("Save"); onClicked: { root.searchResults.quietFolders = quietPaths.text; quietPopup.close() } }
                            QQC2.Button { text: words.i18n("Cancel"); onClicked: quietPopup.close() }
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic }
                }

                ListView {
                    id: resultList
                    objectName: "search-result-list"
                    anchors.fill: parent
                    anchors.topMargin: 38
                    clip: true
                    spacing: 6
                    currentIndex: count > 0 ? 0 : -1
                    model: root.searchResults
                    // Model insertions and changing child heights can preserve
                    // an old scroll offset even when the first row is selected.
                    // Let layout settle before aligning a fresh search to its
                    // actual origin; never reset a user's lower selection.
                    function settleAtBeginning() {
                        Qt.callLater(function() {
                            if (resultList.currentIndex <= 0 && !root.searchResults.selectionPinned()) {
                                resultList.forceLayout()
                                resultList.positionViewAtBeginning()
                            }
                        })
                    }
                    onCountChanged: settleAtBeginning()
                    onHeightChanged: settleAtBeginning()

                    Connections {
                        target: root.searchResults
                        function onQueryingChanged() {
                            if (!root.searchResults.querying) resultList.settleAtBeginning()
                        }
                        function onSelectionChanged() {
                            if (root.searchResults.selectionPinned())
                                resultList.currentIndex = root.searchResults.selectedRow()
                        }
                    }

                    delegate: Rectangle {
                        id: resultDelegate
                        objectName: "result-" + index
                        Accessible.role: Accessible.ListItem
                        Accessible.name: model.display || ""
                        Accessible.description: model.subtext || ""
                        Accessible.selected: ListView.isCurrentItem
                        Accessible.onPressAction: root.runResult(index)
                        required property int index
                        required property var model
                        readonly property var connectedDevices: {
                            const revision = root.launcherController.relatedRevision
                            return root.launcherController.relatedItems(index)
                        }
                        readonly property bool alreadyOpen:
                            root.launcherController.contextAvailable
                            && root.launcherController.resultIsOpen(index)

                        width: resultList.width
                        height: 62 + deviceChildren.height
                        radius: root.paperRadius
                        color: "transparent"
                        Rectangle {
                            objectName: "parent-highlight-" + resultDelegate.index
                            width: parent.width; height: 62; radius: root.paperRadius
                            color: resultDelegate.ListView.isCurrentItem && root.selectedChildKey === ""
                                ? "#3dffffff" : (hover.hovered ? "#22ffffff" : "transparent")
                        }

                        Row {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 62
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 14

                            Kirigami.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                source: resultDelegate.model.decoration
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 46
                                spacing: 3

                                Row {
                                    width: parent.width
                                    spacing: 9

                                    Text {
                                        width: Math.min(implicitWidth,
                                            parent.width - openLabel.width
                                            - parent.spacing)
                                        text: resultDelegate.model.display
                                        color: root.primaryText
                                        font.pixelSize: 16
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: openLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: words.i18n("OPEN")
                                        visible: resultDelegate.alreadyOpen
                                        color: "#ff71e6be"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: resultDelegate.model.subtext
                                        || resultDelegate.model.category || words.i18n("Result")
                                    color: root.secondaryText
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Column {
                            id: deviceChildren
                            x: 60
                            y: 62
                            width: parent.width - x - 14
                            spacing: 4
                            Repeater {
                                model: resultDelegate.connectedDevices
                                delegate: Rectangle {
                                    id: childRow
                                    required property var modelData
                                    required property int index
                                    objectName: "child-" + resultDelegate.index + "-" + index
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.status ? words.i18nc("a setting, then its state", "%1 · %2", modelData.label, modelData.status) : modelData.label
                                    width: deviceChildren.width
                                    height: 40
                                    radius: height / 2
                                    color: resultDelegate.ListView.isCurrentItem && root.selectedChildKey === root.childKey(modelData)
                                        ? "#3dffffff" : (childHover.hovered ? "#22ffffff" : "transparent")
                                    Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 2.5; color: root.secondaryText }
                                    Text {
                                        x: 27; width: parent.width - x - 12; height: parent.height
                                        text: root.childLaunchFailed && root.selectedChildKey === root.childKey(childRow.modelData)
                                            ? words.i18nc("a setting, then why it did not open", "%1 · Couldn't open settings—try again", childRow.modelData.label)
                                            : childRow.modelData.status ? words.i18nc("a setting, then its state", "%1 · %2", childRow.modelData.label, childRow.modelData.status)
                                            : childRow.modelData.label
                                        font.pixelSize: 12; color: root.secondaryText
                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    }
                                    HoverHandler { id: childHover }
                                    TapHandler {
                                        enabled: !root.guestDragged && !root.applicationLaunchPending
                                        onPressedChanged: if (pressed) {
                                            resultList.currentIndex = resultDelegate.index
                                            root.searchResults.pinSelection(resultDelegate.index)
                                            root.selectedChildKey = root.childKey(childRow.modelData)
                                        }
                                        onTapped: root.openChildSettings()
                                    }
                                }
                            }
                        }
                        Item {
                        width: parent.width
                        height: 62
                        HoverHandler { id: hover }
                        TapHandler {
                            enabled: !root.guestDragged
                                && !root.applicationLaunchPending
                            onPressedChanged: {
                                if (pressed) {
                                    root.selectedChildKey = ""
                                    resultList.currentIndex = resultDelegate.index
                                    root.searchResults.pinSelection(resultDelegate.index)
                                }
                            }
                            onTapped: {
                                root.runResult(root.searchResults.selectedRow())
                            }
                        }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: query.text.length > 0
                        && !root.searchResults.querying
                        && resultList.count === 0
                    objectName: "web-fallback"
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    Accessible.onPressAction: root.submit()
                    text: words.i18n("Search the web for “%1”", query.text)
                    color: root.secondaryText
                    font.pixelSize: 15
                    width: parent.width - 28
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    TapHandler { onTapped: root.submit() }
                }
            }

            Item {
                id: drawerHandle
                objectName: "drawer-header"
                readonly property real sectionGap: 16
                readonly property real openHeight: 44
                // Search, in the open header, keeps to the middle: centred,
                // and as clear of Back as of the sort button.
                readonly property real fieldSide: Math.max(backButton.x + backButton.width,
                    width - hiddenButton.x) + 12
                readonly property real fieldWidth: Math.max(160,
                    Math.min(width - 2 * fieldSide, Math.max(360, width / 2)))
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

                // Back returns to search. The suite's grey pill, 30 high in
                // its 42 touch, mirrors the sort button across the header.
                Item {
                    id: backButton
                    objectName: "drawer-back"
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: backLabel.x + backLabel.implicitWidth + 14
                    height: 42
                    opacity: Math.max(0, (root.drawerProgress - 0.65) / 0.35)
                    enabled: root.drawerOpen && opacity > 0.9
                    Accessible.role: Accessible.Button
                    Accessible.name: backLabel.text
                    Accessible.onPressAction: root.setDrawerOpen(false)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 30
                        radius: height / 2
                        color: backTap.pressed ? "#4A4A4A"
                            : backHover.hovered ? "#333333" : root.controlColor
                        Behavior on color { ColorAnimation { duration: root.ms(90) } }
                        SuiteIcon {
                            glyph: "chevron-left"
                            width: 14; height: 14
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: backLabel
                            x: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: words.i18n("Back")
                            color: root.primaryText
                            font.pixelSize: 13
                        }
                    }
                    HoverHandler {
                        id: backHover
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                        cursorShape: Qt.PointingHandCursor
                    }
                    // A tap, so a pull that starts on Back still closes the
                    // drawer by its edge.
                    TapHandler { id: backTap; onTapped: root.setDrawerOpen(false) }
                }

                // The eye shows what is hidden: hidden applications in Browse
                // everything, hidden files in Files. Again, it hides them.
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
                    anchors.right: sortButton.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: sortButton.verticalCenter
                    width: 42
                    height: 42
                    opacity: sortButton.opacity
                    enabled: sortButton.enabled
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
                        color: hiddenPress.pressed ? "#4A4A4A"
                            : hiddenButton.showing ? "#333333"
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

                Item {
                id: sortButton
                    objectName: "sort-button"
                    Accessible.role: Accessible.ButtonMenu
                    Accessible.name: root.filesMode ? words.i18n("Sort: %1", sortLabel.text) : words.i18n("Sort")
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    // In Files the order is a grey pill naming it, as the
                    // suite's header controls are.
                    width: root.filesMode ? Math.max(42, sortLabel.implicitWidth + 46) : 42
                    height: 42
                    opacity: Math.max(0, (root.drawerProgress - 0.72) / 0.28)
                    enabled: root.drawerOpen && opacity > 0.9

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        visible: !root.filesMode
                        width: 20
                        height: 20
                        source: root.applicationCatalog.descending
                            ? "view-sort-descending-symbolic"
                            : "view-sort-ascending-symbolic"
                        color: root.primaryText
                    }

                    Rectangle {
                        visible: root.filesMode
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 30
                        radius: height / 2
                        color: sortPress.pressed || fileSort.visible ? "#4A4A4A"
                            : sortHover.hovered ? "#333333" : root.controlColor
                        Behavior on color { ColorAnimation { duration: root.ms(90) } }
                        Text {
                            id: sortLabel
                            anchors.verticalCenter: parent.verticalCenter
                            x: 14
                            text: sortButton.fileOrderFixed ? words.i18n("Recent") : [words.i18n("Name A–Z"), words.i18n("Name Z–A"), words.i18n("Newest"), words.i18n("Largest")][root.fileBrowser ? root.fileBrowser.sortMode : 0]
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
                        onClicked: {
                            if (root.filesMode) fileSort.openUnder(sortButton)
                            else root.sortMenuOpen = !root.sortMenuOpen
                        }
                    }
                    // Recent keeps the order of use.
                    readonly property bool fileOrderFixed: !!root.fileBrowser && root.fileBrowser.placeKind === "recent"
                    // Files' order, kept inside the sheet under the button.
                    SheetMenu {
                        id: fileSort
                        objectName: "files-sort-menu"
                        bounds: sheet
                        bottomMargin: root.keysReach
                        keysReach: root.keysReach
                        readonly property int mode: root.fileBrowser ? root.fileBrowser.sortMode : 0
                        SheetMenuItem { text: words.i18n("Name A–Z"); checkable: true; checked: fileSort.mode === 0; enabled: !sortButton.fileOrderFixed; onTriggered: root.fileBrowser.sortMode=0 }
                        SheetMenuItem { text: words.i18n("Name Z–A"); checkable: true; checked: fileSort.mode === 1; enabled: !sortButton.fileOrderFixed; onTriggered: root.fileBrowser.sortMode=1 }
                        SheetMenuItem { text: words.i18n("Newest first"); checkable: true; checked: fileSort.mode === 2; enabled: !sortButton.fileOrderFixed; onTriggered: root.fileBrowser.sortMode=2 }
                        SheetMenuItem { text: words.i18n("Largest first"); checkable: true; checked: fileSort.mode === 3; enabled: !sortButton.fileOrderFixed; onTriggered: root.fileBrowser.sortMode=3 }
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
                surfaceColor: root.surfaceColor
                surfaceOutline: root.surfaceOutline
                controlColor: root.controlColor
                primaryText: root.primaryText
                onBack: root.closeNotes()
                onGrow: root.growNotes()
                onFinished: root.launcherController.close()
            }

            GeniePane {
                id: geniePane
                objectName: "genie-pane"
                anchors.fill: parent
                z: 5
                genie: root.genie
                progress: root.genieProgress
                fieldRest: Qt.rect(searchField.x, searchField.y, searchField.width, searchField.height)
                growing: root.modeGrowing
                keysUp: root.keysUp
                surfaceColor: root.surfaceColor
                surfaceOutline: root.surfaceOutline
                controlColor: root.controlColor
                primaryText: root.primaryText
                onBack: root.closeMode()
                onGrow: root.growMode()
            }

            Loader {
                id: filesLoader
                active: false
                asynchronous: true
                sourceComponent: FilesPane {
                    objectName: "files-pane"
                    browser: root.fileBrowser
                    compact: root.keysUp
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
                transform: Translate { y: -20*(1-root.drawerProgress) }
            }
            GridView {
                id: applicationGrid
                objectName: "application-grid"
                x: 0
                y: searchField.y + searchField.height + drawerHandle.sectionGap
                width: parent.width
                height: Math.max(0, parent.height - y)
                clip: true
                opacity: root.drawerProgress
                visible: !root.filesMode && root.drawerProgress > 0.01
                    && !root.applicationLaunchPending
                model: root.applicationCatalog
                cellWidth: width / Math.max(3,
                    Math.min(6, Math.floor(width / 126)))
                cellHeight: root.launcherController.drawerExpanded ? 112 : 94
                boundsBehavior: Flickable.StopAtBounds
                z: 3
                // The arrow keys have chosen an application, which Enter
                // opens: it shows, and stays in view.
                property bool keyChosen: false
                function choose(index) {
                    currentIndex = index
                    keyChosen = true
                    positionViewAtIndex(index, GridView.Contain)
                }
                // The first press shows the application Enter would open;
                // each one after moves the choice, Left and Right by one,
                // Up and Down by a row.
                function step(across, down) {
                    const from = Math.max(0, currentIndex)
                    const columns = Math.max(1, Math.floor(width / cellWidth))
                    const to = from + across + (down || 0) * columns
                    choose(keyChosen ? Math.max(0, Math.min(count - 1, to)) : from)
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: root.ms(180)
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: catalogDelegate
                    objectName: "application-tile-" + index
                    Accessible.role: Accessible.Button
                    Accessible.name: model.name
                    Accessible.focused: chosen
                    Accessible.onPressAction: root.runCatalogApplication(index, model.name)
                    required property int index
                    required property var model
                    readonly property bool chosen: applicationGrid.keyChosen
                        && applicationGrid.currentIndex === index
                    width: applicationGrid.cellWidth
                    height: applicationGrid.cellHeight

                    Rectangle {
                        id: catalogTile
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: root.paperRadius
                        color: catalogHover.hovered || catalogDelegate.chosen
                            ? "#20ffffff" : "transparent"
                        // A hidden application, shown by the eye, is dimmed.
                        opacity: catalogDelegate.model.hidden ? 0.45 : 1
                        // The chosen application rises, as a touched one does.
                        scale: catalogDelegate.chosen ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: root.ms(120) } }

                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            width: root.launcherController.drawerExpanded ? 52 : 42
                            height: width
                            source: catalogDelegate.model.icon
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.bottomMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            text: catalogDelegate.model.name
                            color: root.primaryText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        HoverHandler { id: catalogHover }
                        TapHandler {
                            enabled: !root.guestDragged
                                && !root.applicationLaunchPending
                            longPressThreshold: 0.5
                            onTapped: root.runCatalogApplication(
                                catalogDelegate.index,
                                catalogDelegate.model.name)
                            onLongPressed: root.showApplicationSheet(
                                catalogDelegate.index, catalogTile, point.position)
                        }
                        TapHandler {
                            enabled: !root.applicationLaunchPending
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => root.showApplicationSheet(
                                catalogDelegate.index, catalogTile, eventPoint.position)
                        }
                    }
                }
            }

            // An application's sheet: its own actions, then Hide or Unhide,
            // and Uninstall where the software centre can show it.
            SheetMenu {
                id: applicationSheet
                objectName: "application-sheet"
                bounds: sheet
                bottomMargin: root.keysReach
                keysReach: root.keysReach
                property int row: -1
                property var actions: []
                property bool hidden: false
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
                    objectName: "application-sheet-hide"
                    text: applicationSheet.hidden ? words.i18n("Unhide") : words.i18n("Hide")
                    onTriggered: root.applicationCatalog.setHidden(applicationSheet.row, !applicationSheet.hidden)
                }
                SheetMenuItem {
                    objectName: "application-sheet-uninstall"
                    text: words.i18n("Uninstall…")
                    visible: root.applicationCatalog.softwareReady
                        && root.applicationCatalog.canUninstall(applicationSheet.row)
                    onTriggered: {
                        if (root.applicationCatalog.uninstall(applicationSheet.row))
                            root.launcherController.finishLaunch()
                    }
                }
            }

            Text {
                anchors.centerIn: applicationGrid
                visible: root.drawerOpen && !root.filesMode && query.text.length > 0
                    && applicationGrid.count === 0
                text: words.i18n("No applications found")
                color: root.secondaryText
                font.pixelSize: 15
                z: 4
            }

            Rectangle {
                id: sortMenu
                objectName: "sort-menu"
                anchors.right: parent.right
                y: drawerHandle.y + drawerHandle.height + 4
                width: 132
                height: 92
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
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    Repeater {
                        model: [
                            { "label": words.i18n("A to Z"), "descending": false },
                            { "label": words.i18n("Z to A"), "descending": true }
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
                            readonly property bool selected: root.applicationCatalog.descending
                                === sortChoice.modelData.descending
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
                                    root.applicationCatalog.descending =
                                        sortChoice.modelData.descending
                                    applicationGrid.currentIndex =
                                        applicationGrid.count > 0 ? 0 : -1
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
                    color: "#24ffffff"

                    Rectangle {
                        id: launchProgress
                        width: 28
                        height: parent.height
                        radius: height / 2
                        color: "#d9ffffff"

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
    Connections {
        target: root.genie
        ignoreUnknownSignals: true
        function onWindowShown(requestToken) { root.modeWindowShown(requestToken) }
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
