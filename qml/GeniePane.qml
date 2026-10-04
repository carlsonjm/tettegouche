/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.ki18n

pragma ComponentBehavior: Bound

// Genie, one of Search's modes: the search field travels into the header and
// holds the question, and the answer arrives below it, with the drawer's
// motion. Split Rock keeps the conversation; this draws it.
Item {
    id: pane

    required property var genie
    // How far the mode has opened, 0 to 1, on the drawer's own easing.
    required property real progress
    // Where the search field rests, which the question field travels from.
    required property rect fieldRest
    property bool keysUp: false
    property color surfaceColor: "#141414"
    property color surfaceOutline: "#5a5a5a"
    property color controlColor: "#242424"
    property color primaryText: "#f2ffffff"
    property bool growing: false

    signal back()
    signal grow()

    // Opening shows the conversation's question as Split Rock keeps it.
    function focusField() {
        question.text = pane.genie ? pane.genie.question : ""
        question.forceActiveFocus()
    }
    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp(v) { return Math.max(0, Math.min(1, v)) }
    function ask(text) {
        if (!pane.genie || text.trim().length === 0) return
        question.text = text
        pane.genie.ask(text)
    }

    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }

    readonly property real headerHeight: 44
    // The question keeps to the middle of the header, as clear of Back as of
    // Expand, as search does in Apps and Files.
    readonly property real fieldSide: Math.max(backPill.x + backPill.width,
        width - growPill.x) + 12
    readonly property real fieldWidth: Math.max(160,
        Math.min(width - 2 * fieldSide, Math.max(360, width / 2)))
    readonly property string phase: genie ? genie.phase : ""
    readonly property bool answering: phase === "answering"

    visible: progress > 0.001
    enabled: progress > 0.9 && !growing

    // The question field: from search's place and shape to the header's.
    Item {
        id: fieldFrame
        x: pane.lerp(pane.fieldRest.x, (pane.width - pane.fieldWidth) / 2, pane.progress)
        y: pane.lerp(pane.fieldRest.y, 0, pane.progress)
        width: pane.lerp(pane.fieldRest.width, pane.fieldWidth, pane.progress)
        height: pane.lerp(pane.fieldRest.height, pane.headerHeight, pane.progress)
        z: 2
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: pane.controlColor
            opacity: pane.clamp(pane.progress * 2)
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: pane.surfaceOutline
        }
        SuiteIcon {
            id: lamp
            glyph: "genie"
            width: 18
            height: 18
            x: 18
            anchors.verticalCenter: parent.verticalCenter
        }
        QQC2.TextField {
            id: question
            objectName: "genie-question"
            anchors.left: lamp.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            background: null
            color: pane.primaryText
            placeholderText: words.i18n("Ask, or say what you want done")
            placeholderTextColor: "#8E929A"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            opacity: pane.clamp((pane.progress - 0.3) / 0.7)
            Accessible.name: words.i18n("Ask Genie")
            onAccepted: pane.ask(text)
            Connections {
                target: pane.genie
                function onConversationChanged() {
                    if (!question.activeFocus && pane.genie.question !== "") question.text = pane.genie.question
                }
            }
        }
    }

    // Header, as Apps and Files place theirs: Back from 65% of the way,
    // Expand from 72%.
    Pill {
        id: backPill
        objectName: "genie-back"
        x: 14
        y: (pane.headerHeight - height) / 2
        label: words.i18n("Back")
        glyph: "chevron-left"
        opacity: pane.clamp((pane.progress - 0.65) / 0.35)
        onActivated: pane.back()
    }
    Pill {
        id: growPill
        objectName: "genie-expand"
        x: pane.width - width - 14
        y: (pane.headerHeight - height) / 2
        label: words.i18n("Expand")
        glyph: "maximize-2"
        opacity: pane.clamp((pane.progress - 0.72) / 0.28)
        onActivated: pane.grow()
    }

    // What Genie says, settling 20 px as the mode opens, as Files does.
    Rectangle {
        id: body
        objectName: "genie-answer"
        x: 0
        y: pane.headerHeight + 16
        width: pane.width
        height: Math.max(0, pane.height - y)
        radius: 12
        color: "#1C1C1C"
        opacity: pane.progress
        transform: Translate { y: -20 * (1 - pane.progress) }
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: answerColumn.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: answerColumn
                width: parent.width
                spacing: 12

                // Before any answer: what the assistant needs, or what to ask.
                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    color: pane.phase === "failed" ? "#E08A80" : pane.primaryText
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    text: !pane.genie ? ""
                        : pane.phase === "choose" ? words.i18n("Choose an assistant in Genie to begin.")
                        : pane.phase === "sign-in" ? words.i18n("Sign in to %1 in Genie to begin.", pane.genie.assistant)
                        : pane.phase === "starting" ? words.i18n("Starting %1…", pane.genie.assistant)
                        : pane.phase === "failed" ? (pane.genie.problem !== "" ? pane.genie.problem : words.i18n("Genie could not answer."))
                        : pane.genie.answer !== "" ? pane.genie.answer
                        : pane.answering ? words.i18n("Thinking…")
                        : ""
                }
                Repeater {
                    model: pane.genie && pane.phase !== "failed" ? pane.genie.steps : []
                    delegate: Row {
                        id: step
                        required property string modelData
                        required property int index
                        width: answerColumn.width
                        spacing: 12
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: pane.controlColor
                            Text {
                                anchors.centerIn: parent
                                text: step.index + 1
                                color: pane.primaryText
                                font.pixelSize: 12
                                font.weight: Font.Black
                            }
                        }
                        Text {
                            width: step.width - 36
                            text: step.modelData
                            wrapMode: Text.Wrap
                            color: "#E4E4EA"
                            font.pixelSize: 15
                            lineHeight: 1.3
                        }
                    }
                }
                // With nothing asked yet, the assistant's suggestions.
                Flow {
                    width: parent.width
                    spacing: 8
                    visible: !!pane.genie && pane.phase === "ready" && pane.genie.answer === ""
                    Repeater {
                        model: pane.genie ? pane.genie.suggestions : []
                        delegate: Pill {
                            required property string modelData
                            objectName: "genie-suggestion"
                            label: modelData
                            tall: true
                            onActivated: pane.ask(modelData)
                        }
                    }
                }
                Row {
                    spacing: 8
                    visible: !!pane.genie && (pane.phase === "choose" || pane.phase === "sign-in")
                    Pill {
                        objectName: "genie-open"
                        label: words.i18n("Open Genie")
                        tall: true
                        light: true
                        onActivated: pane.grow()
                    }
                }
                Row {
                    spacing: 8
                    visible: pane.answering
                    Pill {
                        objectName: "genie-stop"
                        label: words.i18n("Stop")
                        tall: true
                        onActivated: pane.genie.cancel()
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    visible: !!pane.genie && pane.phase === "ready" && pane.genie.answer !== ""
                    // Do it, where the answer asks for a change: unavailable,
                    // with why, until Genie may make it.
                    Pill {
                        objectName: "genie-do-it"
                        visible: !!pane.genie && (pane.genie.canDoIt || pane.genie.doItReason !== "")
                        label: words.i18n("Do it")
                        tall: true
                        light: true
                        dimmed: !pane.genie || !pane.genie.canDoIt
                        onActivated: pane.genie.act("do-it")
                    }
                    Pill {
                        objectName: "genie-show-me-how"
                        label: words.i18n("Show me how")
                        tall: true
                        onActivated: pane.genie.act("show-me-how")
                    }
                    Pill {
                        objectName: "genie-keep"
                        label: pane.genie && pane.genie.kept ? words.i18n("Kept") : words.i18n("Keep this")
                        tall: true
                        onActivated: pane.genie.act("keep")
                    }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    color: "#A8A8B0"
                    font.pixelSize: 13
                    text: pane.genie && pane.phase === "ready" && pane.genie.answer !== "" && !pane.genie.canDoIt
                        ? pane.genie.doItReason : ""
                }
                // Why the last request could not be done, outside a failed
                // answer, which says it above.
                Text {
                    objectName: "genie-problem"
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    color: "#E08A80"
                    font.pixelSize: 13
                    text: pane.genie && pane.phase !== "failed" ? pane.genie.problem : ""
                }
            }
        }
    }

    component Pill: ModePill {
        primaryText: pane.primaryText
        surfaceColor: pane.surfaceColor
        controlColor: pane.controlColor
    }
}
