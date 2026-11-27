/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects

// The raised key Search marks what is chosen with, as under the mode shown,
// and the field is made of: one flat fill; one fine edge, lit along the top
// and fading out toward the bottom, so it turns round the ends with no join;
// and a wide soft shadow cast from inside it, whose far fade alone shows
// past the key. It fades in and out where it is.
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
    property real shadowInset: Math.min(4, height / 8)
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
        anchors.topMargin: key.shadowInset + 4
        anchors.bottomMargin: -2 * key.lift
        radius: Math.max(0, key.radius - key.shadowInset)
        color: key.tone.keyCast
        layer.enabled: key.visible
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blurMax: 48
            blur: 1
        }
        opacity: 0.7 + 0.15 * key.lift
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: key.radius
        color: key.fill
        Behavior on color { ColorAnimation { duration: key.fadeDuration } }
    }
    // The edge, one line all round: lit along the top, the plain edge from
    // halfway down, fading out toward the shadow below, so the rim
    // turns down round the ends with no join.
    Canvas {
        id: rim
        anchors.fill: parent
        readonly property color lit: key.tone.keyRim
        readonly property color plain: key.edge
        onLitChanged: requestPaint()
        onPlainChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width < 2 || height < 2) return
            const shade = ctx.createLinearGradient(0, 0, 0, height)
            shade.addColorStop(0, lit)
            shade.addColorStop(0.5, plain)
            shade.addColorStop(1, Qt.rgba(plain.r, plain.g, plain.b, 0))
            ctx.strokeStyle = shade
            ctx.lineWidth = 1
            const r = Math.min(key.radius, height / 2) - 0.5
            ctx.beginPath()
            ctx.roundedRect(0.5, 0.5, width - 1, height - 1, r, r)
            ctx.stroke()
        }
    }
}
