/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

// The raised key under the mode shown, made again wherever Search marks what
// is chosen, as under the chosen result: lighter at its top edge, with a
// hairline and the same soft shadow. It fades in and out where it is.
Item {
    id: key
    required property SearchColors tone
    // Whether it shows.
    property bool shown: true
    property real radius: height / 2
    // How long it takes to fade, at Plasma's animation speed.
    property int fadeDuration: 120
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: key.fadeDuration; easing.type: Easing.OutCubic } }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: key.radius
        border.width: 1
        border.color: key.tone.modeKeyEdge
        gradient: Gradient {
            GradientStop { position: 0; color: key.tone.modeKeyTop }
            GradientStop { position: 1; color: key.tone.modeKeyBottom }
        }
        // Its shade drawn again with a fine grain, so no lines show between
        // its greys. Drawn once the key has come to rest under a row, so
        // moving through rows stays quick; the grain is too fine to be seen
        // arriving.
        Timer {
            id: settle
            interval: 160
            running: key.shown
        }
        Loader {
            anchors.fill: parent
            anchors.margins: 1
            active: key.shown && key.visible && !settle.running
            sourceComponent: GrainFill {
                upper: key.tone.modeKeyTop
                lower: key.tone.modeKeyBottom
                keyHeight: face.height
                topInset: 1
                round: Math.max(0, Math.min(key.radius, face.height / 2) - 1)
            }
        }
        // As the mode highlight's: a soft, blurred shadow that fades out
        // all round, with no hard line beneath it.
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: key.tone.modeKeyShadow
            shadowBlur: 0.45
            shadowOpacity: 0.6
            shadowVerticalOffset: 1
        }
    }
}
