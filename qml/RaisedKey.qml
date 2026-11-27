/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The raised key Search marks what is chosen with, as under the mode shown,
// and the field is made of: one flat fill; one fine edge, lit along the top
// and fading out toward the bottom, so it turns round the ends with no join.
// It casts no shadow. It fades in and out where it is.
Item {
    id: key
    required property SearchColors tone
    // Whether it shows.
    property bool shown: true
    property real radius: height / 2
    property color fill: tone.modeKey
    property color edge: tone.modeKeyEdge
    // How long it takes to fade, at Plasma's animation speed.
    property int fadeDuration: 120
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: key.fadeDuration; easing.type: Easing.OutCubic } }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: key.radius
        color: key.fill
        Behavior on color { ColorAnimation { duration: key.fadeDuration } }
    }
    // The edge, one line all round: lit along the top, half the plain edge
    // at mid-height, fading out toward the bottom, so the rim
    // turns down round the ends with no join.
    Canvas {
        id: rim
        anchors.fill: parent
        readonly property color lit: key.tone.keyRim
        readonly property color plain: key.edge
        onLitChanged: requestPaint()
        onPlainChanged: requestPaint()
        Connections { target: key.tone; function onDarkChanged() { rim.requestPaint() } }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width < 2 || height < 2) return
            const shade = ctx.createLinearGradient(0, 0, 0, height)
            shade.addColorStop(0, lit)
            // On a light ground the edge alone sets a white key apart, so
            // it stays whole there.
            const dark = key.tone.dark
            shade.addColorStop(0.5, Qt.rgba(plain.r, plain.g, plain.b, plain.a * (dark ? 0.5 : 1)))
            shade.addColorStop(1, Qt.rgba(plain.r, plain.g, plain.b, dark ? 0 : plain.a))
            ctx.strokeStyle = shade
            ctx.lineWidth = 1
            const r = Math.min(key.radius, height / 2) - 0.5
            ctx.beginPath()
            ctx.roundedRect(0.5, 0.5, width - 1, height - 1, r, r)
            ctx.stroke()
        }
    }
}
