/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import QtQuick.Controls as C
import QtQuick.Layouts

// A question asked before something that is hard to take back, in the
// sheet's own look: its title, what will happen, and two pills, Cancel and
// the action itself by name. It darkens only the sheet it sits in, through
// the sheet's own shade, and it goes at once when answered, so the next tap
// reaches what it lands on.
C.Dialog {
    id: confirm
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
    // Its words come from the launcher's catalog.
    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }
    // The verb on the pill that goes ahead: "Move to Trash", not "OK".
    property string action: ""
    // What going ahead does, said under the question.
    property string body: ""
    modal: true
    dim: false
    focus: true
    anchors.centerIn: parent
    width: Math.min(440, parent ? parent.width - 48 : 440)
    leftPadding: 22; rightPadding: 22; topPadding: 20; bottomPadding: 18
    C.Overlay.modal: Item {}

    // The question and what it does are the dialog's own content, which it
    // sizes to the width it has, so long words wrap without their height
    // feeding back into that width.
    header: null
    contentItem: Column {
        id: question
        spacing: 12
        // The sheet's colours, from the theme of the window it opens in.
        SearchColors {
            id: tone
            theme: question.Kirigami.Theme
        }
        Text {
            width: parent.width
            text: confirm.title
            color: tone.text
            font.pixelSize: 17
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }
        Text {
            objectName: confirm.objectName + "-body"
            width: parent.width
            visible: text.length > 0
            text: confirm.body
            color: tone.bodyText
            font.pixelSize: 14
            wrapMode: Text.Wrap
        }
    }
    footer: RowLayout {
        spacing: 8
        Item { Layout.fillWidth: true }
        ConfirmPill { objectName: "confirm-cancel"; text: words.i18n("Cancel"); focus: true; onClicked: confirm.reject() }
        ConfirmPill { objectName: "confirm-action"; text: confirm.action; strong: true; onClicked: confirm.accept() }
        Item { implicitWidth: 14 }
    }
    background: Rectangle {
        radius: 12
        color: tone.surface
        border.width: 1
        border.color: tone.outline
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: confirm.ms(120); easing.type: Easing.OutCubic }
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
            color: tone.text
            font.pixelSize: 14
            font.weight: pill.strong ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: height / 2
            color: pill.down ? tone.controlPressed : pill.hovered ? tone.controlHover : tone.control
            border.width: pill.visualFocus ? 1 : 0
            border.color: tone.text
            Behavior on color { ColorAnimation { duration: confirm.ms(90) } }
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }
}
