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
    id: resultsArea
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property TextInput query
    required property Item searchField
    readonly property alias resultList: resultList
    // The scope line, 8 above the first row; rows 56 tall, the 32 icon with
    // 12 above and below, and 4 apart.
    readonly property int scopeHeight: 32
    readonly property int listTop: 16 + scopeHeight + 8
    readonly property int rowHeight: 56
    readonly property int rowGap: 4

    y: searchField.y + searchField.height + 16
    width: parent.width
    height: parent.height - y
    opacity: launcher.applicationLaunchPending ? 0 : 1
    visible: query.text.length > 0 && !launcher.drawerOpen

    // The files' scope, which the Helpers have no use for.
    Row {
        visible: !launcher.helpersShown
        spacing: 20
        Text {
            objectName: "file-scope-toggle"
            Accessible.role: Accessible.Button
            Accessible.name: text
            text: launcher.searchResults.allFiles ? words.i18n("All files ⇄") : words.i18n("Everyday search ⇄")
            color: launcher.primaryText
            font.pixelSize: 12
            height: resultsArea.scopeHeight
            verticalAlignment: Text.AlignVCenter
            TapHandler {
                onTapped: {
                    launcher.searchResults.allFiles = !launcher.searchResults.allFiles
                    launcher.selectedChildKey = ""
                    launcher.childLaunchFailed = false
                    resultList.currentIndex = resultList.count > 0 ? 0 : -1
                    resultList.settleAtBeginning()
                }
            }
        }
        Text {
            objectName: "quiet-folders-button"
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.onPressAction: { quietPaths.text = launcher.searchResults.quietFolders || ""; quietPopup.open() }
            text: words.i18n("Quiet folders…")
            color: launcher.secondaryText
            font.pixelSize: 12
            height: resultsArea.scopeHeight
            verticalAlignment: Text.AlignVCenter
            TapHandler { onTapped: { quietPaths.text = launcher.searchResults.quietFolders || ""; quietPopup.open() } }
        }
    }

    QQC2.Popup {
        id: quietPopup
        width: Math.min(480, resultsArea.width)
        height: 250
        x: (resultsArea.width - width) / 2
        y: 38
        padding: 16
        bottomMargin: launcher.keysReach
        modal: true
        background: Rectangle { color: launcher.surfaceColor; radius: launcher.paperRadius; border.color: launcher.surfaceOutline }
        contentItem: Column {
            spacing: 10
            Text { text: words.i18n("Quiet folders"); color: launcher.primaryText; font.pixelSize: 16 }
            Text {
                text: words.i18n("One full folder path per line. All files includes these again.")
                color: launcher.secondaryText
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 12
            }
            QQC2.ScrollView {
                width: parent.width
                height: 110
                QQC2.TextArea { id: quietPaths; color: launcher.primaryText; wrapMode: TextEdit.NoWrap }
            }
            Row {
                spacing: 16
                QQC2.Button { text: words.i18n("Save"); onClicked: { launcher.searchResults.quietFolders = quietPaths.text; quietPopup.close() } }
                QQC2.Button { text: words.i18n("Cancel"); onClicked: quietPopup.close() }
            }
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic }
    }

    // Ask's answer, above the Helpers it names.
    AskAnswer {
        id: askAnswer
        width: parent.width
        askClient: launcher.askClient
        tone: resultsArea.tone
        words: resultsArea.words
        visible: launcher.askShown && shown
    }

    ListView {
        id: resultList
        objectName: "search-result-list"
        anchors.fill: parent
        anchors.topMargin: askAnswer.visible ? askAnswer.height + 8 : resultsArea.scopeHeight + 8
        clip: true
        // A wheel notch scrolls 80 pixels at Plasma's usual three lines per notch.
        Kirigami.WheelHandler { target: resultList; verticalStepSize: Qt.styleHints.wheelScrollLines * 80 / 3 }
        spacing: resultsArea.rowGap
        currentIndex: count > 0 ? 0 : -1
        model: launcher.searchResults
        // Model insertions and changing child heights can preserve
        // an old scroll offset even when the first row is selected.
        // Let layout settle before aligning a fresh search to its
        // actual origin; never reset a user's lower selection.
        function settleAtBeginning() {
            Qt.callLater(function() {
                if (resultList.currentIndex <= 0 && !launcher.searchResults.selectionPinned()) {
                    resultList.forceLayout()
                    resultList.positionViewAtBeginning()
                }
            })
        }
        onCountChanged: settleAtBeginning()
        onHeightChanged: if (!launcher.sheetResizing) settleAtBeginning()
        Connections {
            target: launcher
            function onSheetResizingChanged() {
                if (!launcher.sheetResizing) resultList.settleAtBeginning()
            }
        }

        Connections {
            target: launcher.searchResults
            function onQueryingChanged() {
                if (!launcher.searchResults.querying) resultList.settleAtBeginning()
            }
            function onSelectionChanged() {
                if (launcher.searchResults.selectionPinned())
                    resultList.currentIndex = launcher.searchResults.selectedRow()
            }
        }

        delegate: Rectangle {
            id: resultDelegate
            objectName: "result-" + index
            Accessible.role: Accessible.ListItem
            Accessible.name: model.display || ""
            Accessible.description: model.subtext || ""
            Accessible.selected: ListView.isCurrentItem
            Accessible.onPressAction: launcher.runResult(index)
            required property int index
            required property var model
            readonly property var connectedDevices: {
                const revision = launcher.launcherController.relatedRevision
                return launcher.launcherController.relatedItems(index)
            }
            readonly property bool alreadyOpen:
                launcher.launcherController.contextAvailable
                && launcher.launcherController.resultIsOpen(index)

            width: resultList.width
            height: resultsArea.rowHeight + deviceChildren.height
            radius: launcher.paperRadius
            color: "transparent"
            Rectangle {
                objectName: "parent-highlight-" + resultDelegate.index
                width: parent.width; height: resultsArea.rowHeight; radius: launcher.paperRadius
                color: resultDelegate.ListView.isCurrentItem && launcher.selectedChildKey === ""
                    ? tone.current : (hover.hovered ? tone.hover : "transparent")
            }

            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: resultsArea.rowHeight
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    source: resultDelegate.model.decoration
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44
                    spacing: 3

                    Row {
                        width: parent.width
                        spacing: 9

                        Text {
                            width: Math.min(implicitWidth,
                                parent.width - openLabel.width
                                - parent.spacing)
                            text: resultDelegate.model.display
                            color: launcher.primaryText
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
                        color: launcher.secondaryText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            Column {
                id: deviceChildren
                x: 56
                y: resultsArea.rowHeight
                width: parent.width - x - 12
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
                        color: resultDelegate.ListView.isCurrentItem && launcher.selectedChildKey === launcher.childKey(modelData)
                            ? tone.current : (childHover.hovered ? tone.hover : "transparent")
                        Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 2.5; color: launcher.secondaryText }
                        Text {
                            x: 27; width: parent.width - x - 12; height: parent.height
                            text: launcher.childLaunchFailed && launcher.selectedChildKey === launcher.childKey(childRow.modelData)
                                ? words.i18nc("a setting, then why it did not open", "%1 · Couldn't open settings—try again", childRow.modelData.label)
                                : childRow.modelData.status ? words.i18nc("a setting, then its state", "%1 · %2", childRow.modelData.label, childRow.modelData.status)
                                : childRow.modelData.label
                            font.pixelSize: 12; color: launcher.secondaryText
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                        }
                        HoverHandler { id: childHover }
                        TapHandler {
                            enabled: !launcher.guestDragged && !launcher.applicationLaunchPending
                            onPressedChanged: if (pressed) {
                                resultList.currentIndex = resultDelegate.index
                                launcher.searchResults.pinSelection(resultDelegate.index)
                                launcher.selectedChildKey = launcher.childKey(childRow.modelData)
                            }
                            onTapped: launcher.openChildSettings()
                        }
                    }
                }
            }
            Item {
            id: resultTarget
            width: parent.width
            height: resultsArea.rowHeight
            HoverHandler { id: hover }
            TapHandler {
                enabled: !launcher.guestDragged && !launcher.applicationLaunchPending
                longPressThreshold: 0.5
                onPressedChanged: {
                    if (pressed) {
                        launcher.selectedChildKey = ""
                        resultList.currentIndex = resultDelegate.index
                        launcher.searchResults.pinSelection(resultDelegate.index)
                    }
                }
                onTapped: {
                    launcher.runResult(launcher.searchResults.selectedRow())
                }
                onLongPressed: launcher.showResultSheet(resultDelegate.index, resultTarget, point.position)
            }
            TapHandler {
                enabled: !launcher.guestDragged && !launcher.applicationLaunchPending
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                acceptedButtons: Qt.RightButton
                onTapped: eventPoint => launcher.showResultSheet(resultDelegate.index, resultTarget, eventPoint.position)
            }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: query.text.length > 0
            && !launcher.searchResults.querying
            && resultList.count === 0
            && !askAnswer.visible
        objectName: "web-fallback"
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: launcher.submit()
        text: words.i18n("Search the web for “%1”", query.text)
        color: launcher.secondaryText
        font.pixelSize: 15
        width: parent.width - 28
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        TapHandler { onTapped: launcher.submit() }
    }
}
