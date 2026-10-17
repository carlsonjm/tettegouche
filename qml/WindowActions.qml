/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

// The window's buttons, at the right of Search's row of modes (and of Notes'
// own header): Expand, which grows Search to fill the screen and brings it back, Pop out,
// which gives what is open a window of its own, and Close, which puts Search
// away, last as a window's is. All are round, 30 in a 42 touch, as the eye is.
Row {
    id: actions
    // Names each button for tests and tools: "<prefix>-expand",
    // "<prefix>-pop-out", "<prefix>-close".
    property string prefix: ""
    property bool expanded: false
    property bool expandShown: true
    property bool popOutShown: true
    // What Pop out opens, said to a screen reader.
    property string popOutName: words.i18n("Open in its own window")
    signal expand()
    signal popOut()
    signal dismiss()
    spacing: 4

    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }
    Corner {
        objectName: actions.prefix + "-expand"
        visible: actions.expandShown
        glyph: actions.expanded ? "minimize-2" : "maximize-2"
        name: actions.expanded ? words.i18n("Make smaller") : words.i18n("Expand")
        onActivated: actions.expand()
    }
    Corner {
        objectName: actions.prefix + "-pop-out"
        visible: actions.popOutShown
        glyph: "square-arrow-out-up-right"
        name: actions.popOutName
        onActivated: actions.popOut()
    }
    Corner {
        objectName: actions.prefix + "-close"
        glyph: "x"
        name: words.i18n("Close Search")
        onActivated: actions.dismiss()
    }

    component Corner: Item {
        id: corner
        property string glyph
        property string name
        signal activated()
        // A duration at Plasma's animation speed: 1 ms when it is instant.
        function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
        width: 42
        height: 42
        activeFocusOnTab: true
        SearchColors {
            id: cornerTone
            theme: corner.Kirigami.Theme
        }
        Accessible.role: Accessible.Button
        Accessible.name: corner.name
        Accessible.onPressAction: corner.activated()
        Keys.onReturnPressed: corner.activated()
        Keys.onEnterPressed: corner.activated()
        Keys.onSpacePressed: corner.activated()
        Rectangle {
            anchors.centerIn: parent
            width: 30
            height: 30
            radius: height / 2
            color: press.pressed ? cornerTone.controlPressed
                : hover.hovered || corner.activeFocus ? cornerTone.controlHover : "transparent"
            Behavior on color { ColorAnimation { duration: corner.ms(90) } }
        }
        SuiteIcon {
            anchors.centerIn: parent
            glyph: corner.glyph
            width: 18
            height: 18
        }
        HoverHandler {
            id: hover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        }
        MouseArea {
            id: press
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: corner.activated()
        }
    }
}
