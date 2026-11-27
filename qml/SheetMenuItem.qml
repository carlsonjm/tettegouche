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
    // A second, quieter line under the text, such as the folder a line acts on.
    property string detail: ""
    // A line that takes something away reads in the theme's warning colour.
    property bool destructive: false
    // A glyph before the text, for a menu of a drawer's actions.
    property string glyph: ""
    // What a line that opens its own choices holds now, quiet at its right
    // with a chevron.
    property string value: ""
    // A setting that flips in place: a switch at the right, and the menu
    // stays open so the change shows.
    property bool toggle: false
    property bool keepsOpen: toggle
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
        if (menu && !keepsOpen) menu.close()
    }

    readonly property real lead: glyph.length ? 30 : 0
    readonly property real trail: (checkable ? 26 : 0) + (toggle ? 58 : 0)
        + (value.length ? valueLabel.implicitWidth + 30 : 0)
    implicitWidth: Math.max(label.implicitWidth, detailLabel.implicitWidth) + 28 + lead + trail
    implicitHeight: visible ? (detail.length ? 52 : 40) : 0
    height: implicitHeight
    Accessible.role: checkable || toggle ? Accessible.CheckBox : Accessible.MenuItem
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
        anchors.verticalCenterOffset: line.detail.length ? -8 : 0
        x: 14 + line.lead
        width: parent.width - 28 - line.lead - line.trail
        text: line.text
        color: !line.enabled ? tone.disabledText : line.destructive ? tone.errorText : tone.text
        font.pixelSize: 14
        elide: Text.ElideMiddle
    }
    Text {
        id: detailLabel
        visible: line.detail.length > 0
        anchors.top: label.bottom
        anchors.topMargin: 1
        x: label.x
        width: label.width
        text: line.detail
        color: tone.secondaryText
        font.pixelSize: 12
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
    SuiteIcon {
        visible: line.glyph.length > 0
        glyph: line.glyph || "circle"
        width: 18; height: 18
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        opacity: line.enabled ? 1 : 0.42
    }
    Row {
        visible: line.value.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            id: valueLabel
            anchors.verticalCenter: parent.verticalCenter
            text: line.value
            color: line.enabled ? tone.secondaryText : tone.disabledText
            font.pixelSize: 14
        }
        SuiteIcon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: "chevron-down"
            width: 14; height: 14
            opacity: line.enabled ? 0.8 : 0.42
        }
    }
    // The switch: a track that fills with the text's colour when on, and a
    // knob that slides across.
    Rectangle {
        objectName: line.objectName.length ? line.objectName + "-switch" : ""
        visible: line.toggle
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 20
        radius: height / 2
        color: line.checked ? tone.text : tone.controlPressed
        Behavior on color { ColorAnimation { duration: line.ms(120) } }
        Rectangle {
            width: 16; height: 16
            radius: 8
            y: 2
            x: line.checked ? parent.width - width - 2 : 2
            color: line.checked ? tone.surface : tone.secondaryText
            Behavior on x { NumberAnimation { duration: line.ms(120); easing.type: Easing.OutCubic } }
        }
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
