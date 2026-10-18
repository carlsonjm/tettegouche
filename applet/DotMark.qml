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

    // The face: a disc whose edge thickens inward to fill it at rest and
    // thins to the ring's edge as it opens. The scene graph smooths a
    // rectangle's rounded edge at any scale, where a path showed steps.
    Item {
        objectName: "dotMarkFace"
        anchors.fill: parent
        opacity: dot.loading ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.centerIn: parent
            width: 2 * dot.outer
            height: width
            radius: width / 2
            antialiasing: true
            color: "transparent"
            border.width: dot.outer - dot.inner
            border.color: dot.pearl ? "#F4F4FA" : dot.ink
        }
        // At rest the pearl is lit from above and a shade deeper toward its
        // lower edge; that light fades as the middle starts to clear.
        Rectangle {
            anchors.centerIn: parent
            width: 2 * dot.outer
            height: width
            radius: width / 2
            antialiasing: true
            opacity: Math.max(0, 1 - dot.openness * 4)
            visible: dot.pearl && opacity > 0
            gradient: Gradient {
                GradientStop { position: 0; color: "#FFFFFF" }
                GradientStop { position: 0.55; color: "#F4F4FA" }
                GradientStop { position: 1; color: "#DCDCE4" }
            }
        }
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

    // The new dot: it grows from nothing once the ring has formed, and goes
    // at once as the ring starts to fill back.
    Rectangle {
        id: seedDot
        objectName: "dotMarkSeed"
        readonly property bool grown: dot.seed && !dot.loading && dot.openness > 0.98
        property real shown: 0
        onGrownChanged: {
            seedGrowth.stop()
            if (grown) seedGrowth.start()
            else shown = 0
        }
        Component.onCompleted: shown = grown ? 1 : 0
        NumberAnimation {
            id: seedGrowth
            target: seedDot
            property: "shown"
            from: 0
            to: 1
            duration: Math.max(1, Math.round(240 * dot.speed))
            easing.type: Easing.OutCubic
        }
        antialiasing: true
        anchors.centerIn: parent
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
