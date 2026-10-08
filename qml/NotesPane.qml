/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.ki18n
import org.kde.kirigami as Kirigami

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
    SearchColors {
        id: tone
        theme: pane.Kirigami.Theme
    }
    property color surfaceColor: tone.surface
    property color surfaceOutline: tone.outline
    property color controlColor: tone.control
    property color primaryText: tone.primaryText
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
    // Folder and Stuck to, as Gooseberry's own card has them, where it
    // offers them; an older Gooseberry offers Belongs to instead.
    readonly property bool chips: !!quickNote && quickNote.offersFolders
    // The chip whose choices are open under it: "folder", "window" or none.
    property string choosing: ""
    readonly property string stuckLabel: {
        if (!quickNote || !quickNote.stuck) return ""
        const windows = quickNote.windows || []
        for (let i = 0; i < windows.length; ++i)
            if (windows[i].chosen) return windows[i].label || windows[i].window || ""
        return quickNote.stuckWindow
    }
    function choose(which) {
        choosing = choosing === which ? "" : which
        newFolder.text = ""
    }
    function closeChoices() {
        choosing = ""
        newFolder.text = ""
        focusPad()
    }
    // The chips, or Belongs to, with their choices, and the footer, under
    // the pad.
    readonly property real placeHeight: chips ? 40 + (choosing !== "" ? 6 + 40 : 0) : 17 + 6 + 40
    readonly property real bottomHeight: 14 + placeHeight + 14 + 44
    readonly property rect padEnd: Qt.rect(0, padTop, width,
        Math.max(60, height - padTop - bottomHeight))
    // The note is paper of its own colour on any ground, with dark ink.
    readonly property string noteHex: quickNote && quickNote.colourHex !== "" ? quickNote.colourHex : "#F2D98A"

    visible: progress > 0.001
    enabled: progress > 0.9 && !growing
    onProgressChanged: if (progress < 0.001) choosing = ""
    onChipsChanged: if (!chips) choosing = ""

    // Esc first closes a chip's choices, and then is Search's.
    Keys.onEscapePressed: event => {
        if (choosing === "") {
            event.accepted = false
            return
        }
        closeChoices()
    }

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
            // Dark ink on the note's pale paper, whatever the ground around it.
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
                        // A swatch is the paper's own colour; a mid grey stands in
                        // for one the notes application does not name.
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

    // The chips, or Belongs to, and the footer settle 20 px upward as the
    // mode opens.
    Column {
        id: lower
        x: 0
        y: pane.padEnd.y + pane.padEnd.height + 14
        width: pane.width
        spacing: 14
        opacity: pane.progress
        transform: Translate { y: 20 * (1 - pane.progress) }

        // Where the note is kept, and the window it is stuck to: two chips,
        // both already filled in, each opening its choices under it.
        Column {
            objectName: "notes-chips"
            width: parent.width
            spacing: 6
            visible: pane.chips
            enabled: !!pane.quickNote && !pane.quickNote.readOnly
            opacity: pane.quickNote && pane.quickNote.readOnly ? 0.45 : 1
            Row {
                spacing: 8
                Chip {
                    objectName: "notes-folder"
                    maxWidth: (pane.width - 8) / 2
                    label: pane.quickNote ? words.i18n("Folder · %1 ▾", pane.quickNote.folderLabel) : ""
                    spokenLabel: pane.quickNote ? words.i18n("Folder: %1", pane.quickNote.folderLabel) : ""
                    chosen: pane.choosing === "folder"
                    onActivated: pane.choose("folder")
                }
                Chip {
                    objectName: "notes-stuck"
                    maxWidth: (pane.width - 8) / 2
                    label: pane.quickNote && pane.quickNote.stuck ? words.i18n("Stuck to · %1 ▾", pane.stuckLabel)
                        : words.i18n("Not stuck to a window ▾")
                    spokenLabel: pane.quickNote && pane.quickNote.stuck ? words.i18n("Stuck to %1", pane.stuckLabel)
                        : words.i18n("Not stuck to a window")
                    chosen: pane.choosing === "window"
                    onActivated: pane.choose("window")
                }
            }
            Flickable {
                objectName: "notes-folder-choices"
                visible: pane.choosing === "folder"
                width: parent.width
                height: 40
                contentWidth: folderRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: folderRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.folders : []
                        delegate: Chip {
                            required property var modelData
                            objectName: "notes-folder-" + (modelData.name || "inbox")
                            label: modelData.workspace ? words.i18n("%1 · this workspace", modelData.label || "")
                                : (modelData.label || "")
                            radio: true
                            chosen: !!modelData.chosen
                            onActivated: {
                                pane.quickNote.setFolder(modelData.name || "")
                                pane.closeChoices()
                            }
                        }
                    }
                    QQC2.TextField {
                        id: newFolder
                        objectName: "notes-new-folder"
                        width: 200
                        height: 40
                        leftPadding: 16
                        rightPadding: 16
                        color: pane.primaryText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        placeholderText: words.i18n("New folder")
                        placeholderTextColor: tone.hintText
                        Accessible.name: words.i18n("New folder")
                        background: Rectangle {
                            radius: 20
                            color: pane.controlColor
                            border.width: 1
                            border.color: newFolder.activeFocus ? pane.primaryText : pane.surfaceOutline
                        }
                        onAccepted: {
                            const name = text.trim()
                            if (name === "") return
                            pane.quickNote.setFolder(name)
                            pane.closeChoices()
                        }
                    }
                }
            }
            Flickable {
                objectName: "notes-window-choices"
                visible: pane.choosing === "window"
                width: parent.width
                height: 40
                contentWidth: windowRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: windowRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.windows : []
                        delegate: Chip {
                            required property var modelData
                            required property int index
                            objectName: "notes-window-" + index
                            label: modelData.label || modelData.window || ""
                            radio: true
                            chosen: !!modelData.chosen
                            onActivated: {
                                pane.quickNote.setStuck(modelData.window || "", modelData.app || "")
                                pane.closeChoices()
                            }
                        }
                    }
                    Chip {
                        objectName: "notes-dont-stick"
                        label: words.i18n("Don't stick to a window")
                        radio: true
                        chosen: !!pane.quickNote && !pane.quickNote.stuck
                        onActivated: {
                            pane.quickNote.setStuck("", "")
                            pane.closeChoices()
                        }
                    }
                }
            }
        }

        Column {
            objectName: "notes-belongs"
            width: parent.width
            spacing: 6
            visible: !pane.chips
            Text {
                text: words.i18n("Belongs to").toUpperCase()
                color: tone.hintText
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
                            required property int index
                            objectName: "notes-belongs-" + index
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
                color: trouble ? tone.troubleText : tone.goodText
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

    // A choice under the pad, filled when chosen or open.
    component Chip: Rectangle {
        id: chipItem
        property string label
        property string spokenLabel: label
        property bool chosen: false
        // A choice among others rather than a chip that opens them.
        property bool radio: false
        // A long label ends in an ellipsis rather than pushing past the pane.
        property real maxWidth: pane.width
        signal activated()
        height: 40
        width: Math.min(chipText.implicitWidth + 32, maxWidth)
        radius: 20
        color: chosen ? pane.primaryText : pane.controlColor
        border.width: activeFocus ? 2 : 1
        border.color: chosen || activeFocus ? pane.primaryText : pane.surfaceOutline
        activeFocusOnTab: true
        Accessible.role: radio ? Accessible.RadioButton : Accessible.Button
        Accessible.name: spokenLabel
        Accessible.checked: chosen
        Accessible.onPressAction: chipItem.activated()
        Keys.onReturnPressed: chipItem.activated()
        Keys.onEnterPressed: chipItem.activated()
        Keys.onSpacePressed: chipItem.activated()
        Text {
            id: chipText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, chipItem.width - 32)
            elide: Text.ElideRight
            text: chipItem.label
            color: chipItem.chosen ? pane.surfaceColor : pane.primaryText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: chipItem.activated()
        }
    }

    component Pill: ModePill {
        primaryText: pane.primaryText
        surfaceColor: pane.surfaceColor
        controlColor: pane.controlColor
    }
}
