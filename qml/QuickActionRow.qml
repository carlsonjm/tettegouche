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
// it may be due instead. It holds the highlight until Down moves into the
// results, so Enter is its own.
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
            Accessible.onPressAction: quick.launcher.runQuickAction()

            // Under the row's own controls, so a tap on one of them is
            // that control's alone.
            Item {
                width: parent.width
                height: 64
                HoverHandler { id: rowHover }
                TapHandler {
                    enabled: !quick.launcher.guestDragged && !quick.launcher.applicationLaunchPending
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
                    source: "io.github.carlsonjm.Gooseberry"
                    fallback: "knotes"
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - change.width - openPill.width - 24
                    spacing: 3
                    Text {
                        id: title
                        objectName: "quick-action-title"
                        width: parent.width
                        text: quick.action === null ? ""
                            : quick.reminder ? quick.words.i18n("Remind me: %1", quick.action.text)
                            : quick.words.i18n("New note: %1", quick.action.text)
                        color: quick.launcher.primaryText
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }
                    Text {
                        id: sub
                        objectName: "quick-action-sub"
                        width: parent.width
                        text: quick.launcher.quickActionFailed ? quick.words.i18n("Notes could not take it this time")
                            : quick.chosenTime ? quick.words.i18n("Notes · %1 · opens the note for you to look over", quick.launcher.quickWhenLabel(quick.chosenTime))
                            : quick.words.i18n("Notes · opens the note for you to look over")
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
                Rectangle {
                    id: openPill
                    objectName: "quick-action-pill"
                    anchors.verticalCenter: parent.verticalCenter
                    width: openLabel.implicitWidth + 32
                    height: 32
                    radius: 16
                    color: openTap.pressed ? quick.tone.lightPressed : quick.tone.primaryText
                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: quick.words.i18nc("a pill: open the note", "Open")
                        color: quick.tone.surface
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    // Taken here, so the row's own tap does not run it again.
                    MouseArea {
                        id: openTap
                        anchors.fill: parent
                        enabled: !quick.launcher.guestDragged && !quick.launcher.applicationLaunchPending
                        onClicked: quick.launcher.runQuickAction()
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
