/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// A key's face drawn flat: one even shade, with a fine rim that is
// brightest along its top and settles to a quiet hairline by halfway down.
// One shade has nothing to step between, so no lines can show in it, and
// nothing is drawn as Search opens.
Item {
    id: flat
    property color fill
    // The rim along the top, and the hairline it settles to.
    property color rimTop
    property color rim
    property real radius: height / 2

    Rectangle {
        id: rimFace
        anchors.fill: parent
        radius: flat.radius
        gradient: Gradient {
            GradientStop { position: 0; color: flat.rimTop }
            GradientStop { position: 0.5; color: flat.rim }
            GradientStop { position: 1; color: flat.rim }
        }
    }
    // The shade, inside the rim. Its own hairline is the rim's.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, flat.radius - 1)
        color: flat.fill
    }
}
