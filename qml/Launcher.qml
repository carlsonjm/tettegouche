/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

Item {
    id: root

    required property var launcherController
    required property var searchResults
    required property var applicationCatalog
    focus: true
    readonly property color primaryText: "#f2ffffff"
    readonly property color secondaryText: "#a8ffffff"
    readonly property color surfaceColor: "#141414"
    readonly property color surfaceOutline: "#5a5a5a"
    readonly property color controlColor: "#242424"
    readonly property int cardRadius: 10
    readonly property int contentInset: 22
    property bool pendingLaunch: false
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

    SequentialAnimation {
        id: openingSequence
        ScriptAction { script: { root.openingText = 0; root.openingControls = 0; root.openingIcon = 0; root.openingShine = 0 } }
        PauseAnimation { duration: 60 }
        NumberAnimation { target: root; property: "openingControls"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "openingIcon"; to: 1; duration: 120; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 140 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "openingText"; to: 1; duration: 280; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 180 }
                NumberAnimation { target: root; property: "openingShine"; to: 1; duration: 460; easing.type: Easing.InOutSine }
            }
        }
    }

    function setDrawerOpen(open) {
        root.drawerOpen = open
        if (!open) {
            root.sortMenuOpen = false
        }
        root.applicationCatalog.filterText = open ? query.text : ""
        root.searchResults.queryString = open ? "" : query.text
        drawerSettle.to = open ? 1 : 0
        drawerSettle.restart()
        if (open) {
            root.searchEngaged = false
            root.forceActiveFocus()
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
        if (root.launcherController.activateIfOpen(index)) {
            root.launcherController.finishLaunch()
            return true
        }
        const applicationName = String(
            root.searchResults.data(
                root.searchResults.index(index, 0), Qt.DisplayRole))
        const waitsForWindow =
            root.launcherController.beginGuestApplicationLaunch()
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

    function runCatalogApplication(index, applicationName) {
        if (root.launcherController.activateCatalogIfOpen(index)) {
            root.launcherController.finishLaunch()
            return true
        }
        const waitsForWindow =
            root.launcherController.beginGuestApplicationLaunch()
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

    function submit() {
        if (root.drawerOpen && applicationGrid.count > 0) {
            const row = Math.max(0, applicationGrid.currentIndex)
            runCatalogApplication(row,
                root.applicationCatalog.applicationName(row))
        } else if (resultList.count > 0) {
            runResult(Math.max(0, resultList.currentIndex))
        } else if (root.searchResults.querying) {
            pendingLaunch = true
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.sortMenuOpen) {
                root.sortMenuOpen = false
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
        if (!query.activeFocus && event.text.length > 0
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
        function onOpened() {
            query.text = ""
            root.pendingLaunch = false
            root.applicationLaunchPending = false
            root.launchingApplication = ""
            root.searchEngaged = false
            root.drawerOpen = false
            root.drawerProgress = 0
            root.sortMenuOpen = false
            root.forceActiveFocus()
            root.guestDrag = 0
            root.guestExiting = false
            root.guestDragged = false
            sheet.opacity = 1
            sheet.scale = 1
            openingSequence.restart()
        }
        function onGuestLaunchReady() {
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
        x: root.launcherController.guestMode
            ? root.launcherController.guestX
            : (parent.width - width) / 2
        y: root.launcherController.guestMode
            ? root.launcherController.guestY
            : Math.round((parent.height - height) / 2)
        width: root.launcherController.guestMode
            ? root.launcherController.guestWidth
            : Math.min(720, parent.width - 40)
        height: root.launcherController.guestMode
            ? root.launcherController.guestHeight
            : Math.min(480, parent.height - 72)
        radius: root.cardRadius
        color: root.surfaceColor
        border.width: 1
        border.color: root.surfaceOutline
        clip: true
        transform: Translate { x: root.guestDrag }

        DragHandler {
            id: guestDragHandler
            enabled: root.launcherController.guestMode
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
                readonly property bool resting:
                    query.text.length === 0
                    && resultList.count === 0
                    && !root.searchResults.querying
                    && !root.applicationLaunchPending
                    && root.drawerProgress < 0.01
                width: resting ? Math.min(parent.width,
                    Math.max(360, parent.width * 0.72)) : parent.width
                height: 58
                x: (parent.width - width) / 2
                y: resting ? Math.round((parent.height - height) * 0.44) : 0
                radius: height / 2
                color: root.searchEngaged || query.text.length > 0
                    ? root.controlColor : "transparent"
                opacity: root.applicationLaunchPending ? 0 : 1
                enabled: !root.applicationLaunchPending
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

                Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Item {
                    id: trailingAction
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
                        if (text.length > 0) {
                            root.searchEngaged = true
                        }
                        root.pendingLaunch = false
                        root.applicationCatalog.filterText = root.drawerOpen
                            ? text : ""
                        root.searchResults.queryString = root.drawerOpen
                            ? "" : text
                        resultList.currentIndex = resultList.count > 0 ? 0 : -1
                        applicationGrid.currentIndex =
                            applicationGrid.count > 0 ? 0 : -1
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.searchEngaged = true
                        }
                    }

                    Keys.onPressed: event => {
                        if (root.drawerOpen && event.key === Qt.Key_Down
                                && applicationGrid.count > 0) {
                            applicationGrid.currentIndex = Math.min(
                                applicationGrid.count - 1,
                                Math.max(0,
                                    applicationGrid.currentIndex + 1))
                            event.accepted = true
                        } else if (root.drawerOpen && event.key === Qt.Key_Up
                                   && applicationGrid.count > 0) {
                            applicationGrid.currentIndex = Math.max(
                                0, applicationGrid.currentIndex - 1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down
                                   && resultList.count > 0) {
                            resultList.currentIndex = Math.min(
                                resultList.count - 1,
                                Math.max(0, resultList.currentIndex + 1))
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up
                                   && resultList.count > 0) {
                            resultList.currentIndex = Math.max(
                                0, resultList.currentIndex - 1)
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
                        text: "Just type"
                        color: "#86ffffff"
                        font.pixelSize: restingBrowseLabel.font.pixelSize
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

            Item {
                id: resultsArea
                y: searchField.y + searchField.height + 16
                width: parent.width
                height: parent.height - y
                opacity: root.applicationLaunchPending ? 0 : 1
                visible: query.text.length > 0 && !root.drawerOpen

                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                ListView {
                    id: resultList
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    currentIndex: count > 0 ? 0 : -1
                    model: root.searchResults

                    delegate: Rectangle {
                        id: resultDelegate
                        required property int index
                        required property var model
                        readonly property bool alreadyOpen:
                            root.launcherController.contextAvailable
                            && root.launcherController.resultIsOpen(index)

                        width: resultList.width
                        height: 62
                        radius: 16
                        color: ListView.isCurrentItem
                            ? "#3dffffff"
                            : (hover.hovered ? "#22ffffff" : "transparent")

                        Row {
                            anchors.fill: parent
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
                                        text: "OPEN"
                                        visible: resultDelegate.alreadyOpen
                                        color: "#ff71e6be"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: resultDelegate.model.subtext
                                        || "Application"
                                    color: root.secondaryText
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        HoverHandler { id: hover }
                        TapHandler {
                            enabled: !root.guestDragged
                                && !root.applicationLaunchPending
                            onTapped: {
                                resultList.currentIndex = resultDelegate.index
                                root.runResult(resultDelegate.index)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: query.text.length > 0
                        && !root.searchResults.querying
                        && resultList.count === 0
                    text: "No applications found"
                    color: root.secondaryText
                    font.pixelSize: 15
                }
            }

            Item {
                id: drawerHandle
                readonly property real revealDistance: Math.max(1,
                    content.height - searchField.height - height - 32)
                property real dragStartProgress: 0
                x: 0
                y: Math.round(parent.height - height - 4
                    - root.drawerProgress * revealDistance)
                width: parent.width
                height: 44
                opacity: (query.text.length === 0 || root.drawerOpen)
                    && !root.applicationLaunchPending ? root.openingControls : 0
                transform: Translate { y: (1 - root.openingControls) * 10 }
                enabled: opacity > 0.5
                z: 4

                Text {
                    id: restingBrowseLabel
                    objectName: "browse-label"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 1
                    text: "Browse everything"
                    color: restingBrowseHover.running || !restingBrowseMouse.containsMouse
                        ? root.secondaryText : root.primaryText
                    Behavior on color { ColorAnimation { duration: 100 } }
                    font.pixelSize: 13
                    font.letterSpacing: 0.25
                    opacity: Math.max(0, 1 - root.drawerProgress * 3)
                    enabled: opacity > 0.5

                    Timer { id: restingBrowseHover; interval: 220 }
                    MouseArea {
                        id: restingBrowseMouse
                        anchors.fill: parent
                        anchors.leftMargin: -12
                        anchors.rightMargin: -12
                        anchors.topMargin: -3
                        anchors.bottomMargin: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (containsMouse) restingBrowseHover.restart()
                            else restingBrowseHover.stop()
                        }
                        onClicked: root.setDrawerOpen(true)
                    }
                }

                Text {
                    id: openBrowseLabel
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Browse everything"
                    color: openBrowseHover.running || !openBrowseMouse.containsMouse
                        ? root.secondaryText : root.primaryText
                    Behavior on color { ColorAnimation { duration: 100 } }
                    font.pixelSize: 13
                    font.letterSpacing: 0.25
                    opacity: Math.max(0,
                        (root.drawerProgress - 0.65) / 0.35)
                    enabled: root.drawerOpen && opacity > 0.9

                    Timer { id: openBrowseHover; interval: 220 }
                    MouseArea {
                        id: openBrowseMouse
                        anchors.fill: parent
                        anchors.leftMargin: -4
                        anchors.rightMargin: -12
                        anchors.topMargin: -3
                        anchors.bottomMargin: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (containsMouse) openBrowseHover.restart()
                            else openBrowseHover.stop()
                        }
                        onClicked: root.setDrawerOpen(false)
                    }
                }

                Item {
                    id: grabberTarget
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(6 + (1 - root.drawerProgress) * 10)
                    width: 124
                    height: 32

                    Rectangle {
                        anchors.centerIn: parent
                        width: drawerDrag.active ? 48 : 42
                        height: 4
                        radius: 2
                        color: drawerHover.hovered || drawerDrag.active
                            ? root.primaryText : root.surfaceOutline

                        Behavior on width {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    HoverHandler { id: drawerHover }
                }

                Item {
                    id: sortButton
                    objectName: "sort-button"
                    anchors.right: parent.right
                    anchors.rightMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42
                    opacity: Math.max(0, (root.drawerProgress - 0.72) / 0.28)
                    enabled: root.drawerOpen && opacity > 0.9

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: root.applicationCatalog.descending
                            ? "view-sort-descending-symbolic"
                            : "view-sort-ascending-symbolic"
                        color: root.primaryText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sortMenuOpen = !root.sortMenuOpen
                    }
                }

                DragHandler {
                    id: drawerDrag
                    margin: 4
                    target: null
                    xAxis.enabled: false
                    yAxis.enabled: true
                    acceptedDevices: PointerDevice.Mouse
                        | PointerDevice.TouchPad
                        | PointerDevice.TouchScreen
                    onActiveChanged: {
                        if (active) {
                            root.sortMenuOpen = false
                            drawerHandle.dragStartProgress =
                                root.drawerProgress
                            drawerSettle.stop()
                        } else {
                            root.setDrawerOpen(root.drawerProgress > 0.34)
                        }
                    }
                    onTranslationChanged: {
                        if (active) {
                            root.drawerProgress = Math.max(0, Math.min(1,
                                drawerHandle.dragStartProgress
                                - translation.y
                                    / drawerHandle.revealDistance))
                        }
                    }
                }
            }

            GridView {
                id: applicationGrid
                x: 0
                y: drawerHandle.y + drawerHandle.height + 10
                width: parent.width
                height: Math.max(0, parent.height - y)
                clip: true
                opacity: root.drawerProgress
                visible: root.drawerProgress > 0.01
                    && !root.applicationLaunchPending
                model: root.applicationCatalog
                cellWidth: width / Math.max(3,
                    Math.min(6, Math.floor(width / 126)))
                cellHeight: 94
                boundsBehavior: Flickable.StopAtBounds
                z: 3

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: catalogDelegate
                    required property int index
                    required property var model
                    width: applicationGrid.cellWidth
                    height: applicationGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 16
                        color: catalogHover.hovered
                            ? "#20ffffff" : "transparent"

                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            width: 42
                            height: 42
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
                            onTapped: root.runCatalogApplication(
                                catalogDelegate.index,
                                catalogDelegate.model.name)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: applicationGrid
                visible: root.drawerOpen && query.text.length > 0
                    && applicationGrid.count === 0
                text: "No applications found"
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
                radius: 14
                color: root.surfaceColor
                border.width: 1
                border.color: root.surfaceOutline
                visible: opacity > 0
                enabled: root.sortMenuOpen && root.drawerOpen
                opacity: root.sortMenuOpen && root.drawerOpen ? 1 : 0
                z: 8

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    Repeater {
                        model: [
                            { "label": "A to Z", "descending": false },
                            { "label": "Z to A", "descending": true }
                        ]

                        delegate: Rectangle {
                            id: sortChoice
                            required property var modelData
                            width: parent.width
                            height: 38
                            radius: height / 2
                            readonly property bool selected: root.applicationCatalog.descending
                                === sortChoice.modelData.descending
                            color: selected ? root.controlColor : "transparent"
                            border.width: !selected && choiceHover.hovered ? 1 : 0
                            border.color: root.surfaceOutline
                            Behavior on color { ColorAnimation { duration: 100 } }

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
                    text: "Opening"
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
        duration: 260
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: guestReturn
        target: root
        property: "guestDrag"
        to: 0
        duration: 210
        easing.type: Easing.OutBack
        onFinished: root.guestDragged = false
    }

    ParallelAnimation {
        id: launchReadyExit
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 0.96
            duration: 190
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 0
            duration: 190
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
            duration: 220
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 0.72
            duration: 220
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 0
            duration: 220
            easing.type: Easing.InCubic
        }
        onFinished: root.launcherController.completeGuestHandoff()
    }
}
