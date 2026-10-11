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

    // Anything typed that nothing else takes goes into search.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && filter.text.length > 0) {
            filter.text = ""
            event.accepted = true
            return
        }
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter
                && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab
                && !filter.activeFocus && event.text.length > 0
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            filter.forceActiveFocus()
            filter.insert(filter.cursorPosition, event.text)
            event.accepted = true
        }
    }

    // The order on search's left and the eye inside it, by its search icon,
    // search centred.
    Item {
        id: header
        objectName: "files-window-header"
        x: window.contentInset
        y: 14
        width: window.width - 2 * window.contentInset
        height: 44
        readonly property real flankWidth: sort.width + 4
        readonly property real fieldWidth: Math.max(160,
            Math.min(width - 2 * flankWidth, Math.max(360, width / 2)))

        Item {
            id: eye
            objectName: "files-window-hidden"
            readonly property bool showing: !!window.fileBrowser && window.fileBrowser.hidden
            x: field.x + field.width - 9 - clear.width - width
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

        Rectangle {
            id: field
            objectName: "files-window-search"
            x: (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: header.fieldWidth
            height: 44
            radius: height / 2
            color: filter.activeFocus || filter.text.length > 0 ? tone.control : "transparent"
            border.width: 1
            border.color: tone.outline
            Behavior on color { ColorAnimation { duration: window.ms(150); easing.type: Easing.OutCubic } }

            TextInput {
                id: filter
                objectName: "files-window-query"
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.right: clear.left
                anchors.rightMargin: 10 + 42
                anchors.verticalCenter: parent.verticalCenter
                color: tone.primaryText
                selectionColor: tone.selection
                selectedTextColor: tone.selectedText
                font.pixelSize: 16
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.name: words.i18n("Search this folder")
                onTextChanged: if (window.fileBrowser) window.fileBrowser.filter = text
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filter.text.length === 0
                    text: words.i18n("Just type")
                    color: tone.placeholderText
                    font.pixelSize: 16
                }
            }
            Item {
                id: clear
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                Accessible.role: Accessible.Button
                Accessible.name: filter.text.length > 0 ? words.i18n("Clear search") : words.i18n("Search")
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: filter.text.length > 0 ? "edit-clear-symbolic" : "system-search"
                    color: tone.primaryText
                }
                TapHandler {
                    onTapped: {
                        filter.text = ""
                        filter.forceActiveFocus()
                    }
                }
            }
        }

        // The order, a grey pill naming it, as in Search; Recent keeps the
        // order of use.
        Item {
            id: sort
            objectName: "files-window-sort"
            readonly property bool fixed: !!window.fileBrowser && window.fileBrowser.placeKind === "recent"
            x: field.x - 4 - width
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(42, sortLabel.implicitWidth + 46)
            height: 42
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: words.i18n("Sort: %1", sortLabel.text)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 30
                radius: height / 2
                color: sortPress.pressed || sortMenu.visible ? tone.controlPressed
                    : sortHover.hovered ? tone.controlHover : tone.control
                Behavior on color { ColorAnimation { duration: window.ms(90) } }
                Text {
                    id: sortLabel
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    text: sort.fixed ? words.i18n("Recent") : [words.i18n("Name A–Z"), words.i18n("Name Z–A"), words.i18n("Newest"), words.i18n("Largest")][window.fileBrowser ? window.fileBrowser.sortMode : 0]
                    color: tone.primaryText
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
                onClicked: sortMenu.openUnder(sort)
            }
            SheetMenu {
                id: sortMenu
                objectName: "files-window-sort-menu"
                bounds: window
                readonly property int mode: window.fileBrowser ? window.fileBrowser.sortMode : 0
                SheetMenuItem { text: words.i18n("Name A–Z"); checkable: true; checked: sortMenu.mode === 0; enabled: !sort.fixed; onTriggered: window.fileBrowser.sortMode = 0 }
                SheetMenuItem { text: words.i18n("Name Z–A"); checkable: true; checked: sortMenu.mode === 1; enabled: !sort.fixed; onTriggered: window.fileBrowser.sortMode = 1 }
                SheetMenuItem { text: words.i18n("Newest first"); checkable: true; checked: sortMenu.mode === 2; enabled: !sort.fixed; onTriggered: window.fileBrowser.sortMode = 2 }
                SheetMenuItem { text: words.i18n("Largest first"); checkable: true; checked: sortMenu.mode === 3; enabled: !sort.fixed; onTriggered: window.fileBrowser.sortMode = 3 }
            }
        }
    }

    FilesPane {
        id: pane
        objectName: "files-window-pane"
        browser: window.fileBrowser
        carryArea: window
        x: window.contentInset
        y: header.y + header.height + 16
        width: window.width - 2 * window.contentInset
        height: Math.max(0, window.height - y - window.contentInset)
        onCarryOut: paths => window.launcherController.carryOut(paths, Qt.rect(0, 0, window.width, window.height))
    }
}
