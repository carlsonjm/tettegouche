/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.ki18n

pragma ComponentBehavior: Bound

// Notes, one of Search's modes: the search field becomes the note pad in the
// same window, with the drawer's motion. The notes application keeps the
// note; this draws it.
Item {
    id: pane

    required property var quickNote
    // How far the mode has opened, 0 to 1, on the drawer's own easing.
    required property real progress
    // Where the search field rests, which the pad grows out of.
    required property rect fieldRest
    property color surfaceColor: "#141414"
    property color surfaceOutline: "#5a5a5a"
    property color controlColor: "#242424"
    property color primaryText: "#f2ffffff"
    property bool growing: false

    signal back()
    signal grow()
    signal finished()

    function focusPad() { pad.forceActiveFocus() }
    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp(v) { return Math.max(0, Math.min(1, v)) }

    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }

    readonly property real headerHeight: 44
    readonly property real padTop: headerHeight + 14
    // Belongs to, its choices and the footer, under the pad.
    readonly property real bottomHeight: 14 + 17 + 6 + 40 + 14 + 44
    readonly property rect padEnd: Qt.rect(0, padTop, width,
        Math.max(60, height - padTop - bottomHeight))
    readonly property string noteHex: quickNote && quickNote.colourHex !== "" ? quickNote.colourHex : "#F2D98A"

    visible: progress > 0.001
    enabled: progress > 0.9 && !growing

    // The pad: from the field's place and shape to its own.
    Item {
        id: padFrame
        x: pane.lerp(pane.fieldRest.x, pane.padEnd.x, pane.progress)
        y: pane.lerp(pane.fieldRest.y, pane.padEnd.y, pane.progress)
        width: pane.lerp(pane.fieldRest.width, pane.padEnd.width, pane.progress)
        height: pane.lerp(pane.fieldRest.height, pane.padEnd.height, pane.progress)
        readonly property real cornerRadius: pane.lerp(pane.fieldRest.height / 2, 14, pane.progress)

        Rectangle {
            anchors.fill: parent
            radius: padFrame.cornerRadius
            color: pane.noteHex
            opacity: pane.clamp(pane.progress * 2)
        }
        Rectangle {
            anchors.fill: parent
            radius: padFrame.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: pane.surfaceOutline
            opacity: 1 - pane.progress
        }
        QQC2.TextArea {
            id: pad
            objectName: "notes-pad"
            anchors.fill: parent
            anchors.margins: 4
            leftPadding: 16
            rightPadding: 16
            topPadding: 12
            background: null
            color: "#1A1A1A"
            selectionColor: "#40000000"
            selectedTextColor: "#1A1A1A"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            wrapMode: TextEdit.Wrap
            readOnly: !pane.quickNote || pane.quickNote.readOnly
            opacity: pane.clamp((pane.progress - 0.5) / 0.5)
            placeholderText: words.i18n("Write a note")
            placeholderTextColor: "#80000000"
            Accessible.name: words.i18n("Note")
            // Typing is the person's; a change kept elsewhere arrives only
            // while it is not being typed into.
            onTextChanged: if (activeFocus && pane.quickNote && text !== pane.quickNote.text) pane.quickNote.setText(text)
            Connections {
                target: pane.quickNote
                function onNoteChanged() {
                    if (!pad.activeFocus && pad.text !== pane.quickNote.text) pad.text = pane.quickNote.text
                }
            }
            Component.onCompleted: if (pane.quickNote) text = pane.quickNote.text
        }
    }

    // Header, as Apps and Files place theirs: Back from 65% of the way, the
    // rest from 72%.
    Item {
        id: header
        width: pane.width
        height: pane.headerHeight

        Pill {
            id: backPill
            objectName: "notes-back"
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: words.i18n("Back")
            glyph: "chevron-left"
            opacity: pane.clamp((pane.progress - 0.65) / 0.35)
            onActivated: pane.back()
        }

        Row {
            id: swatches
            objectName: "notes-colours"
            anchors.centerIn: parent
            spacing: 6
            opacity: pane.clamp((pane.progress - 0.72) / 0.28)
            Repeater {
                model: pane.quickNote ? pane.quickNote.colours : []
                delegate: Item {
                    id: swatch
                    required property string modelData
                    required property int index
                    readonly property bool chosen: pane.quickNote && pane.quickNote.colour === modelData
                    width: 38
                    height: 38
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData
                    Accessible.checked: chosen
                    Rectangle {
                        anchors.centerIn: parent
                        width: 38; height: 38; radius: 19
                        color: swatch.chosen ? pane.primaryText : "transparent"
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: swatch.chosen ? 34 : 0; height: width; radius: width / 2
                        color: pane.surfaceColor
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: 14
                        color: pane.quickNote ? (pane.quickNote.colourHexes[swatch.index] || "#888888") : "#888888"
                    }
                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: pane.quickNote.setColour(swatch.modelData)
                    }
                }
            }
        }

        Pill {
            id: growPill
            objectName: "notes-all"
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: words.i18n("All notes")
            glyph: "maximize-2"
            opacity: pane.clamp((pane.progress - 0.72) / 0.28)
            onActivated: pane.grow()
        }
    }

    // Belongs to and the footer settle 20 px upward as the mode opens.
    Column {
        id: lower
        x: 0
        y: pane.padEnd.y + pane.padEnd.height + 14
        width: pane.width
        spacing: 14
        opacity: pane.progress
        transform: Translate { y: 20 * (1 - pane.progress) }

        Column {
            width: parent.width
            spacing: 6
            Text {
                text: words.i18n("Belongs to").toUpperCase()
                color: "#8A8A90"
                font.pixelSize: 11
                font.weight: Font.Black
                font.letterSpacing: 0.9
            }
            Flickable {
                width: parent.width
                height: 40
                contentWidth: choices.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: choices
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.choices : []
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool chosen: !!modelData.chosen
                            height: 40
                            width: chipLabel.implicitWidth + 32
                            radius: 20
                            color: chosen ? pane.primaryText : pane.controlColor
                            border.width: 1
                            border.color: chosen ? pane.primaryText : pane.surfaceOutline
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: chipLabel.text
                            Accessible.checked: chosen
                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData.label || ""
                                color: chip.chosen ? pane.surfaceColor : pane.primaryText
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: pane.quickNote.setBelongs(chip.modelData.kind || "", chip.modelData.project || "")
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 44
            Text {
                anchors.left: parent.left
                anchors.right: footerButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                readonly property bool trouble: !!pane.quickNote && (pane.quickNote.problem !== "" || pane.quickNote.readOnly)
                text: !pane.quickNote ? ""
                    : pane.quickNote.readOnly ? words.i18n("Kept by a newer Gooseberry; not changed here")
                    : pane.quickNote.problem !== "" ? words.i18n("Not kept yet: %1", pane.quickNote.problem)
                    : words.i18n("Saved as you go")
                color: trouble ? "#E08A80" : "#7FD1BE"
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Row {
                id: footerButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Pill {
                    objectName: "notes-tuck-away"
                    label: words.i18n("Tuck away")
                    tall: true
                    onActivated: { pane.quickNote.tuckAway(); pane.finished() }
                }
                Pill {
                    objectName: "notes-done"
                    label: words.i18n("Done")
                    tall: true
                    light: true
                    onActivated: { pane.quickNote.done(); pane.finished() }
                }
            }
        }
    }

    // The suite's grey pill: 30 high in a 42 touch in the header, 44 below.
    component Pill: Item {
        id: pill
        property string label
        property string glyph: ""
        property bool tall: false
        property bool light: false
        signal activated()
        width: pillRow.implicitWidth + (tall ? 36 : 28)
        height: tall ? 44 : 42
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: pill.activated()
        Keys.onReturnPressed: pill.activated()
        Keys.onEnterPressed: pill.activated()
        Keys.onSpacePressed: pill.activated()
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: pill.tall ? 44 : 30
            radius: height / 2
            scale: pillTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            color: pill.light ? (pillTap.pressed ? "#d8d8de" : pane.primaryText)
                : pillTap.pressed ? "#4A4A4A" : pillHover.hovered ? "#333333" : pane.controlColor
            Behavior on color { ColorAnimation { duration: 90 } }
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6
                SuiteIcon {
                    visible: pill.glyph !== ""
                    glyph: pill.glyph === "" ? "circle" : pill.glyph
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: pill.label
                    color: pill.light ? pane.surfaceColor : pane.primaryText
                    font.pixelSize: pill.tall ? 14 : 13
                    font.weight: pill.light ? Font.Black : Font.Normal
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: "#b0ffffff"
            visible: pill.activeFocus
        }
        HoverHandler {
            id: pillHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: pillTap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: pill.activated()
        }
    }
}
