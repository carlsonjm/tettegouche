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
                // A shadow is dark on any ground.
                color: Qt.rgba(0, 0, 0, modelData.alpha)
            }
        }
    }

    // One of Search's modes along its top, Apps, Files or Notes: its glyph
    // and its word on a pill, filled behind the one shown.
    component FirstPill: Item {
        id: pill
        property string label
        // Whether its mode is the one shown.
        property bool selected: false
        // How far it has arrived, 0 to 1.
        property real reveal: 1
        signal activated()
        width: pillLabel.implicitWidth + 28
        height: 44
        opacity: reveal
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checkable: true
        Accessible.checked: selected
        Keys.onReturnPressed: pill.activated()
        Keys.onEnterPressed: pill.activated()
        Keys.onSpacePressed: pill.activated()
        Rectangle {
            id: pillFace
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 40
            radius: height / 2
            color: pillTap.pressed ? tone.doorPressed
                : pill.selected ? tone.current
                : pillHover.hovered ? tone.doorHover : "transparent"
            scale: pillTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.ms(90) } }
            Text {
                id: pillLabel
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.selected ? root.primaryText : root.secondaryText
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: root.ms(90) } }
            }
        }
        // Keyboard focus alone gets an outline.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width + 6
            height: pillFace.height + 6
            x: -3
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: tone.focusRing
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

    // An application used lately: its icon, large, and its whole name on up
    // to two lines.
    component RecentApp: Item {
        id: tile
        required property int index
        required property var model
        readonly property bool mine: tile.model.kind === "application"
        objectName: mine ? "recent-" + index : ""
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: tile.model.name
        Keys.onReturnPressed: root.runRecent(tile.index, tile.model.name)
        Keys.onEnterPressed: root.runRecent(tile.index, tile.model.name)
        Keys.onSpacePressed: root.runRecent(tile.index, tile.model.name)
        Rectangle {
            id: tileFace
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: root.paperRadius
            color: tileTap.pressed ? tone.tilePressed : tileHover.hovered ? tone.tileHover : "transparent"
            scale: tileTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.ms(120) } }
            LiftShadow { lifted: tileTap.pressed }
            Kirigami.Icon {
                x: (parent.width - 56) / 2
                y: 12
                width: 56
                height: 56
                source: tile.model.icon
            }
            Text {
                x: 6
                y: 12 + 56 + 8
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
                text: tile.model.name
                color: root.primaryText
                font.pixelSize: 13
            }
        }
        Rectangle {
            anchors.fill: tileFace
            anchors.margins: -2
            radius: root.paperRadius + 2
            color: "transparent"
            border.width: 1.5
            border.color: tone.focusRing
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

    // A file used lately, as a card of paper: its picture, or its kind's icon
    // where it has none, its name, and the folder it is in with when.
    component RecentFile: Item {
        id: card
        required property int index
        required property var model
        readonly property bool mine: card.model.kind === "file"
        readonly property bool pictured: (card.model.thumbnail || "").length > 0
        objectName: mine ? "recent-" + index : ""
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: card.model.name
        Keys.onReturnPressed: root.runRecent(card.index, card.model.name)
        Keys.onEnterPressed: root.runRecent(card.index, card.model.name)
        Keys.onSpacePressed: root.runRecent(card.index, card.model.name)
        Rectangle {
            id: cardFace
            anchors.fill: parent
            radius: root.paperRadius
            color: cardTap.pressed ? tone.tilePressed : cardHover.hovered ? tone.tileHover : tone.subtle
            scale: cardTap.pressed ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.ms(120) } }
            LiftShadow { lifted: cardTap.pressed }
            Rectangle {
                id: preview
                x: 8
                y: 8
                width: parent.width - 16
                height: Math.max(24, parent.height - 8 - 50)
                radius: 6
                color: tone.subtle
                clip: true
                Image {
                    anchors.fill: parent
                    visible: card.pictured
                    source: card.pictured ? card.model.thumbnail : ""
                    sourceSize: Qt.size(Math.ceil(preview.width * 2), Math.ceil(preview.height * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: !card.pictured
                    width: Math.min(48, preview.height - 16)
                    height: width
                    source: card.model.icon
                }
            }
            Text {
                id: cardName
                x: 12
                y: preview.y + preview.height + 8
                width: parent.width - 24
                elide: Text.ElideMiddle
                text: card.model.name
                color: root.primaryText
                font.pixelSize: 15
            }
            Text {
                x: 12
                y: cardName.y + cardName.height + 2
                width: parent.width - 24
                elide: Text.ElideRight
                text: root.usedWhere(card.model.where || "", card.model.when)
                color: root.secondaryText
                font.pixelSize: 12
            }
        }
        Rectangle {
            anchors.fill: cardFace
            anchors.margins: -2
            radius: root.paperRadius + 2
            color: "transparent"
            border.width: 1.5
            border.color: tone.focusRing
            visible: card.activeFocus
        }
        HoverHandler {
            id: cardHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: cardTap
            enabled: !root.guestDragged && !root.applicationLaunchPending
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.runRecent(card.index, card.model.name)
        }
    }

    // A section's heading on the first screen, and See all at its end, which
    // opens the mode that holds everything of its kind.
    component SectionHead: Item {
        id: head
        property string title
        property string prefix
        property bool seeAllShown: true
        signal seeAll()
        height: 40
        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: root.secondaryText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Item {
            objectName: head.prefix + "-see-all"
            anchors.right: parent.right
            width: seeAllRow.implicitWidth + 24
            height: 40
            visible: head.seeAllShown
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: words.i18nc("opens everything of a recent section's kind", "See all %1", head.title)
            Accessible.onPressAction: head.seeAll()
            Keys.onReturnPressed: head.seeAll()
            Keys.onEnterPressed: head.seeAll()
            Keys.onSpacePressed: head.seeAll()
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 32
                radius: height / 2
                color: seeAllTap.pressed ? tone.doorPressed : seeAllHover.hovered ? tone.doorHover : "transparent"
                border.width: parent.activeFocus ? 1.5 : 0
                border.color: tone.focusRing
                Behavior on color { ColorAnimation { duration: root.ms(120) } }
            }
            Row {
                id: seeAllRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: words.i18n("See all")
                    color: root.secondaryText
                    font.pixelSize: 13
                }
                SuiteIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "chevron-right"
                    width: 14
                    height: 14
                    opacity: 0.66
                }
            }
            HoverHandler {
                id: seeAllHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: seeAllTap
                enabled: !root.guestDragged
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: head.seeAll()
            }
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
        // Files windows of their own stay as they are; Files opens here too.
        if (open) root.filesMode = mode === "files"
        root.guestDrag = 0
        // Every drawer opens at Search's own size, a card in Spread; Expand
        // fills the screen. Moving between drawers keeps the size chosen.
        const wasOpen = root.drawerOpen
        root.drawerOpen = open
        if (!open || !wasOpen) root.launcherController.setDrawerExpanded(false)
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
                applicationLines.positionViewAtIndex(applicationGrid.lineOf[row], ListView.Contain)
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
    // window keeps its size: Notes turns the field into the note pad.
    function openMode(name) {
        const client = name === "notes" ? root.quickNote : null
        if (!client || !client.available || root.modeGrowing) return false
        client.start()
        root.modeShown = name
        root.modeOpen = true
        root.sortMenuOpen = false
        modeSettle.to = 1
        modeSettle.restart()
        notesPane.focusPad()
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
    // Notes asked for from outside Search, as the dot's slide asks: it opens,
    // or Search closes when it is the mode already open. Search may have only
    // just opened, before Notes has answered whether it is there; the mode
    // then waits for the answer, and falls back to its own sheet if
    // Gooseberry's interface never answers.
    function openModeDirectly(name) {
        modeWait.stop()
        root.modeAwaited = ""
        if (root.modeOpen && root.modeShown === name) {
            root.launcherController.close()
            return
        }
        if (root.drawerOpen) root.setDrawerOpen(false)
        if (root.modeOpen) return
        if (name !== "notes" || !root.notesDoor) return
        const client = root.quickNote
        if (client && client.available) {
            root.openNotes()
            return
        }
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
        root.openNotes()
    }
    property string modeAwaited: ""
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
    function closeMode() {
        if (!root.modeOpen || root.modeGrowing) return
        if (root.modeShown === "notes") root.quickNote.flush()
        root.modeOpen = false
        // Search goes back to the size it had before Expand.
        if (root.launcherController.drawerExpanded) root.launcherController.setDrawerExpanded(false)
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
        // as the screen allows. Typing, a drawer or a mode gives it at least
        // its working height, growing down from where it rested.
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
                    : Math.max(0, Math.min(Math.round((root.launcherController.availableArea.height - restingHeight) / 2),
                        root.launcherController.availableArea.height - height - 10)))))
        width: root.launcherController.guestMode
            ? root.launcherController.guestWidth
            : root.launcherController.drawerExpanded
                ? Math.max(1, root.launcherController.availableArea.width - 20)
                : Math.min(small ? smallWidth : universalWidth, root.launcherController.availableArea.width - 40)
        height: Math.max(Math.min(restHeight, 160), Math.min(restHeight, keysLine - highest))
        Behavior on x { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        Behavior on y { enabled: root.launcherController.guestMode; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
        // The keys' own easing already moves the sheet; chasing it would lag.
        Behavior on height { enabled: !keysMotion.running; NumberAnimation { duration: root.ms(220); easing.type: Easing.OutCubic } }
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

            Rectangle {
                id: searchField
                objectName: "search-field"
                // Nothing typed and nothing found: the first screen.
                readonly property bool idle:
                    query.text.length === 0
                    && resultList.count === 0
                    && !root.searchResults.querying
                    && !root.applicationLaunchPending
                // Lit while it holds the keys or what was typed.
                readonly property bool lit: query.activeFocus || query.text.length > 0
                // One field, in one place, on every screen: under the modes,
                // on the same edges as they are, 44 tall. Only what is under
                // it changes. In a room
                // taller than it needs, with nothing under it, it rests in
                // the middle, and rises as a drawer or a mode opens.
                readonly property real restY: idle && !firstRow.fits
                    ? Math.max(0, Math.round((parent.height - height) / 2)) : 0
                x: Math.round((parent.width - width) / 2)
                y: Math.round(restY * (1 - root.drawerProgress) * (1 - root.modeProgress))
                Behavior on y {
                    enabled: (root.drawerProgress <= 0 || root.drawerProgress >= 1)
                        && (root.modeProgress <= 0 || root.modeProgress >= 1)
                    NumberAnimation { duration: root.ms(260); easing.type: Easing.OutCubic }
                }
                width: parent.width
                height: root.fieldHeight
                radius: height / 2
                color: root.controlColor
                opacity: (root.applicationLaunchPending ? 0 : 1)
                    * Math.max(0, 1 - root.modeProgress * 2)
                    * root.openingControls
                enabled: !root.applicationLaunchPending && !root.modeOpen

                // A hairline of light along its upper edge, as on a raised
                // key, and a ring that comes up while it holds the keys.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: tone.dark ? "#14ffffff" : "#0d000000"
                    opacity: searchField.lit ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: root.ms(150) } }
                }
                Rectangle {
                    objectName: "search-ring"
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: height / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.rgba(tone.focusRing.r, tone.focusRing.g, tone.focusRing.b, 0.16)
                    opacity: searchField.lit ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: root.ms(150) } }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(tone.focusRing.r, tone.focusRing.g, tone.focusRing.b, 0.55)
                    }
                }

                Behavior on opacity {
                    // The notes pad grows out of the field; its own motion
                    // carries the fade.
                    enabled: root.modeProgress <= 0 || root.modeProgress >= 1
                    NumberAnimation { duration: root.ms(140); easing.type: Easing.OutCubic }
                }

                SuiteIcon {
                    id: searchGlyph
                    glyph: "search"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    opacity: (searchField.lit ? 0.9 : 0.55) * root.openingIcon
                    Behavior on opacity { NumberAnimation { duration: root.ms(150) } }
                }

                // Clears what was typed; with nothing typed, a hint of what
                // Enter does takes its place.
                Item {
                    id: trailingAction
                    objectName: "search-clear"
                    Accessible.role: Accessible.Button
                    Accessible.name: words.i18n("Clear search")
                    Accessible.onPressAction: { root.searchEngaged = true; query.text = ""; query.forceActiveFocus() }
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    visible: query.text.length > 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: clearHover.hovered ? tone.controlHover : "transparent"
                    }
                    SuiteIcon {
                        anchors.centerIn: parent
                        glyph: "x"
                        width: 18
                        height: 18
                    }
                    HoverHandler {
                        id: clearHover
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                    }
                    TapHandler {
                        onTapped: {
                            root.searchEngaged = true
                            query.text = ""
                            query.forceActiveFocus()
                            root.launcherController.showInputMethod()
                        }
                    }
                }

                TextInput {
                    id: query
                    objectName: "search-query"
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    // Clear, and an open drawer's eye, sit at its end.
                    anchors.rightMargin: 20 + (trailingAction.visible ? 36 : 0) + 42 * root.drawerProgress
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.primaryText
                    selectionColor: tone.selection
                    selectedTextColor: tone.selectedText
                    font.pixelSize: 16
                    font.weight: Font.Medium
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
                        applicationGrid.reset()
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.searchEngaged = true
                        }
                    }

                    Keys.onPressed: event => {
                        if (root.drawerOpen && !root.filesMode && event.key === Qt.Key_Down
                                && applicationGrid.choices.length > 0) {
                            applicationGrid.step(0, 1)
                            event.accepted = true
                        } else if (root.drawerOpen && !root.filesMode && event.key === Qt.Key_Up
                                   && applicationGrid.choices.length > 0) {
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
                        text: root.drawerOpen
                            ? (root.filesMode ? words.i18n("Find in Files") : words.i18n("Find an app"))
                            : words.i18n("Just type")
                        color: tone.placeholderText
                        font.pixelSize: 15
                        font.weight: Font.Medium
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
                                    color: tone.shine
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

            // Search's modes along its top, on every screen, as one row: the
            // dot for Search's first screen, then Apps, Files and, where
            // Gooseberry is installed, Notes. The grey pill marks the one
            // shown, the dot while none is, and a tap moves between them. The
            // field and whatever the mode shows sit below it.
            Item {
                id: modeRow
                objectName: "mode-row"
                // The mode shown: "apps", "files", "notes", or "" on the
                // first screen.
                readonly property string current: root.notesOpen ? "notes"
                    : root.drawerOpen ? (root.filesMode ? "files" : "apps") : ""
                readonly property real pillGap: 4
                function show(mode) {
                    if (mode === current) return
                    if (mode === "") {
                        root.goBack()
                        return
                    }
                    if (mode === "notes") {
                        if (root.drawerOpen) root.setDrawerOpen(false)
                        root.openNotes()
                        return
                    }
                    if (root.modeOpen) root.closeMode()
                    root.setDrawerOpen(true, mode)
                }
                // The dot's pill starts on the field's left edge.
                x: -2
                y: -root.modeRowReach - 2
                width: parent.width + 2
                height: 44
                opacity: root.applicationLaunchPending || !root.modeRowShown ? 0 : root.openingControls
                visible: opacity > 0
                enabled: opacity > 0.5 && !root.modeGrowing && !root.choosingFolder
                transform: Translate { y: (1 - root.openingControls) * 6 }
                z: 6

                Row {
                    spacing: modeRow.pillGap
                    // The dot: Search's first screen, from any mode.
                    Item {
                        id: homeDot
                        objectName: "home-dot"
                        readonly property bool selected: modeRow.current === ""
                        width: 44
                        height: 44
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: words.i18n("Search")
                        Accessible.checkable: true
                        Accessible.checked: selected
                        Accessible.onPressAction: modeRow.show("")
                        Keys.onReturnPressed: modeRow.show("")
                        Keys.onEnterPressed: modeRow.show("")
                        Keys.onSpacePressed: modeRow.show("")
                        // A pill like the modes', filled when chosen, around
                        // a small dot.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            radius: width / 2
                            color: homeTap.pressed ? tone.doorPressed
                                : homeDot.selected ? tone.current
                                : homeHover.hovered ? tone.doorHover : "transparent"
                            Behavior on color { ColorAnimation { duration: root.ms(90) } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: width / 2
                            color: root.primaryText
                            opacity: homeDot.selected || homeHover.hovered ? 1 : 0.6
                            scale: homeTap.pressed ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: root.ms(90) } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 46
                            height: 46
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: tone.focusRing
                            visible: homeDot.activeFocus
                        }
                        HoverHandler {
                            id: homeHover
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: homeTap
                            enabled: !root.guestDragged
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: modeRow.show("")
                        }
                    }
                    FirstPill {
                        id: appsPill
                        objectName: "apps-pill"
                        label: words.i18n("Apps")
                        selected: modeRow.current === "apps"
                        onActivated: modeRow.show("apps")
                    }
                    FirstPill {
                        id: filesPill
                        objectName: "files-pill"
                        label: words.i18n("Files")
                        selected: modeRow.current === "files"
                        visible: root.fileBrowser !== null
                        onActivated: modeRow.show("files")
                    }
                    FirstPill {
                        id: notesPill
                        objectName: "notes-pill"
                        label: words.i18n("Notes")
                        selected: modeRow.current === "notes"
                        visible: root.notesPillShown && !!root.notesDoor && root.notesDoor.available
                        onActivated: modeRow.show("notes")
                    }
                }

                // The window's own buttons share the row, at its other end:
                // Expand while a drawer is open, Pop out where Files has a
                // window of its own, and Close, last, as a window's is. Notes
                // keeps its own, in its header.
                WindowActions {
                    id: windowActions
                    prefix: "window"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: Math.max(0, 1 - root.modeProgress * 2)
                    enabled: !root.modeOpen
                    visible: opacity > 0
                    expanded: root.launcherController.drawerExpanded
                    expandShown: root.drawerOpen
                    popOutShown: root.drawerOpen && root.filesMode && root.filesWindowOffered
                    popOutName: words.i18n("Open Files in its own window")
                    onExpand: root.toggleExpanded()
                    onPopOut: root.popOutFiles()
                    onDismiss: root.launcherController.close()
                }
            }

            // Before anything is typed, under the field: the applications and
            // the files used lately, each in a labelled section of its own,
            // eight of each, and none pinned, open or hidden. Each section has
            // its setting, and what is on sets how tall Search rests: the
            // field alone, one section, or both filling the sheet.
            Item {
                id: firstRow
                objectName: "first-row"
                readonly property bool appsShown: root.recentApps && !!root.recentUse
                readonly property bool filesShown: root.recentFiles && !!root.recentUse
                readonly property int sections: (appsShown ? 1 : 0) + (filesShown ? 1 : 0)
                // The Visual sheet's steps: a section apart by the surface's
                // 24, cards by the standard 12.
                readonly property real gap: 24
                readonly property real headHeight: 40
                readonly property real appHeight: 116
                readonly property real cardGap: 12
                // The files' cards, two rows of them, when the files rest
                // alone; with the applications above, they share what is left.
                readonly property real cardHeight: 150
                readonly property int offered: root.recentUse ? root.recentUse.count : 0
                readonly property int appsOffered: root.recentUse
                    ? Math.max(0, Math.min(offered, root.recentUse.applicationCount || 0)) : 0
                readonly property int filesOffered: offered - appsOffered
                // Eight applications where they fit at 72 each, fewer on a
                // narrow sheet; four columns of files, at least two.
                readonly property int appColumns: Math.max(1, Math.min(8, Math.floor(width / 72)))
                readonly property real appWidth: width / appColumns
                readonly property int fileColumns: Math.max(2, Math.min(4, Math.floor((width + cardGap) / (136 + cardGap))))
                readonly property real fileWidth: (width - cardGap * (fileColumns - 1)) / fileColumns
                readonly property real appsReach: appsShown ? headHeight + appHeight : 0
                // How tall its sections are at rest, which sizes the sheet.
                readonly property real naturalHeight: (appsShown ? appsReach : 0)
                    + (sections === 2 ? gap : 0)
                    + (filesShown ? headHeight + 2 * cardHeight + cardGap : 0)
                readonly property real filesY: appsShown ? appsReach + gap : 0
                readonly property real filesRoom: Math.max(0, height - filesY - headHeight)
                readonly property int fileRows: filesRoom >= 2 * 96 + cardGap ? 2 : filesRoom >= 96 ? 1 : 0
                readonly property real fileHeight: fileRows > 0
                    ? Math.min(176, (filesRoom - cardGap * (fileRows - 1)) / fileRows) : 0
                readonly property real reach: gap + height
                readonly property bool fits: sections > 0
                // The row arrives as one group. Typing sends it away, sinking
                // a little, and clearing the field brings it back the same way
                // it first came.
                readonly property int doors: 0
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
                x: 0
                y: searchField.y + searchField.height + gap
                width: parent.width
                height: Math.max(0, parent.height - y)
                opacity: fits && !root.applicationLaunchPending
                    ? rest * Math.max(0, 1 - root.drawerProgress * 3)
                        * Math.max(0, 1 - root.modeProgress * 3) : 0
                visible: opacity > 0
                enabled: resting && opacity > 0.5 && !root.drawerOpen && !root.modeOpen
                transform: Translate { y: root.reducedMotion ? 0 : (1 - firstRow.rest) * 6 }

                SectionHead {
                    id: appsHead
                    objectName: "recent-apps"
                    visible: firstRow.appsShown
                    width: parent.width
                    title: words.i18n("Recent apps")
                    prefix: "recent-apps"
                    opacity: firstRow.reveal(firstRow.doors)
                    onSeeAll: modeRow.show("apps")
                }
                Text {
                    objectName: "recent-apps-empty"
                    x: 12
                    y: firstRow.headHeight + (firstRow.appHeight - height) / 2
                    visible: firstRow.appsShown && firstRow.appsOffered === 0
                    text: words.i18n("The apps you open show up here.")
                    color: root.secondaryText
                    font.pixelSize: 13
                }
                Repeater {
                    model: firstRow.appsShown ? root.recentUse : null
                    delegate: RecentApp {
                        id: recentApp
                        readonly property real reveal: firstRow.reveal(firstRow.doors)
                        x: index * firstRow.appWidth
                        y: firstRow.headHeight
                        width: firstRow.appWidth
                        height: firstRow.appHeight
                        visible: mine && index < Math.min(firstRow.appColumns, firstRow.appsOffered)
                        opacity: reveal
                        transform: Translate { y: root.reducedMotion ? 0 : (1 - recentApp.reveal) * 10 }
                    }
                }
                SectionHead {
                    id: filesHead
                    objectName: "recent-files"
                    visible: firstRow.filesShown && firstRow.fileRows > 0
                    y: firstRow.filesY
                    width: parent.width
                    title: words.i18n("Recent files")
                    prefix: "recent-files"
                    seeAllShown: root.fileBrowser !== null
                    opacity: firstRow.reveal(firstRow.doors)
                    onSeeAll: modeRow.show("files")
                }
                Text {
                    objectName: "recent-files-empty"
                    x: 12
                    y: firstRow.filesY + firstRow.headHeight + 12
                    visible: filesHead.visible && firstRow.filesOffered === 0
                    text: words.i18n("The files you open show up here.")
                    color: root.secondaryText
                    font.pixelSize: 13
                }
                Repeater {
                    model: firstRow.filesShown ? root.recentUse : null
                    delegate: RecentFile {
                        id: recentFile
                        readonly property int place: index - firstRow.appsOffered
                        readonly property real reveal: firstRow.reveal(firstRow.doors)
                        x: (place % firstRow.fileColumns) * (firstRow.fileWidth + firstRow.cardGap)
                        y: firstRow.filesY + firstRow.headHeight
                            + Math.floor(place / firstRow.fileColumns) * (firstRow.fileHeight + firstRow.cardGap)
                        width: firstRow.fileWidth
                        height: firstRow.fileHeight
                        visible: mine && place >= 0 && place < firstRow.fileColumns * firstRow.fileRows
                        opacity: reveal
                        transform: Translate { y: root.reducedMotion ? 0 : (1 - recentFile.reveal) * 10 }
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
                    // A wheel notch scrolls 80 pixels at Plasma's usual three lines per notch.
                    Kirigami.WheelHandler { target: resultList; verticalStepSize: Qt.styleHints.wheelScrollLines * 80 / 3 }
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
                                ? tone.current : (hover.hovered ? tone.hover : "transparent")
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
                                        color: tone.openTag
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
                                        ? tone.current : (childHover.hovered ? tone.hover : "transparent")
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
                        id: resultTarget
                        width: parent.width
                        height: 62
                        HoverHandler { id: hover }
                        TapHandler {
                            enabled: !root.guestDragged && !root.applicationLaunchPending
                            longPressThreshold: 0.5
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
                            onLongPressed: root.showResultSheet(resultDelegate.index, resultTarget, point.position)
                        }
                        TapHandler {
                            enabled: !root.guestDragged && !root.applicationLaunchPending
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => root.showResultSheet(resultDelegate.index, resultTarget, eventPoint.position)
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
                    x: searchField.x + searchField.width - 12 - (trailingAction.visible ? 36 : 0) - width
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
                onBack: root.closeNotes()
                onExpand: root.toggleExpanded()
                onDismiss: root.launcherController.close()
                onGrow: root.growNotes()
                onFinished: root.launcherController.close()
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
                transform: Translate { y: -20*(1-root.drawerProgress) }
            }
            // Apps' row over its applications: the order, a grey pill naming
            // it at the right, as Files has its own over the folder.
            Item {
                id: sortButton
                objectName: "sort-button"
                // By the catalog's numbers for them; 1 is no longer one.
                readonly property var orderNames: [words.i18n("A to Z"), words.i18n("A to Z"),
                    words.i18n("Most used"), words.i18n("Newest installed")]
                Accessible.role: Accessible.ButtonMenu
                Accessible.name: words.i18n("Sort: %1", sortLabel.text)
                Accessible.onPressAction: root.sortMenuOpen = !root.sortMenuOpen
                x: parent.width - width
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

            // Apps, drawn as lines: a section's row (Most used and Newest
            // installed only), a folder's row, or a row of applications. The
            // applications of an open folder lie under its row on the
            // folder's own ground. Rows are the catalog's, so
            // currentIndex and every tile's index are the catalog's rows.
            Item {
                id: applicationGrid
                objectName: "application-grid"
                x: 0
                y: searchField.y + searchField.height + drawerHandle.sectionGap
                    + sortButton.height + 8
                width: parent.width
                height: Math.max(0, parent.height - y)
                clip: true
                opacity: root.drawerProgress
                visible: !root.filesMode && root.drawerProgress > 0.01
                    && !root.applicationLaunchPending
                z: 3

                readonly property int columns: Math.max(3, Math.min(6, Math.floor(width / 126)))
                readonly property real cellWidth: width / columns
                readonly property real cellHeight: root.launcherController.drawerExpanded ? 112 : 94
                property int count: 0
                property int currentIndex: -1
                // The arrow keys have chosen an application or folder, which
                // Enter opens: it shows, and stays in view.
                property bool keyChosen: false
                property var lines: []
                // Each choosable row, in order, and the line each row lies on.
                property var choices: []
                property var lineOf: ({})
                property string builtFilter: ""
                property int builtOrder: -1
                // What the keys have chosen, by identity rather than row, so
                // a catalog read again keeps the choice where it was.
                property string chosenKey: ""
                onCurrentIndexChanged: chosenKey = keyOf(currentIndex)
                function keyOf(row) {
                    const catalog = root.applicationCatalog
                    if (catalog.isFolder(row)) return "folder:" + catalog.folderId(row)
                    const id = catalog.applicationId(row)
                    return id ? "app:" + id : ""
                }
                function rowOf(key) {
                    const catalog = root.applicationCatalog
                    if (key.startsWith("folder:")) return catalog.folderRow(key.slice(7))
                    return key.startsWith("app:") ? catalog.applicationRow(key.slice(4)) : -1
                }

                function build() {
                    const catalog = root.applicationCatalog
                    const total = catalog.rowCount()
                    const built = []
                    const chosen = []
                    const where = {}
                    // Applications and folders share lines; an open folder's
                    // applications follow on lines of their own under the line
                    // its tile is on.
                    const members = {}
                    for (let row = 0; row < total; ++row) {
                        if (catalog.kind(row) !== "member") continue
                        const folder = catalog.folderOf(row)
                        if (!members[folder]) members[folder] = []
                        members[folder].push(row)
                    }
                    let tiles = null
                    const finish = () => {
                        if (!tiles) return
                        const opened = tiles.rows.filter(row => catalog.kind(row) === "folder")
                            .map(row => members[catalog.folderId(row)] || [])
                            .filter(inside => inside.length > 0)
                        tiles = null
                        for (const inside of opened) {
                            for (let at = 0; at < inside.length; at += columns) {
                                const rows = inside.slice(at, at + columns)
                                built.push({ kind: "tiles", member: true, first: at === 0,
                                             last: at + columns >= inside.length, rows: rows })
                                for (const row of rows) {
                                    chosen.push(row)
                                    where[row] = built.length - 1
                                }
                            }
                        }
                    }
                    for (let row = 0; row < total; ++row) {
                        const kind = catalog.kind(row) || "application"
                        if (kind === "member") continue
                        if (kind === "section") {
                            finish()
                            built.push({ kind: "section", row: row })
                            continue
                        }
                        if (tiles && tiles.rows.length >= columns) finish()
                        if (!tiles) {
                            tiles = { kind: "tiles", member: false, first: false, last: false, rows: [] }
                            built.push(tiles)
                        }
                        tiles.rows.push(row)
                        chosen.push(row)
                        where[row] = built.length - 1
                    }
                    finish()
                    // A folder opened or closed keeps Apps where it was; a new
                    // order or new words start at the top.
                    const keep = builtFilter === catalog.filterText && builtOrder === catalog.sortOrder
                    const top = applicationLines.contentY - applicationLines.originY
                    builtFilter = catalog.filterText
                    builtOrder = catalog.sortOrder
                    count = total
                    choices = chosen
                    lineOf = where
                    lines = built
                    if (keep) {
                        applicationLines.forceLayout()
                        applicationLines.contentY = applicationLines.originY
                            + Math.max(0, Math.min(top, applicationLines.contentHeight - applicationLines.height))
                        // Applications installed or removed meanwhile move
                        // rows: the keys' choice and an open sheet stay with
                        // what they were on, and a sheet whose application
                        // or folder has gone closes.
                        if (keyChosen) {
                            const kept = rowOf(chosenKey)
                            if (kept >= 0) currentIndex = kept
                        }
                        if (applicationSheet.opened && applicationSheet.applicationId !== "") {
                            const at = catalog.applicationRow(applicationSheet.applicationId)
                            if (at >= 0) applicationSheet.row = at
                            else applicationSheet.close()
                        }
                        if (folderSheet.opened && folderSheet.folder !== ""
                                && catalog.folderRow(folderSheet.folder) < 0)
                            folderSheet.close()
                    }
                    if (choices.indexOf(currentIndex) < 0) {
                        currentIndex = choices.length > 0 ? choices[0] : -1
                        keyChosen = false
                    }
                    chosenKey = keyOf(currentIndex)
                }
                onColumnsChanged: build()
                Component.onCompleted: build()
                Connections {
                    target: root.applicationCatalog
                    function onModelReset() { applicationGrid.build() }
                    function onRowsInserted() { applicationGrid.build() }
                    function onRowsRemoved() { applicationGrid.build() }
                    function onDataChanged() { applicationGrid.build() }
                }

                // The choice starts over, unshown.
                function reset() {
                    currentIndex = choices.length > 0 ? choices[0] : -1
                    keyChosen = false
                }
                function choose(row) {
                    currentIndex = row
                    keyChosen = true
                    if (lineOf[row] !== undefined)
                        applicationLines.positionViewAtIndex(lineOf[row], ListView.Contain)
                }
                // The first press shows what Enter would open; each one after
                // moves the choice, Left and Right by one, Up and Down by a
                // line, to the same place along it.
                function step(across, down) {
                    if (choices.length === 0) return
                    const from = choices.indexOf(currentIndex) >= 0 ? currentIndex : choices[0]
                    if (!keyChosen) {
                        choose(from)
                        return
                    }
                    if (across) {
                        const at = Math.max(0, Math.min(choices.length - 1, choices.indexOf(from) + across))
                        choose(choices[at])
                        return
                    }
                    const fromLine = lines[lineOf[from]]
                    const place = fromLine.rows.indexOf(from)
                    let line = lineOf[from]
                    let to = from
                    for (let steps = Math.abs(down || 0); steps > 0; --steps) {
                        let next = line + (down > 0 ? 1 : -1)
                        while (next >= 0 && next < lines.length && lines[next].kind === "section")
                            next += down > 0 ? 1 : -1
                        if (next < 0 || next >= lines.length) break
                        line = next
                        to = lines[line].rows[Math.min(place, lines[line].rows.length - 1)]
                    }
                    choose(to)
                }

                ListView {
                    id: applicationLines
                    objectName: "application-lines"
                    width: parent.width
                    height: parent.height
                    model: applicationGrid.lines
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400
                    // A wheel notch scrolls 80 pixels at Plasma's usual three lines per notch.
                    Kirigami.WheelHandler { target: applicationLines; verticalStepSize: Qt.styleHints.wheelScrollLines * 80 / 3 }

                    delegate: Item {
                        id: line
                        required property var modelData
                        required property int index
                        readonly property string kind: modelData.kind
                        width: ListView.view.width
                        height: kind === "section" ? 36
                            : applicationGrid.cellHeight + (modelData.last ? 6 : 0)

                        // A section's row: its time, over a line.
                        Item {
                            visible: line.kind === "section"
                            anchors.fill: parent
                            Text {
                                id: sectionLabel
                                objectName: "apps-section-label"
                                x: 10
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                text: line.kind === "section" ? root.applicationCatalog.item(line.modelData.row).name : ""
                                color: root.secondaryText
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                Accessible.role: Accessible.Heading
                                Accessible.name: text
                            }
                            Rectangle {
                                anchors.left: sectionLabel.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: sectionLabel.verticalCenter
                                height: 1
                                color: root.surfaceOutline
                            }
                        }

                        // An open folder's ground under its applications.
                        Rectangle {
                            visible: line.kind === "tiles" && line.modelData.member
                            x: 5
                            width: parent.width - 10
                            height: parent.height - (line.modelData.last ? 6 : 0)
                            color: root.controlColor
                            opacity: 0.5
                            topLeftRadius: line.modelData.first ? root.paperRadius : 0
                            topRightRadius: line.modelData.first ? root.paperRadius : 0
                            bottomLeftRadius: line.modelData.last ? root.paperRadius : 0
                            bottomRightRadius: line.modelData.last ? root.paperRadius : 0
                        }

                        Row {
                            visible: line.kind === "tiles"
                            Repeater {
                                model: line.kind === "tiles" ? line.modelData.rows : []
                                delegate: catalogTileComponent
                            }
                        }
                    }
                }
            }

            Component {
                id: catalogTileComponent
                Item {
                    id: catalogDelegate
                    required property var modelData
                    readonly property int row: modelData
                    readonly property var info: root.applicationCatalog.item(row)
                    // A folder is a tile of its own: up to four of its
                    // applications on one face, its name under it. A tap opens
                    // it in place, its applications on lines under its own.
                    readonly property bool isFolder: info.kind === "folder"
                    readonly property string folder: isFolder ? root.applicationCatalog.folderId(row) : ""
                    readonly property bool open: isFolder && root.applicationCatalog.isOpen(row)
                    readonly property bool renaming: isFolder && root.renamingFolder !== ""
                        && root.renamingFolder === folder
                    objectName: (isFolder ? "apps-folder-" : "application-tile-") + row
                    Accessible.role: Accessible.Button
                    Accessible.name: isFolder ? words.i18n("%1, folder", info.name) : info.name
                    Accessible.focused: chosen
                    Accessible.expandable: isFolder
                    Accessible.expanded: open
                    function carry() {
                        if (isFolder) root.carryFolder(row)
                        else root.carryApplication(row)
                    }
                    function showSheet(at) {
                        if (isFolder) root.showFolderSheet(row, catalogTile, at)
                        else root.showApplicationSheet(row, catalogTile, at)
                    }
                    function startRename() {
                        folderName.forceActiveFocus()
                        folderName.selectAll()
                    }
                    onRenamingChanged: if (renaming) Qt.callLater(catalogDelegate.startRename)
                    Component.onCompleted: if (renaming) Qt.callLater(catalogDelegate.startRename)
                    Accessible.onPressAction: root.runCatalogApplication(row, info.name)
                    Accessible.checkable: root.choosingFolder && !isFolder
                    Accessible.checked: picked
                    readonly property bool picked: root.choosingFolder && !isFolder
                        && root.folderPicks.indexOf(root.applicationCatalog.applicationId(row)) >= 0
                    readonly property bool chosen: applicationGrid.keyChosen
                        && applicationGrid.currentIndex === row
                    width: applicationGrid.cellWidth
                    height: applicationGrid.cellHeight

                    // An application carried onto another makes a folder of
                    // the two; onto a folder or one in an open folder, it goes in.
                    DropArea {
                        id: gatherDrop
                        anchors.fill: parent
                        readonly property string format: "application/x-tettegouche-application"
                        onEntered: drag => {
                            const id = drag.formats.indexOf(format) >= 0 ? String(drag.getDataAsString(format)) : ""
                            drag.accepted = id !== "" && id !== root.applicationCatalog.applicationId(catalogDelegate.row)
                        }
                        onDropped: drop => {
                            const id = String(drop.getDataAsString(format))
                            const row = catalogDelegate.row
                            drop.accept(Qt.CopyAction)
                            // After the drop has finished with this tile.
                            Qt.callLater(() => root.applicationCatalog.gather(row, id))
                        }
                    }

                    Rectangle {
                        id: catalogTile
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: root.paperRadius
                        color: catalogDelegate.picked ? tone.controlPressed
                            : catalogHover.hovered || catalogDelegate.chosen || gatherDrop.containsDrag
                            ? tone.tileHover : catalogDelegate.open ? root.controlColor : "transparent"
                        // A hidden application, shown by the eye, is dimmed,
                        // as is a folder while applications are chosen.
                        opacity: catalogDelegate.info.hidden
                            || (root.choosingFolder && catalogDelegate.isFolder) ? 0.45 : 1

                        // Chosen for the new folder.
                        Rectangle {
                            objectName: "application-picked"
                            visible: catalogDelegate.picked
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 20
                            height: 20
                            radius: 10
                            color: root.controlColor
                            border.width: 1.5
                            border.color: root.primaryText
                            z: 2
                            SuiteIcon {
                                anchors.centerIn: parent
                                glyph: "check"
                                width: 14
                                height: 14
                            }
                        }
                        // The chosen application rises, as a touched one does.
                        scale: catalogDelegate.chosen ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: root.ms(120) } }

                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            width: root.launcherController.drawerExpanded ? 52 : 42
                            height: width
                            visible: !catalogDelegate.isFolder
                            source: catalogDelegate.isFolder ? "" : catalogDelegate.info.icon
                        }

                        Rectangle {
                            id: folderFace
                            objectName: "apps-folder-tile"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            width: root.launcherController.drawerExpanded ? 52 : 42
                            height: width
                            radius: width * 0.26
                            visible: catalogDelegate.isFolder
                            color: root.controlColor
                            border.width: 1
                            border.color: root.surfaceOutline
                            Grid {
                                anchors.centerIn: parent
                                columns: 2
                                spacing: parent.width * 0.06
                                Repeater {
                                    model: catalogDelegate.isFolder ? (catalogDelegate.info.folderIcons || []) : []
                                    delegate: Kirigami.Icon {
                                        required property var modelData
                                        width: folderFace.width * 0.36
                                        height: width
                                        source: modelData
                                    }
                                }
                            }
                        }

                        TextInput {
                            id: folderName
                            objectName: "apps-folder-name"
                            visible: catalogDelegate.isFolder
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.bottomMargin: 8
                            horizontalAlignment: TextInput.AlignHCenter
                            text: catalogDelegate.isFolder ? catalogDelegate.info.name : ""
                            color: root.primaryText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            readOnly: !catalogDelegate.renaming
                            enabled: catalogDelegate.renaming
                            selectByMouse: true
                            maximumLength: 40
                            clip: true
                            Accessible.role: Accessible.EditableText
                            Accessible.name: words.i18n("Folder name")
                            function keep() {
                                if (!catalogDelegate.renaming) return
                                if (text.trim().length > 0 && text.trim() !== catalogDelegate.info.name)
                                    root.applicationCatalog.renameFolder(catalogDelegate.folder, text)
                                root.renamingFolder = ""
                            }
                            onAccepted: { keep(); root.forceActiveFocus() }
                            onActiveFocusChanged: if (!activeFocus) keep()
                            Keys.onEscapePressed: event => {
                                text = catalogDelegate.info.name
                                root.renamingFolder = ""
                                root.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                        Rectangle {
                            anchors.top: folderName.bottom
                            anchors.horizontalCenter: folderName.horizontalCenter
                            width: Math.min(folderName.width, folderName.contentWidth + 8)
                            height: 1
                            color: root.surfaceOutline
                            visible: folderName.activeFocus
                        }

                        Text {
                            visible: !catalogDelegate.isFolder
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.bottomMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            text: catalogDelegate.info.name
                            color: root.primaryText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        HoverHandler { id: catalogHover }
                        TapHandler {
                            id: catalogTap
                            enabled: !root.guestDragged
                                && !root.applicationLaunchPending && !catalogDelegate.renaming
                            longPressThreshold: 0.5
                            // A hold that then moves carries the application.
                            property bool held: false
                            onPressedChanged: if (pressed) held = false
                            onTapped: root.runCatalogApplication(
                                catalogDelegate.row,
                                catalogDelegate.info.name)
                            onLongPressed: {
                                held = true
                                catalogDelegate.showSheet(point.position)
                            }
                        }
                        // Carried by a mouse at once; by touch after a hold,
                        // since a swipe scrolls Apps.
                        DragHandler {
                            objectName: "application-carry"
                            target: null
                            enabled: !root.applicationLaunchPending
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onActiveChanged: if (active) catalogDelegate.carry()
                        }
                        DragHandler {
                            target: null
                            enabled: !root.applicationLaunchPending
                            acceptedDevices: PointerDevice.TouchScreen
                            dragThreshold: catalogTap.held ? Qt.styleHints.startDragDistance : 32767
                            onActiveChanged: if (active) catalogDelegate.carry()
                        }
                        TapHandler {
                            enabled: !root.applicationLaunchPending
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => catalogDelegate.showSheet(eventPoint.position)
                        }
                    }
                }
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
                // Under the sort button.
                anchors.right: parent.right
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
