/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import "IslandRoom.js" as IslandRoom

// Ambient's band: what is going on now, one island for each kind of it,
// centred in the width the panel hands it. The islands share the band by
// turns (IslandRoom.js), and what cannot keep even its first piece folds into
// a round bubble that counts what it holds. Music alone keeps its controls in
// the middle; beside a neighbour, each island reads what it is, then its
// words, then its buttons. The band shows through the islands, and where the
// band is black they take the same black, the suite's, so they melt into it.
// Opening an island is the applet's job; this surface only asks.
Item {
    id: surface

    property var activities: []
    property var monotonicClock: () => 0
    property double clockNowUs: 0
    // The band is black: a card is up, or Plasma's panel is opaque.
    property bool opaque: false
    // An island is open in its own surface, so the closed ones step aside.
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
    // Art, a ring or a mark sits as far from the island's edge as its top.
    readonly property real lead: pillHeight - 2 * inset
    readonly property real artSize: Math.round(pillHeight * 0.68)
    // Tall enough for a second line of words.
    readonly property bool tall: pillHeight >= 40
    readonly property int labelSize: tall ? 13 : 12

    readonly property var transfers: activities.filter(activity => activity.kind === "transfer")
    readonly property var players: activities.filter(activity => activity.kind === "media")
    readonly property var running: transfers.filter(activity => !ended(activity))
    readonly property var endings: transfers.filter(activity => ended(activity))
    readonly property var drives: activities.filter(activity => activity.kind === "drive")
    readonly property var firstTransfer: transfers.length > 0 ? transfers[0] : null

    // Arrival and playing order, kept across updates.
    property var arrivals: ({})
    property var startedPlaying: ({})
    property var lastStates: ({})
    property var bandArrivals: ({})
    // Where each island sits, remembered while one that left fades from it.
    property var places: ({})
    property int serial: 0
    // What the band shows, worked out from those orders: its islands, and the
    // kinds the open island moves between, music and transfers.
    property var bandKinds: []
    property var kinds: []
    property var player: null
    property var otherPlayers: []
    // The newest island has the room until urgency settles it.
    property string room: ""

    readonly property bool alone: bandKinds.length === 1 && bandKinds[0] === "media"
    readonly property var plan: IslandRoom.layout(bandKinds, room, width, measure, available, gap, pillHeight)
    readonly property var folded: plan.folded
    readonly property string bubbleKind: folded.length > 0 ? folded[0] : ""
    readonly property int bubbleCount: folded.reduce((count, kind) => count
        + (kind === "transfer" ? running.length : kind === "arrived" ? endings.length
            : kind === "drive" ? drives.length : 1), 0)
    // The least the band needs: each island's first piece.
    readonly property int minimumUsefulWidth: IslandRoom.minimumWidth(bandKinds, measure, available, gap)
    readonly property bool peeling: mediaIsland.peeling || transferIsland.peeling || arrivedIsland.peeling
        || driveIsland.peeling
    // Carried or flicked, an island leaves through the band's own edges and
    // never passes over what sits beside Ambient, the launcher's dot among them.
    clip: peeling

    onActivitiesChanged: track()
    onChosenPlayerChanged: choose()

    // A kind with no island of its own here, such as a shared screen, takes
    // no room: the layout finds no pieces for it.
    function bandKind(activity) {
        if (activity.kind !== "transfer") return activity.kind;
        return ended(activity) ? "arrived" : "transfer";
    }

    function track() {
        const arrivalsNext = {}, startedNext = {}, statesNext = {}, bandNext = {};
        let newest = "";
        for (const activity of activities) {
            const key = String(activity.id);
            arrivalsNext[key] = key in arrivals ? arrivals[key] : ++serial;
            const playing = activity.state === "playing";
            startedNext[key] = playing && lastStates[key] !== "playing" ? ++serial
                : key in startedPlaying ? startedPlaying[key] : 0;
            statesNext[key] = activity.state;
            const band = bandKind(activity);
            if (band in bandNext) continue;
            if (band in bandArrivals) {
                bandNext[band] = bandArrivals[band];
                continue;
            }
            // What ended keeps its place beside the transfers it came from.
            bandNext[band] = band === "arrived" && "transfer" in bandArrivals
                ? bandArrivals.transfer + 0.5 : ++serial;
            if (!newest || bandNext[band] > bandNext[newest]) newest = band;
        }
        arrivals = arrivalsNext;
        startedPlaying = startedNext;
        lastStates = statesNext;
        bandArrivals = bandNext;
        const placesNext = Object.assign({}, places);
        for (const band in bandNext) placesNext[band] = bandNext[band];
        places = placesNext;
        const bandOrder = Object.keys(bandNext).sort((a, b) => bandNext[a] - bandNext[b]);
        if (JSON.stringify(bandOrder) !== JSON.stringify(bandKinds)) bandKinds = bandOrder;
        const openOrder = [];
        for (const band of bandOrder) {
            if (band !== "media" && band !== "transfer" && band !== "arrived") continue;
            const kind = band === "media" ? "media" : "transfer";
            if (openOrder.indexOf(kind) < 0) openOrder.push(kind);
        }
        if (JSON.stringify(openOrder) !== JSON.stringify(kinds)) kinds = openOrder;
        if (newest) {
            room = newest;
            roomSettles.restart();
        } else if (room && !(room in bandNext)) {
            room = "";
        }
        // An island set aside stays gone once its activity has left; one
        // whose activity is still here comes back.
        for (const island of [mediaIsland, transferIsland, arrivedIsland, driveIsland])
            if (island.kind in bandNext) island.leaving = false;
        choose();
    }

    Timer {
        id: roomSettles
        interval: 2400
        onTriggered: surface.room = ""
    }

    // The player that started playing last keeps its island, unless the
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

    // ---------------------------------------------------------------- words

    readonly property bool canToggle: capability(player, player && player.state === "playing" ? "pause" : "play")
    readonly property string mediaTitle: player ? player.title || player.source || qsTr("Media") : ""
    readonly property string mediaArtist: player && player.artist ? player.artist : ""
    readonly property string mediaTime: player && player.positionUs !== undefined
        ? formatTime(mediaPositionUs(player)) : ""
    readonly property string mediaDuration: player && player.durationUs !== undefined
        ? formatTime(player.durationUs) : ""
    // The clock's width follows its digits' count, not each second.
    readonly property string mediaTimeShape: mediaTime.replace(/[0-9]/g, "0")

    readonly property var transferShown: running.length === 1 ? running[0] : null
    readonly property string transferName: running.length > 1
        ? qsTr("%1 transfers").arg(running.length) : transferTitle(transferShown)
    readonly property string transferBytesText: transferBytes(transferShown)
    readonly property string transferSource: transferShown && transferShown.source
        && transferShown.source !== transferName ? transferShown.source : ""
    function transferLine(bytes, source) {
        return [bytes ? transferBytesText : "", source ? transferSource : ""]
            .filter(text => text.length > 0).join(" · ");
    }

    readonly property var endingShown: endings.length === 1 ? endings[0] : null
    readonly property bool endingFailed: endings.some(activity => activity.state === "failed")
    readonly property string endingName: endings.length > 1
        ? (endingFailed ? qsTr("%1 transfers ended") : qsTr("%1 files arrived")).arg(endings.length)
        : transferTitle(endingShown)
    readonly property string endingWords: endingShown ? endingShown.description || "" : ""

    // Drives open one at a time, the newest first.
    readonly property var driveShown: drives.length > 0 ? drives[drives.length - 1] : null
    readonly property string driveName: driveShown ? driveShown.title || qsTr("Drive") : ""
    readonly property string driveSize: driveShown && known(driveShown.sizeBytes) && driveShown.sizeBytes > 0
        ? formatBytes(driveShown.sizeBytes) : ""
    readonly property string openLabel: qsTr("Open")

    FontMetrics { id: strongMetrics; font.pixelSize: surface.labelSize; font.weight: Font.DemiBold }
    FontMetrics { id: plainMetrics; font.pixelSize: surface.labelSize }
    FontMetrics { id: smallMetrics; font.pixelSize: 11 }

    // ---------------------------------------------------------------- sizes

    function textWidth(metrics, text) {
        return text ? Math.ceil(metrics.advanceWidth(text)) : 0;
    }
    // One or two lines of words, as wide as the wider, with room either side.
    function column(top, bottom, most) {
        const widest = Math.max(top, bottom);
        return widest > 0 ? 12 + Math.min(most, widest) : 0;
    }
    function mediaWords(title) {
        return title ? column(textWidth(strongMetrics, mediaTitle),
            available("media", "artist") ? textWidth(smallMetrics, mediaArtist) : 0, 80) : 0;
    }
    function mediaClock(time, duration) {
        return column(time ? textWidth(plainMetrics, mediaTimeShape) + 2 : 0,
            duration ? textWidth(smallMetrics, mediaDuration.replace(/[0-9]/g, "0")) + 2 : 0, 60);
    }
    function transferWords(name, bytes, source) {
        return column(name ? textWidth(strongMetrics, transferName) : 0,
            textWidth(smallMetrics, transferLine(bytes, source)), 150);
    }
    function endingWordsWidth(name, words) {
        return column(name ? textWidth(strongMetrics, endingName) : 0,
            words ? textWidth(smallMetrics, endingWords) : 0, 150);
    }
    function driveWords(name, size) {
        return column(name ? textWidth(strongMetrics, driveName) : 0,
            size ? textWidth(smallMetrics, driveSize) : 0, 150);
    }
    // A pill as wide as its word, within a finger's reach.
    function openWidth() {
        return Math.max(reach, textWidth(strongMetrics, openLabel) + 36);
    }
    function skipWidth() {
        return reach * ((capability(player, "previous") ? 1 : 0) + (capability(player, "next") ? 1 : 0));
    }
    // Music alone: its controls in the middle, art and title on one side and
    // time and player on the other, the sides alike so the controls stay put.
    // With nothing yet on one side, it keeps no empty half.
    function mediaStart(items) {
        return (items.indexOf("art") >= 0 ? lead : 0) + mediaWords(items.indexOf("title") >= 0);
    }
    function mediaEnd(items) {
        return mediaClock(items.indexOf("time") >= 0, items.indexOf("duration") >= 0)
            + (items.indexOf("player") >= 0 ? lead : 0);
    }
    function balanced(items) {
        return alone && mediaStart(items) > 0 && mediaEnd(items) > 0;
    }
    function mediaSides(items) {
        const start = mediaStart(items), end = mediaEnd(items);
        return balanced(items) ? 2 * Math.max(start, end) : start + end;
    }

    // An island's whole width showing `items`.
    function measure(kind, items) {
        const has = piece => items.indexOf(piece) >= 0;
        if (kind === "media") {
            const middle = (has("toggle") ? reach : 0) + (has("skip") ? skipWidth() : 0);
            return 2 * inset + middle + mediaSides(items);
        }
        if (kind === "transfer")
            return 2 * inset + (has("ring") ? lead : 0) + (has("cancel") ? reach : 0)
                + transferWords(has("name"), has("bytes"), has("source"));
        if (kind === "arrived")
            return 2 * inset + (has("mark") ? lead : 0) + (has("show") ? reach : 0)
                + endingWordsWidth(has("name"), has("words"));
        if (kind === "drive")
            return 2 * inset + (has("icon") ? lead : 0) + (has("open") ? openWidth() : 0)
                + driveWords(has("name"), has("size"));
        return 0;
    }

    // What each island could show now.
    function available(kind, piece) {
        switch (kind + "." + piece) {
        case "media.toggle": return canToggle;
        case "media.title": case "media.art": case "media.player": return player !== null;
        case "media.skip": return capability(player, "previous") || capability(player, "next");
        case "media.artist": return tall && mediaArtist !== "";
        case "media.time": return player !== null && player.positionUs !== undefined;
        case "media.duration": return tall && player !== null && player.durationUs !== undefined;
        case "transfer.ring": case "transfer.name": return running.length > 0;
        case "transfer.percent": return transferShown !== null && known(transferShown.progress);
        case "transfer.bytes": return tall && transferBytesText !== "";
        case "transfer.source": return tall && transferSource !== "";
        case "transfer.cancel": return capability(transferShown, "cancel");
        case "arrived.mark": case "arrived.name": return endings.length > 0;
        case "arrived.show": return endingShown !== null && endingShown.state === "finished"
            && capability(endingShown, "showInFiles");
        case "arrived.words": return tall && endingWords !== "";
        case "drive.icon": case "drive.name": return driveShown !== null;
        case "drive.size": return tall && driveSize !== "";
        case "drive.open": return capability(driveShown, "open");
        }
        return false;
    }

    // ---------------------------------------------------------------- places

    readonly property real islandY: Math.round((height - pillHeight) / 2)

    function islandOf(kind) {
        return kind === "media" ? mediaIsland : kind === "transfer" ? transferIsland
            : kind === "arrived" ? arrivedIsland : kind === "drive" ? driveIsland : null;
    }
    // Islands sit in the order they arrived, the fold last, the whole group
    // centred; each takes its share as it comes and goes, so its neighbours
    // move over as it does.
    function slotX(kind) {
        const order = Object.keys(places).sort((a, b) => places[a] - places[b])
            .map(islandOf).filter(island => island !== null);
        let total = 0, at = 0, before = 0;
        for (const island of order) {
            const share = Math.min(1, island.presence);
            const space = gap * Math.min(before, share);
            if (island.kind === kind) at = total + space;
            total += space + island.width;
            before = Math.max(before, share);
        }
        const space = gap * Math.min(before, bubble.presence);
        if (kind === "fold") at = total + space;
        total += space + bubble.slotWidth;
        return Math.round((width - total) / 2) + at;
    }

    // The open island shows music, or every transfer, the ended ones included.
    function openKind(kind) {
        return kind === "media" ? "media" : "transfer";
    }
    // A drive's island is one tap: Files opens the drive, mounting it first.
    function open(kind) {
        if (kind === "drive") invoke(driveShown, "open");
        else openRequested(openKind(kind));
    }
    // Where the open island grows from.
    function islandFor(kind) {
        const candidates = kind === "media" ? [mediaIsland] : [transferIsland, arrivedIsland];
        for (const island of candidates)
            if (island.present) return island.shape;
        return bubble;
    }
    function spoken(kind) {
        if (kind === "media") return qsTr("Media %1, open").arg(mediaTitle);
        if (kind === "transfer") return qsTr("%n transfer(s), open", "", running.length);
        if (kind === "drive") return qsTr("%1, open in Files").arg(driveName);
        return qsTr("%1, open").arg(endingName);
    }
    // What an island shows goes aside: the player it shows, or all it holds.
    function setAside(kind) {
        if (kind === "media") invoke(player, "setAside");
        else for (const activity of kind === "transfer" ? running : kind === "drive" ? drives : endings)
            invoke(activity, "setAside");
    }

    // ---------------------------------------------------------------- pieces

    // The settled feel: no overshoot, as the mock-up showed it.
    component SettledAnimation: NumberAnimation {
        duration: 340
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 0.08, 0.26, 0.92, 1, 1]
    }

    // One island. A sideways drag, by finger or mouse, anywhere on it, its
    // controls included, carries it: it sheds its details as a narrower band
    // would, down to its least, then slides on with the finger and fades. Its
    // neighbours hold their places until it has gone aside.
    component BandIsland: Item {
        id: island
        required property string kind
        default property alias pieces: row.data
        readonly property var planned: surface.plan.shown[kind] || []
        readonly property bool present: surface.plan.shown[kind] !== undefined
        // Set aside, it stays gone while its activity leaves.
        property bool leaving: false
        property real presence: present && !leaving ? 1 : 0
        Behavior on presence { SettledAnimation {} }
        onPresenceChanged: if (presence === 0) leaving = false

        property real peel: 0
        // Its width at rest, held while it is carried.
        property real restWidth: 0
        onPeelingChanged: if (!peeling) restWidth = pill.width
        property real peelVelocity: 0
        property real peelSampleX: 0
        property double peelSampleAt: 0
        readonly property bool peeling: carry.active || peelBack.running || peelAway.running
        readonly property real least: planned.length > 0 ? surface.measure(kind, planned.slice(0, 1)) : 0
        readonly property real peelAll: Math.max(48, restWidth - least)
        readonly property var items: peeling && peel !== 0
            ? IslandRoom.trim(kind, planned, restWidth - Math.abs(peel), surface.measure) : planned
        readonly property Item shape: pill
        function has(piece) { return items.indexOf(piece) >= 0; }

        x: surface.slotX(kind)
        y: surface.islandY
        width: peeling ? restWidth : pill.width * presence
        height: surface.pillHeight

        // Let go: peeled to its least, or flicked the way it was carried, it
        // goes aside; otherwise it comes back whole.
        function release() {
            const flicked = Math.abs(peelVelocity) > 0.6 && Math.sign(peelVelocity) === Math.sign(peel);
            if (peel !== 0 && (Math.abs(peel) >= peelAll || flicked)) {
                peelAway.to = Math.sign(peel) * (surface.width + restWidth);
                peelAway.start();
            } else {
                peelBack.start();
            }
        }
        SettledAnimation { id: peelBack; target: island; property: "peel"; to: 0; duration: 240 }
        NumberAnimation {
            id: peelAway
            target: island
            property: "peel"
            duration: 160
            easing.type: Easing.InCubic
            onFinished: {
                island.leaving = true;
                surface.setAside(island.kind);
                island.peel = 0;
            }
        }

        Rectangle {
            id: pill
            objectName: "ambient-band-" + island.kind
            property real lift: pillArea.pressed ? 1.03 : 1
            Behavior on lift { NumberAnimation { duration: 120 } }
            x: (island.width - width) / 2 + island.peel
            width: row.width + 2 * surface.inset
            onWidthChanged: if (!island.peeling) island.restWidth = width
            height: surface.pillHeight
            radius: height / 2
            color: surface.opaque ? "#141414" : Qt.rgba(248 / 255, 248 / 255, 1, 0.07)
            border.width: 1
            border.color: Qt.rgba(248 / 255, 248 / 255, 1, 0.10)
            opacity: (island.leaving ? 0 : Math.min(1, island.presence * 1.4))
                * (1 - Math.max(0, Math.min(1, (Math.abs(island.peel) - island.peelAll) / 80)))
            visible: opacity > 0 && !surface.opened
            scale: (0.7 + 0.3 * Math.min(1, island.presence)) * lift
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: surface.spoken(island.kind)
            Accessible.onPressAction: surface.open(island.kind)
            Keys.onReturnPressed: surface.open(island.kind)
            Keys.onEnterPressed: surface.open(island.kind)
            Keys.onSpacePressed: surface.open(island.kind)
            Keys.onDeletePressed: surface.setAside(island.kind)
            Behavior on color { ColorAnimation { duration: 200 } }

            // A tap away from the controls opens the island.
            MouseArea {
                id: pillArea
                anchors.fill: parent
                onClicked: surface.open(island.kind)
            }
            // Once it moves, the drag is the island's, not a press.
            DragHandler {
                id: carry
                target: null
                yAxis.enabled: false
                enabled: !surface.opened && !peelAway.running
                onActiveChanged: {
                    if (active) {
                        peelBack.stop();
                        island.peelVelocity = 0;
                        island.peelSampleX = 0;
                        island.peelSampleAt = Date.now();
                    } else {
                        island.release();
                    }
                }
                onActiveTranslationChanged: {
                    if (!active) return;
                    const now = Date.now();
                    const dt = Math.max(1, now - island.peelSampleAt);
                    const dx = activeTranslation.x - island.peelSampleX;
                    // Smoothed, so the last few moves decide a flick.
                    island.peelVelocity = 0.6 * (dx / dt) + 0.4 * island.peelVelocity;
                    island.peelSampleX = activeTranslation.x;
                    island.peelSampleAt = now;
                    island.peel = activeTranslation.x;
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
                visible: pill.activeFocus
            }
            Row {
                id: row
                x: surface.inset
                height: surface.pillHeight
            }
        }
    }

    // A piece of an island: it takes its share of the band as it comes and
    // goes, and while its island is carried it goes at once.
    component Piece: Item {
        id: piece
        required property BandIsland island
        property string name: ""
        property bool shows: name === "" || island.has(name)
        property bool when: true
        property real size: 0
        readonly property bool showing: when && shows && size > 0
        // Room for words, less the space either side.
        readonly property real inner: Math.max(0, size - 12)
        width: showing ? size : 0
        height: surface.pillHeight
        visible: width > 0.5
        clip: width < size - 0.5
        opacity: showing ? 1 : 0
        Behavior on width { enabled: !piece.island.peeling; SettledAnimation {} }
        Behavior on opacity { enabled: !piece.island.peeling; NumberAnimation { duration: 200 } }
    }

    // A control: the glyph rises under a finger or a press.
    component IslandButton: Item {
        id: button
        property string glyph
        property real size: 20
        property string label
        signal activated()
        anchors.centerIn: parent
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
        font.pixelSize: surface.labelSize
        elide: Text.ElideRight
        maximumLineCount: 1
    }
    component Detail: Label {
        opacity: 0.66
        font.pixelSize: 11
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

    // How a transfer ended: a closed ring with a check, or with a cross.
    component Mark: Item {
        id: mark
        property bool failed: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: 0.5
            radius: width / 2
            color: "transparent"
            border.width: mark.width < 26 ? 2.5 : 3
            border.color: "#F8F8FF"
        }
        SuiteIcon {
            anchors.centerIn: parent
            width: Math.round(mark.width * 0.55)
            height: width
            glyph: mark.failed ? "x" : "check"
        }
    }

    // ---------------------------------------------------------------- islands

    // Music. Alone, its controls sit in the middle; beside a neighbour, its
    // time and player move before them.
    BandIsland {
        id: mediaIsland
        kind: "media"
        Piece {
            island: mediaIsland
            name: "art"
            size: surface.lead
            Art {
                anchors.centerIn: parent
                width: surface.artSize
                height: surface.artSize
                activity: surface.player
                corner: surface.artSize > 26 ? 8 : 6
            }
        }
        Piece {
            id: mediaWordsPiece
            island: mediaIsland
            name: "title"
            size: surface.mediaWords(true)
            Column {
                x: 6
                width: mediaWordsPiece.inner
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    objectName: "ambient-media-title"
                    width: parent.width
                    text: surface.mediaTitle
                    font.weight: Font.DemiBold
                }
                Detail {
                    objectName: "ambient-media-artist"
                    width: parent.width
                    visible: mediaIsland.has("artist")
                    text: surface.mediaArtist
                }
            }
        }
        Piece {
            island: mediaIsland
            when: surface.balanced(mediaIsland.items)
            size: Math.max(0, surface.mediaEnd(mediaIsland.items) - surface.mediaStart(mediaIsland.items))
        }
        MediaClock { when: !surface.alone; tag: "-beside" }
        MediaPlayerIcon { when: !surface.alone; tag: "-beside" }
        Row {
            objectName: "ambient-media-transport"
            anchors.verticalCenter: parent.verticalCenter
            Piece {
                island: mediaIsland
                shows: mediaIsland.has("skip") && surface.capability(surface.player, "previous")
                size: surface.reach
                IslandButton {
                    objectName: "ambient-media-previous"
                    glyph: "skip-back"
                    label: qsTr("Previous")
                    onActivated: surface.invoke(surface.player, "previous")
                }
            }
            Piece {
                island: mediaIsland
                name: "toggle"
                size: surface.reach
                IslandButton {
                    objectName: "ambient-media-toggle"
                    glyph: surface.player && surface.player.state === "playing" ? "pause" : "play"
                    size: 22
                    label: surface.player && surface.player.state === "playing" ? qsTr("Pause") : qsTr("Play")
                    onActivated: surface.invoke(surface.player,
                        surface.player && surface.player.state === "playing" ? "pause" : "play")
                }
            }
            Piece {
                island: mediaIsland
                shows: mediaIsland.has("skip") && surface.capability(surface.player, "next")
                size: surface.reach
                IslandButton {
                    objectName: "ambient-media-next"
                    glyph: "skip-forward"
                    label: qsTr("Next")
                    onActivated: surface.invoke(surface.player, "next")
                }
            }
        }
        Piece {
            island: mediaIsland
            when: surface.balanced(mediaIsland.items)
            size: Math.max(0, surface.mediaStart(mediaIsland.items) - surface.mediaEnd(mediaIsland.items))
        }
        MediaClock { when: surface.alone }
        MediaPlayerIcon { when: surface.alone }
    }

    component MediaClock: Piece {
        id: clock
        property string tag: ""
        island: mediaIsland
        shows: mediaIsland.has("time") || mediaIsland.has("duration")
        size: surface.mediaClock(mediaIsland.has("time"), mediaIsland.has("duration"))
        Column {
            x: 6
            width: clock.inner
            anchors.verticalCenter: parent.verticalCenter
            Label {
                objectName: "ambient-media-time" + clock.tag
                anchors.right: parent.right
                visible: mediaIsland.has("time")
                text: surface.mediaTime
                font.features: ({ "tnum": 1 })
            }
            Detail {
                objectName: "ambient-media-duration" + clock.tag
                anchors.right: parent.right
                visible: mediaIsland.has("duration")
                text: surface.mediaDuration
                font.features: ({ "tnum": 1 })
            }
        }
    }
    component MediaPlayerIcon: Piece {
        id: playerIcon
        property string tag: ""
        island: mediaIsland
        name: "player"
        size: surface.lead
        Kirigami.Icon {
            objectName: "ambient-media-player" + playerIcon.tag
            anchors.centerIn: parent
            width: surface.artSize > 26 ? 24 : 18
            height: width
            source: surface.player && surface.player.icon ? surface.player.icon : "audio-x-generic-symbolic"
        }
    }

    // What is on its way: progress with its percentage inside, what and
    // from where, and Cancel when the source allows it.
    BandIsland {
        id: transferIsland
        kind: "transfer"
        Piece {
            island: transferIsland
            name: "ring"
            size: surface.lead
            Progress {
                anchors.centerIn: parent
                width: surface.artSize
                height: surface.artSize
                activity: surface.running.length > 0 ? surface.running[0] : null
            }
            Text {
                objectName: "ambient-transfer-progress"
                anchors.centerIn: parent
                visible: transferIsland.has("percent")
                text: surface.transferShown && surface.known(surface.transferShown.progress)
                    ? Math.round(Math.max(0, Math.min(1, Number(surface.transferShown.progress))) * 100) : ""
                color: "#F8F8FF"
                font.pixelSize: surface.tall ? 10 : 9
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
        Piece {
            id: transferWordsPiece
            island: transferIsland
            shows: transferIsland.has("name") || transferIsland.has("bytes") || transferIsland.has("source")
            size: surface.transferWords(transferIsland.has("name"), transferIsland.has("bytes"),
                transferIsland.has("source"))
            Column {
                x: 6
                width: transferWordsPiece.inner
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    objectName: "ambient-transfer-title"
                    width: parent.width
                    visible: transferIsland.has("name")
                    text: surface.transferName
                    font.weight: Font.DemiBold
                }
                Detail {
                    objectName: "ambient-transfer-detail"
                    width: parent.width
                    visible: text.length > 0
                    text: surface.transferLine(transferIsland.has("bytes"), transferIsland.has("source"))
                }
            }
        }
        Piece {
            island: transferIsland
            name: "cancel"
            size: surface.reach
            IslandButton {
                objectName: "ambient-transfer-cancel"
                glyph: "x"
                label: qsTr("Cancel %1").arg(surface.transferTitle(surface.transferShown))
                onActivated: surface.invoke(surface.transferShown, "cancel")
            }
        }
    }

    // What arrived, or failed to, waiting out its minute: how it ended, what
    // it was, and Show in Files.
    BandIsland {
        id: arrivedIsland
        kind: "arrived"
        Piece {
            island: arrivedIsland
            name: "mark"
            size: surface.lead
            Mark {
                objectName: "ambient-arrived-mark"
                anchors.centerIn: parent
                width: surface.artSize
                height: surface.artSize
                failed: surface.endingFailed
            }
        }
        Piece {
            id: endingWordsPiece
            island: arrivedIsland
            shows: arrivedIsland.has("name") || arrivedIsland.has("words")
            size: surface.endingWordsWidth(arrivedIsland.has("name"), arrivedIsland.has("words"))
            Column {
                x: 6
                width: endingWordsPiece.inner
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    objectName: "ambient-arrived-name"
                    width: parent.width
                    visible: arrivedIsland.has("name")
                    text: surface.endingName
                    font.weight: Font.DemiBold
                }
                Detail {
                    objectName: "ambient-arrived-words"
                    width: parent.width
                    visible: arrivedIsland.has("words")
                    text: surface.endingWords
                }
            }
        }
        Piece {
            island: arrivedIsland
            name: "show"
            size: surface.reach
            IslandButton {
                objectName: "ambient-arrived-show"
                glyph: "folder-open"
                label: qsTr("Show %1 in Files").arg(surface.endingName)
                onActivated: surface.invoke(surface.endingShown, "showInFiles")
            }
        }
    }

    // A drive plugged in that nothing has mounted: what it is, how big, and
    // Open. The whole island is one tap: Files opens the drive.
    BandIsland {
        id: driveIsland
        kind: "drive"
        Piece {
            island: driveIsland
            name: "icon"
            size: surface.lead
            Kirigami.Icon {
                objectName: "ambient-drive-icon"
                anchors.centerIn: parent
                width: surface.artSize > 26 ? 24 : 18
                height: width
                source: surface.driveShown && surface.driveShown.icon ? surface.driveShown.icon : "drive-removable-media"
            }
        }
        Piece {
            id: driveWordsPiece
            island: driveIsland
            shows: driveIsland.has("name") || driveIsland.has("size")
            size: surface.driveWords(driveIsland.has("name"), driveIsland.has("size"))
            Column {
                x: 6
                width: driveWordsPiece.inner
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    objectName: "ambient-drive-name"
                    width: parent.width
                    visible: driveIsland.has("name")
                    text: surface.driveName
                    font.weight: Font.DemiBold
                }
                Detail {
                    objectName: "ambient-drive-size"
                    width: parent.width
                    visible: driveIsland.has("size")
                    text: surface.driveSize
                }
            }
        }
        Piece {
            id: openPiece
            island: driveIsland
            name: "open"
            size: surface.openWidth()
            Rectangle {
                id: openPill
                objectName: "ambient-drive-open"
                anchors.centerIn: parent
                width: openPiece.size - 8
                height: Math.min(30, surface.pillHeight - 12)
                radius: height / 2
                color: Qt.rgba(248 / 255, 248 / 255, 1, openArea.pressed ? 0.24 : 0.14)
                scale: openArea.pressed ? 1.06 : 1
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Open %1 in Files").arg(surface.driveName)
                Accessible.onPressAction: surface.open("drive")
                Keys.onReturnPressed: surface.open("drive")
                Keys.onEnterPressed: surface.open("drive")
                Keys.onSpacePressed: surface.open("drive")
                border.width: activeFocus ? 1 : 0
                border.color: "#F8F8FF"
                Behavior on scale { NumberAnimation { duration: 90 } }
                Label {
                    anchors.centerIn: parent
                    text: surface.openLabel
                    font.weight: Font.DemiBold
                }
            }
            // The pill takes a finger across the island's full height.
            MouseArea {
                id: openArea
                anchors.fill: parent
                onClicked: surface.open("drive")
            }
        }
    }

    // What has no room of its own folds in here, counted.
    Rectangle {
        id: bubble
        objectName: "ambient-bubble"
        readonly property bool shown: surface.folded.length > 0
        property real presence: shown ? 1 : 0
        Behavior on presence { SettledAnimation {} }
        readonly property real slotWidth: surface.pillHeight * presence
        x: surface.slotX("fold") - (width - slotWidth) / 2
        y: surface.islandY
        width: surface.pillHeight
        height: surface.pillHeight
        radius: width / 2
        color: surface.opaque ? "#141414" : Qt.rgba(248 / 255, 248 / 255, 1, 0.07)
        border.width: 1
        border.color: Qt.rgba(248 / 255, 248 / 255, 1, 0.10)
        opacity: Math.min(1, presence * 1.4)
        visible: opacity > 0 && !surface.opened
        scale: (0.4 + 0.6 * Math.min(1, presence)) * (bubbleArea.pressed ? 1.1 : 1)
        activeFocusOnTab: shown
        Accessible.role: Accessible.Button
        Accessible.name: surface.bubbleKind ? surface.spoken(surface.bubbleKind) : ""
        Accessible.onPressAction: surface.open(surface.bubbleKind)
        Keys.onReturnPressed: surface.open(surface.bubbleKind)
        Keys.onEnterPressed: surface.open(surface.bubbleKind)
        Keys.onSpacePressed: surface.open(surface.bubbleKind)
        Behavior on color { ColorAnimation { duration: 200 } }

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
            activity: surface.running.length > 0 ? surface.running[0] : null
        }
        Mark {
            anchors.centerIn: parent
            width: surface.artSize
            height: width
            visible: surface.bubbleKind === "arrived"
            failed: surface.endingFailed
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: surface.artSize > 26 ? 24 : 18
            height: width
            visible: surface.bubbleKind === "drive"
            source: surface.driveShown && surface.driveShown.icon ? surface.driveShown.icon : "drive-removable-media"
        }
        Rectangle {
            objectName: "ambient-bubble-count"
            visible: surface.bubbleCount > 1
            x: parent.width - width * 0.8
            y: -4
            width: surface.tall ? 18 : 15
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
            onClicked: surface.open(surface.bubbleKind)
        }
    }
}
