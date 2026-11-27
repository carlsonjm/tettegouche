/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

// The raised key Search marks what is chosen with, as under the mode shown,
// and the field is made of: one flat fill with a fine edge, a lit rim along
// its top, and two shadows, a soft one close under it and a wide, faint one
// that fades out all round, so it lifts off the sheet with no hard line
// beneath it. It fades in and out where it is.
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
    // How long it takes to fade, at Plasma's animation speed.
    property int fadeDuration: 120
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: key.fadeDuration; easing.type: Easing.OutCubic } }

    // The wide shadow, round the key and its close one.
    Item {
        anchors.fill: parent
        layer.enabled: key.visible
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: key.tone.modeKeyShadow
            blurMax: 48
            shadowBlur: 1
            shadowOpacity: 0.42 + 0.2 * key.lift
            shadowVerticalOffset: 4 + 2 * key.lift
        }

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
            layer.enabled: key.visible
            layer.effect: MultiEffect {
                autoPaddingEnabled: true
                shadowEnabled: true
                shadowColor: key.tone.modeKeyShadow
                blurMax: 8
                shadowBlur: 0.6
                shadowOpacity: 0.55
                shadowVerticalOffset: 1
            }
        }
    }
}
