/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n

// Ask's answer at the top of the Helpers it names: on the Subtle fill at
// paper 10, 12 by 16 inside, the words at 15 and who gave them at 12 beneath.
// Before the model is downloaded the same box says what Ask needs under a
// heading at 16: the model by name, its size, that it runs here and nothing
// leaves the computer, with Download, Codex only where Codex is installed,
// and Not now. Without llama.cpp it says so first, and offers to install it
// in the download's place. While it downloads, a 4 tall bar fills in it on
// the raised grey. Under Codex only, a question waits for Ask Codex. An
// answer that would write in one of the person's apps ends with its Do it
// card: what it does and the first words it writes, with a Do it pill 32
// tall; the write is made only on that tap, and the card then says how it
// went. Who answered names what the apps' tools read for it.
Rectangle {
    id: answer
    required property var askClient
    required property SearchColors tone
    required property KI18nContext words
    // The person's tap on Install llama.cpp, and on Ask Codex under Codex only.
    signal installEngine()
    signal askCodex()
    readonly property string phase: askClient ? askClient.state : "idle"
    readonly property bool needsModel: phase === "needsModel"
    readonly property bool needsEngine: needsModel && !!askClient && askClient.needsEngine
    readonly property bool downloading: phase === "downloading"
    readonly property bool codexOnly: phase === "codexOnly"
    readonly property bool offersCodexOnly: needsModel && !!askClient && askClient.codexInstalled
    readonly property bool handedOn: phase === "answered" && !!askClient && askClient.handedToCodex
    // Where Codex is signed in, an answer offers it after the Helpers.
    readonly property bool codexOffered: phase === "answered" && !!askClient && askClient.codexReady && !handedOn
    // While the model on this computer thinks, which can take most of a
    // minute, the box says so rather than leaving only the web below.
    readonly property bool thinking: phase === "asking" && !!askClient && askClient.text.length === 0
    readonly property var card: phase === "answered" && askClient && askClient.doIt && askClient.doIt.title !== undefined
        ? askClient.doIt : null
    readonly property string doing: askClient ? askClient.doItState : ""
    readonly property var readNames: phase === "answered" && askClient ? askClient.read : []
    readonly property string modelName: askClient && askClient.modelName.length > 0 ? askClient.modelName : words.i18n("the model")
    readonly property bool shown: phase === "asking" ? true
        : phase === "answered" ? askClient.text.length > 0
        : needsModel || downloading || codexOnly || phase === "off" || phase === "problem"

    objectName: "ask-answer"
    visible: shown
    height: shown ? column.implicitHeight + 24 : 0
    radius: 10
    color: tone.subtle
    Accessible.role: Accessible.StaticText
    Accessible.name: heading.visible ? heading.text + ". " + said.text : said.text

    Column {
        id: column
        x: 16
        y: 12
        width: parent.width - 32
        spacing: 8

        Text {
            id: heading
            objectName: "ask-answer-heading"
            width: parent.width
            visible: answer.needsModel || answer.downloading
            text: answer.needsEngine ? answer.words.i18n("Ask needs llama.cpp before it can answer here")
                : answer.downloading ? answer.words.i18n("Downloading %1", answer.modelName)
                : answer.offersCodexOnly ? answer.words.i18n("Answer here on this computer, or with Codex")
                : answer.words.i18n("Answer here on this computer")
            color: answer.tone.primaryText
            font.pixelSize: 16
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }

        Text {
            id: said
            objectName: "ask-answer-text"
            width: parent.width
            visible: text.length > 0
            text: !answer.askClient ? ""
                : answer.downloading ? answer.words.i18n("Once it's here, Ask answers this question. If the connection drops, the download picks up where it stopped.")
                : answer.askClient.text.length > 0 ? answer.askClient.text
                : answer.thinking ? answer.words.i18n("Looking into it…")
                : answer.phase === "off" ? answer.words.i18n("Ask is switched off in Settings.")
                : answer.phase === "problem" ? answer.words.i18n("Ask couldn't answer this time. The Helpers below still can.")
                : ""
            color: answer.tone.primaryText
            font.pixelSize: 15
            lineHeight: 1.3
            wrapMode: Text.Wrap
        }

        // The other way, where Codex is installed: no model at all.
        Text {
            objectName: "ask-answer-codex"
            width: parent.width
            visible: answer.offersCodexOnly
            text: answer.needsEngine
                ? answer.words.i18n("Or skip both: with Codex only, your questions go to Codex online, on your own ChatGPT plan.")
                : answer.words.i18n("Or skip the download: with Codex only, your questions go to Codex online, on your own ChatGPT plan.")
            color: answer.tone.secondaryText
            font.pixelSize: 15
            lineHeight: 1.3
            wrapMode: Text.Wrap
        }

        // Pills 40 tall, 8 apart, 4 below the words; the main one light with
        // ink, Codex only on the raised grey, Not now bare until hovered.
        Item {
            width: parent.width
            height: choices.height + 4
            visible: answer.needsModel || answer.codexOnly
            Row {
                id: choices
                y: 4
                spacing: 8
                Repeater {
                    model: answer.codexOnly
                        ? [{name: "ask-codex-now", label: answer.words.i18n("Ask Codex"), kind: "main"}]
                        : [{name: answer.needsEngine ? "ask-install-engine" : "ask-download",
                            label: answer.needsEngine ? answer.words.i18n("Install llama.cpp")
                                : answer.askClient && answer.askClient.modelName.length > 0 ? answer.words.i18n("Download %1", answer.askClient.modelName)
                                : answer.words.i18n("Download"),
                            kind: "main"}]
                          .concat(answer.offersCodexOnly ? [{name: "ask-codex-only", label: answer.words.i18n("Codex only"), kind: "raised"}] : [])
                          .concat([{name: "ask-not-now", label: answer.words.i18n("Not now"), kind: "bare"}])
                    Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool main: modelData.kind === "main"
                        objectName: modelData.name
                        width: choiceLabel.implicitWidth + 36
                        height: 40
                        radius: 20
                        color: main ? (choiceTap.pressed ? answer.tone.lightPressed : answer.tone.primaryText)
                            : choiceTap.pressed ? answer.tone.controlPressed
                            : choiceHover.hovered ? answer.tone.controlHover
                            : modelData.kind === "raised" ? answer.tone.control : "transparent"
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.onPressAction: choice.activate()
                        Keys.onReturnPressed: choice.activate()
                        Keys.onEnterPressed: choice.activate()
                        Keys.onSpacePressed: choice.activate()
                        function activate() {
                            switch (modelData.name) {
                            case "ask-download": answer.askClient.download(); break
                            case "ask-install-engine": answer.installEngine(); break
                            case "ask-codex-only": answer.askClient.chooseCodexOnly(); break
                            case "ask-codex-now": answer.askCodex(); break
                            default: answer.askClient.notNow()
                            }
                        }
                        Text {
                            id: choiceLabel
                            anchors.centerIn: parent
                            text: choice.modelData.label
                            color: choice.main ? answer.tone.surface : answer.tone.primaryText
                            font.pixelSize: 14
                            font.weight: choice.main ? Font.DemiBold : Font.Normal
                        }
                        HoverHandler { id: choiceHover }
                        TapHandler { id: choiceTap; onTapped: choice.activate() }
                    }
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

        // Who answered, so it is never mistaken for Codex; before the model,
        // whose it is and how Codex signs in.
        Text {
            objectName: "ask-answer-who"
            width: parent.width
            visible: text.length > 0
            text: !answer.askClient ? ""
                : answer.downloading
                ? answer.words.i18n("%1% of %2",
                    Math.round(100 * answer.askClient.progress), answer.askClient.size)
                : answer.needsEngine ? answer.words.i18n("Install opens Install an app at llama.cpp, and waits for your yes")
                : answer.needsModel ? [answer.askClient.modelCredit,
                        answer.offersCodexOnly ? answer.words.i18n("Codex signs you in through its own page") : ""]
                    .filter(part => part.length > 0).join(" · ")
                : answer.codexOnly ? answer.words.i18n("Codex only · nothing is sent until you tap · warnings about scams and passwords still come from this computer")
                : answer.handedOn ? answer.words.i18n("From this computer · Codex answers in its own window")
                : answer.thinking ? answer.words.i18n("On this computer · an answer can take up to a minute")
                : answer.readNames.length > 0 ? answer.words.i18n("On this computer · Read: %1", answer.readNames.join(", "))
                : answer.card ? answer.words.i18n("Answered on this computer · nothing changes until you tap Do it")
                : answer.phase === "answered" || answer.phase === "asking" ? answer.words.i18n("Answered on this computer · nothing changes until you open a Helper")
                : ""
            color: answer.tone.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        // The Do it card: what it does, in the app's words, and the first
        // words it writes; then Do it, or how the write went.
        Item {
            objectName: "ask-do-it"
            visible: answer.card !== null
            width: parent.width
            height: Math.max(doItWords.implicitHeight, 32) + 4
            Column {
                id: doItWords
                y: 4
                width: parent.width - doItEnd.width - 12
                spacing: 2
                Text {
                    objectName: "ask-do-it-what"
                    width: parent.width
                    text: !answer.card ? "" : answer.card.what || answer.card.app || ""
                    color: answer.tone.primaryText
                    font.pixelSize: 15
                    wrapMode: Text.Wrap
                }
                Text {
                    objectName: "ask-do-it-title"
                    width: parent.width
                    visible: text.length > 0
                    text: answer.card && answer.card.title ? answer.words.i18n("“%1”", answer.card.title) : ""
                    color: answer.tone.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                Text {
                    objectName: "ask-do-it-problem"
                    width: parent.width
                    visible: answer.doing === "failed"
                    text: answer.askClient && answer.askClient.doItProblem.length > 0
                        ? answer.words.i18n("It didn't work: %1", answer.askClient.doItProblem)
                        : answer.words.i18n("It didn't work. Nothing was changed.")
                    color: answer.tone.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
            Item {
                id: doItEnd
                anchors.right: parent.right
                y: 4
                width: answer.doing === "done" || answer.doing === "failed" ? doneText.implicitWidth : doItPill.width
                height: 32
                Rectangle {
                    id: doItPill
                    objectName: "ask-do-it-run"
                    visible: answer.doing === "" || answer.doing === "running"
                    width: doItLabel.implicitWidth + 32
                    height: 32
                    radius: 16
                    color: doItTap.pressed || answer.doing === "running" ? answer.tone.lightPressed : answer.tone.primaryText
                    activeFocusOnTab: visible && answer.doing === ""
                    Accessible.role: Accessible.Button
                    Accessible.name: answer.card ? answer.words.i18n("Do it: %1", answer.card.what || answer.card.app || answer.card.title || "") : ""
                    Accessible.onPressAction: doItPill.activate()
                    Keys.onReturnPressed: doItPill.activate()
                    Keys.onEnterPressed: doItPill.activate()
                    Keys.onSpacePressed: doItPill.activate()
                    function activate() { if (answer.askClient) answer.askClient.runDoIt() }
                    Text {
                        id: doItLabel
                        anchors.centerIn: parent
                        text: answer.doing === "running" ? answer.words.i18n("Doing it…") : answer.words.i18n("Do it")
                        color: answer.tone.surface
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    TapHandler { id: doItTap; enabled: answer.doing === ""; onTapped: doItPill.activate() }
                }
                Text {
                    id: doneText
                    objectName: "ask-do-it-done"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    visible: answer.doing === "done" || answer.doing === "failed"
                    text: answer.doing === "done" ? answer.words.i18n("Done") : answer.words.i18n("Didn't work")
                    color: answer.tone.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
