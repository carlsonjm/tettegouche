/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// The quick action the typed words name, above the results: what will
// happen in a sentence, a pill that does it, and, for a reminder, the times
// it may be due instead. A switch is set right here, and the row then says
// what was done, with Undo. It holds the highlight until Down moves into
// the results, so Enter is its own.
Item {
    id: quick
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    // Whether results are listed under it, which then carry a label.
    required property bool resultsListed

    readonly property var action: launcher.quickAction
    readonly property bool reminder: action !== null && action.kind === "reminder"
    readonly property var choices: reminder && action.choices ? action.choices : []
    readonly property bool editing: launcher.quickActionEditing && choices.length > 1
    readonly property var chosenTime: choices.length > 0
        ? choices[Math.min(launcher.quickActionChoice, choices.length - 1)] : null
    readonly property bool isSwitch: action !== null && launcher.quickActionSwitch
    readonly property bool done: launcher.quickActionDone !== null
    readonly property bool moot: launcher.quickActionMoot
    readonly property string switchName: !isSwitch ? ""
        : action.kind === "bluetooth" ? words.i18n("Bluetooth") : words.i18n("Do not disturb")

    function titleText() {
        if (action === null) return ""
        if (reminder) return words.i18n("Remind me: %1", action.text)
        if (!isSwitch) return words.i18n("New note: %1", action.text)
        if (moot) return action.on ? words.i18nc("%1 is a switch's name", "%1 is already on", switchName)
            : words.i18nc("%1 is a switch's name", "%1 is already off", switchName)
        if (done) return action.on ? words.i18nc("%1 is a switch's name", "%1 is on", switchName)
            : words.i18nc("%1 is a switch's name", "%1 is off", switchName)
        if (!action.on) return words.i18nc("%1 is a switch's name", "Turn off %1", switchName)
        return action.until
            ? words.i18nc("%1 is a switch's name, %2 a time", "Turn on %1 until %2", switchName,
                          launcher.quickUntilLabel(action.until))
            : words.i18nc("%1 is a switch's name", "Turn on %1", switchName)
    }
    function subText() {
        if (launcher.quickActionFailed)
            return isSwitch ? words.i18n("That could not be changed this time")
                : words.i18n("Notes could not take it this time")
        if (isSwitch) {
            if (moot) return words.i18n("Nothing to change")
            if (!done) return words.i18n("Happens right here, nothing opens")
            if (!action.on) return words.i18n("Changed right here")
            return action.until ? words.i18nc("%1 is a time", "Until %1", launcher.quickUntilLabel(action.until))
                : words.i18n("Until you turn it off")
        }
        return chosenTime ? words.i18n("Notes · %1 · opens the note for you to look over", launcher.quickWhenLabel(chosenTime))
            : words.i18n("Notes · opens the note for you to look over")
    }
    function act() {
        if (done) launcher.undoQuickAction()
        else launcher.runQuickAction()
    }

    visible: action !== null
    height: action !== null ? column.height : 0

    Column {
        id: column
        width: parent.width

        Text {
            x: 12
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: quick.words.i18n("Quick action")
            color: quick.launcher.secondaryText
            font.pixelSize: 12
        }

        Rectangle {
            id: row
            objectName: "quick-action"
            width: parent.width
            height: 64 + (quick.editing ? choiceColumn.height + 14 : 0)
            radius: quick.launcher.paperRadius
            color: quick.launcher.quickActionLeads ? (quick.editing ? quick.tone.hover : quick.tone.current)
                : rowHover.hovered ? quick.tone.hover : quick.tone.subtle
            Accessible.role: Accessible.Button
            Accessible.name: title.text
            Accessible.description: sub.text
            Accessible.onPressAction: if (!quick.done) quick.launcher.runQuickAction()

            // Under the row's own controls, so a tap on one of them is
            // that control's alone.
            Item {
                width: parent.width
                height: 64
                HoverHandler { id: rowHover }
                TapHandler {
                    enabled: !quick.launcher.guestDragged && !quick.launcher.applicationLaunchPending && !quick.done
                    onTapped: quick.launcher.runQuickAction()
                }
            }

            Row {
                x: 12
                width: parent.width - 24
                height: 64
                spacing: 12

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    source: !quick.isSwitch ? "io.github.carlsonjm.Gooseberry"
                        : quick.done ? "emblem-ok-symbolic"
                        : quick.action !== null && quick.action.kind === "bluetooth" ? "network-bluetooth-symbolic" : "notifications-disabled-symbolic"
                    fallback: quick.isSwitch ? "preferences-system" : "knotes"
                    color: quick.launcher.primaryText
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - change.width - undoKey.width - openPill.width - 36
                    spacing: 3
                    Text {
                        id: title
                        objectName: "quick-action-title"
                        width: parent.width
                        text: quick.titleText()
                        color: quick.launcher.primaryText
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }
                    Text {
                        id: sub
                        objectName: "quick-action-sub"
                        width: parent.width
                        text: quick.subText()
                        color: quick.launcher.quickActionFailed ? quick.tone.troubleText : quick.launcher.secondaryText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                // Tab, or a tap here, opens the times.
                Item {
                    id: change
                    objectName: "quick-action-change"
                    readonly property bool offered: quick.choices.length > 1 && !quick.editing
                    anchors.verticalCenter: parent.verticalCenter
                    width: offered ? changeRow.width + 16 : 0
                    height: 44
                    visible: offered
                    Accessible.role: Accessible.Button
                    Accessible.name: quick.words.i18n("Change the time")
                    Accessible.onPressAction: quick.launcher.editQuickAction(true)
                    Row {
                        id: changeRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: keyLabel.implicitWidth + 12
                            height: 20
                            radius: 6
                            color: "transparent"
                            border.color: quick.tone.outline
                            Text {
                                id: keyLabel
                                anchors.centerIn: parent
                                text: quick.words.i18nc("the Tab key", "Tab")
                                color: quick.launcher.secondaryText
                                font.pixelSize: 12
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: quick.words.i18nc("after the Tab key: what it does", "change")
                            color: quick.launcher.secondaryText
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: quick.launcher.editQuickAction(true)
                    }
                }
                // Ctrl+Z, beside Undo, takes back the switch just set.
                Item {
                    id: undoKey
                    objectName: "quick-action-undo-key"
                    anchors.verticalCenter: parent.verticalCenter
                    width: quick.done ? undoKeyLabel.implicitWidth + 12 : 0
                    height: 20
                    visible: quick.done
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: "transparent"
                        border.color: quick.tone.outline
                        Text {
                            id: undoKeyLabel
                            anchors.centerIn: parent
                            text: quick.words.i18nc("the keys Ctrl and Z", "Ctrl+Z")
                            color: quick.launcher.secondaryText
                            font.pixelSize: 12
                        }
                    }
                }
                Rectangle {
                    id: openPill
                    objectName: "quick-action-pill"
                    anchors.verticalCenter: parent.verticalCenter
                    width: quick.moot ? 0 : openLabel.implicitWidth + 32
                    height: 32
                    radius: 16
                    visible: !quick.moot
                    color: quick.done ? (openTap.pressed ? quick.tone.controlPressed : quick.tone.controlHover)
                        : openTap.pressed ? quick.tone.lightPressed : quick.tone.primaryText
                    Accessible.role: Accessible.Button
                    Accessible.name: openLabel.text
                    Accessible.onPressAction: quick.act()
                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: quick.done ? quick.words.i18nc("a pill: take back what was just changed", "Undo")
                            : !quick.isSwitch ? quick.words.i18nc("a pill: open the note", "Open")
                            : quick.action !== null && quick.action.on ? quick.words.i18nc("a pill: turn a switch on", "Turn on")
                            : quick.words.i18nc("a pill: turn a switch off", "Turn off")
                        color: quick.done ? quick.launcher.primaryText : quick.tone.surface
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    // Taken here, so the row's own tap does not run it again.
                    MouseArea {
                        id: openTap
                        anchors.fill: parent
                        enabled: !quick.launcher.guestDragged && !quick.launcher.applicationLaunchPending
                        onClicked: quick.act()
                    }
                }
            }

            Column {
                id: choiceColumn
                visible: quick.editing
                x: 56
                y: 64
                width: parent.width - 68
                spacing: 10
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: quick.editing ? quick.choices : []
                        Rectangle {
                            id: choice
                            required property int index
                            required property var modelData
                            readonly property bool chosen: index === quick.launcher.quickActionChoice
                            objectName: "quick-action-time-" + index
                            width: choiceLabel.implicitWidth + 28
                            height: 32
                            radius: 16
                            color: chosen ? quick.tone.controlPressed
                                : choiceHover.hovered ? quick.tone.controlHover : quick.tone.control
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: choiceLabel.text
                            Accessible.checked: chosen
                            Accessible.onPressAction: quick.launcher.quickActionChoice = index
                            Text {
                                id: choiceLabel
                                anchors.centerIn: parent
                                text: quick.launcher.quickWhenLabel(choice.modelData)
                                color: quick.launcher.primaryText
                                font.pixelSize: 14
                            }
                            HoverHandler { id: choiceHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: quick.launcher.quickActionChoice = choice.index
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: quick.words.i18n("Left and Right choose · Enter opens the note · Esc goes back")
                    color: quick.launcher.secondaryText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            x: 12
            visible: quick.resultsListed
            height: visible ? 32 : 8
            verticalAlignment: Text.AlignBottom
            bottomPadding: 6
            text: quick.words.i18n("Results")
            color: quick.launcher.secondaryText
            font.pixelSize: 12
        }
    }
}
