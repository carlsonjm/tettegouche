/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// Apps, drawn as lines: a section's row (Most used and Newest
// installed only), a folder's row, or a row of applications. The
// applications of an open folder lie under its row on the
// folder's own ground. Rows are the catalog's, so
// currentIndex and every tile's index are the catalog's rows.
Item {
    id: applicationGrid
    objectName: "application-grid"
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property SheetMenu applicationSheet
    required property Item drawerHandle
    required property SheetMenu folderSheet
    required property Item searchField
    required property Item sheet
    required property Item sortButton
    readonly property alias applicationLines: applicationLines

    Component {
        id: catalogTileComponent
        Item {
            id: catalogDelegate
            required property var modelData
            readonly property int row: modelData
            readonly property var info: launcher.applicationCatalog.item(row)
            // A folder is a tile of its own: up to four of its
            // applications on one face, its name under it. A tap opens
            // it in place, its applications on lines under its own.
            readonly property bool isFolder: info.kind === "folder"
            readonly property string folder: isFolder ? launcher.applicationCatalog.folderId(row) : ""
            readonly property bool open: isFolder && launcher.applicationCatalog.isOpen(row)
            readonly property bool renaming: isFolder && launcher.renamingFolder !== ""
                && launcher.renamingFolder === folder
            objectName: (isFolder ? "apps-folder-" : "application-tile-") + row
            Accessible.role: Accessible.Button
            Accessible.name: isFolder ? words.i18n("%1, folder", info.name) : info.name
            Accessible.focused: chosen
            Accessible.expandable: isFolder
            Accessible.expanded: open
            function carry() {
                if (isFolder) launcher.carryFolder(row)
                else launcher.carryApplication(row)
            }
            function showSheet(at) {
                if (isFolder) launcher.showFolderSheet(row, catalogTile, at)
                else launcher.showApplicationSheet(row, catalogTile, at)
            }
            function startRename() {
                folderName.forceActiveFocus()
                folderName.selectAll()
            }
            onRenamingChanged: if (renaming) Qt.callLater(catalogDelegate.startRename)
            Component.onCompleted: if (renaming) Qt.callLater(catalogDelegate.startRename)
            Accessible.onPressAction: launcher.runCatalogApplication(row, info.name)
            Accessible.checkable: launcher.choosingFolder && !isFolder
            Accessible.checked: picked
            readonly property bool picked: launcher.choosingFolder && !isFolder
                && launcher.folderPicks.indexOf(launcher.applicationCatalog.applicationId(row)) >= 0
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
                    drag.accepted = id !== "" && id !== launcher.applicationCatalog.applicationId(catalogDelegate.row)
                }
                onDropped: drop => {
                    const id = String(drop.getDataAsString(format))
                    const row = catalogDelegate.row
                    drop.accept(Qt.CopyAction)
                    // After the drop has finished with this tile.
                    Qt.callLater(() => launcher.applicationCatalog.gather(row, id))
                }
            }

            Rectangle {
                id: catalogTile
                anchors.fill: parent
                anchors.margins: 5
                radius: launcher.paperRadius
                color: catalogDelegate.picked ? tone.controlPressed
                    : catalogHover.hovered || catalogDelegate.chosen || gatherDrop.containsDrag
                    ? tone.tileHover : catalogDelegate.open ? launcher.controlColor : "transparent"
                // A hidden application, shown by the eye, is dimmed,
                // as is a folder while applications are chosen.
                opacity: catalogDelegate.info.hidden
                    || (launcher.choosingFolder && catalogDelegate.isFolder) ? 0.45 : 1

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
                    color: launcher.controlColor
                    border.width: 1.5
                    border.color: launcher.primaryText
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
                Behavior on scale { NumberAnimation { duration: launcher.ms(120) } }

                Kirigami.Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    width: launcher.launcherController.drawerExpanded ? 52 : 42
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
                    width: launcher.launcherController.drawerExpanded ? 52 : 42
                    height: width
                    radius: width * 0.26
                    visible: catalogDelegate.isFolder
                    color: launcher.controlColor
                    border.width: 1
                    border.color: launcher.surfaceOutline
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
                    color: launcher.primaryText
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
                            launcher.applicationCatalog.renameFolder(catalogDelegate.folder, text)
                        launcher.renamingFolder = ""
                    }
                    onAccepted: { keep(); launcher.forceActiveFocus() }
                    onActiveFocusChanged: if (!activeFocus) keep()
                    Keys.onEscapePressed: event => {
                        text = catalogDelegate.info.name
                        launcher.renamingFolder = ""
                        launcher.forceActiveFocus()
                        event.accepted = true
                    }
                }
                Rectangle {
                    anchors.top: folderName.bottom
                    anchors.horizontalCenter: folderName.horizontalCenter
                    width: Math.min(folderName.width, folderName.contentWidth + 8)
                    height: 1
                    color: launcher.surfaceOutline
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
                    color: launcher.primaryText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                HoverHandler { id: catalogHover }
                TapHandler {
                    id: catalogTap
                    enabled: !launcher.guestDragged
                        && !launcher.applicationLaunchPending && !catalogDelegate.renaming
                    longPressThreshold: 0.5
                    // A hold that then moves carries the application.
                    property bool held: false
                    onPressedChanged: if (pressed) held = false
                    onTapped: launcher.runCatalogApplication(
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
                    enabled: !launcher.applicationLaunchPending
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onActiveChanged: if (active) catalogDelegate.carry()
                }
                DragHandler {
                    target: null
                    enabled: !launcher.applicationLaunchPending
                    acceptedDevices: PointerDevice.TouchScreen
                    dragThreshold: catalogTap.held ? Qt.styleHints.startDragDistance : 32767
                    onActiveChanged: if (active) catalogDelegate.carry()
                }
                TapHandler {
                    enabled: !launcher.applicationLaunchPending
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.RightButton
                    onTapped: eventPoint => catalogDelegate.showSheet(eventPoint.position)
                }
            }
        }
    }

    x: 0
    y: searchField.y + searchField.height + drawerHandle.sectionGap
        + sortButton.height + 8
    width: parent.width
    height: Math.max(0, parent.height - y)
    clip: true
    opacity: launcher.drawerProgress
    visible: !launcher.filesMode && launcher.drawerProgress > 0.01
        && !launcher.applicationLaunchPending
    z: 3

    readonly property int columns: Math.max(3, Math.min(6, Math.floor(width / 126)))
    readonly property real cellWidth: width / columns
    readonly property real cellHeight: launcher.launcherController.drawerExpanded ? 112 : 94
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
        const catalog = launcher.applicationCatalog
        if (catalog.isFolder(row)) return "folder:" + catalog.folderId(row)
        const id = catalog.applicationId(row)
        return id ? "app:" + id : ""
    }
    function rowOf(key) {
        const catalog = launcher.applicationCatalog
        if (key.startsWith("folder:")) return catalog.folderRow(key.slice(7))
        return key.startsWith("app:") ? catalog.applicationRow(key.slice(4)) : -1
    }

    function build() {
        const catalog = launcher.applicationCatalog
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
        target: launcher.applicationCatalog
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
                    text: line.kind === "section" ? launcher.applicationCatalog.item(line.modelData.row).name : ""
                    color: launcher.secondaryText
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
                    color: launcher.surfaceOutline
                }
            }

            // An open folder's ground under its applications.
            Rectangle {
                visible: line.kind === "tiles" && line.modelData.member
                x: 5
                width: parent.width - 10
                height: parent.height - (line.modelData.last ? 6 : 0)
                color: launcher.controlColor
                opacity: 0.5
                topLeftRadius: line.modelData.first ? launcher.paperRadius : 0
                topRightRadius: line.modelData.first ? launcher.paperRadius : 0
                bottomLeftRadius: line.modelData.last ? launcher.paperRadius : 0
                bottomRightRadius: line.modelData.last ? launcher.paperRadius : 0
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
