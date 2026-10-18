/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

// The Tette Dot. At rest it is a solid 20 px disc; open, its middle clears
// from the centre out as it grows, until it is a 28 px ring with a 2 px edge.
// It is the mark alone, with nothing drawn behind or around it, and the same
// in the panel and in Search. While something is loading the ring dims and a
// quarter of it turns. Whatever the dot is given as children sits in the
// ring's middle once the ring has formed; with nothing to hold there, a new
// small dot grows in the middle instead, so the open dot never reads empty.
Item {
    id: dot

    // 0 solid, 1 a ring.
    property real openness: 0
    property bool loading: false
    // Ghost White lit from above on the dark band, or one flat ink.
    property bool pearl: true
    property color ink: "#F8F8FF"
    // A loop of the turning quarter, in ms.
    property int turnMs: 1000
    default property alias middle: centre.data
    // Whether the middle holds the new small dot rather than a mark.
    property bool seed: true
    // Plasma's animation speed, as a factor of the default.
    property real speed: 1

    readonly property real restSize: 20
    readonly property real openSize: 28
    readonly property real edge: 2
    readonly property real outer: (restSize + (openSize - restSize) * openness) / 2
    // The hole reaches the ring's edge exactly as the dot reaches its size,
    // so the edge is the same width the whole way and nothing jumps.
    readonly property real inner: (openSize / 2 - edge) * openness

    implicitWidth: openSize
    implicitHeight: openSize

    Shape {
        objectName: "dotMarkFace"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: dot.loading ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillColor: dot.ink
            fillGradient: dot.pearl ? pearlFill : null

            PathAngleArc {
                centerX: dot.width / 2
                centerY: dot.height / 2
                radiusX: dot.outer
                radiusY: dot.outer
                startAngle: 0
                sweepAngle: 360
                moveToStart: true
            }
            PathAngleArc {
                centerX: dot.width / 2
                centerY: dot.height / 2
                radiusX: dot.inner < 0.25 ? 0 : dot.inner
                radiusY: dot.inner < 0.25 ? 0 : dot.inner
                startAngle: 0
                sweepAngle: 360
                moveToStart: true
            }
        }
    }

    LinearGradient {
        id: pearlFill
        x1: 0
        y1: dot.height / 2 - dot.outer
        x2: 0
        y2: dot.height / 2 + dot.outer
        GradientStop { position: 0; color: "#FFFFFF" }
        GradientStop { position: 0.55; color: "#F4F4FA" }
        GradientStop { position: 1; color: "#DCDCE4" }
    }

    // Loading: a quarter of the ring, lit, going round.
    Shape {
        objectName: "dotMarkLoading"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: dot.loading
        RotationAnimator on rotation {
            running: dot.loading && dot.visible
            from: 0
            to: 360
            duration: dot.turnMs
            loops: Animation.Infinite
        }

        ShapePath {
            strokeWidth: dot.edge
            strokeColor: dot.ink
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: dot.width / 2
                centerY: dot.height / 2
                radiusX: dot.openSize / 2 - dot.edge / 2
                radiusY: dot.openSize / 2 - dot.edge / 2
                startAngle: -90
                sweepAngle: 90
                moveToStart: true
            }
        }
    }

    // The new dot: it grows once the ring has formed, and goes at once as the
    // ring starts to fill back.
    Rectangle {
        id: seedDot
        objectName: "dotMarkSeed"
        antialiasing: true
        anchors.centerIn: parent
        readonly property real grown: dot.seed && !dot.loading && dot.openness > 0.98 ? 1 : 0
        property real shown: grown
        Behavior on shown {
            enabled: seedDot.shown < seedDot.grown
            NumberAnimation { duration: Math.max(1, Math.round(240 * dot.speed)); easing.type: Easing.OutCubic }
        }
        width: 12 * shown
        height: width
        radius: width / 2
        visible: shown > 0
        color: dot.ink
        gradient: dot.pearl ? seedFill : null
        Gradient {
            id: seedFill
            GradientStop { position: 0; color: "#FFFFFF" }
            GradientStop { position: 0.55; color: "#F4F4FA" }
            GradientStop { position: 1; color: "#DCDCE4" }
        }
    }

    Item {
        id: centre
        objectName: "dotMarkMiddle"
        anchors.centerIn: parent
        width: dot.openSize - 2 * dot.edge
        height: width
        opacity: dot.loading ? 0 : Math.max(0, dot.openness * 2 - 1)
        visible: opacity > 0
    }
}
