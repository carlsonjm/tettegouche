/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtCore

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
    // Whether it shows now. One hidden this way keeps its grain, drawn, for
    // when it shows again.
    property bool shown: true
    property real arrival: armed ? 1 : 0
    Behavior on arrival { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    opacity: shown ? arrival : 0
    Connections {
        target: grain.Window.window
        enabled: !grain.armed
        function onFrameSwapped() { grain.armed = true }
    }
    Component.onCompleted: if (!Window.window) armed = true
    // Where the drawn grain is kept between starts.
    readonly property string cacheFolder: {
        const folder = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString()
        return folder.replace(/^file:\/\//, "")
    }

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

    // One piece of the grain: drawn once on a canvas and kept as a picture
    // in the cache, which Search shows from then on. A canvas's drawing is
    // lost whenever the window gives back what it draws with, as it may
    // when hidden; a picture is shown again from the file, and the next
    // start draws nothing at all.
    component Piece: Item {
        id: piece
        property real shapeX: 0
        property real shapeWidth: 0
        readonly property string file: !grain.armed || !grain.visible || width < 1 || height < 1 ? ""
            : grain.cacheFolder + "/tettegouche-grain-" + Qt.md5([grain.upper, grain.lower, grain.keyHeight, grain.topInset,
                grain.round, grain.dots, width, height, shapeX, shapeWidth].join("|")) + ".png"
        // Where the picture could not be kept, the canvas shows instead.
        property bool unsaved: false
        Image {
            id: picture
            anchors.fill: parent
            smooth: false
            cache: false
            source: piece.file && !piece.unsaved ? "file://" + piece.file : ""
            onStatusChanged: if (status === Image.Error) painter.active = true
        }
        Loader {
            id: painter
            anchors.fill: parent
            active: false
            sourceComponent: Canvas {
                id: drawing
                smooth: false
                // Saving the picture reports it painted again; only the first
                // report saves.
                property bool saving: false
                // Drawn unseen behind the picture, unless it cannot be kept.
                opacity: piece.unsaved ? 1 : 0
                Component.onCompleted: requestPaint()
                onPaint: grain.paint(this, piece.shapeX, piece.shapeWidth)
                onPainted: {
                    if (piece.unsaved || saving) return
                    const kept = piece.file
                    if (!kept) return
                    saving = true
                    const ok = save(kept)
                    if (ok) {
                        picture.source = ""
                        picture.source = "file://" + kept
                        Qt.callLater(() => { painter.active = false })
                    } else {
                        piece.unsaved = true
                    }
                }
                Connections {
                    target: piece
                    function onFileChanged() { if (piece.file) { drawing.saving = false; drawing.requestPaint() } }
                }
            }
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
    // The far end is small and rides the key's edge as it grows, so it is
    // drawn on a canvas each time, and again as the window shows, which
    // may have lost it while hidden.
    Canvas {
        id: farEnd
        x: Math.floor((grain.width - grain.endWidth) * grain.dots) / grain.dots
        width: grain.width - x
        height: grain.height
        smooth: false
        onPaint: grain.paint(this, width - 4 * grain.round, 4 * grain.round)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: grain
            function onUpperChanged() { farEnd.requestPaint() }
            function onLowerChanged() { farEnd.requestPaint() }
            function onVisibleChanged() { farEnd.requestPaint() }
            function onDotsChanged() { farEnd.requestPaint() }
            function onKeyHeightChanged() { farEnd.requestPaint() }
            function onRoundChanged() { farEnd.requestPaint() }
            function onArmedChanged() { farEnd.requestPaint() }
        }
        Connections {
            target: grain.Window.window
            function onVisibleChanged() { if (grain.Window.window.visible) farEnd.requestPaint() }
        }
    }
}
