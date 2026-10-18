/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

// The size of a drawer's tiles: one grey pill split in two, − and +, 30 high
// inside its 42 touch, each half 36 wide with a hairline between them. Every
// drawer has it after its order, at the right of the row under search, so
// the size is changed in the same place wherever it is.
Item {
    id: pill
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }
    SearchColors {
        id: tone
        theme: pill.Kirigami.Theme
    }
    // The size now, from 0 up to highest.
    property int level: 1
    property int highest: 3
    signal resize(int step)
    implicitWidth: 72
    implicitHeight: 42

    Rectangle {
        y: 6; width: parent.width; height: parent.height - 12
        radius: height / 2
        color: tone.control
        Rectangle { x: 36; y: 7; width: 1; height: parent.height - 14; color: tone.line }
    }
    component Half: Item {
        id: half
        property bool larger: false
        readonly property alias pressed: halfTap.pressed
        x: larger ? 36 : 0
        width: 36; height: 42
        enabled: larger ? pill.level < pill.highest : pill.level > 0
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: larger ? words.i18n("Larger tiles") : words.i18n("Smaller tiles")
        Accessible.onPressAction: if (enabled) pill.resize(larger ? 1 : -1)
        Keys.onReturnPressed: if (enabled) pill.resize(larger ? 1 : -1)
        Keys.onEnterPressed: if (enabled) pill.resize(larger ? 1 : -1)
        Keys.onSpacePressed: if (enabled) pill.resize(larger ? 1 : -1)
        // Each half lights as its own half of the pill.
        Item {
            y: 6; width: 36; height: 30
            clip: true
            Rectangle {
                x: half.larger ? -15 : 0
                width: 51; height: 30
                radius: 15
                color: halfTap.pressed && half.enabled ? tone.controlPressed
                    : halfHover.hovered && half.enabled ? tone.controlHover : "transparent"
                border.width: half.visualFocus ? 1 : 0
                border.color: tone.text
                Behavior on color { ColorAnimation { duration: pill.ms(90) } }
            }
        }
        readonly property bool visualFocus: activeFocus
        SuiteIcon {
            anchors.centerIn: parent
            glyph: half.larger ? "plus" : "minus"
            width: 16; height: 16
            opacity: half.enabled ? 1 : 0.42
        }
        HoverHandler {
            id: halfHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        }
        TapHandler {
            id: halfTap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: pill.resize(half.larger ? 1 : -1)
        }
    }
    Half { objectName: pill.objectName + "-smaller" }
    Half { objectName: pill.objectName + "-larger"; larger: true }
}
