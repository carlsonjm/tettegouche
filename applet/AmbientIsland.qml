/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

// The island opened: a clear surface over the whole display with the island
// grown out of its place in the band into a black card. A tap outside it or
// Esc closes it back into the band. The applet places the surface; this file
// draws it and asks the surface below to act.
Window {
    id: overlay

    // The closed island this one grew from, which holds the activities.
    property var surface: null
    property string kind: "media"
    // Where the closed island sits, and the side of the band it belongs to,
    // in this surface's coordinates.
    property rect start: Qt.rect(0, 0, 44, 44)
    property real sideLeft: 0
    property real sideRight: width
    property bool expanded: false
    signal closed()

    title: qsTr("Ambient")
    color: "transparent"
    flags: Qt.FramelessWindowHint

    readonly property color ink: "#F8F8FF"
    readonly property real openWidth: Math.min(384, width - 16)
    readonly property real openHeight: content.implicitHeight + 36
    readonly property real openX: Math.max(8, Math.min(width - 8 - openWidth,
        Math.max(sideLeft, Math.min(sideRight - openWidth, start.x + start.width / 2 - openWidth / 2))))
    readonly property real openY: Math.max(8, start.y + start.height - openHeight)
    readonly property var activity: kind === "media" ? (surface ? surface.player : null) : null

    // Not close(): that is the window's own, and would drop it at once.
    function dismiss() {
        if (!expanded) return;
        expanded = false;
        closing.restart();
    }
    Timer {
        id: opening
        interval: 30
        onTriggered: overlay.expanded = true
    }
    Timer {
        id: closing
        interval: 320
        onTriggered: overlay.closed()
    }
    onVisibleChanged: if (visible) opening.restart()
    onActiveChanged: if (!active && expanded && visible) dismiss()

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.dismiss()
    }

    // A tap anywhere outside the card closes the island.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.dismiss()
    }

    // ---------------------------------------------------------------- pieces

    component Label: Text {
        color: overlay.ink
        font.pixelSize: 13
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    component GlyphButton: Item {
        id: button
        property string glyph
        property real size: 22
        property string label
        signal activated()
        width: 44
        height: 44
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        SuiteIcon {
            anchors.centerIn: parent
            width: button.size
            height: button.size
            glyph: button.glyph
            scale: buttonArea.pressed ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        Rectangle {
            anchors.centerIn: parent
            width: button.size + 14
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: overlay.ink
            opacity: 0.6
            visible: button.activeFocus
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            onClicked: button.activated()
        }
    }

    component PillButton: Rectangle {
        id: pill
        property string label
        property bool filled: false
        signal activated()
        height: 40
        width: Math.max(40, pillText.implicitWidth + 28)
        radius: height / 2
        color: filled ? overlay.ink : Qt.rgba(248 / 255, 248 / 255, 1, pillArea.pressed ? 0.22 : 0.12)
        scale: pillArea.pressed ? 1.04 : 1
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        border.width: activeFocus ? 1 : 0
        border.color: overlay.ink
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.filled ? "#000000" : overlay.ink
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            onClicked: pill.activated()
        }
    }

    component Art: Item {
        id: art
        property var activity: null
        property real corner: 8
        Rectangle {
            anchors.fill: parent
            radius: art.corner
            color: "#2A2A2F"
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.6)
                height: width
                source: art.activity && art.activity.icon ? art.activity.icon : "audio-x-generic-symbolic"
            }
        }
        Kirigami.ShadowedImage {
            anchors.fill: parent
            radius: art.corner
            color: "transparent"
            source: art.activity && art.activity.artUrl ? art.activity.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    component Progress: Item {
        id: progressMark
        property var activity: null
        property bool showNumber: false
        readonly property bool known: activity !== null && activity !== undefined
            && activity.progress !== undefined && activity.progress !== null
        Canvas {
            anchors.fill: parent
            visible: progressMark.known
            readonly property real value: progressMark.known ? Number(progressMark.activity.progress) : 0
            onValueChanged: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const thickness = 3.5;
                const radius = Math.min(width, height) / 2 - thickness / 2 - 0.5;
                context.lineWidth = thickness;
                context.lineCap = "round";
                context.strokeStyle = "rgba(248,248,255,0.22)";
                context.beginPath();
                context.arc(width / 2, height / 2, radius, 0, 2 * Math.PI, false);
                context.stroke();
                context.strokeStyle = "#F8F8FF";
                context.beginPath();
                context.arc(width / 2, height / 2, radius, -Math.PI / 2,
                    -Math.PI / 2 + 2 * Math.PI * Math.max(0, Math.min(1, value)), false);
                context.stroke();
            }
        }
        Text {
            anchors.centerIn: parent
            visible: progressMark.known && progressMark.showNumber
            text: progressMark.known ? Math.round(Number(progressMark.activity.progress) * 100) : ""
            color: overlay.ink
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
        }
        SuiteIcon {
            anchors.centerIn: parent
            visible: !progressMark.known
            width: Math.round(parent.width * 0.55)
            height: width
            glyph: "download"
        }
    }

    // ---------------------------------------------------------------- card

    Rectangle {
        id: card
        objectName: "ambient-island-open"
        x: overlay.expanded ? overlay.openX : overlay.start.x
        y: overlay.expanded ? overlay.openY : overlay.start.y
        width: overlay.expanded ? overlay.openWidth : overlay.start.width
        height: overlay.expanded ? overlay.openHeight : overlay.start.height
        // A pill in the band, and a note once open: Shuffle's 12 px for what
        // floats above everything and closes.
        radius: Math.min(height / 2, 12)
        color: "#000000"
        border.width: 1
        border.color: Qt.rgba(248 / 255, 248 / 255, 1, 0.12)
        clip: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

        // Taps on the card itself stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            x: 18
            y: 18
            width: overlay.openWidth - 36
            spacing: 14
            opacity: overlay.expanded ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: overlay.expanded ? 260 : 90
                    easing.type: overlay.expanded ? Easing.InQuad : Easing.Linear
                }
            }

            // With more than one kind going on, a row to move between them.
            Row {
                objectName: "ambient-island-kinds"
                visible: overlay.surface !== null && overlay.surface.kinds.length > 1
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: overlay.surface ? overlay.surface.kinds : []
                    delegate: Item {
                        id: choice
                        required property string modelData
                        width: 44
                        height: 40
                        activeFocusOnTab: true
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData === "media" ? qsTr("Media") : qsTr("Transfers")
                        Keys.onReturnPressed: overlay.kind = modelData
                        Keys.onSpacePressed: overlay.kind = modelData
                        Item {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            opacity: overlay.kind === choice.modelData ? 1 : 0.45
                            scale: overlay.kind === choice.modelData ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Art {
                                anchors.fill: parent
                                visible: choice.modelData === "media"
                                activity: overlay.surface ? overlay.surface.player : null
                                corner: width / 2
                            }
                            Progress {
                                anchors.fill: parent
                                visible: choice.modelData === "transfer"
                                activity: overlay.surface ? overlay.surface.firstTransfer : null
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: overlay.kind = choice.modelData }
                    }
                }
            }

            // Music.
            Column {
                objectName: "ambient-island-media"
                visible: overlay.kind === "media" && overlay.activity !== null
                width: parent.width
                spacing: 10

                Row {
                    spacing: 14
                    Art {
                        width: 64
                        height: 64
                        activity: overlay.activity
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - 78
                        spacing: 2
                        Label {
                            width: parent.width
                            text: overlay.activity ? overlay.activity.title || overlay.activity.source || qsTr("Media") : ""
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                        Label {
                            width: parent.width
                            visible: text.length > 0
                            text: overlay.activity ? [overlay.activity.artist, overlay.activity.album]
                                .filter(Boolean).join(" · ") : ""
                            font.pixelSize: 14
                            opacity: 0.66
                        }
                        Row {
                            spacing: 6
                            Kirigami.Icon {
                                width: 14
                                height: 14
                                source: overlay.activity && overlay.activity.icon ? overlay.activity.icon : ""
                            }
                            Label {
                                text: overlay.activity ? overlay.activity.source || "" : ""
                                font.pixelSize: 12
                                opacity: 0.66
                            }
                        }
                    }
                }

                // Where the track is, and a place to move it to.
                Item {
                    id: seek
                    objectName: "ambient-island-seek"
                    readonly property real lengthUs: overlay.activity && overlay.activity.durationUs !== undefined
                        ? Number(overlay.activity.durationUs) : 0
                    readonly property bool movable: lengthUs > 0 && overlay.surface
                        && overlay.surface.capability(overlay.activity, "seekTo")
                    readonly property real positionUs: seekArea.pressed ? dragUs
                        : overlay.surface ? overlay.surface.mediaPositionUs(overlay.activity) : 0
                    property real dragUs: 0
                    visible: lengthUs > 0
                    width: parent.width
                    height: 40
                    Accessible.role: Accessible.Slider
                    Accessible.name: qsTr("Position")
                    Rectangle {
                        y: 12
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(248 / 255, 248 / 255, 1, 0.22)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, seek.positionUs / Math.max(1, seek.lengthUs)))
                            height: parent.height
                            radius: 2
                            color: overlay.ink
                        }
                        Rectangle {
                            visible: seek.movable
                            x: parent.width * Math.max(0, Math.min(1, seek.positionUs / Math.max(1, seek.lengthUs))) - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: overlay.ink
                            scale: seekArea.pressed ? 1.5 : 1
                            Behavior on scale { NumberAnimation { duration: 90 } }
                        }
                    }
                    Label {
                        y: 22
                        text: overlay.surface ? overlay.surface.formatTime(seek.positionUs) : ""
                        font.pixelSize: 11
                        opacity: 0.66
                        font.features: ({ "tnum": 1 })
                    }
                    Label {
                        y: 22
                        anchors.right: parent.right
                        text: overlay.surface ? "−" + overlay.surface.formatTime(Math.max(0, seek.lengthUs - seek.positionUs)) : ""
                        font.pixelSize: 11
                        opacity: 0.66
                        font.features: ({ "tnum": 1 })
                    }
                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        enabled: seek.movable
                        preventStealing: true
                        function place(x) { seek.dragUs = Math.max(0, Math.min(1, x / width)) * seek.lengthUs; }
                        onPressed: mouse => place(mouse.x)
                        onPositionChanged: mouse => place(mouse.x)
                        onReleased: overlay.surface.invoke(overlay.activity, "seekTo", Math.round(seek.dragUs))
                    }
                }

                Row {
                    objectName: "ambient-island-transport"
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    GlyphButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "previous")
                        glyph: "skip-back"
                        label: qsTr("Previous")
                        onActivated: overlay.surface.invoke(overlay.activity, "previous")
                    }
                    Rectangle {
                        id: bigToggle
                        objectName: "ambient-island-toggle"
                        readonly property bool playing: overlay.activity !== null && overlay.activity.state === "playing"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, playing ? "pause" : "play")
                        width: 56
                        height: 56
                        radius: 28
                        color: Qt.rgba(248 / 255, 248 / 255, 1, 0.14)
                        border.width: activeFocus ? 1 : 0
                        border.color: overlay.ink
                        scale: toggleArea.pressed ? 1.1 : 1
                        activeFocusOnTab: visible
                        Accessible.role: Accessible.Button
                        Accessible.name: playing ? qsTr("Pause") : qsTr("Play")
                        Accessible.onPressAction: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                        Keys.onReturnPressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                        Keys.onSpacePressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        SuiteIcon {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            glyph: bigToggle.playing ? "pause" : "play"
                        }
                        MouseArea {
                            id: toggleArea
                            anchors.fill: parent
                            onClicked: overlay.surface.invoke(overlay.activity, bigToggle.playing ? "pause" : "play")
                        }
                    }
                    GlyphButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "next")
                        glyph: "skip-forward"
                        label: qsTr("Next")
                        onActivated: overlay.surface.invoke(overlay.activity, "next")
                    }
                }

                // The other players, waiting here rather than in the band.
                Repeater {
                    model: overlay.surface ? overlay.surface.otherPlayers : []
                    delegate: Item {
                        id: other
                        required property var modelData
                        width: content.width
                        height: 40
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Show %1 here").arg(modelData.source || modelData.title || "")
                        Keys.onReturnPressed: overlay.surface.chosenPlayer = String(modelData.id)
                        Keys.onSpacePressed: overlay.surface.chosenPlayer = String(modelData.id)
                        readonly property bool playing: modelData.state === "playing"
                        MouseArea { anchors.fill: parent; onClicked: overlay.surface.chosenPlayer = String(other.modelData.id) }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Kirigami.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                source: other.modelData.icon || "audio-x-generic-symbolic"
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: content.width - 30 - 44
                                text: [other.modelData.source, other.modelData.title,
                                    other.playing ? qsTr("playing") : qsTr("paused")]
                                    .filter(Boolean).join(" · ")
                                font.pixelSize: 12
                                opacity: 0.66
                            }
                        }
                        // A waiting player plays or pauses from here, without
                        // taking the island.
                        GlyphButton {
                            objectName: "ambient-island-other-toggle-" + other.modelData.id
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: overlay.surface !== null
                                && overlay.surface.capability(other.modelData, other.playing ? "pause" : "play")
                            glyph: other.playing ? "pause" : "play"
                            size: 18
                            label: (other.playing ? qsTr("Pause %1") : qsTr("Play %1"))
                                .arg(other.modelData.source || other.modelData.title || "")
                            onActivated: overlay.surface.invoke(other.modelData, other.playing ? "pause" : "play")
                        }
                    }
                }

                PillButton {
                    objectName: "ambient-island-raise"
                    anchors.right: parent.right
                    visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "raise")
                    label: qsTr("Show %1").arg(overlay.activity ? overlay.activity.source || qsTr("player") : "")
                    onActivated: {
                        overlay.surface.invoke(overlay.activity, "raise");
                        overlay.dismiss();
                    }
                }
            }

            // Transfers, each with its own progress and actions.
            Column {
                objectName: "ambient-island-transfers"
                visible: overlay.kind === "transfer"
                width: parent.width
                spacing: 6
                Label {
                    text: overlay.surface && overlay.surface.transfers.length > 1
                        ? qsTr("%1 transfers").arg(overlay.surface.transfers.length) : qsTr("Transfer")
                    font.pixelSize: 12
                    opacity: 0.66
                }
                // Counted rather than listed: each update is a new list, and a
                // Repeater given a new list makes every row again, whose ring
                // then draws from blank. Rows stay while the count holds.
                Repeater {
                    model: overlay.surface ? overlay.surface.transfers.length : 0
                    delegate: Column {
                        id: row
                        required property int index
                        readonly property var modelData: overlay.surface && overlay.surface.transfers[index]
                            ? overlay.surface.transfers[index] : ({})
                        objectName: "ambient-island-transfer-" + modelData.id
                        readonly property bool suspended: modelData.state === "suspended"
                        width: content.width
                        spacing: 4
                        Row {
                            width: parent.width
                            height: 56
                            spacing: 10
                            Progress {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                activity: row.modelData
                                showNumber: true
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.width - 50 - (pauseButton.visible ? 54 : 0) - (cancelButton.visible ? 54 : 0)
                                Label {
                                    width: parent.width
                                    text: overlay.surface ? overlay.surface.transferTitle(row.modelData) : ""
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    width: parent.width
                                    text: row.suspended ? qsTr("Paused")
                                        : overlay.surface && overlay.surface.ended(row.modelData) ? row.modelData.description || ""
                                        : row.modelData.evidence === "filesystem" ? qsTr("Incoming file · completion unknown")
                                        : overlay.surface ? overlay.surface.transferBytes(row.modelData) || overlay.surface.percentage(row.modelData) : ""
                                    color: row.suspended ? "#E3B866" : overlay.ink
                                    opacity: row.suspended ? 1 : 0.66
                                    font.pixelSize: 12
                                }
                            }
                            GlyphButton {
                                id: pauseButton
                                anchors.verticalCenter: parent.verticalCenter
                                visible: overlay.surface !== null && overlay.surface.capability(row.modelData, row.suspended ? "resume" : "suspend")
                                glyph: row.suspended ? "play" : "pause"
                                label: row.suspended ? qsTr("Resume") : qsTr("Pause transfer")
                                onActivated: overlay.surface.invoke(row.modelData, row.suspended ? "resume" : "suspend")
                            }
                            GlyphButton {
                                id: cancelButton
                                objectName: "ambient-island-cancel-" + row.modelData.id
                                anchors.verticalCenter: parent.verticalCenter
                                visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "cancel")
                                glyph: "x"
                                label: qsTr("Cancel %1").arg(overlay.surface ? overlay.surface.transferTitle(row.modelData) : "")
                                onActivated: overlay.surface.invoke(row.modelData, "cancel")
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-show-" + row.modelData.id
                            anchors.right: parent.right
                            visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "showInFiles")
                            label: qsTr("Show in Files")
                            onActivated: {
                                overlay.surface.invoke(row.modelData, "showInFiles");
                                overlay.dismiss();
                            }
                        }
                    }
                }
            }
        }
    }
}
