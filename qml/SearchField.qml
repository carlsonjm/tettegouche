/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

Rectangle {
    id: searchField
    objectName: "search-field"
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item applicationGrid
    required property Loader filesLoader
    required property Item firstRow
    required property ListView resultList
    readonly property alias query: query
    readonly property alias trailingAction: trailingAction

    // Nothing typed and nothing found: the first screen.
    readonly property bool idle:
        query.text.length === 0
        && resultList.count === 0
        && !launcher.searchResults.querying
        && !launcher.applicationLaunchPending
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
    y: Math.round(restY * (1 - launcher.drawerProgress) * (1 - launcher.modeProgress))
    Behavior on y {
        enabled: (launcher.drawerProgress <= 0 || launcher.drawerProgress >= 1)
            && (launcher.modeProgress <= 0 || launcher.modeProgress >= 1)
        NumberAnimation { duration: launcher.ms(260); easing.type: Easing.OutCubic }
    }
    width: parent.width
    height: launcher.fieldHeight
    radius: height / 2
    color: launcher.controlColor
    opacity: (launcher.applicationLaunchPending ? 0 : 1)
        * Math.max(0, 1 - launcher.modeProgress * 2)
        * launcher.openingControls
    enabled: !launcher.applicationLaunchPending && !launcher.modeOpen

    // A hairline of light along its upper edge, as on a raised
    // key, and a ring that comes up while it holds the keys.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: tone.dark ? "#14ffffff" : "#0d000000"
        opacity: searchField.lit ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: launcher.ms(150) } }
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
        Behavior on opacity { NumberAnimation { duration: launcher.ms(150) } }
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
        enabled: launcher.modeProgress <= 0 || launcher.modeProgress >= 1
        NumberAnimation { duration: launcher.ms(140); easing.type: Easing.OutCubic }
    }

    SuiteIcon {
        id: searchGlyph
        glyph: "search"
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        opacity: (searchField.lit ? 0.9 : 0.55) * launcher.openingIcon
        Behavior on opacity { NumberAnimation { duration: launcher.ms(150) } }
    }

    // Clears what was typed; with nothing typed, a hint of what
    // Enter does takes its place.
    Item {
        id: trailingAction
        objectName: "search-clear"
        Accessible.role: Accessible.Button
        Accessible.name: words.i18n("Clear search")
        Accessible.onPressAction: { launcher.searchEngaged = true; query.text = ""; query.forceActiveFocus() }
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
                launcher.searchEngaged = true
                query.text = ""
                query.forceActiveFocus()
                launcher.launcherController.showInputMethod()
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
        anchors.rightMargin: 20 + (trailingAction.visible ? 36 : 0) + 42 * launcher.drawerProgress
        anchors.verticalCenter: parent.verticalCenter
        color: launcher.primaryText
        selectionColor: tone.selection
        selectedTextColor: tone.selectedText
        font.pixelSize: 16
        font.weight: Font.Medium
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText

        onTextChanged: {
            launcher.selectedChildKey = ""
            launcher.childLaunchFailed = false
            if (text.length > 0) {
                launcher.searchEngaged = true
            }
            launcher.pendingLaunch = false
            launcher.applicationCatalog.filterText = launcher.drawerOpen && !launcher.filesMode
                ? text : ""
            if (launcher.fileBrowser && launcher.filesMode) launcher.fileBrowser.filter = text
            launcher.searchResults.queryString = launcher.drawerOpen
                ? "" : text
            resultList.currentIndex = resultList.count > 0 ? 0 : -1
            resultList.settleAtBeginning()
            applicationGrid.reset()
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                launcher.searchEngaged = true
            }
        }

        Keys.onPressed: event => {
            if (launcher.drawerOpen && !launcher.filesMode && event.key === Qt.Key_Down
                    && applicationGrid.choices.length > 0) {
                applicationGrid.step(0, 1)
                event.accepted = true
            } else if (launcher.drawerOpen && !launcher.filesMode && event.key === Qt.Key_Up
                       && applicationGrid.choices.length > 0) {
                applicationGrid.step(0, -1)
                event.accepted = true
            } else if (launcher.drawerOpen && launcher.filesMode && event.key === Qt.Key_Down
                       && filesLoader.item) {
                // From the filter into the files: the keys move there.
                filesLoader.item.focusFiles()
                event.accepted = true
            } else if (event.key === Qt.Key_Down
                       && resultList.count > 0) {
                launcher.moveResultSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Up
                       && resultList.count > 0) {
                launcher.moveResultSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter) {
                launcher.submit()
                event.accepted = true
            }
        }

        Text {
            id: placeholder
            objectName: "just-type-placeholder"
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: query.text.length === 0
            text: launcher.drawerOpen
                ? (launcher.filesMode ? words.i18n("Find in Files") : words.i18n("Find an app"))
                : words.i18n("Just type")
            color: tone.placeholderText
            font.pixelSize: 15
            font.weight: Font.Medium
            opacity: launcher.openingText
            transform: Translate { y: (1 - launcher.openingText) * 3 }

            // A single soft light pass, clipped to copies of the
            // glyphs rather than a rectangle crossing the field.
            Repeater {
                model: 7
                delegate: Item {
                    required property int index
                    x: launcher.openingShine * (placeholder.implicitWidth + 35)
                        - 35 + index * 5
                    width: 5
                    height: placeholder.height
                    clip: true
                    visible: launcher.openingShine > 0 && launcher.openingShine < 1
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
        enabled: !launcher.guestDragged
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            launcher.searchEngaged = true
            query.forceActiveFocus()
            launcher.launcherController.showInputMethod()
        }
    }
}
