/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import QtQuick.Window
import org.kde.kirigami as Kirigami

// The island opened: a clear surface over the whole display with the island
// grown out of its place in the band into a black card. A tap outside it or
// Esc closes it back into the band. The applet places the surface; this file
// draws it and asks the surface below to act.
Window {
    id: overlay
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)); }
    // Its words come from the panel widget's catalog, the one Plasma gives
    // the widget, so they translate in the panel and in tests alike.
    KI18nContext {
        id: words
        translationDomain: "plasma_applet_co.goodinput.tettegouche"
    }

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

    title: words.i18n("Ambient")
    color: "transparent"
    flags: Qt.FramelessWindowHint

    AmbientColors {
        id: tone
        theme: card.Kirigami.Theme
    }
    readonly property color ink: tone.text
    readonly property real openWidth: Math.min(384, width - 16)
    // The card grows up from the band, and no taller than the room above it;
    // what does not fit scrolls. A band reaching past the display's bottom,
    // as a panel tucked away under another surface does, is taken as ending
    // at the display's edge, so the card's foot stays on it.
    readonly property real bandFoot: Math.min(start.y + start.height, height)
    readonly property real openRoom: Math.max(120, bandFoot - 8)
    readonly property real openHeight: Math.min(content.implicitHeight + 36, openRoom)
    readonly property real openX: Math.max(8, Math.min(width - 8 - openWidth,
        Math.max(sideLeft, Math.min(sideRight - openWidth, start.x + start.width / 2 - openWidth / 2))))
    readonly property real openY: Math.max(8, bandFoot - openHeight)
    readonly property var activity: kind === "media" ? (surface ? surface.player : null) : null
    // The fact from Core the card answers, while Core still asks it.
    readonly property var question: kind === "core" && surface && surface.coreAsks ? surface.coreShown : null
    onQuestionChanged: if (kind === "core" && question === null) dismiss()
    // An answer goes to Core, which takes the fact off the island.
    function answer(action) {
        if (question) surface.invoke(question, action);
        dismiss();
    }

    // The keeper of saved layouts, for Layouts: the widget, which asks Split
    // Rock's Core. It lists `layouts`, reads `currentLayout` on
    // readCurrentLayout(), and saves, opens, and removes them.
    property var layouts: null
    readonly property var savedLayouts: kind === "layouts" && layouts && layouts.layouts ? layouts.layouts : []
    // Layouts shows the saved layouts, or the form that saves what's open.
    property bool savingLayout: false
    // The saved layout whose Remove shows, by its id.
    property string chosenLayout: ""
    // The form: what is open, less the groups taken out; whether Core has
    // answered; and the workspace's name.
    property var keptGroups: []
    property bool currentRead: false
    property string workspaceName: ""
    readonly property bool canSave: layoutName.text.trim().length > 0 && keptGroups.length > 0
    onKindChanged: {
        savingLayout = false;
        chosenLayout = "";
    }
    function saveWhatsOpen() {
        keptGroups = [];
        currentRead = false;
        workspaceName = "";
        layoutName.text = "";
        savingLayout = true;
        layoutName.forceActiveFocus();
        if (layouts) layouts.readCurrentLayout();
    }
    function takeCurrent() {
        const current = layouts ? layouts.currentLayout : null;
        if (!savingLayout || !current || current.available === undefined) return;
        keptGroups = current.available && current.groups ? current.groups.slice() : [];
        workspaceName = current.workspaceName || "";
        currentRead = true;
    }
    Connections {
        target: overlay.layouts
        ignoreUnknownSignals: true
        function onCurrentLayoutChanged() { overlay.takeCurrent(); }
    }
    // Open, Save and Not now close the island; Core and Cards do the rest.
    function openLayout(id) {
        if (layouts) layouts.openLayout(id);
        dismiss();
    }
    function saveLayout() {
        if (!canSave) return;
        if (layouts) layouts.saveLayout(layoutName.text.trim(), keptGroups, false);
        dismiss();
    }

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
        interval: overlay.ms(320)
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
            Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
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
        color: filled ? overlay.ink : tone.wash(pillArea.pressed ? 0.22 : 0.12)
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
        Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.filled ? tone.textOnInk : overlay.ink
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            onClicked: pill.activated()
        }
    }

    // A saved layout drawn small: each group a card, a Stack's cards fanned
    // 5 px behind its front one, and its apps' names beneath.
    component Miniature: Flow {
        id: miniature
        property var groups: []
        spacing: 8
        Repeater {
            model: miniature.groups
            delegate: Column {
                id: drawn
                required property var modelData
                readonly property var names: modelData.names || modelData.apps || []
                readonly property int fanned: Math.min(3, Math.max(1, names.length))
                spacing: 4
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64 + 5 * (drawn.fanned - 1)
                    height: 44 + 5 * (drawn.fanned - 1)
                    Repeater {
                        model: drawn.fanned
                        delegate: Rectangle {
                            required property int index
                            x: 5 * (drawn.fanned - 1 - index)
                            y: 5 * (drawn.fanned - 1 - index)
                            z: -index
                            width: 64
                            height: 44
                            radius: 6
                            color: tone.over(0.14)
                            border.width: 1
                            border.color: tone.wash(0.35)
                            opacity: [1, 0.7, 0.45][index]
                            Text {
                                anchors.fill: parent
                                anchors.margins: 4
                                visible: parent.index === 0
                                text: drawn.names[0] || ""
                                color: overlay.ink
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(92, implicitWidth)
                    text: drawn.names.join(words.i18nc("@info between apps in a Stack", ", "))
                    font.pixelSize: 11
                    opacity: 0.66
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
            }
        }
    }

    component Art: Item {
        id: art
        property var activity: null
        property real corner: 10
        Rectangle {
            anchors.fill: parent
            radius: art.corner
            color: tone.art
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
            id: ring
            anchors.fill: parent
            visible: progressMark.known
            readonly property real value: progressMark.known ? Number(progressMark.activity.progress) : 0
            readonly property color ink: overlay.ink
            onValueChanged: requestPaint()
            onInkChanged: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const thickness = 3.5;
                const radius = Math.min(width, height) / 2 - thickness / 2 - 0.5;
                context.lineWidth = thickness;
                context.lineCap = "round";
                context.strokeStyle = tone.wash(0.22);
                context.beginPath();
                context.arc(width / 2, height / 2, radius, 0, 2 * Math.PI, false);
                context.stroke();
                context.strokeStyle = ring.ink;
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
        color: tone.card
        border.width: 1
        border.color: tone.wash(0.12)
        clip: true
        Behavior on x { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on y { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on width { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on height { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

        // Taps on the card itself stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            id: scroller
            objectName: "ambient-island-scroll"
            x: 18
            y: 18
            width: overlay.openWidth - 36
            height: Math.max(0, card.height - 36)
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            interactive: contentHeight > height + 0.5
            boundsBehavior: Flickable.StopAtBounds
            // A wheel notch scrolls 80 pixels at Plasma's usual three lines per notch.
            Kirigami.WheelHandler { target: scroller; verticalStepSize: Qt.styleHints.wheelScrollLines * 80 / 3 }

            Column {
                id: content
                width: overlay.openWidth - 36
                spacing: 14
                opacity: overlay.expanded ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: overlay.ms(overlay.expanded ? 260 : 90)
                        easing.type: overlay.expanded ? Easing.InQuad : Easing.Linear
                    }
                }

                // With more than one kind going on, a row to move between them.
                Row {
                    objectName: "ambient-island-kinds"
                    visible: overlay.kind !== "core" && overlay.kind !== "layouts" && overlay.surface !== null
                        && overlay.surface.kinds.length > 1
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
                            Accessible.name: modelData === "media" ? words.i18n("Media") : words.i18n("Transfers")
                            Keys.onReturnPressed: overlay.kind = modelData
                            Keys.onSpacePressed: overlay.kind = modelData
                            Item {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                opacity: overlay.kind === choice.modelData ? 1 : 0.45
                                scale: overlay.kind === choice.modelData ? 1.12 : 1
                                Behavior on scale { NumberAnimation { duration: overlay.ms(160); easing.type: Easing.OutBack } }
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
                                text: overlay.activity ? overlay.activity.title || overlay.activity.source || words.i18n("Media") : ""
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
                        Accessible.name: words.i18n("Position")
                        // Focused, the arrows move the media five seconds at a time.
                        activeFocusOnTab: movable
                        function step(byUs) {
                            overlay.surface.invoke(overlay.activity, "seekTo",
                                Math.round(Math.max(0, Math.min(lengthUs, positionUs + byUs))));
                        }
                        Keys.onLeftPressed: if (movable) step(-5000000)
                        Keys.onRightPressed: if (movable) step(5000000)
                        Rectangle {
                            y: 12
                            width: parent.width
                            height: 4
                            radius: 2
                            color: tone.wash(0.22)
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
                                scale: seekArea.pressed || seek.activeFocus ? 1.5 : 1
                                Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
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
                            label: words.i18n("Previous")
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
                            color: tone.wash(0.14)
                            border.width: activeFocus ? 1 : 0
                            border.color: overlay.ink
                            scale: toggleArea.pressed ? 1.1 : 1
                            activeFocusOnTab: visible
                            Accessible.role: Accessible.Button
                            Accessible.name: playing ? words.i18n("Pause") : words.i18n("Play")
                            Accessible.onPressAction: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Keys.onReturnPressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Keys.onSpacePressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
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
                            label: words.i18n("Next")
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
                            Accessible.name: words.i18n("Show %1 here", modelData.source || modelData.title || "")
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
                                        other.playing ? words.i18n("playing") : words.i18n("paused")]
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
                                label: other.playing ? words.i18n("Pause %1", other.modelData.source || other.modelData.title || "")
                                    : words.i18n("Play %1", other.modelData.source || other.modelData.title || "")
                                onActivated: overlay.surface.invoke(other.modelData, other.playing ? "pause" : "play")
                            }
                        }
                    }

                    PillButton {
                        objectName: "ambient-island-raise"
                        anchors.right: parent.right
                        visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "raise")
                        label: words.i18n("Show %1", overlay.activity ? overlay.activity.source || words.i18n("player") : "")
                        onActivated: {
                            overlay.surface.invoke(overlay.activity, "raise");
                            overlay.dismiss();
                        }
                    }
                }

                // A question from Core: its icon, the question and its detail,
                // then its answers as pills, the tap's own first and Not now
                // last, with the choices Core lists between them.
                Column {
                    objectName: "ambient-island-core"
                    visible: overlay.question !== null
                    width: parent.width
                    spacing: 14
                    Row {
                        width: parent.width
                        spacing: 12
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 10
                            color: tone.art
                            Kirigami.Icon {
                                objectName: "ambient-island-core-icon"
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: overlay.surface ? overlay.surface.coreIcon : ""
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 52
                            spacing: 2
                            Label {
                                objectName: "ambient-island-core-line"
                                width: parent.width
                                text: overlay.question ? overlay.question.line || overlay.question.title || "" : ""
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                            }
                            Label {
                                objectName: "ambient-island-core-detail"
                                width: parent.width
                                visible: text.length > 0
                                text: overlay.question ? overlay.question.detail || "" : ""
                                opacity: 0.66
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                            }
                        }
                    }
                    Flow {
                        objectName: "ambient-island-core-answers"
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-core-open"
                            filled: true
                            label: overlay.question ? overlay.question.actionText || words.i18n("Open") : ""
                            onActivated: overlay.answer("open")
                        }
                        Repeater {
                            model: overlay.surface ? overlay.surface.coreChoices : []
                            delegate: PillButton {
                                required property var modelData
                                objectName: "ambient-island-core-choice-" + modelData.action
                                label: modelData.text
                                onActivated: overlay.answer(modelData.action)
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-core-not-now"
                            label: overlay.surface ? overlay.surface.coreNotNow : ""
                            onActivated: overlay.answer("not-now")
                        }
                    }
                }

                // Layouts, asked for from Search: each saved layout drawn
                // small with its Open pill, then Save what's open and Close.
                Column {
                    objectName: "ambient-island-layouts"
                    visible: overlay.kind === "layouts" && !overlay.savingLayout
                    width: parent.width
                    spacing: 12
                    Row {
                        spacing: 0
                        Label {
                            id: layoutsTitle
                            objectName: "ambient-island-layouts-title"
                            text: words.i18nc("@title the saved layouts", "Layouts")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Label {
                            objectName: "ambient-island-layouts-count"
                            anchors.baseline: layoutsTitle.baseline
                            visible: overlay.savedLayouts.length > 0
                            text: words.i18ncp("@title after Layouts", " · %1 saved", " · %1 saved", overlay.savedLayouts.length)
                            opacity: 0.66
                        }
                    }
                    Label {
                        objectName: "ambient-island-layouts-none"
                        width: parent.width
                        visible: overlay.savedLayouts.length === 0
                        text: words.i18n("Nothing saved yet. Arrange your apps, then save what's open.")
                        opacity: 0.66
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.savedLayouts
                            delegate: Rectangle {
                                id: saved
                                required property var modelData
                                required property int index
                                readonly property bool chosen: overlay.chosenLayout === modelData.id
                                objectName: "ambient-island-layout-" + modelData.id
                                width: parent.width
                                height: savedColumn.implicitHeight + 24
                                radius: 10
                                color: tone.wash(savedArea.pressed ? 0.12 : 0.075)
                                Accessible.role: Accessible.ListItem
                                Accessible.name: modelData.name
                                // A tap on the row, off its pill, shows its own
                                // Remove.
                                MouseArea {
                                    id: savedArea
                                    anchors.fill: parent
                                    onClicked: overlay.chosenLayout = saved.chosen ? "" : saved.modelData.id
                                }
                                Column {
                                    id: savedColumn
                                    x: 12
                                    y: 12
                                    width: parent.width - 24 - openSaved.width - 12
                                    spacing: 10
                                    Column {
                                        width: parent.width
                                        spacing: 2
                                        Label {
                                            width: parent.width
                                            text: saved.modelData.name
                                            font.pixelSize: 15
                                        }
                                    }
                                    Miniature {
                                        objectName: "ambient-island-layout-miniature-" + saved.modelData.id
                                        width: parent.width
                                        groups: saved.modelData.groups || []
                                    }
                                    Column {
                                        width: parent.width
                                        visible: saved.chosen
                                        spacing: 8
                                        PillButton {
                                            objectName: "ambient-island-layout-remove-" + saved.modelData.id
                                            height: 32
                                            label: words.i18nc("@action:button forgets a saved layout", "Remove")
                                            onActivated: {
                                                overlay.chosenLayout = "";
                                                if (overlay.layouts) overlay.layouts.removeLayout(saved.modelData.id);
                                            }
                                        }
                                    }
                                }
                                PillButton {
                                    id: openSaved
                                    objectName: "ambient-island-layout-open-" + saved.modelData.id
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    y: 12
                                    height: 32
                                    filled: saved.index === 0
                                    label: words.i18nc("@action:button opens a saved layout", "Open")
                                    Accessible.name: words.i18nc("@action:button a saved layout's name", "Open %1", saved.modelData.name)
                                    onActivated: overlay.openLayout(saved.modelData.id)
                                }
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-layouts-save"
                            filled: true
                            label: words.i18n("Save what's open")
                            onActivated: overlay.saveWhatsOpen()
                        }
                        PillButton {
                            objectName: "ambient-island-layouts-close"
                            label: words.i18n("Close")
                            onActivated: overlay.dismiss()
                        }
                    }
                }

                // The same island as a form: a name, what is open on this
                // workspace group by group, each with Remove; then Save and
                // Not now.
                Column {
                    objectName: "ambient-island-layout-form"
                    visible: overlay.kind === "layouts" && overlay.savingLayout
                    width: parent.width
                    spacing: 12
                    Row {
                        width: parent.width
                        Label {
                            id: formTitle
                            text: words.i18n("Save this layout")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Label {
                            objectName: "ambient-island-layout-form-where"
                            anchors.baseline: formTitle.baseline
                            width: parent.width - formTitle.width
                            text: overlay.workspaceName.length > 0
                                ? words.i18nc("@title after Save this layout, a workspace's name", " · what's open on %1", overlay.workspaceName)
                                : words.i18nc("@title after Save this layout", " · what's open")
                            opacity: 0.66
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 10
                        color: tone.wash(0.075)
                        border.width: layoutName.activeFocus ? 1 : 0
                        border.color: tone.wash(0.35)
                        TextInput {
                            id: layoutName
                            objectName: "ambient-island-layout-name"
                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            color: overlay.ink
                            font.pixelSize: 15
                            clip: true
                            selectByMouse: true
                            Accessible.role: Accessible.EditableText
                            Accessible.name: words.i18n("Name")
                            onAccepted: overlay.saveLayout()
                        }
                        Label {
                            anchors.left: layoutName.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: layoutName.text.length === 0
                            text: words.i18n("Name it, such as Coding")
                            font.pixelSize: 15
                            opacity: 0.45
                        }
                    }
                    Label {
                        objectName: "ambient-island-layout-form-empty"
                        width: parent.width
                        visible: overlay.keptGroups.length === 0
                        text: overlay.currentRead ? words.i18n("Nothing open here to save. Arrange your apps, then come back.")
                            : words.i18n("Looking at what's open…")
                        opacity: 0.66
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.keptGroups
                            delegate: Rectangle {
                                id: kept
                                required property var modelData
                                required property int index
                                readonly property var names: modelData.names || modelData.apps || []
                                objectName: "ambient-island-layout-group-" + index
                                width: parent.width
                                height: Math.max(44, keptWords.implicitHeight + 24)
                                radius: 10
                                color: tone.wash(0.075)
                                Column {
                                    id: keptWords
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24 - removeGroup.width - 12
                                    spacing: 2
                                    Label {
                                        objectName: "ambient-island-layout-group-title-" + kept.index
                                        width: parent.width
                                        text: kept.modelData.stack ? words.i18nc("@info apps together in one Stack", "Stack") : kept.names[0] || ""
                                        font.pixelSize: 15
                                    }
                                    Label {
                                        objectName: "ambient-island-layout-group-line-" + kept.index
                                        width: parent.width
                                        text: kept.modelData.stack ? kept.names.join(words.i18nc("@info between apps in a Stack", ", "))
                                            : words.i18nc("@info an app not in a Stack", "On its own")
                                        opacity: 0.66
                                    }
                                }
                                PillButton {
                                    id: removeGroup
                                    objectName: "ambient-island-layout-group-remove-" + kept.index
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 32
                                    label: words.i18nc("@action:button takes a group out of the layout", "Remove")
                                    onActivated: overlay.keptGroups = overlay.keptGroups.filter((group, at) => at !== kept.index)
                                }
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-layout-form-save"
                            filled: true
                            opacity: overlay.canSave ? 1 : 0.4
                            label: words.i18nc("@action:button saves the layout", "Save")
                            onActivated: overlay.saveLayout()
                        }
                        PillButton {
                            objectName: "ambient-island-layout-form-not-now"
                            label: words.i18n("Not now")
                            onActivated: overlay.dismiss()
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
                            ? words.i18np("1 transfer", "%1 transfers", overlay.surface.transfers.length) : words.i18n("Transfer")
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
                                        text: row.suspended ? words.i18n("Paused")
                                            : overlay.surface && overlay.surface.ended(row.modelData) ? row.modelData.description || ""
                                            : row.modelData.evidence === "filesystem" ? words.i18n("Incoming file · completion unknown")
                                            : overlay.surface ? overlay.surface.transferBytes(row.modelData) || overlay.surface.percentage(row.modelData) : ""
                                        color: row.suspended ? tone.waitingText : overlay.ink
                                        opacity: row.suspended ? 1 : 0.66
                                        font.pixelSize: 12
                                    }
                                }
                                GlyphButton {
                                    id: pauseButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: overlay.surface !== null && overlay.surface.capability(row.modelData, row.suspended ? "resume" : "suspend")
                                    glyph: row.suspended ? "play" : "pause"
                                    label: row.suspended ? words.i18n("Resume") : words.i18n("Pause transfer")
                                    onActivated: overlay.surface.invoke(row.modelData, row.suspended ? "resume" : "suspend")
                                }
                                GlyphButton {
                                    id: cancelButton
                                    objectName: "ambient-island-cancel-" + row.modelData.id
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "cancel")
                                    glyph: "x"
                                    label: words.i18n("Cancel %1", overlay.surface ? overlay.surface.transferTitle(row.modelData) : "")
                                    onActivated: overlay.surface.invoke(row.modelData, "cancel")
                                }
                            }
                            PillButton {
                                objectName: "ambient-island-show-" + row.modelData.id
                                anchors.right: parent.right
                                visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "showInFiles")
                                label: words.i18n("Show in Files")
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
}
