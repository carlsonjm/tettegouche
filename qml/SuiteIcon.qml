/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick

Item {
    required property string glyph
    implicitWidth: 20
    implicitHeight: 20

    Image {
        anchors.fill: parent
        // Lucide's glyphs, and the suite's own marks beside them.
        source: Qt.resolvedUrl("../assets/icons/" + (parent.glyph === "genie" ? "suite/" : "lucide/")
            + parent.glyph + ".svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
