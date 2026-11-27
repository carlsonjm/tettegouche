/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The shade of a raised key or the field drawn again over its inside with a
// fine grain: every dot of the screen nudged at random by up to a step
// lighter or darker, the same on red, green and blue, so the few greys
// between its top and bottom blend into one even fade and no row is one
// flat grey. The shades stay the same; only the steps go. One grain dot is
// one dot of the screen, never stretched.
Item {
    id: grain
    // The shade at the top and bottom of the whole key, and how tall the key
    // is, which this sits inside.
    property color upper
    property color lower
    property real keyHeight: height
    // How far down the key this starts, and how round its ends are.
    property real topInset: 0
    property real round: height / 2
    // The widest the key can become, so growing or gliding never draws it
    // again.
    property real widest: width
    readonly property real dots: Math.max(1, Screen.devicePixelRatio)
    // The ends, each on a whole dot of the screen.
    readonly property real endWidth: Math.min(width / 2, Math.ceil(round * dots) / dots)
    visible: !Qt.colorEqual(upper, lower) && width > 0 && height > 1
    // Drawn only once the window has shown its first frame, then faded in,
    // so the grain never holds Search back from opening: painting it takes
    // tens of milliseconds in a fresh process.
    property bool armed: false
    opacity: armed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Connections {
        target: grain.Window.window
        enabled: !grain.armed
        function onFrameSwapped() { grain.armed = true }
    }
    Component.onCompleted: if (!Window.window) armed = true

    // Draws the grain on one canvas, inside the rounded shape set by
    // shapeX and shapeWidth, row by row of the screen's dots.
    function paint(canvas, shapeX, shapeWidth) {
        const ctx = canvas.getContext("2d")
        ctx.reset()
        if (!armed || !visible || canvas.width < 1 || canvas.height < 1) return
        if (shapeWidth > 0) {
            ctx.beginPath()
            ctx.roundedRect(shapeX, 0, shapeWidth, canvas.height, round, round)
            ctx.clip()
        }
        ctx.scale(1 / dots, 1 / dots)
        const w = Math.ceil(canvas.width * dots), h = Math.ceil(canvas.height * dots)
        let seed = 0x2545f491 ^ (w * 131 + Math.round(shapeX))
        const draw = () => {
            seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5
            return (seed & 0xffff) / 65536
        }
        for (let y = 0; y < h; ++y) {
            const t = Math.min(1, (topInset + (y + 0.5) / dots) / keyHeight)
            const c = [upper.r + (lower.r - upper.r) * t, upper.g + (lower.g - upper.g) * t,
                       upper.b + (lower.b - upper.b) * t].map(v => 255 * v)
            const level = (c[0] + c[1] + c[2]) / 3
            const base = Math.round(level)
            // The same nudge on red, green and blue, so the grain is grey.
            const v = c.map(x => Math.round(x - level + base) / 255)
            const tones = [-1, 0, 1].map(d => Qt.rgba(v[0] + d / 255, v[1] + d / 255, v[2] + d / 255, 1))
            ctx.fillStyle = tones[1]
            ctx.fillRect(0, y, w, 1)
            // The dots a step up, and those a step down, each gathered into
            // one shape and filled at once.
            const ups = [], downs = []
            let run = 0, from = 0
            for (let x = 0; x <= w; ++x) {
                const d = x < w ? Math.round(level + draw() + draw() - 1) - base : 0
                if (d !== run) {
                    if (run !== 0) (run > 0 ? ups : downs).push(from, x - from)
                    run = d
                    from = x
                }
            }
            for (const [list, tone] of [[ups, tones[2]], [downs, tones[0]]]) {
                if (!list.length) continue
                ctx.beginPath()
                for (let i = 0; i < list.length; i += 2) ctx.rect(list[i], y, list[i + 1], 1)
                ctx.fillStyle = tone
                ctx.fill()
            }
        }
    }

    component Piece: Canvas {
        property real shapeX: 0
        property real shapeWidth: 0
        smooth: false
        onPaint: grain.paint(this, shapeX, shapeWidth)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: grain
            function onUpperChanged() { requestPaint() }
            function onLowerChanged() { requestPaint() }
            function onVisibleChanged() { requestPaint() }
            function onDotsChanged() { requestPaint() }
            function onKeyHeightChanged() { requestPaint() }
            function onRoundChanged() { requestPaint() }
            function onArmedChanged() { requestPaint() }
        }
    }

    // The body, drawn once at the widest the key can be and only
    // uncovered as the key grows or shrinks; its far end is drawn apart and
    // rides the key's edge, on a whole dot of the screen.
    Item {
        width: Math.max(0, grain.width - grain.endWidth)
        height: grain.height
        clip: true
        Piece {
            width: Math.max(grain.width, grain.widest)
            height: grain.height
            shapeX: 0
            shapeWidth: width
        }
    }
    Piece {
        x: Math.floor((grain.width - grain.endWidth) * grain.dots) / grain.dots
        width: grain.width - x
        height: grain.height
        shapeX: width - 4 * grain.round
        shapeWidth: 4 * grain.round
    }
}
