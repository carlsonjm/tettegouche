/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n

// Ask's answer at the top of the Helpers it names: on the Subtle fill at
// paper 8, 12 by 16 inside, the words at 15 and who gave them at 12 beneath.
// Before the model is downloaded the same box says what Ask needs, with
// Download and Not now; while it downloads, a 4 tall bar fills in it on
// the raised grey.
Rectangle {
    id: answer
    required property var askClient
    required property SearchColors tone
    required property KI18nContext words
    readonly property string phase: askClient ? askClient.state : "idle"
    readonly property bool needsModel: phase === "needsModel"
    readonly property bool downloading: phase === "downloading"
    readonly property bool handedOn: phase === "answered" && !!askClient && askClient.handedToCodex
    // Where Codex is signed in, an answer offers it after the Helpers.
    readonly property bool codexOffered: phase === "answered" && !!askClient && askClient.codexReady && !handedOn
    readonly property bool shown: phase === "asking" ? askClient.text.length > 0
        : phase === "answered" ? askClient.text.length > 0
        : needsModel || downloading || phase === "off" || phase === "problem"

    objectName: "ask-answer"
    visible: shown
    height: shown ? column.implicitHeight + 24 : 0
    radius: 8
    color: tone.subtle
    Accessible.role: Accessible.StaticText
    Accessible.name: said.text

    Column {
        id: column
        x: 16
        y: 12
        width: parent.width - 32
        spacing: 8

        Text {
            id: said
            objectName: "ask-answer-text"
            width: parent.width
            visible: !answer.downloading || text.length > 0
            text: !answer.askClient || answer.downloading ? ""
                : answer.askClient.text.length > 0 ? answer.askClient.text
                : answer.phase === "off" ? answer.words.i18n("Ask is switched off in Settings.")
                : answer.phase === "problem" ? answer.words.i18n("Ask couldn't answer this time. The Helpers below still can.")
                : ""
            color: answer.tone.primaryText
            font.pixelSize: 15
            lineHeight: 1.3
            wrapMode: Text.Wrap
        }

        Row {
            visible: answer.needsModel
            spacing: 8
            Repeater {
                model: [
                    {name: "ask-download", label: answer.words.i18n("Download"), main: true},
                    {name: "ask-not-now", label: answer.words.i18n("Not now"), main: false}
                ]
                // Pills 40 tall, the main one light with ink.
                Rectangle {
                    id: choice
                    required property var modelData
                    objectName: modelData.name
                    width: choiceLabel.implicitWidth + 36
                    height: 40
                    radius: 20
                    color: modelData.main ? (choiceTap.pressed ? answer.tone.lightPressed : answer.tone.primaryText)
                        : choiceTap.pressed ? answer.tone.controlPressed
                        : choiceHover.hovered ? answer.tone.controlHover : answer.tone.control
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.onPressAction: choice.activate()
                    Keys.onReturnPressed: choice.activate()
                    Keys.onEnterPressed: choice.activate()
                    Keys.onSpacePressed: choice.activate()
                    function activate() {
                        if (modelData.main) answer.askClient.download()
                        else answer.askClient.notNow()
                    }
                    Text {
                        id: choiceLabel
                        anchors.centerIn: parent
                        text: choice.modelData.label
                        color: choice.modelData.main ? answer.tone.surface : answer.tone.primaryText
                        font.pixelSize: 14
                        font.weight: choice.modelData.main ? Font.DemiBold : Font.Normal
                    }
                    HoverHandler { id: choiceHover }
                    TapHandler { id: choiceTap; onTapped: choice.activate() }
                }
            }
        }

        Rectangle {
            visible: answer.downloading
            width: parent.width
            height: 4
            radius: 2
            color: answer.tone.control
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, answer.askClient ? answer.askClient.progress : 0))
                height: parent.height
                radius: 2
                color: answer.tone.primaryText
            }
        }

        // Who answered, so it is never mistaken for Codex.
        Text {
            objectName: "ask-answer-who"
            width: parent.width
            visible: answer.downloading || answer.phase === "answered" || answer.phase === "asking"
            text: answer.downloading
                ? answer.words.i18n("Downloading the model · %1% of %2",
                    Math.round(100 * (answer.askClient ? answer.askClient.progress : 0)),
                    answer.askClient ? answer.askClient.size : "")
                : answer.handedOn ? answer.words.i18n("From this computer · Codex answers in its own window")
                : answer.words.i18n("Answered on this computer · nothing changes until you open a Helper")
            color: answer.tone.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
}
