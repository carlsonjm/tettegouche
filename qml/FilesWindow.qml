/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

// Files in a window of its own, as Pop out leaves it: the same Files, with
// its tabs and folder as they were, under the header Files has in Search,
// less Back and the corner, whose work the window's own title bar does.
Rectangle {
    id: window
    required property var fileBrowser
    required property var launcherController
    // Esc with nothing left to clear; the window closes, as its title bar's
    // close does.
    signal dismissed()
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
    readonly property int contentInset: 22
    color: tone.surface
    focus: true

    SearchColors {
        id: tone
        theme: window.Kirigami.Theme
    }
    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }

    // Search narrows the folder, as it does in Search; what was typed there
    // comes along.
    Component.onCompleted: filter.text = window.fileBrowser ? window.fileBrowser.filter : ""
    Connections {
        target: window.fileBrowser
        ignoreUnknownSignals: true
        function onFolderCreated() { filter.text = "" }
        function onFilterCleared() { filter.text = "" }
    }

    // Anything typed that nothing else takes goes into search. Esc clears
    // search, and with nothing typed closes the window, as it closes Files in
    // Search; a key that writes no character never goes in.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (filter.text.length > 0) filter.text = ""
            else window.dismissed()
            event.accepted = true
            return
        }
        if (!filter.activeFocus && event.text.length > 0
                && event.text.charCodeAt(0) >= 32 && event.text !== "\x7f"
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            filter.forceActiveFocus()
            filter.insert(filter.cursorPosition, event.text)
            event.accepted = true
        }
    }

    // Search centred, with the eye inside it by its search icon; the order
    // sits beside New folder, below.
    Item {
        id: header
        objectName: "files-window-header"
        x: window.contentInset
        y: 14
        width: window.width - 2 * window.contentInset
        height: 44
        readonly property real fieldWidth: Math.max(160, Math.min(width, Math.max(360, width / 2)))

        Item {
            id: eye
            objectName: "files-window-hidden"
            readonly property bool showing: !!window.fileBrowser && window.fileBrowser.hidden
            x: field.x + field.width - 8 - clear.width - width
            z: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 42
            Accessible.role: Accessible.CheckBox
            Accessible.name: words.i18n("Show hidden files")
            Accessible.checked: showing
            Accessible.onPressAction: window.fileBrowser.hidden = !window.fileBrowser.hidden
            Rectangle {
                anchors.centerIn: parent
                width: 30
                height: 30
                radius: height / 2
                color: eyePress.pressed ? tone.controlPressed
                    : eye.showing ? tone.controlHover
                    : eyeHover.hovered ? tone.control : "transparent"
                Behavior on color { ColorAnimation { duration: window.ms(90) } }
            }
            SuiteIcon {
                anchors.centerIn: parent
                glyph: eye.showing ? "eye" : "eye-off"
                width: 18
                height: 18
            }
            HoverHandler {
                id: eyeHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            }
            MouseArea {
                id: eyePress
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: window.fileBrowser.hidden = !window.fileBrowser.hidden
            }
        }

        // Search's own field: the same pill, glyph, inset and words as in
        // Search, so moving between them nothing shifts.
        Rectangle {
            id: field
            objectName: "files-window-search"
            readonly property bool lit: filter.activeFocus || filter.text.length > 0
            x: (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: header.fieldWidth
            height: 44
            radius: height / 2
            color: tone.control
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: tone.dark ? "#14ffffff" : "#0d000000"
                opacity: field.lit ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: window.ms(150) } }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 3
                border.color: Qt.rgba(tone.focusRing.r, tone.focusRing.g, tone.focusRing.b, 0.16)
                opacity: field.lit ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: window.ms(150) } }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(tone.focusRing.r, tone.focusRing.g, tone.focusRing.b, 0.55)
                }
            }
            SuiteIcon {
                id: filterGlyph
                glyph: "search"
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                opacity: field.lit ? 0.9 : 0.55
                Behavior on opacity { NumberAnimation { duration: window.ms(150) } }
            }

            TextInput {
                id: filter
                objectName: "files-window-query"
                anchors.left: filterGlyph.right
                anchors.leftMargin: 12
                anchors.right: clear.left
                anchors.rightMargin: 12 + 42
                anchors.verticalCenter: parent.verticalCenter
                color: tone.primaryText
                selectionColor: tone.selection
                selectedTextColor: tone.selectedText
                font.pixelSize: 16
                font.weight: Font.Medium
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.name: words.i18n("Find a file")
                onTextChanged: if (window.fileBrowser) window.fileBrowser.filter = text
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filter.text.length === 0
                    text: words.i18n("Find a file")
                    color: tone.placeholderText
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
            }
            Item {
                id: clear
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                visible: filter.text.length > 0
                Accessible.role: Accessible.Button
                Accessible.name: words.i18n("Clear search")
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
                        filter.text = ""
                        filter.forceActiveFocus()
                    }
                }
            }
        }
    }

    FilesPane {
        id: pane
        objectName: "files-window-pane"
        browser: window.fileBrowser
        // A narrow window folds the places as a card does.
        card: window.width < 900
        carryArea: window
        x: window.contentInset
        y: header.y + header.height + 16
        width: window.width - 2 * window.contentInset
        height: Math.max(0, window.height - y - window.contentInset)
        onCarryOut: paths => window.launcherController.carryOut(paths, Qt.rect(0, 0, window.width, window.height), window.fileBrowser)
    }
}
