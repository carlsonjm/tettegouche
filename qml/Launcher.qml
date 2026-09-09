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
    readonly property color primaryText: "#f2ffffff"
    readonly property color secondaryText: "#a8ffffff"
    readonly property color surfaceColor: "#141414"
    readonly property color surfaceOutline: "#333333"
    readonly property color controlColor: "#242424"
    readonly property int cardRadius: 10
    readonly property int contentInset: 22
    property bool pendingLaunch: false
    property bool applicationLaunchPending: false
    property string launchingApplication: ""
    property real guestDrag: 0
    property bool guestExiting: false
    property bool guestDragged: false

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

    function submit() {
        if (resultList.count > 0) {
            runResult(Math.max(0, resultList.currentIndex))
        } else if (root.searchResults.querying) {
            pendingLaunch = true
        }
    }

    Keys.onEscapePressed: event => {
        root.launcherController.close()
        event.accepted = true
    }

    Connections {
        target: root.launcherController
        function onOpened() {
            query.text = ""
            root.pendingLaunch = false
            root.applicationLaunchPending = false
            root.launchingApplication = ""
            query.forceActiveFocus()
            root.guestDrag = 0
            root.guestExiting = false
            root.guestDragged = false
            sheet.opacity = 1
            sheet.scale = 1
        }
        function onGuestLaunchReady() {
            if (!root.applicationLaunchPending) {
                return
            }
            launchTimeout.stop()
            root.guestExiting = true
            launchReadyExit.restart()
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
        anchors.fill: parent
        color: "#76000000"
        visible: !root.launcherController.guestMode

        TapHandler {
            onTapped: root.launcherController.close()
        }
    }

    Rectangle {
        id: sheet
        x: root.launcherController.guestMode
            ? root.launcherController.guestX
            : (parent.width - width) / 2
        y: root.launcherController.guestMode
            ? root.launcherController.guestY
            : Math.max(36, parent.height * 0.09)
        width: root.launcherController.guestMode
            ? root.launcherController.guestWidth
            : Math.min(720, parent.width - 40)
        height: root.launcherController.guestMode
            ? root.launcherController.guestHeight
            : Math.min(560, parent.height - y - 36)
        radius: root.launcherController.guestMode ? root.cardRadius : 24
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
                width: resting ? Math.min(parent.width,
                    Math.max(360, parent.width * 0.72)) : parent.width
                height: 58
                x: (parent.width - width) / 2
                y: resting ? Math.round((parent.height - height) * 0.44) : 0
                radius: height / 2
                color: root.controlColor
                opacity: root.applicationLaunchPending ? 0 : 1
                enabled: !root.applicationLaunchPending

                Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                Kirigami.Icon {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    source: "system-search"
                    color: root.primaryText
                }

                TextInput {
                    id: query
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 12
                    anchors.right: clearButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.primaryText
                    selectionColor: "#6da9ddff"
                    selectedTextColor: "#ffffffff"
                    font.pixelSize: 18
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText

                    onTextChanged: {
                        root.pendingLaunch = false
                        root.searchResults.queryString = text
                        resultList.currentIndex = resultList.count > 0 ? 0 : -1
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down && resultList.count > 0) {
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
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: query.text.length === 0
                        text: "Find an application"
                        color: "#86ffffff"
                        font: query.font
                    }
                }

                Item {
                    id: clearButton
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    visible: query.text.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: clearHover.hovered ? "#30ffffff" : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.secondaryText
                        font.pixelSize: 25
                    }

                    HoverHandler { id: clearHover }
                    TapHandler {
                        enabled: !root.guestDragged
                        onTapped: {
                            query.text = ""
                            query.forceActiveFocus()
                        }
                    }
                }
            }

            Item {
                id: resultsArea
                y: searchField.y + searchField.height + 16
                width: parent.width
                height: parent.height - y
                opacity: root.applicationLaunchPending ? 0 : 1

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

            Column {
                anchors.centerIn: parent
                spacing: 14
                visible: root.applicationLaunchPending
                opacity: root.applicationLaunchPending ? 1 : 0

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
