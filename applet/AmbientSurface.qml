/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

// Ambient's island: one clear shape centred in the width the panel hands it,
// holding what is going on now. Music alone sits in the middle with its
// controls centred; the next kind of activity to arrive waits in a round
// bubble beside it, and the bubble counts what it holds. The band shows
// through the island, and where the band is black the island takes the same
// black, the suite's, so it melts into it. Opening
// the island is the applet's job; this surface only asks.
Item {
    id: surface

    property var activities: []
    property var monotonicClock: () => 0
    property double clockNowUs: 0
    // The band is black: a card is up, or Plasma's panel is opaque.
    property bool opaque: false
    // The island is open in its own surface, so the closed one steps aside.
    property bool opened: false
    // A player picked inside the open island, kept while it lasts.
    property string chosenPlayer: ""

    signal invokeRequested(string activityId, int generation, string action, var value)
    signal openRequested(string kind)

    // A 44 px island in Shuffle's 64 px band; a shorter panel gets a shorter
    // one. Each control reaches the island's full height and, where the panel
    // allows, 44 px across.
    readonly property real pillHeight: Math.max(24, Math.min(44, height - 8))
    readonly property real reach: Math.max(pillHeight, Math.min(44, height))
    readonly property real gap: 8
    readonly property real inset: 6

    readonly property var transfers: activities.filter(activity => activity.kind === "transfer")
    readonly property var players: activities.filter(activity => activity.kind === "media")

    // Arrival and playing order, kept across updates.
    property var arrivals: ({})
    property var startedPlaying: ({})
    property var lastStates: ({})
    property var kindArrivals: ({})
    property int serial: 0
    // What the island shows, worked out from those orders.
    property var kinds: []
    property var player: null
    property var otherPlayers: []

    readonly property string mainKind: kinds.length > 0 ? kinds[0] : ""
    readonly property bool shared: kinds.length > 1
    readonly property string bubbleKind: shared ? kinds[kinds.length - 1] : ""
    readonly property int bubbleCount: kinds.slice(1).reduce(
        (count, kind) => count + (kind === "transfer" ? transfers.length : 1), 0)
    readonly property var firstTransfer: transfers.length > 0 ? transfers[0] : null
    // Where the island and its bubble sit, for the surface that opens from them.
    readonly property Item islandItem: island
    readonly property Item bubbleItem: bubble

    onActivitiesChanged: track()
    onChosenPlayerChanged: choose()

    function track() {
        const arrivalsNext = {}, startedNext = {}, statesNext = {}, kindsNext = {};
        for (const activity of activities) {
            const key = String(activity.id);
            arrivalsNext[key] = key in arrivals ? arrivals[key] : ++serial;
            const playing = activity.state === "playing";
            startedNext[key] = playing && lastStates[key] !== "playing" ? ++serial
                : key in startedPlaying ? startedPlaying[key] : 0;
            statesNext[key] = activity.state;
            const kind = activity.kind === "media" ? "media" : "transfer";
            if (!(kind in kindsNext))
                kindsNext[kind] = kind in kindArrivals ? kindArrivals[kind] : ++serial;
        }
        arrivals = arrivalsNext;
        startedPlaying = startedNext;
        lastStates = statesNext;
        kindArrivals = kindsNext;
        kinds = Object.keys(kindsNext).sort((a, b) => kindsNext[a] - kindsNext[b]);
        choose();
    }

    // The player that started playing last keeps the island, unless the
    // person picked another inside it.
    function choose() {
        // Read the activities themselves: a binding derived from them may not
        // have caught up yet while their change is still being handled.
        const current = activities.filter(activity => activity.kind === "media");
        let best = null;
        for (const candidate of current) {
            if (String(candidate.id) === chosenPlayer) { best = candidate; break; }
            if (!best) { best = candidate; continue; }
            const a = startedPlaying[String(candidate.id)] || 0;
            const b = startedPlaying[String(best.id)] || 0;
            if (a > b || (a === b && arrivals[String(candidate.id)] > arrivals[String(best.id)]))
                best = candidate;
        }
        player = best;
        otherPlayers = current.filter(candidate => !best || candidate.id !== best.id);
    }

    function capability(activity, name) {
        return Boolean(activity && activity.capabilities && activity.capabilities[name]);
    }
    function invoke(activity, action, value) {
        if (activity)
            invokeRequested(String(activity.id), Number(activity.generation), action,
                value === undefined ? null : value);
    }
    function known(value) {
        return value !== undefined && value !== null;
    }
    function percentage(activity) {
        if (!activity || !known(activity.progress)) return "—";
        return Math.round(Math.max(0, Math.min(1, Number(activity.progress))) * 100) + "%";
    }
    function formatBytes(bytes) {
        if (!known(bytes)) return "";
        const value = Number(bytes);
        if (value >= 1000000000) return (value / 1000000000).toFixed(1) + " GB";
        if (value >= 1000000) return (value / 1000000).toFixed(1) + " MB";
        if (value >= 1000) return (value / 1000).toFixed(1) + " KB";
        return value + " B";
    }
    function transferBytes(activity) {
        if (!activity) return "";
        if (known(activity.processedBytes) && known(activity.totalBytes))
            return formatBytes(activity.processedBytes) + " of " + formatBytes(activity.totalBytes);
        if (known(activity.observedSizeBytes))
            return qsTr("File size %1").arg(formatBytes(activity.observedSizeBytes));
        return "";
    }
    // A transfer that has ended and waits out its minute says how it ended.
    function ended(activity) {
        return !!activity && (activity.state === "finished" || activity.state === "failed");
    }
    function transferTitle(activity) {
        return activity ? activity.title || activity.source || qsTr("Transfer") : "";
    }
    function mediaPositionUs(activity) {
        if (!activity) return 0;
        let position = Number(activity.positionUs || 0);
        if (activity.state === "playing" && activity.sampledAtMonotonicUs !== undefined) {
            const elapsed = Math.max(0, clockNowUs - Number(activity.sampledAtMonotonicUs));
            position += elapsed * Number(activity.rate === undefined ? 1 : activity.rate);
        }
        if (activity.durationUs !== undefined)
            position = Math.min(position, Number(activity.durationUs));
        return Math.max(0, position);
    }
    function formatTime(us) {
        const seconds = Math.floor(Number(us) / 1000000);
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }

    readonly property bool hasPlayingClock: players.some(activity =>
        activity.state === "playing" && activity.positionUs !== undefined)
    Timer {
        interval: 1000
        repeat: true
        running: surface.visible && surface.hasPlayingClock
        triggeredOnStart: true
        onTriggered: surface.clockNowUs = Number(surface.monotonicClock())
    }

    // ---------------------------------------------------------------- sizes

    // Music alone: art and title on one side, the controls in the middle, the
    // time and player on the other; each side gives way before a control does.
    readonly property var mediaControls: ["previous", "toggle", "next"].filter(name =>
        name === "toggle" || capability(player, name))
    readonly property bool canToggle: capability(player, player && player.state === "playing" ? "pause" : "play")
    readonly property real transportFull: (canToggle ? reach : 0)
        + (capability(player, "previous") ? reach : 0) + (capability(player, "next") ? reach : 0)
    readonly property real mediaSideRoom: Math.floor((width - 2 * inset - transportFull) / 2)
    readonly property bool showSkips: mediaSideRoom >= 0
    readonly property real transportWidth: showSkips ? transportFull : (canToggle ? reach : 0)
    readonly property real mediaSide: Math.max(0, Math.min(124, mediaSideRoom))
    readonly property bool mediaWords: mediaSide >= 84
    readonly property real artSize: Math.round(pillHeight * 0.68)
    readonly property real mediaFullWidth: 2 * inset + transportWidth
        + 2 * (mediaWords ? mediaSide : mediaSide >= artSize + 8 ? artSize + 8 : 0)
    // Music sharing the band: art, play or pause, and as much title as fits.
    readonly property real artLead: Math.max(0, (pillHeight - artSize) / 2 - inset)
    readonly property real mediaSmallFixed: artLead + artSize + 4 + (canToggle ? reach : 0) + 8
    readonly property real mediaSmallTitle: Math.max(0, Math.min(84,
        width - 2 * inset - mediaSmallFixed - gap - pillHeight))
    readonly property bool mediaSmallWords: mediaSmallTitle >= 24
    // Transfers first: progress, what and where, the percentage, and Cancel
    // when the source allows it.
    readonly property bool transferHasCancel: transfers.length === 1 && capability(firstTransfer, "cancel")
    readonly property real transferFixed: 1 + 8 + artSize + 8 + 40
        + (transferHasCancel ? 8 + reach : 0)
    readonly property string transferHeadline: transfers.length > 1
        ? qsTr("%1 transfers").arg(transfers.length) : transferTitle(firstTransfer)
    readonly property string transferDetail: transfers.length > 1 || !firstTransfer ? ""
        : ended(firstTransfer) ? firstTransfer.description || ""
        : firstTransfer.evidence === "filesystem" ? qsTr("Incoming file") : transferBytes(firstTransfer)
    TextMetrics { id: headlineMetrics; text: surface.transferHeadline; font.pixelSize: 13; font.weight: Font.DemiBold }
    TextMetrics { id: detailMetrics; text: surface.transferDetail; font.pixelSize: 11 }
    readonly property real transferWords: Math.max(0, Math.min(170,
        Math.ceil(Math.max(headlineMetrics.advanceWidth, pillHeight >= 40 ? detailMetrics.advanceWidth : 0)),
        width - 2 * inset - transferFixed - 8 - (shared ? gap + pillHeight : 0)))
    readonly property bool transferShowsWords: transferWords >= 48

    readonly property real islandWidth: {
        if (kinds.length === 0) return pillHeight;
        if (mainKind === "media")
            return shared ? 2 * inset + mediaSmallFixed + (mediaSmallWords ? mediaSmallTitle : 0)
                : mediaFullWidth;
        return 2 * inset + transferFixed + (transferShowsWords ? 8 + transferWords : 0);
    }
    readonly property real groupWidth: islandWidth + (shared ? gap + pillHeight : 0)
    readonly property real islandX: Math.max(0, Math.round((width - groupWidth) / 2))
    readonly property real islandY: Math.round((height - pillHeight) / 2)
    // The least the island needs: its first control, and the bubble.
    readonly property int minimumUsefulWidth: kinds.length === 0 ? 0
        : Math.ceil(2 * inset + (mainKind === "media" ? mediaSmallFixed : transferFixed)
            + (shared ? gap + pillHeight : 0))

    // ---------------------------------------------------------------- pieces

    // A control: the glyph rises under a finger or a press.
    component IslandButton: Item {
        id: button
        property string glyph
        property real size: 20
        property string label
        signal activated()
        width: surface.reach
        height: surface.reach
        activeFocusOnTab: true
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
            width: button.size + 12
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: "#F8F8FF"
            opacity: 0.6
            visible: button.activeFocus
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            onClicked: button.activated()
        }
    }

    component Label: Text {
        color: "#F8F8FF"
        font.pixelSize: surface.pillHeight >= 40 ? 13 : 12
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // Album art, or the player's own icon when there is none.
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
                width: Math.round(parent.width * 0.7)
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

    // A transfer's reported progress as a ring; the download mark alone when
    // the source reports none.
    component Progress: Item {
        id: progressMark
        property var activity: null
        readonly property bool known: activity !== null && surface.known(activity.progress)
        Canvas {
            id: ring
            anchors.fill: parent
            visible: progressMark.known
            readonly property real value: progressMark.known ? Number(progressMark.activity.progress) : 0
            onValueChanged: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const thickness = width < 26 ? 2.5 : 3;
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
        SuiteIcon {
            anchors.centerIn: parent
            visible: !progressMark.known
            width: Math.round(parent.width * 0.6)
            height: width
            glyph: "download"
        }
    }

    // One closed layout; the island shows the one that fits what is going on.
    component IslandLayout: Row {
        property bool active: false
        anchors.centerIn: parent
        height: surface.pillHeight
        opacity: active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // ---------------------------------------------------------------- island

    Rectangle {
        id: island
        objectName: "ambient-island"
        x: surface.islandX
        y: surface.islandY
        width: surface.islandWidth
        height: surface.pillHeight
        radius: height / 2
        color: surface.opaque ? "#141414" : Qt.rgba(248 / 255, 248 / 255, 1, 0.07)
        border.width: 1
        border.color: Qt.rgba(248 / 255, 248 / 255, 1, 0.10)
        opacity: surface.kinds.length > 0 ? 1 : 0
        visible: opacity > 0 && !surface.opened
        scale: islandArea.pressed ? 1.03 : 1
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: surface.mainKind === "media"
            ? qsTr("Media %1, open").arg(surface.player ? surface.player.title || surface.player.source || "" : "")
            : qsTr("%n transfer(s), open", "", surface.transfers.length)
        Accessible.onPressAction: surface.openRequested(surface.mainKind)
        Keys.onReturnPressed: surface.openRequested(surface.mainKind)
        Keys.onEnterPressed: surface.openRequested(surface.mainKind)
        Keys.onSpacePressed: surface.openRequested(surface.mainKind)

        Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }

        // A tap away from the controls opens the island.
        MouseArea {
            id: islandArea
            anchors.fill: parent
            onClicked: surface.openRequested(surface.mainKind)
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: "#F8F8FF"
            opacity: 0.5
            visible: island.activeFocus
        }

        // Music alone.
        IslandLayout {
            id: mediaFull
            objectName: "ambient-media-full"
            active: surface.mainKind === "media" && !surface.shared
            Item {
                width: surface.mediaWords ? surface.mediaSide
                    : surface.mediaSide >= surface.artSize + 8 ? surface.artSize + 8 : 0
                height: surface.pillHeight
                Art {
                    x: (surface.pillHeight - surface.artSize) / 2 - surface.inset
                    anchors.verticalCenter: parent.verticalCenter
                    width: surface.artSize
                    height: surface.artSize
                    visible: parent.width > 0
                    activity: surface.player
                    corner: surface.artSize > 26 ? 8 : 6
                }
                Column {
                    x: surface.artSize + 10
                    width: parent.width - x - 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.mediaWords
                    Label {
                        objectName: "ambient-media-title"
                        width: parent.width
                        text: surface.player ? surface.player.title || surface.player.source || qsTr("Media") : ""
                        font.weight: Font.DemiBold
                    }
                    Label {
                        objectName: "ambient-media-artist"
                        width: parent.width
                        visible: surface.pillHeight >= 40 && text.length > 0
                        text: surface.player && surface.player.artist ? surface.player.artist : ""
                        opacity: 0.66
                        font.pixelSize: 11
                    }
                }
            }
            Row {
                objectName: "ambient-media-transport"
                anchors.verticalCenter: parent.verticalCenter
                IslandButton {
                    objectName: "ambient-media-previous"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.showSkips && surface.capability(surface.player, "previous")
                    glyph: "skip-back"
                    label: qsTr("Previous")
                    onActivated: surface.invoke(surface.player, "previous")
                }
                IslandButton {
                    objectName: "ambient-media-toggle"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.canToggle
                    glyph: surface.player && surface.player.state === "playing" ? "pause" : "play"
                    size: 22
                    label: surface.player && surface.player.state === "playing" ? qsTr("Pause") : qsTr("Play")
                    onActivated: surface.invoke(surface.player,
                        surface.player && surface.player.state === "playing" ? "pause" : "play")
                }
                IslandButton {
                    objectName: "ambient-media-next"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.showSkips && surface.capability(surface.player, "next")
                    glyph: "skip-forward"
                    label: qsTr("Next")
                    onActivated: surface.invoke(surface.player, "next")
                }
            }
            Item {
                width: surface.mediaWords ? surface.mediaSide
                    : surface.mediaSide >= surface.artSize + 8 ? surface.artSize + 8 : 0
                height: surface.pillHeight
                Column {
                    anchors.right: playerIcon.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.mediaWords && surface.player !== null
                        && (surface.player.positionUs !== undefined || surface.player.durationUs !== undefined)
                    Label {
                        objectName: "ambient-media-time"
                        anchors.right: parent.right
                        text: surface.player && surface.player.positionUs !== undefined
                            ? surface.formatTime(surface.mediaPositionUs(surface.player)) : "—"
                        font.features: ({ "tnum": 1 })
                    }
                    Label {
                        anchors.right: parent.right
                        visible: surface.pillHeight >= 40 && surface.player !== null && surface.player.durationUs !== undefined
                        text: surface.player && surface.player.durationUs !== undefined
                            ? surface.formatTime(surface.player.durationUs) : ""
                        opacity: 0.66
                        font.pixelSize: 11
                        font.features: ({ "tnum": 1 })
                    }
                }
                Kirigami.Icon {
                    id: playerIcon
                    anchors.right: parent.right
                    anchors.rightMargin: (surface.pillHeight - width) / 2 - surface.inset
                    anchors.verticalCenter: parent.verticalCenter
                    width: surface.artSize > 26 ? 24 : 18
                    height: width
                    visible: parent.width > 0
                    source: surface.player && surface.player.icon ? surface.player.icon : "audio-x-generic-symbolic"
                }
            }
        }

        // Music sharing the band.
        IslandLayout {
            id: mediaSmall
            objectName: "ambient-media-small"
            active: surface.mainKind === "media" && surface.shared
            spacing: 0
            Item { width: surface.artLead; height: 1 }
            Art {
                anchors.verticalCenter: parent.verticalCenter
                width: surface.artSize
                height: surface.artSize
                activity: surface.player
                corner: surface.artSize > 26 ? 8 : 6
            }
            Item { width: 4; height: 1 }
            IslandButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: surface.canToggle
                glyph: surface.player && surface.player.state === "playing" ? "pause" : "play"
                size: 22
                label: surface.player && surface.player.state === "playing" ? qsTr("Pause") : qsTr("Play")
                onActivated: surface.invoke(surface.player,
                    surface.player && surface.player.state === "playing" ? "pause" : "play")
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: surface.mediaSmallTitle
                visible: surface.mediaSmallWords
                text: surface.player ? surface.player.title || surface.player.source || qsTr("Media") : ""
                font.weight: Font.DemiBold
            }
            Item { width: 8; height: 1 }
        }

        // Transfers first, alone or sharing the band.
        IslandLayout {
            id: transferLayout
            objectName: "ambient-transfer"
            active: surface.mainKind === "transfer"
            spacing: 8
            Item { width: 1; height: 1 }
            Progress {
                anchors.verticalCenter: parent.verticalCenter
                width: surface.artSize
                height: surface.artSize
                activity: surface.firstTransfer
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: surface.transferWords
                visible: surface.transferShowsWords
                Label {
                    objectName: "ambient-transfer-title"
                    width: parent.width
                    text: surface.transferHeadline
                    font.weight: Font.DemiBold
                }
                Label {
                    width: parent.width
                    visible: surface.pillHeight >= 40 && text.length > 0
                    text: surface.transferDetail
                    opacity: 0.66
                    font.pixelSize: 11
                }
            }
            Label {
                objectName: "ambient-transfer-progress"
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: surface.transfers.length > 1 ? "" : surface.percentage(surface.firstTransfer)
                font.features: ({ "tnum": 1 })
            }
            IslandButton {
                objectName: "ambient-transfer-cancel"
                anchors.verticalCenter: parent.verticalCenter
                visible: surface.transferHasCancel
                glyph: "x"
                label: qsTr("Cancel %1").arg(surface.transferTitle(surface.firstTransfer))
                onActivated: surface.invoke(surface.firstTransfer, "cancel")
            }
        }
    }

    // What arrived after the island's own activity.
    Rectangle {
        id: bubble
        objectName: "ambient-bubble"
        readonly property bool shown: surface.shared
        x: island.x + island.width + surface.gap
        y: surface.islandY
        width: surface.pillHeight
        height: surface.pillHeight
        radius: width / 2
        color: island.color
        border.width: 1
        border.color: island.border.color
        opacity: shown ? 1 : 0
        visible: opacity > 0 && !surface.opened
        scale: shown ? (bubbleArea.pressed ? 1.1 : 1) : 0.4
        activeFocusOnTab: shown
        Accessible.role: Accessible.Button
        Accessible.name: surface.bubbleKind === "media" ? qsTr("Media, open")
            : qsTr("%n transfer(s), open", "", surface.transfers.length)
        Accessible.onPressAction: surface.openRequested(surface.bubbleKind)
        Keys.onReturnPressed: surface.openRequested(surface.bubbleKind)
        Keys.onEnterPressed: surface.openRequested(surface.bubbleKind)
        Keys.onSpacePressed: surface.openRequested(surface.bubbleKind)
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }

        Art {
            anchors.centerIn: parent
            width: surface.artSize
            height: width
            visible: surface.bubbleKind === "media"
            activity: surface.player
            corner: width / 2
        }
        Progress {
            anchors.centerIn: parent
            width: surface.artSize
            height: width
            visible: surface.bubbleKind === "transfer"
            activity: surface.firstTransfer
        }
        Rectangle {
            objectName: "ambient-bubble-count"
            visible: surface.bubbleCount > 1
            x: parent.width - width * 0.8
            y: -4
            width: surface.pillHeight >= 40 ? 18 : 15
            height: width
            radius: width / 2
            color: "#F8F8FF"
            Text {
                anchors.centerIn: parent
                text: surface.bubbleCount
                color: "#000000"
                font.pixelSize: parent.width > 16 ? 11 : 10
                font.weight: Font.Bold
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: "#F8F8FF"
            opacity: 0.5
            visible: bubble.activeFocus
        }
        // A small bubble still takes a finger across the band.
        MouseArea {
            id: bubbleArea
            anchors.centerIn: parent
            width: Math.max(parent.width, surface.reach)
            height: Math.max(parent.height, surface.reach)
            enabled: bubble.shown
            onClicked: surface.openRequested(surface.bubbleKind)
        }
    }
}
