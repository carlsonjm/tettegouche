/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

// The raised key Search marks what is chosen with, as under the mode shown,
// and the field is made of: one flat fill with a fine edge, a lit rim along
// its top, and a wide soft shadow pulled in under it, whose far fade alone
// shows past the key, with no line beneath it. It fades in and out where it is.
Item {
    id: key
    required property SearchColors tone
    // Whether it shows.
    property bool shown: true
    property real radius: height / 2
    property color fill: tone.modeKey
    property color edge: tone.modeKeyEdge
    // How far it is lifted, 0 to 1: a deeper, wider shadow.
    property real lift: 0
    // How far the shape casting the shadow sits inside the key's edge.
    property real shadowInset: Math.min(10, height / 4)
    // How long it takes to fade, at Plasma's animation speed.
    property int fadeDuration: 120
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: key.fadeDuration; easing.type: Easing.OutCubic } }

    // The shadow: cast by a shape drawn smaller than the key and hidden
    // under it, blurred wide, so only its far fade reaches out past the
    // key's edge, and never a dark line along it.
    Rectangle {
        anchors.fill: parent
        anchors.margins: key.shadowInset
        anchors.topMargin: key.shadowInset + 2 + 2 * key.lift
        anchors.bottomMargin: key.shadowInset - 4 - 2 * key.lift
        radius: Math.max(0, key.radius - key.shadowInset)
        color: key.tone.modeKeyShadow
        layer.enabled: key.visible
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blurMax: 32
            blur: 1
        }
        opacity: 0.75 + 0.25 * key.lift
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: face
            anchors.fill: parent
            radius: key.radius
            border.width: 1
            border.color: key.edge
            color: key.fill
            Behavior on color { ColorAnimation { duration: key.fadeDuration } }
            Behavior on border.color { ColorAnimation { duration: key.fadeDuration } }
            // The lit rim: the edge's upper half a little brighter.
            Item {
                width: parent.width
                height: Math.max(1, Math.min(parent.height / 2, key.radius + 2))
                clip: true
                Rectangle {
                    width: face.width
                    height: face.height
                    radius: face.radius
                    color: "transparent"
                    border.width: 1
                    border.color: key.tone.keyRim
                }
            }
        }
    }
}
