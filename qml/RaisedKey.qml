/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The raised key under the mode shown, made again wherever Search marks what
// is chosen, as under the chosen result: one even shade, its rim lit along
// the top, and no shadow. It fades in and out where it is.
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

    FlatKey {
        id: face
        anchors.fill: parent
        radius: key.radius
        fill: key.tone.modeKeyFill
        rimTop: key.tone.modeKeyRimTop
        rim: key.tone.modeKeyEdge
        // No shadow, and nothing drawn as Search opens.
    }
}
