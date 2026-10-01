/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts

// A question asked before something that is hard to take back, in the
// sheet's own look: its title, what will happen, and two pills, Cancel and
// the action itself by name. It darkens only the sheet it sits in, through
// the sheet's own shade, and it goes at once when answered, so the next tap
// reaches what it lands on.
C.Dialog {
    id: confirm
    // The verb on the pill that goes ahead: "Move to Trash", not "OK".
    property string action: ""
    modal: true
    dim: false
    focus: true
    anchors.centerIn: parent
    width: Math.min(440, parent ? parent.width - 48 : 440)
    leftPadding: 22; rightPadding: 22; topPadding: 4; bottomPadding: 18
    C.Overlay.modal: Item {}

    header: Text {
        text: confirm.title
        leftPadding: 22; rightPadding: 22; topPadding: 20; bottomPadding: 8
        color: "#F8F8FF"
        font.pixelSize: 17
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
    }
    footer: RowLayout {
        spacing: 8
        Item { Layout.fillWidth: true }
        ConfirmPill { objectName: "confirm-cancel"; text: qsTr("Cancel"); focus: true; onClicked: confirm.reject() }
        ConfirmPill { objectName: "confirm-action"; text: confirm.action; strong: true; onClicked: confirm.accept() }
        Item { implicitWidth: 14 }
    }
    background: Rectangle {
        radius: 12
        color: "#141414"
        border.width: 1
        border.color: "#5a5a5a"
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
    }

    component ConfirmPill: C.Button {
        id: pill
        property bool strong: false
        hoverEnabled: true
        implicitHeight: 38
        Layout.bottomMargin: 18
        leftPadding: 18; rightPadding: 18
        contentItem: Text {
            text: pill.text
            color: "#F8F8FF"
            font.pixelSize: 14
            font.weight: pill.strong ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: height / 2
            color: pill.down ? "#4A4A4A" : pill.hovered ? "#333333" : "#242424"
            border.width: pill.visualFocus ? 1 : 0
            border.color: "#F8F8FF"
            Behavior on color { ColorAnimation { duration: 90 } }
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }
}
