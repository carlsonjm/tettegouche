/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The suite's grey pill inside Search's modes: 30 high in a 42 touch in the
// header, 44 below; the light one for the main action.
Item {
    id: pill
    property string label
    property string glyph: ""
    property bool tall: false
    property bool light: false
    property bool dimmed: false
    property color primaryText: "#f2ffffff"
    property color surfaceColor: "#141414"
    property color controlColor: "#242424"
    signal activated()
    width: pillRow.implicitWidth + (tall ? 36 : 28)
    height: tall ? 44 : 42
    opacity: dimmed ? 0.45 : 1
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: pill.activated()
    Keys.onReturnPressed: pill.activated()
    Keys.onEnterPressed: pill.activated()
    Keys.onSpacePressed: pill.activated()
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: pill.tall ? 44 : 30
        radius: height / 2
        scale: pillTap.pressed ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        color: pill.light ? (pillTap.pressed ? "#d8d8de" : pill.primaryText)
            : pillTap.pressed ? "#4A4A4A" : pillHover.hovered ? "#333333" : pill.controlColor
        Behavior on color { ColorAnimation { duration: 90 } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            SuiteIcon {
                visible: pill.glyph !== ""
                glyph: pill.glyph === "" ? "circle" : pill.glyph
                width: 14
                height: 14
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: pill.label
                color: pill.light ? pill.surfaceColor : pill.primaryText
                font.pixelSize: pill.tall ? 14 : 13
                font.weight: pill.light ? Font.Black : Font.Normal
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
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
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: pill.activated()
    }
}
