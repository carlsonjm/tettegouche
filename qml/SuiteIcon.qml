/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: suiteIcon
    required property string glyph
    // The glyphs are drawn in Ghost White and shown as drawn on a dark ground;
    // on a light one they are recoloured to the theme's text.
    readonly property color ink: tone.text
    implicitWidth: 20
    implicitHeight: 20

    SearchColors {
        id: tone
        theme: suiteIcon.Kirigami.Theme
    }

    Image {
        objectName: "suiteIconImage"
        anchors.fill: parent
        // Lucide's glyphs, and the suite's own marks beside them.
        source: Qt.resolvedUrl("../assets/icons/" + (suiteIcon.glyph === "genie" || suiteIcon.glyph === "notes" ? "suite/" : "lucide/")
            + suiteIcon.glyph + ".svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        layer.enabled: !tone.dark
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: suiteIcon.ink
        }
    }
}
