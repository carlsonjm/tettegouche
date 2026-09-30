/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtTest
import "../applet" as Applet

TestCase {
    id: testCase
    name: "AmbientIsland"
    when: windowShown
    width: 640
    height: 180
    visible: true

    readonly property var transfer: ({
        id: "transfer-1", generation: 3, kind: "transfer", state: "running",
        source: "Files", icon: "folder-download-symbolic", title: "Fedora.iso",
        progress: 0.68, processedBytes: 3200000000, totalBytes: 4700000000,
        capabilities: {cancel: true, suspend: true}
    })
    readonly property var secondTransfer: ({
        id: "transfer-2", generation: 4, kind: "transfer", state: "suspended",
        source: "Files", title: "Photos", progress: 0.2,
        capabilities: {cancel: true, resume: true}
    })
    readonly property var unknownFile: ({
        id: "file-1", generation: 1, kind: "transfer", state: "running",
        source: "Incoming file", title: "archive.part", progress: null,
        observedSizeBytes: 2048, evidence: "filesystem",
        capabilities: {showInFiles: true}
    })
    readonly property var arrived: ({
        id: "job:7", generation: 2, kind: "transfer", state: "finished",
        source: "KDE Connect", title: "photo.png", description: "Arrived in Downloads",
        progress: 1, evidence: "job", capabilities: {showInFiles: true}
    })
    readonly property var failed: ({
        id: "job:8", generation: 2, kind: "transfer", state: "failed",
        source: "KDE Connect", title: "Transfer failed", description: "The phone went out of reach",
        evidence: "job", capabilities: {}
    })
    readonly property var media: ({
        id: "media-1", generation: 8, kind: "media", state: "playing",
        source: "Spotify", icon: "spotify", title: "Houdini", artist: "Dua Lipa",
        positionUs: 10000000, sampledAtMonotonicUs: 1000000,
        durationUs: 180000000, rate: 1,
        capabilities: {play: true, pause: true, previous: true, next: true,
            seek: true, seekBack: true, seekTo: true, raise: true}
    })
    readonly property var otherMedia: ({
        id: "media-2", generation: 2, kind: "media", state: "paused",
        source: "Zen Browser", title: "A video",
        capabilities: {play: true, pause: true}
    })

    Component {
        id: surfaceComponent
        Applet.AmbientSurface { height: 64; monotonicClock: () => 2000000 }
    }
    Component {
        id: islandComponent
        Applet.AmbientIsland { width: 900; height: 600 }
    }

    function createSurface(width, activities) {
        const surface = createTemporaryObject(surfaceComponent, testCase, {width: width});
        verify(surface !== null);
        surface.activities = activities;
        wait(0);
        return surface;
    }
    function island(surface) { return findChild(surface, "ambient-island"); }
    function bubble(surface) { return findChild(surface, "ambient-bubble"); }
    function spyOn(target, signalName) {
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy {}', testCase);
        spy.target = target;
        spy.signalName = signalName;
        return spy;
    }
    function settle() { wait(420); }

    function test_empty_is_quiet() {
        const surface = createSurface(405, []);
        compare(surface.minimumUsefulWidth, 0);
        verify(!island(surface).visible);
        verify(!bubble(surface).visible);
    }

    function test_music_alone_is_centred_with_its_controls() {
        const surface = createSurface(405, [media]);
        settle();
        const shape = island(surface);
        verify(shape.visible);
        compare(shape.height, 44);
        fuzzyCompare(shape.x + shape.width / 2, surface.width / 2, 0.5);
        const transport = findChild(surface, "ambient-media-transport");
        fuzzyCompare(transport.mapToItem(surface, transport.width / 2, 0).x, surface.width / 2, 0.5);
        const toggle = findChild(surface, "ambient-media-toggle");
        verify(toggle.width >= 44 && toggle.height >= 44);
        verify(findChild(surface, "ambient-media-previous").visible);
        verify(findChild(surface, "ambient-media-next").visible);
        verify(findChild(surface, "ambient-media-title").visible);
        verify(findChild(surface, "ambient-media-time").visible);
        verify(shape.x >= 0 && shape.x + shape.width <= surface.width);
    }

    function test_music_gives_words_before_controls() {
        const narrow = createSurface(200, [media]);
        settle();
        verify(!findChild(narrow, "ambient-media-title").visible);
        verify(findChild(narrow, "ambient-media-previous").visible);
        verify(findChild(narrow, "ambient-media-next").visible);
        verify(island(narrow).width <= narrow.width);
        const tight = createSurface(100, [media]);
        settle();
        verify(!findChild(tight, "ambient-media-previous").visible);
        verify(findChild(tight, "ambient-media-toggle").visible);
    }

    function test_first_to_arrive_keeps_the_island() {
        const surface = createSurface(405, [transfer]);
        surface.activities = [transfer, media];
        settle();
        compare(surface.mainKind, "transfer");
        compare(surface.bubbleKind, "media");
        compare(surface.bubbleCount, 1);
        verify(bubble(surface).visible);
        verify(!findChild(bubble(surface), "ambient-bubble-count").visible);
        const shape = island(surface), mark = bubble(surface);
        fuzzyCompare((shape.x + mark.x + mark.width) / 2, surface.width / 2, 0.5);

        const musicFirst = createSurface(405, [media]);
        musicFirst.activities = [transfer, media];
        musicFirst.activities = [transfer, secondTransfer, media];
        settle();
        compare(musicFirst.mainKind, "media");
        compare(musicFirst.bubbleKind, "transfer");
        compare(musicFirst.bubbleCount, 2);
        verify(findChild(bubble(musicFirst), "ambient-bubble-count").visible);
        // When the island's own activity ends, the next one takes the island.
        musicFirst.activities = [transfer, secondTransfer];
        settle();
        compare(musicFirst.mainKind, "transfer");
        verify(!bubble(musicFirst).visible);
    }

    function test_one_player_at_a_time() {
        const surface = createSurface(405, [media]);
        const later = Object.assign({}, otherMedia, {state: "playing"});
        surface.activities = [media, later];
        compare(surface.player.id, "media-2");
        compare(surface.otherPlayers.length, 1);
        compare(surface.otherPlayers[0].id, "media-1");
        compare(surface.kinds.length, 1);
        surface.chosenPlayer = "media-1";
        compare(surface.player.id, "media-1");
        // Several players are one activity: the bubble never holds a second one.
        verify(!bubble(surface).visible);
    }

    function test_clear_over_the_band_black_with_it() {
        const surface = createSurface(405, [media]);
        const shape = island(surface);
        verify(shape.color.a < 0.2);
        surface.opaque = true;
        // The band's own black, the suite's, not a darker one of its own.
        tryVerify(() => Qt.colorEqual(shape.color, "#141414"));
        compare(bubble(surface).color, shape.color);
    }

    function test_controls_act_and_the_rest_opens() {
        const surface = createSurface(405, [media]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        const toggle = findChild(surface, "ambient-media-toggle");
        mouseClick(toggle, toggle.width / 2, toggle.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "media-1");
        compare(invoked.signalArguments[0][1], 8);
        compare(invoked.signalArguments[0][2], "pause");
        compare(opens.count, 0);
        const shape = island(surface);
        mouseClick(shape, 8, shape.height / 2);
        compare(opens.count, 1);
        compare(opens.signalArguments[0][0], "media");

        surface.activities = [media, transfer];
        settle();
        const mark = bubble(surface);
        mouseClick(mark, mark.width / 2, mark.height / 2);
        compare(opens.count, 2);
        compare(opens.signalArguments[1][0], "transfer");
        // Opened elsewhere, the band's island and bubble step aside.
        surface.opened = true;
        verify(!shape.visible);
        verify(!mark.visible);
    }

    function test_transfer_alone_keeps_its_cancel() {
        const surface = createSurface(405, [transfer]);
        settle();
        const cancel = findChild(surface, "ambient-transfer-cancel");
        verify(cancel.visible);
        verify(cancel.width >= 44);
        compare(findChild(surface, "ambient-transfer-progress").text, "68%");
        const invoked = spyOn(surface, "invokeRequested");
        mouseClick(cancel, cancel.width / 2, cancel.height / 2);
        compare(invoked.signalArguments[0][2], "cancel");
    }

    function test_unknown_filesystem_evidence_stays_honest() {
        const surface = createSurface(405, [unknownFile]);
        compare(surface.percentage(unknownFile), "—");
        compare(surface.transferBytes(unknownFile), "File size 2.0 KB");
        compare(surface.transferDetail, "Incoming file");
        verify(!findChild(surface, "ambient-transfer-cancel").visible);
    }

    function test_paused_media_clock_stops() {
        const surface = createSurface(405, [media]);
        surface.clockNowUs = 2000000;
        compare(surface.mediaPositionUs(media), 11000000);
        const paused = Object.assign({}, media, {state: "paused"});
        compare(surface.mediaPositionUs(paused), 10000000);
    }

    function openIsland(surface, kind) {
        const opened = createTemporaryObject(islandComponent, testCase,
            {surface: surface, kind: kind, start: Qt.rect(40, 540, 392, 44), sideLeft: 0, sideRight: 460});
        verify(opened !== null);
        opened.show();
        tryVerify(() => opened.expanded);
        wait(360);
        return opened;
    }

    function test_open_island_grows_from_its_place() {
        const surface = createSurface(405, [media, otherMedia]);
        const opened = openIsland(surface, "media");
        const card = findChild(opened.contentItem, "ambient-island-open");
        fuzzyCompare(card.y + card.height, 584, 0.5);
        verify(card.height > 200);
        verify(card.x >= 0 && card.x + card.width <= 460);
        const closed = spyOn(opened, "closed");
        opened.dismiss();
        tryCompare(closed, "count", 1);
        fuzzyCompare(card.height, 44, 0.5);
    }

    function test_open_music_moves_and_raises() {
        const surface = createSurface(405, [media, otherMedia]);
        const opened = openIsland(surface, "media");
        const invoked = spyOn(surface, "invokeRequested");
        const seek = findChild(opened.contentItem, "ambient-island-seek");
        verify(seek.visible && seek.movable);
        mousePress(seek, seek.width / 2, 14);
        mouseMove(seek, seek.width * 0.75, 14);
        mouseRelease(seek, seek.width * 0.75, 14);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][2], "seekTo");
        fuzzyCompare(invoked.signalArguments[0][3], 135000000, 1000000);
        const back = findChild(opened.contentItem, "ambient-island-seek-back");
        mouseClick(back, back.width / 2, back.height / 2);
        compare(invoked.signalArguments[1][2], "seekBack");
        // The other player waits here, and plays from its own row.
        compare(surface.otherPlayers.length, 1);
        const otherToggle = findChild(opened.contentItem, "ambient-island-other-toggle-media-2");
        verify(otherToggle.visible);
        mouseClick(otherToggle, otherToggle.width / 2, otherToggle.height / 2);
        compare(invoked.signalArguments[2][0], "media-2");
        compare(invoked.signalArguments[2][2], "play");
        verify(opened.expanded);
        const raise = findChild(opened.contentItem, "ambient-island-raise");
        verify(raise.visible);
        mouseClick(raise, raise.width / 2, raise.height / 2);
        compare(invoked.signalArguments[3][2], "raise");
        tryVerify(() => !opened.expanded);
    }

    function test_open_music_without_capabilities_offers_none() {
        const plain = Object.assign({}, media, {capabilities: {play: true, pause: true}});
        const surface = createSurface(405, [plain]);
        const opened = openIsland(surface, "media");
        verify(!findChild(opened.contentItem, "ambient-island-seek").movable);
        verify(!findChild(opened.contentItem, "ambient-island-seek-back").visible);
        verify(!findChild(opened.contentItem, "ambient-island-seek-forward").visible);
        verify(!findChild(opened.contentItem, "ambient-island-raise").visible);
    }

    function test_open_transfers_list_each_with_its_own_actions() {
        const surface = createSurface(405, [transfer, secondTransfer, unknownFile]);
        const opened = openIsland(surface, "transfer");
        verify(findChild(opened.contentItem, "ambient-island-transfer-transfer-1").visible);
        verify(findChild(opened.contentItem, "ambient-island-transfer-transfer-2").visible);
        verify(findChild(opened.contentItem, "ambient-island-transfer-file-1").visible);
        verify(!findChild(opened.contentItem, "ambient-island-cancel-file-1").visible);
        const invoked = spyOn(surface, "invokeRequested");
        const cancel = findChild(opened.contentItem, "ambient-island-cancel-transfer-2");
        mouseClick(cancel, cancel.width / 2, cancel.height / 2);
        compare(invoked.signalArguments[0][0], "transfer-2");
        compare(invoked.signalArguments[0][2], "cancel");
        const show = findChild(opened.contentItem, "ambient-island-show-file-1");
        verify(show.visible);
        mouseClick(show, show.width / 2, show.height / 2);
        compare(invoked.signalArguments[1][0], "file-1");
        compare(invoked.signalArguments[1][2], "showInFiles");
    }

    // A transfer keeps its row in the open island as its progress moves: a
    // row made again for each update draws its ring from blank, and strobes.
    function test_open_transfer_keeps_its_row_as_progress_moves() {
        const surface = createSurface(405, [transfer, secondTransfer]);
        const opened = openIsland(surface, "transfer");
        const row = findChild(opened.contentItem, "ambient-island-transfer-transfer-1");
        verify(row !== null);
        for (let step = 1; step <= 3; ++step) {
            surface.activities = [Object.assign({}, transfer, {progress: 0.68 + step * 0.05}), secondTransfer];
            wait(0);
            verify(findChild(opened.contentItem, "ambient-island-transfer-transfer-1") === row);
        }
        fuzzyCompare(row.modelData.progress, 0.83, 0.001);
    }

    // An ended transfer waiting out its minute says how it ended, and an
    // arrival keeps Show in Files.
    function test_ended_transfers_say_how_they_ended() {
        const surface = createSurface(405, [arrived]);
        compare(surface.transferDetail, "Arrived in Downloads");
        const opened = openIsland(surface, "transfer");
        const show = findChild(opened.contentItem, "ambient-island-show-job:7");
        verify(show !== null && show.visible);
        verify(!findChild(opened.contentItem, "ambient-island-cancel-job:7").visible);
        surface.activities = [failed];
        wait(0);
        compare(surface.transferDetail, "The phone went out of reach");
    }

    function test_open_island_moves_between_kinds_and_closes_outside() {
        const surface = createSurface(405, [media, transfer]);
        const opened = openIsland(surface, "media");
        verify(findChild(opened.contentItem, "ambient-island-kinds").visible);
        verify(findChild(opened.contentItem, "ambient-island-media").visible);
        opened.kind = "transfer";
        verify(findChild(opened.contentItem, "ambient-island-transfers").visible);
        verify(!findChild(opened.contentItem, "ambient-island-media").visible);
        const closed = spyOn(opened, "closed");
        mouseClick(opened.contentItem, 800, 40);
        tryCompare(closed, "count", 1);
    }
}
