/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami

// One line of a SheetMenu: a pill as tall as a fingertip, lighter under the
// pointer or the keys, darker pressed. A line that can be on shows a check.
Item {
    id: line
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
    readonly property bool isSheetMenuItem: true
    property string text: ""
    property bool checkable: false
    property bool checked: false
    property var menu: null
    signal triggered()
    SearchColors {
        id: tone
        theme: line.Kirigami.Theme
    }

    // Chosen by a tap, a click or Enter: the line acts, then the menu closes.
    // A check shows what its setting holds; the line's action changes that.
    function choose() {
        if (!enabled) return
        triggered()
        if (menu) menu.close()
    }

    implicitWidth: label.implicitWidth + 28 + (checkable ? 26 : 0)
    implicitHeight: visible ? 40 : 0
    height: implicitHeight
    Accessible.role: checkable ? Accessible.CheckBox : Accessible.MenuItem
    Accessible.name: text
    Accessible.checked: checked
    Accessible.onPressAction: choose()

    readonly property bool keyed: !!menu && menu.current >= 0
        && menu.contentItem.children[menu.current] === line
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: tap.pressed ? tone.controlHover
            : (hover.hovered || line.keyed) && line.enabled ? tone.control : "transparent"
        Behavior on color { ColorAnimation { duration: line.ms(90) } }
    }
    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        width: parent.width - 28 - (line.checkable ? 26 : 0)
        text: line.text
        color: line.enabled ? tone.text : tone.disabledText
        font.pixelSize: 14
        elide: Text.ElideMiddle
    }
    SuiteIcon {
        visible: line.checkable && line.checked
        glyph: "check"
        width: 16; height: 16
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }
    HoverHandler {
        id: hover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    }
    // The line keeps the tap, so nothing under the menu takes it too.
    TapHandler {
        id: tap
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: line.choose()
    }
}
