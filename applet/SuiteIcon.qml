/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick

Item {
    required property string glyph
    objectName: "suiteIcon-" + glyph
    implicitWidth: 20
    implicitHeight: 20

    Image {
        objectName: "suiteIconImage"
        anchors.fill: parent
        source: "qrc:/qt/qml/plasma/applet/studio/warbler/tettegouche/"
            + parent.glyph + ".svg"
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
