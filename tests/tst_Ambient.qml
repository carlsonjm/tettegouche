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
    readonly property var drive: ({
        id: "drive:/org/freedesktop/UDisks2/block_devices/sdz1", generation: 5, kind: "drive",
        state: "waiting", title: "STICK", icon: "drive-removable-media-usb-pendrive",
        sizeBytes: 32000000000, capabilities: {open: true}
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

    // Stand-ins for a dark and a light Plasma style, so the colours do not
    // depend on the style the test happens to run under.
    QtObject {
        id: darkStyle
        property color backgroundColor: "#141414"
        property color textColor: "#E0E0E0"
    }
    QtObject {
        id: lightStyle
        property color backgroundColor: "#F2F2F2"
        property color textColor: "#102729"
        property color neutralTextColor: "#B65C00"
    }
    Component {
        id: colorsComponent
        Applet.AmbientColors {}
    }
    // The colours a surface or an open island paints with.
    function colors(item) { return findChild(item, "ambientColors"); }

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
    // An island as drawn, and the island that carries it.
    function island(surface, kind) { return findChild(surface, "ambient-band-" + kind); }
    function carrier(surface, kind) { return island(surface, kind).parent; }
    function bubble(surface) { return findChild(surface, "ambient-bubble"); }
    function shown(surface, kind) { return surface.plan.shown[kind] || []; }
    // Where an item sits across the band.
    function leftOf(surface, item) { return item.mapToItem(surface, 0, 0).x; }
    function rightOf(surface, item) { return item.mapToItem(surface, item.width, 0).x; }
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
        verify(!island(surface, "media").visible);
        verify(!island(surface, "transfer").visible);
        verify(!island(surface, "arrived").visible);
        verify(!bubble(surface).visible);
    }

    function test_music_alone_is_centred_with_its_controls() {
        const surface = createSurface(405, [media]);
        settle();
        const shape = island(surface, "media");
        verify(shape.visible);
        compare(shape.height, 44);
        fuzzyCompare(leftOf(surface, shape) + shape.width / 2, surface.width / 2, 1);
        const transport = findChild(surface, "ambient-media-transport");
        fuzzyCompare(leftOf(surface, transport) + transport.width / 2, surface.width / 2, 1);
        const toggle = findChild(surface, "ambient-media-toggle");
        verify(toggle.width >= 44 && toggle.height >= 44);
        verify(findChild(surface, "ambient-media-previous").visible);
        verify(findChild(surface, "ambient-media-next").visible);
        verify(findChild(surface, "ambient-media-title").visible);
        verify(findChild(surface, "ambient-media-artist").visible);
        verify(findChild(surface, "ambient-media-time").visible);
        // The time and the player sit after the controls when music is alone.
        verify(leftOf(surface, findChild(surface, "ambient-media-time")) > rightOf(surface, transport));
        verify(leftOf(surface, shape) >= 0 && rightOf(surface, shape) <= surface.width);
    }

    // Music drops in its own order, the last first: play or pause stays longest,
    // then the title, the art, and the skips.
    function test_music_alone_drops_in_its_order() {
        const narrow = createSurface(200, [media]);
        settle();
        compare(shown(narrow, "media").slice(0, 2), ["toggle", "title"]);
        verify(findChild(narrow, "ambient-media-title").visible);
        verify(findChild(narrow, "ambient-media-toggle").visible);
        verify(!findChild(narrow, "ambient-media-previous").visible);
        verify(!findChild(narrow, "ambient-media-next").visible);
        verify(island(narrow, "media").width <= narrow.width);
        const tight = createSurface(100, [media]);
        settle();
        compare(shown(tight, "media"), ["toggle"]);
        verify(findChild(tight, "ambient-media-toggle").visible);
        verify(!findChild(tight, "ambient-media-title").visible);
        const wide = createSurface(640, [media]);
        settle();
        for (const piece of ["toggle", "title", "art", "skip", "artist", "time", "duration", "player"])
            verify(shown(wide, "media").indexOf(piece) >= 0, piece);
    }

    // Each kind is its own island, in the order they arrived, the whole group
    // centred; neither passes over the other or the band's edges.
    function test_neighbours_sit_side_by_side() {
        const surface = createSurface(405, [transfer]);
        surface.activities = [transfer, media];
        settle();
        const first = island(surface, "transfer"), second = island(surface, "media");
        verify(first.visible && second.visible);
        verify(rightOf(surface, first) <= leftOf(surface, second));
        fuzzyCompare(leftOf(surface, second) - rightOf(surface, first), surface.gap, 1);
        fuzzyCompare(leftOf(surface, first) + rightOf(surface, second), surface.width, 2);
        verify(leftOf(surface, first) >= 0 && rightOf(surface, second) <= surface.width);
        verify(!bubble(surface).visible);
        // When one island's activity ends, its neighbour takes the room back.
        const shared = second.width;
        surface.activities = [media];
        settle();
        verify(!first.visible);
        verify(second.width > shared);
        fuzzyCompare(leftOf(surface, second) + second.width / 2, surface.width / 2, 1);
    }

    // Beside a neighbour, an island reads what it is, then its words, then its
    // buttons; play or pause is last.
    function test_buttons_come_last_beside_a_neighbour() {
        const surface = createSurface(460, [media, transfer]);
        settle();
        const shape = island(surface, "media");
        const transport = findChild(surface, "ambient-media-transport");
        const title = findChild(surface, "ambient-media-title");
        verify(findChild(surface, "ambient-media-toggle").visible && title.visible);
        verify(rightOf(surface, title) <= leftOf(surface, transport));
        fuzzyCompare(rightOf(surface, transport), rightOf(surface, shape) - surface.inset, 1);
        // The time, when it fits, reads before the controls.
        const time = findChild(surface, "ambient-media-time-beside");
        if (time.visible) verify(rightOf(surface, time) <= leftOf(surface, transport));
        const cancel = findChild(surface, "ambient-transfer-cancel");
        verify(cancel.visible);
        fuzzyCompare(rightOf(surface, cancel), rightOf(surface, island(surface, "transfer")) - surface.inset, 1);
    }

    // The newest island has the room: it takes its turn first. Once urgency
    // settles it, a transfer goes before music.
    function test_newest_has_the_room_then_urgency() {
        const surface = createSurface(300, [transfer]);
        surface.activities = [transfer, media];
        compare(surface.room, "media");
        tryCompare(surface, "room", "", 3000);
        // Across widths, the room never gives the newest less, and somewhere
        // it gives it more than urgency would.
        let more = 0;
        for (let width = 180; width <= 480; width += 4) {
            surface.width = width;
            surface.room = "media";
            const withRoom = shown(surface, "media").length;
            surface.room = "";
            const byUrgency = shown(surface, "media").length;
            verify(withRoom >= byUrgency, "width " + width);
            if (withRoom > byUrgency) ++more;
        }
        verify(more > 0);
    }

    // Names are the last to get room: a transfer shows its size and Cancel
    // before where it came from, and music keeps its skips before its player.
    function test_names_wait_for_the_rest() {
        const surface = createSurface(460, [media, transfer]);
        tryCompare(surface, "room", "", 3000);
        settle();
        const music = shown(surface, "media");
        if (music.indexOf("player") >= 0)
            verify(music.indexOf("skip") >= 0 && music.indexOf("time") >= 0);
        const moving = shown(surface, "transfer");
        if (moving.indexOf("source") >= 0 || moving.indexOf("name") >= 0)
            verify(moving.indexOf("bytes") >= 0 && moving.indexOf("cancel") >= 0);
    }

    // What cannot keep even its first piece folds into a counted bubble.
    function test_what_does_not_fit_folds_into_the_bubble() {
        const surface = createSurface(150, [media, transfer, secondTransfer]);
        surface.activities = [media, transfer, secondTransfer, arrived];
        settle();
        const mark = bubble(surface);
        verify(mark.visible);
        verify(surface.folded.length > 0);
        let visible = 0;
        for (const kind of ["media", "transfer", "arrived"]) {
            const shape = island(surface, kind);
            if (!shape.visible) continue;
            ++visible;
            verify(leftOf(surface, shape) >= 0 && rightOf(surface, shape) <= surface.width);
            verify(rightOf(surface, shape) <= leftOf(surface, mark) || leftOf(surface, shape) >= rightOf(surface, mark));
        }
        verify(visible >= 1);
        verify(rightOf(surface, mark) <= surface.width);
        if (surface.folded.indexOf("transfer") >= 0) {
            compare(surface.bubbleCount >= 2, true);
            verify(findChild(mark, "ambient-bubble-count").visible);
        }
        const opens = spyOn(surface, "openRequested");
        mouseClick(mark, mark.width / 2, mark.height / 2);
        compare(opens.count, 1);
        compare(opens.signalArguments[0][0], surface.bubbleKind === "media" ? "media" : "transfer");
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
        // Several players are one island.
        settle();
        verify(!bubble(surface).visible);
        verify(!island(surface, "transfer").visible);
    }

    function test_clear_over_the_band_black_with_it() {
        const surface = createSurface(405, [media]);
        colors(surface).theme = darkStyle;
        const shape = island(surface, "media");
        verify(shape.color.a < 0.2);
        surface.opaque = true;
        // The band's own black, the suite's, not a darker one of its own.
        tryVerify(() => Qt.colorEqual(shape.color, "#141414"));
        compare(bubble(surface).color, shape.color);
        compare(island(surface, "transfer").color, shape.color);
    }

    // On a dark style Ambient keeps the suite's values; on a light one its
    // ground and ink are the style's, and its washes are that ink.
    function test_colours_follow_the_style() {
        const dark = createTemporaryObject(colorsComponent, testCase, {theme: darkStyle});
        verify(dark.dark);
        verify(Qt.colorEqual(dark.text, "#F8F8FF"));
        verify(Qt.colorEqual(dark.surface, "#141414"));
        verify(Qt.colorEqual(dark.card, "#000000"));
        verify(Qt.colorEqual(dark.textOnInk, "#000000"));
        verify(Qt.colorEqual(dark.art, "#2A2A2F"));
        verify(Qt.colorEqual(dark.waitingText, "#E3B866"));
        verify(Qt.colorEqual(dark.wash(0.07), Qt.rgba(248 / 255, 248 / 255, 1, 0.07)));

        const light = createTemporaryObject(colorsComponent, testCase, {theme: lightStyle});
        verify(!light.dark);
        verify(Qt.colorEqual(light.text, "#102729"));
        verify(Qt.colorEqual(light.surface, "#F2F2F2"));
        verify(Qt.colorEqual(light.card, "#F2F2F2"));
        verify(Qt.colorEqual(light.textOnInk, "#F2F2F2"));
        verify(Qt.colorEqual(light.waitingText, "#B65C00"));
        const wash = light.wash(0.12);
        verify(Qt.colorEqual(Qt.rgba(wash.r, wash.g, wash.b, 1), "#102729"));
        fuzzyCompare(wash.a, 0.12, 0.01);
        // The square behind a player's icon is a light grey the icon reads on.
        verify(light.art.hslLightness > 0.7 && light.art.hslLightness < light.surface.hslLightness);
    }

    // On a light style an island on an opaque band takes the style's ground,
    // and words in the band and the open island take its ink.
    function test_islands_on_a_light_style() {
        const surface = createSurface(405, [media]);
        colors(surface).theme = lightStyle;
        settle();
        const shape = island(surface, "media");
        verify(Qt.colorEqual(Qt.rgba(shape.color.r, shape.color.g, shape.color.b, 1), "#102729"));
        verify(shape.color.a < 0.2);
        surface.opaque = true;
        tryVerify(() => Qt.colorEqual(shape.color, "#F2F2F2"));
        verify(Qt.colorEqual(findChild(surface, "ambient-media-title").color, "#102729"));

        const open = createTemporaryObject(islandComponent, testCase, {surface: surface, kind: "media"});
        verify(open !== null);
        colors(open.contentItem).theme = lightStyle;
        const card = findChild(open.contentItem, "ambient-island-open");
        verify(Qt.colorEqual(card.color, "#F2F2F2"));
        verify(Qt.colorEqual(open.ink, "#102729"));
        colors(open.contentItem).theme = darkStyle;
        verify(Qt.colorEqual(card.color, "#000000"));
        verify(Qt.colorEqual(open.ink, "#F8F8FF"));
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
        const shape = island(surface, "media");
        mouseClick(shape, 8, shape.height / 2);
        compare(opens.count, 1);
        compare(opens.signalArguments[0][0], "media");
        compare(surface.islandFor("media"), shape);

        surface.activities = [media, transfer];
        settle();
        const moving = island(surface, "transfer");
        mouseClick(moving, 8, moving.height / 2);
        compare(opens.count, 2);
        compare(opens.signalArguments[1][0], "transfer");
        compare(surface.islandFor("transfer"), moving);
        // Opened elsewhere, the band's islands step aside.
        surface.opened = true;
        verify(!shape.visible);
        verify(!moving.visible);
    }

    function test_transfer_alone_keeps_its_cancel() {
        const surface = createSurface(405, [transfer]);
        settle();
        const cancel = findChild(surface, "ambient-transfer-cancel");
        verify(cancel.visible);
        verify(cancel.width >= 44);
        // The percentage rides inside the ring.
        const progress = findChild(surface, "ambient-transfer-progress");
        verify(progress.visible);
        compare(progress.text, "68");
        compare(findChild(surface, "ambient-transfer-title").text, "Fedora.iso");
        compare(findChild(surface, "ambient-transfer-detail").text, "3.2 GB of 4.7 GB · Files");
        const invoked = spyOn(surface, "invokeRequested");
        mouseClick(cancel, cancel.width / 2, cancel.height / 2);
        compare(invoked.signalArguments[0][2], "cancel");
    }

    function test_unknown_filesystem_evidence_stays_honest() {
        const surface = createSurface(405, [unknownFile]);
        settle();
        compare(surface.percentage(unknownFile), "—");
        compare(surface.transferBytes(unknownFile), "File size 2.0 KB");
        compare(findChild(surface, "ambient-transfer-detail").text, "File size 2.0 KB · Incoming file");
        verify(!findChild(surface, "ambient-transfer-progress").visible);
        verify(!findChild(surface, "ambient-transfer-cancel").visible);
    }

    function test_paused_media_clock_stops() {
        const surface = createSurface(405, [media]);
        surface.clockNowUs = 2000000;
        compare(surface.mediaPositionUs(media), 11000000);
        const paused = Object.assign({}, media, {state: "paused"});
        compare(surface.mediaPositionUs(paused), 10000000);
    }

    // An ended transfer waiting out its minute is an island of its own: how
    // it ended, what it was, and Show in Files for an arrival.
    function test_an_arrival_waits_with_show_in_files() {
        const surface = createSurface(405, [arrived]);
        settle();
        const shape = island(surface, "arrived");
        verify(shape.visible);
        verify(!island(surface, "transfer").visible);
        compare(findChild(surface, "ambient-arrived-name").text, "photo.png");
        compare(findChild(surface, "ambient-arrived-words").text, "Arrived in Downloads");
        verify(!findChild(surface, "ambient-arrived-mark").failed);
        const show = findChild(surface, "ambient-arrived-show");
        verify(show.visible);
        verify(rightOf(surface, show) > rightOf(surface, findChild(surface, "ambient-arrived-name")));
        const invoked = spyOn(surface, "invokeRequested");
        mouseClick(show, show.width / 2, show.height / 2);
        compare(invoked.signalArguments[0][0], "job:7");
        compare(invoked.signalArguments[0][2], "showInFiles");
        const opens = spyOn(surface, "openRequested");
        mouseClick(shape, 8, shape.height / 2);
        compare(opens.signalArguments[0][0], "transfer");
        compare(surface.islandFor("transfer"), shape);

        surface.activities = [failed];
        settle();
        verify(findChild(surface, "ambient-arrived-mark").failed);
        compare(findChild(surface, "ambient-arrived-words").text, "The phone went out of reach");
        verify(!findChild(surface, "ambient-arrived-show").visible);
    }

    // A drive plugged in that nothing mounted is one tap: the island or its
    // Open asks for the drive, never the open island.
    function test_a_drive_waits_with_open() {
        const surface = createSurface(405, [drive]);
        settle();
        const shape = island(surface, "drive");
        verify(shape.visible);
        compare(surface.kinds.length, 0);
        compare(findChild(surface, "ambient-drive-name").text, "STICK");
        compare(findChild(surface, "ambient-drive-size").text, "32.0 GB");
        const open = findChild(surface, "ambient-drive-open");
        verify(open.visible);
        verify(rightOf(surface, open) > rightOf(surface, findChild(surface, "ambient-drive-name")));
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(open, open.width / 2, open.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], drive.id);
        compare(invoked.signalArguments[0][1], 5);
        compare(invoked.signalArguments[0][2], "open");
        mouseClick(shape, 8, shape.height / 2);
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][2], "open");
        compare(opens.count, 0);
    }

    // Beside music, a drive goes first by urgency and keeps Open at its end.
    function test_a_drive_beside_music() {
        const surface = createSurface(300, [drive]);
        surface.activities = [drive, media];
        tryCompare(surface, "room", "", 3000);
        settle();
        verify(island(surface, "drive").visible && island(surface, "media").visible);
        verify(rightOf(surface, island(surface, "drive")) <= leftOf(surface, island(surface, "media")));
        verify(shown(surface, "drive").indexOf("open") >= 0);
        compare(surface.kinds, ["media"]);
    }

    // Flicked away, the drive is set aside: filed with Open in Files.
    function test_flicking_a_drive_sets_it_aside() {
        const surface = createSurface(405, [drive]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const at = centreOf(surface, "drive");
        const touch = touchEvent(surface);
        touch.press(0, surface, at.x, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x - 30, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x - 70, at.y).commit();
        wait(16);
        touch.release(0, surface, at.x - 70, at.y).commit();
        tryCompare(invoked, "count", 1);
        compare(invoked.signalArguments[0][0], drive.id);
        compare(invoked.signalArguments[0][2], "setAside");
    }

    // A kind the band draws no island for takes no room and opens nothing.
    function test_an_undrawn_kind_takes_no_room() {
        const unknown = {id: "other:x", generation: 1, kind: "other", state: "running",
            title: "Something", capabilities: {}};
        const surface = createSurface(405, [media, unknown]);
        settle();
        compare(surface.kinds, ["media"]);
        verify(!island(surface, "transfer").visible);
        fuzzyCompare(leftOf(surface, island(surface, "media")) + island(surface, "media").width / 2, surface.width / 2, 1);
    }

    // A shared screen says who receives it, beside a red dot, with Stop at
    // its end; a tap elsewhere on it opens nothing, and a flick sets it aside.
    function test_a_shared_screen_offers_stop() {
        const share = {id: "screen:x", generation: 4, kind: "screen", state: "running",
            title: "Sharing contents to Zen Browser", icon: "zen-browser", capabilities: {stop: true}};
        const beside = createSurface(460, [media, share]);
        compare(beside.kinds, ["media"]);
        const surface = createSurface(460, [share]);
        settle();
        const shape = island(surface, "screen");
        verify(shape.visible);
        compare(findChild(surface, "ambient-screen-who").text, "Sharing contents to Zen Browser");
        verify(findChild(surface, "ambient-screen-dot").visible);
        const stop = findChild(surface, "ambient-screen-stop");
        verify(stop.visible);
        verify(rightOf(surface, stop) > rightOf(surface, findChild(surface, "ambient-screen-who")));
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(stop, stop.width / 2, stop.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "screen:x");
        compare(invoked.signalArguments[0][2], "stop");
        mouseClick(shape, 10, shape.height / 2);
        compare(opens.count, 0);
        compare(invoked.count, 1);
        // Narrow, it keeps Stop longest.
        surface.width = 160;
        verify(shown(surface, "screen").indexOf("stop") >= 0);
    }

    // An application waiting on the person shows its icon, its name and its
    // dialog's question; a tap anywhere on it brings it forward and opens
    // nothing, and narrow, it keeps its icon longest, then its name.
    function test_a_waiting_application_comes_forward() {
        const waiting = {id: "waiting:w1", generation: 6, kind: "waiting", state: "running",
            title: "Kate", icon: "kate", question: "Save changes to the letter?", capabilities: {raise: true}};
        const surface = createSurface(460, [waiting]);
        settle();
        const shape = island(surface, "waiting");
        verify(shape.visible);
        compare(shown(surface, "waiting"), ["icon", "name", "question"]);
        compare(findChild(surface, "ambient-waiting-icon").source, "kate");
        compare(findChild(surface, "ambient-waiting-name").text, "Kate");
        compare(findChild(surface, "ambient-waiting-question").text, "Save changes to the letter?");
        verify(rightOf(surface, findChild(surface, "ambient-waiting-icon"))
            <= leftOf(surface, findChild(surface, "ambient-waiting-name")) + 1);
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(shape, shape.width - 12, shape.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "waiting:w1");
        compare(invoked.signalArguments[0][1], 6);
        compare(invoked.signalArguments[0][2], "raise");
        compare(opens.count, 0);
        // Its question goes first, then its name; the icon stays.
        surface.width = 120;
        settle();
        compare(shown(surface, "waiting"), ["icon", "name"]);
        surface.width = 60;
        settle();
        compare(shown(surface, "waiting"), ["icon"]);
        // With no question to read, it names the application alone.
        const plain = createSurface(460, [Object.assign({}, waiting, {question: ""})]);
        settle();
        compare(shown(plain, "waiting"), ["icon", "name"]);
        verify(!findChild(plain, "ambient-waiting-question").visible);
    }

    // Beside music, a waiting application has the room first, and what does
    // not fit folds into the bubble, whose tap brings the newest waiting
    // application forward.
    function test_a_waiting_application_beside_media() {
        const waiting = {id: "waiting:w2", generation: 7, kind: "waiting", state: "running",
            title: "Firefox", icon: "firefox", question: "Leave page?", capabilities: {raise: true}};
        const surface = createSurface(460, [media, waiting]);
        settle();
        compare(surface.bandKinds, ["media", "waiting"]);
        verify(shown(surface, "waiting").indexOf("name") >= 0);
        const narrow = createSurface(100, [media, waiting]);
        settle();
        compare(narrow.folded, ["media"]);
        compare(shown(narrow, "waiting"), ["icon"]);
        const second = Object.assign({}, waiting, {id: "waiting:w3", generation: 9, title: "Kate", icon: "kate"});
        const folded = createSurface(48, [media, waiting, second]);
        settle();
        verify(folded.folded.indexOf("waiting") >= 0);
        const invoked = spyOn(folded, "invokeRequested");
        mouseClick(bubble(folded));
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "waiting:w3");
        compare(invoked.signalArguments[0][2], "raise");
    }

    // A transfer that ends keeps its place in the band.
    function test_an_ended_transfer_keeps_its_place() {
        const surface = createSurface(460, [transfer]);
        surface.activities = [transfer, media];
        settle();
        const done = Object.assign({}, transfer, {state: "finished", description: "Arrived in Downloads",
            capabilities: {showInFiles: true}});
        surface.activities = [done, media];
        settle();
        verify(!island(surface, "transfer").visible);
        verify(rightOf(surface, island(surface, "arrived")) <= leftOf(surface, island(surface, "media")));
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
        // Focused, the track moves five seconds with the arrows.
        opened.requestActivate();
        tryVerify(() => opened.active);
        seek.forceActiveFocus();
        verify(seek.activeFocus);
        const before = seek.positionUs;
        keyClick(Qt.Key_Right);
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][2], "seekTo");
        fuzzyCompare(invoked.signalArguments[1][3], before + 5000000, 1000000);
        // Back and forward ten seconds have left the island.
        compare(findChild(opened.contentItem, "ambient-island-seek-back"), null);
        compare(findChild(opened.contentItem, "ambient-island-seek-forward"), null);
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

    // A list longer than the room above the band scrolls inside the card,
    // which stays on the display.
    function test_open_transfers_scroll_when_long() {
        const many = [];
        for (let i = 0; i < 20; ++i)
            many.push(Object.assign({}, transfer, {id: "transfer-many-" + i, title: "File " + i}));
        const surface = createSurface(405, many);
        const opened = openIsland(surface, "transfer");
        const card = findChild(opened.contentItem, "ambient-island-open");
        const scroller = findChild(opened.contentItem, "ambient-island-scroll");
        verify(card.y >= 0);
        fuzzyCompare(card.y + card.height, 584, 0.5);
        verify(scroller.interactive);
        scroller.contentY = scroller.contentHeight - scroller.height;
        const last = findChild(opened.contentItem, "ambient-island-transfer-transfer-many-19");
        const bottom = last.mapToItem(card, 0, last.height).y;
        verify(bottom <= card.height + 0.5);
        verify(bottom > 0);
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

    // The open island lists ended transfers with the rest, arrivals keeping
    // Show in Files.
    function test_open_island_lists_what_ended() {
        const surface = createSurface(405, [arrived]);
        const opened = openIsland(surface, "transfer");
        const show = findChild(opened.contentItem, "ambient-island-show-job:7");
        verify(show !== null && show.visible);
        verify(!findChild(opened.contentItem, "ambient-island-cancel-job:7").visible);
    }

    // A sideways drag, measured against the band, which does not move.
    function centreOf(surface, kind) {
        const shape = island(surface, kind);
        return {x: leftOf(surface, shape) + shape.width / 2, y: shape.mapToItem(surface, 0, shape.height / 2).y};
    }
    function slowDrag(surface, kind, dx) {
        const at = centreOf(surface, kind);
        mousePress(surface, at.x, at.y);
        const steps = Math.ceil(Math.abs(dx) / 16);
        for (let step = 1; step <= steps; ++step) {
            mouseMove(surface, at.x + dx * step / steps, at.y);
            wait(40);
        }
        return at;
    }

    // A slow sideways drag sheds the island's details as a narrower band
    // would, keeping play or pause; let go early and it springs back whole,
    // with nothing set aside.
    function test_slow_drag_sheds_then_springs_back() {
        const surface = createSurface(405, [media]);
        settle();
        verify(findChild(surface, "ambient-media-title").visible);
        const invoked = spyOn(surface, "invokeRequested");
        const at = slowDrag(surface, "media", -160);
        verify(surface.clip); // leaves through its own edge, not over its neighbours
        // It sheds in its own order: the skips before the title.
        verify(!findChild(surface, "ambient-media-previous").visible);
        verify(findChild(surface, "ambient-media-title").visible);
        for (let step = 1; step <= 5; ++step) { mouseMove(surface, at.x - 160 - step * 16, at.y); wait(40); }
        verify(!findChild(surface, "ambient-media-title").visible);
        verify(findChild(surface, "ambient-media-toggle").visible);
        verify(Math.abs(carrier(surface, "media").peel) < carrier(surface, "media").peelAll);
        mouseRelease(surface, at.x - 240, at.y);
        tryCompare(carrier(surface, "media"), "peel", 0);
        compare(invoked.count, 0);
        settle();
        verify(findChild(surface, "ambient-media-title").visible);
        tryVerify(() => !surface.clip); // at rest, its focus ring and press may reach past
    }

    // An island pops up into its place, a touch past its size and back, and
    // pops down where it stands before its neighbour moves over.
    function test_island_pops_up_and_down() {
        const surface = createSurface(460, [transfer]);
        settle();
        surface.activities = [transfer, media];
        const music = island(surface, "media");
        tryVerify(() => music.scale > 1.001, 1000);
        settle();
        compare(music.scale, 1);
        surface.activities = [transfer];
        // While it pops down, it keeps its room in the band.
        wait(60);
        compare(carrier(surface, "media").presence, 1);
        tryVerify(() => !music.visible, 1000);
        settle();
        fuzzyCompare(centreOf(surface, "transfer").x, surface.width / 2, 1);
    }

    // Let go past its least, the island fades where it was let go rather than
    // travelling on.
    function test_set_aside_fades_where_let_go() {
        const surface = createSurface(460, [media, transfer]);
        settle();
        const music = carrier(surface, "media");
        const at = slowDrag(surface, "media", -(music.peelAll + 20));
        const held = music.peel;
        mouseRelease(surface, at.x - music.peelAll - 20, at.y);
        tryVerify(() => music.fade < 1, 1000);
        fuzzyCompare(music.peel, held, 1);
        tryCompare(music, "peel", 0);
        verify(!island(surface, "media").visible);
    }

    // Peeled past its least, the island goes aside: the player it shows, and
    // only that; its neighbour holds its place while it is carried.
    function test_drag_past_its_least_sets_it_aside() {
        const surface = createSurface(460, [media, transfer]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const neighbour = island(surface, "transfer");
        const standing = leftOf(surface, neighbour);
        const music = carrier(surface, "media");
        const at = slowDrag(surface, "media", -(music.peelAll + 20));
        fuzzyCompare(leftOf(surface, neighbour), standing, 0.5);
        mouseRelease(surface, at.x - music.peelAll - 20, at.y);
        tryCompare(invoked, "count", 1);
        compare(invoked.signalArguments[0][0], "media-1");
        compare(invoked.signalArguments[0][2], "setAside");
        tryCompare(music, "peel", 0);
        // Gone aside, it does not come back while its activity leaves, and
        // its neighbour takes the room.
        verify(!island(surface, "media").visible);
        surface.activities = [transfer];
        settle();
        verify(!island(surface, "media").visible);
        fuzzyCompare(centreOf(surface, "transfer").x, surface.width / 2, 1);
    }

    // A quick flick by touch sets aside what the island shows: every transfer.
    function test_flick_by_touch_sets_it_aside() {
        const surface = createSurface(405, [transfer, secondTransfer]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const at = centreOf(surface, "transfer");
        const touch = touchEvent(surface);
        touch.press(0, surface, at.x, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x + 30, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x + 70, at.y).commit();
        wait(16);
        touch.release(0, surface, at.x + 70, at.y).commit();
        tryCompare(invoked, "count", 2);
        compare(invoked.signalArguments[0][2], "setAside");
        compare(invoked.signalArguments[1][2], "setAside");
        compare([invoked.signalArguments[0][0], invoked.signalArguments[1][0]].sort(), ["transfer-1", "transfer-2"]);
    }

    // Flicking an arrival away files it now.
    function test_flicking_an_arrival_files_it() {
        const surface = createSurface(405, [media, arrived]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const at = centreOf(surface, "arrived");
        const touch = touchEvent(surface);
        touch.press(0, surface, at.x, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x + 30, at.y).commit();
        wait(16);
        touch.move(0, surface, at.x + 70, at.y).commit();
        wait(16);
        touch.release(0, surface, at.x + 70, at.y).commit();
        tryCompare(invoked, "count", 1);
        compare(invoked.signalArguments[0][0], "job:7");
        compare(invoked.signalArguments[0][2], "setAside");
    }

    // A drag that starts on play or pause is the island's: it does not press.
    function test_drag_from_a_control_does_not_press_it() {
        const surface = createSurface(405, [media]);
        settle();
        const invoked = spyOn(surface, "invokeRequested");
        const toggle = findChild(surface, "ambient-media-toggle");
        const at = toggle.mapToItem(surface, toggle.width / 2, toggle.height / 2);
        mousePress(surface, at.x, at.y);
        for (let step = 1; step <= 4; ++step) { mouseMove(surface, at.x + step * 12, at.y); wait(40); }
        mouseRelease(surface, at.x + 48, at.y);
        tryCompare(carrier(surface, "media"), "peel", 0);
        compare(invoked.count, 0);
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
