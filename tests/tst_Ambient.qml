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

    // A stand-in for the widget as keeper of saved layouts: what it lists,
    // what is open once asked, and every call made of it.
    Component {
        id: layoutsComponent
        QtObject {
            property bool keepsLayouts: true
            property var layouts: [
                {id: "1", name: "Coding", atSignIn: true, groups: [
                    {apps: ["ghostty", "claude"], names: ["Ghostty", "Claude"], stack: true},
                    {apps: ["zen"], names: ["Zen"], stack: false},
                    {apps: ["mail", "notes", "files"], names: ["Mail", "Notes", "Files"], stack: true}]},
                {id: "2", name: "Writing", atSignIn: false, groups: [
                    {apps: ["notes", "zen"], names: ["Notes", "Zen"], stack: true}]}]
            property var currentLayout: ({})
            property var calls: []
            function readCurrentLayout() { calls.push(["read"]); currentLayout = {}; }
            function saveLayout(name, groups, atSignIn) { calls.push(["save", name, groups, atSignIn]); }
            function openLayout(id) { calls.push(["open", id]); }
            function removeLayout(id) { calls.push(["remove", id]); }
            function setLayoutAtSignIn(id, on) { calls.push(["atSignIn", id, on]); }
        }
    }
    function openLayouts(host) {
        const opened = createTemporaryObject(islandComponent, testCase,
            {surface: createSurface(460, []), layouts: host, kind: "layouts",
             start: Qt.rect(40, 540, 44, 44), sideLeft: 0, sideRight: 460});
        verify(opened !== null);
        opened.show();
        tryVerify(() => opened.expanded);
        wait(360);
        return opened;
    }
    function tap(item) { mouseClick(item, item.width / 2, item.height / 2); }
    // What a tap shows in the open island is laid out on the next frame and
    // the card then grows to it, so a test taps it only once it rests.

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

    // Outlined, each island is a pill and album art keeps to it. Without an
    // outline, art takes an application's place in Shuffle's dock, its words a
    // step away; islands stand apart by the suite's room between sections,
    // and the group keeps that room from the end it is gathered against.
    function test_without_an_outline_art_takes_an_applications_place() {
        const pill = createSurface(640, [media]);
        settle();
        const pillArt = findChild(pill, "ambient-media-art");
        compare(pillArt.width, 30);
        compare(pillArt.corner, 10);
        compare(pill.gap, 8);
        compare(pill.margin, 0);

        const open = createSurface(640, [media]);
        open.outlined = false;
        settle();
        const art = findChild(open, "ambient-media-art");
        // The dock's square in a 64 px band is 46; artwork fills 42 of 48.
        compare(art.width, 40);
        compare(art.height, 40);
        compare(art.corner, 6);
        verify(art.height <= open.pillHeight);
        const shape = island(open, "media");
        fuzzyCompare(leftOf(open, art), leftOf(open, shape), 1);
        fuzzyCompare(leftOf(open, findChild(open, "ambient-media-title")) - rightOf(open, art), 8, 1);
    }

    function test_without_an_outline_islands_stand_apart() {
        const surface = createSurface(640, [transfer, media]);
        surface.outlined = false;
        settle();
        const first = island(surface, "transfer"), second = island(surface, "media");
        compare(surface.gap, 24);
        fuzzyCompare(leftOf(surface, second) - rightOf(surface, first), 24, 1);
        fuzzyCompare(leftOf(surface, first) + rightOf(surface, second), surface.width, 2);
        surface.align = "start";
        settle();
        fuzzyCompare(leftOf(surface, first), 24, 1);
        surface.align = "end";
        settle();
        fuzzyCompare(rightOf(surface, second), surface.width - 24, 1);
        // The room it keeps is part of the least it needs.
        const least = surface.minimumUsefulWidth;
        surface.outlined = true;
        verify(surface.minimumUsefulWidth < least);
        settle();
        fuzzyCompare(rightOf(surface, second), surface.width, 1);
    }

    // With room to spare the islands stand whole, and that is their natural
    // width: a band given exactly it sheds nothing. What they occupy follows
    // them as they come and go, and with nothing going on both are nothing.
    function test_the_islands_natural_width_is_what_they_use_whole() {
        const surface = createSurface(2000, [transfer, media]);
        surface.align = "start";
        settle();
        const first = island(surface, "transfer"), second = island(surface, "media");
        fuzzyCompare(leftOf(surface, first), 0, 1);
        fuzzyCompare(surface.naturalWidth, rightOf(surface, second), 2);
        fuzzyCompare(surface.occupiedWidth, surface.naturalWidth, 2);
        const whole = shown(surface, "media").length;
        surface.width = surface.naturalWidth;
        settle();
        compare(shown(surface, "media").length, whole);
        fuzzyCompare(rightOf(surface, second), surface.width, 2);
        surface.activities = [];
        compare(surface.naturalWidth, 0);
        verify(surface.occupiedWidth > 0);
        settle();
        compare(surface.occupiedWidth, 0);
    }

    // Unset, each look keeps its own room. A host's spacing is the room in
    // both, and the margin without an outline, held to 4 to 32 px, and it
    // takes effect as it changes.
    function test_a_hosts_spacing_parts_the_islands() {
        const surface = createSurface(640, [transfer, media]);
        settle();
        const first = island(surface, "transfer"), second = island(surface, "media");
        compare(surface.spacing, 0);
        compare(surface.gap, 8);
        surface.spacing = 14;
        settle();
        compare(surface.gap, 14);
        fuzzyCompare(leftOf(surface, second) - rightOf(surface, first), 14, 1);
        surface.outlined = false;
        surface.align = "start";
        settle();
        compare(surface.gap, 14);
        compare(surface.margin, 14);
        fuzzyCompare(leftOf(surface, first), 14, 1);
        fuzzyCompare(leftOf(surface, second) - rightOf(surface, first), 14, 1);
        surface.spacing = 2;
        compare(surface.gap, 4);
        surface.spacing = 40;
        compare(surface.gap, 32);
        surface.spacing = -6;
        compare(surface.gap, 4);
        surface.spacing = 0;
        compare(surface.gap, 24);
        surface.outlined = true;
        compare(surface.gap, 8);
    }

    // A waiting application's icon and a drive's are drawn as the dock draws
    // an application without an outline, and as before inside a pill.
    function test_without_an_outline_icons_are_pictures() {
        const waiting = {id: "waiting:w3", generation: 1, kind: "waiting", state: "running",
            title: "Kate", icon: "kate", capabilities: {raise: true}};
        const surface = createSurface(640, [waiting, drive]);
        settle();
        compare(findChild(surface, "ambient-waiting-icon").width, 24);
        compare(findChild(surface, "ambient-drive-icon").width, 24);
        surface.outlined = false;
        settle();
        compare(findChild(surface, "ambient-waiting-icon").width, 46);
        compare(findChild(surface, "ambient-drive-icon").width, 46);
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

    // A fact from Split Rock's Core shows its icon, what it is and how it
    // stands, and below, the detail and what can be done; a tap opens its card
    // through Core and opens no island, and setting it aside tells Core.
    function test_a_core_fact_opens_its_card() {
        const fact = {id: "core:storage", generation: 3, kind: "core", state: "running",
            title: "Storage", line: "91% full", detail: "45 GB free", actionText: "Free up space",
            icon: "drive-harddisk", capabilities: {open: true}};
        const surface = createSurface(460, [fact]);
        settle();
        const shape = island(surface, "core");
        verify(shape.visible);
        compare(shown(surface, "core"), ["icon", "name", "detail"]);
        compare(findChild(surface, "ambient-core-icon").source, "drive-harddisk");
        compare(findChild(surface, "ambient-core-name").text, "Storage · 91% full");
        compare(findChild(surface, "ambient-core-detail").text, "45 GB free · Free up space");
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(shape, shape.width - 12, shape.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "core:storage");
        compare(invoked.signalArguments[0][1], 3);
        compare(invoked.signalArguments[0][2], "open");
        compare(opens.count, 0);
        surface.setAside("core");
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][2], "setAside");
        surface.width = 60;
        settle();
        compare(shown(surface, "core"), ["icon"]);
    }

    // A Windows program's fact adds "Don't tell me again" after its words: a
    // tap on it tells Core never, a tap elsewhere still opens the card. Other
    // facts have no such pill.
    function test_a_windows_fact_offers_dont_tell_me_again() {
        const storage = {id: "core:storage", generation: 3, kind: "core", state: "running",
            title: "Storage", line: "91% full", icon: "drive-harddisk", capabilities: {open: true}};
        const plain = createSurface(640, [storage]);
        settle();
        verify(shown(plain, "core").indexOf("never") < 0);
        verify(!findChild(plain, "ambient-core-never").visible);

        const fact = {id: "core:windows", generation: 5, kind: "core", state: "running",
            title: "Windows program", line: "setup.exe", actionText: "Find the Linux version",
            icon: "application-x-ms-dos-executable", capabilities: {open: true, never: true}};
        const surface = createSurface(640, [fact]);
        settle();
        const shape = island(surface, "core");
        verify(shown(surface, "core").indexOf("never") >= 0);
        const never = findChild(surface, "ambient-core-never");
        verify(never.visible);
        compare(never.Accessible.name, "Don't tell me again: Windows program · setup.exe");
        verify(leftOf(surface, never) >= rightOf(surface, findChild(surface, "ambient-core-name")) + 12 - 1);
        const invoked = spyOn(surface, "invokeRequested");
        mouseClick(never, never.width / 2, never.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "core:windows");
        compare(invoked.signalArguments[0][1], 5);
        compare(invoked.signalArguments[0][2], "never");
        mouseClick(shape, 12, shape.height / 2);
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][2], "open");
    }

    // A fact that asks opens in place rather than acting on a tap: the card
    // shows the question, its tap's words first, the choices Core lists in
    // Core's order, and Not now last in Core's words where it gives them.
    // Each answer goes to Core and closes the card.
    function test_a_core_question_opens_with_its_answers() {
        const fact = {id: "core:memory", generation: 7, kind: "core", state: "running",
            title: "Workspace Memory", line: "Bring back 4 apps from yesterday?",
            detail: "Each one goes back to its place", actionText: "Bring back", icon: "window-restore",
            asks: true, choices: [{action: "always", text: "Always"}], dismissText: "",
            capabilities: {open: true, always: true, "not-now": true}};
        const surface = createSurface(640, [fact]);
        settle();
        const shape = island(surface, "core");
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(shape, shape.width - 12, shape.height / 2);
        compare(invoked.count, 0);
        compare(opens.count, 1);
        compare(opens.signalArguments[0][0], "core");

        const opened = openIsland(surface, "core");
        const card = findChild(opened.contentItem, "ambient-island-core");
        verify(card.visible);
        verify(!findChild(opened.contentItem, "ambient-island-kinds").visible);
        compare(findChild(opened.contentItem, "ambient-island-core-line").text, "Bring back 4 apps from yesterday?");
        compare(findChild(opened.contentItem, "ambient-island-core-detail").text, "Each one goes back to its place");
        const main = findChild(opened.contentItem, "ambient-island-core-open");
        const always = findChild(opened.contentItem, "ambient-island-core-choice-always");
        const notNow = findChild(opened.contentItem, "ambient-island-core-not-now");
        compare(main.label, "Bring back");
        verify(main.filled);
        compare(always.label, "Always");
        verify(!always.filled);
        compare(notNow.label, "Not now");
        // The island's pills: 40 tall, round, 8 apart, in reading order.
        for (const pill of [main, always, notNow]) {
            compare(pill.height, 40);
            compare(pill.radius, 20);
        }
        const along = item => item.mapToItem(card, 0, 0);
        fuzzyCompare(along(always).x, along(main).x + main.width + 8, 0.5);
        fuzzyCompare(along(notNow).x, along(always).x + always.width + 8, 0.5);

        const closed = spyOn(opened, "closed");
        mouseClick(always, always.width / 2, always.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "core:memory");
        compare(invoked.signalArguments[0][1], 7);
        compare(invoked.signalArguments[0][2], "always");
        tryCompare(closed, "count", 1);

        const again = openIsland(surface, "core");
        const later = findChild(again.contentItem, "ambient-island-core-not-now");
        mouseClick(later, later.width / 2, later.height / 2);
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][2], "not-now");
    }

    // An offer with its own words for Not now and no choices has two pills;
    // Core's words are drawn as given, and the card closes when Core stops
    // asking.
    function test_a_core_offer_says_not_now_in_cores_words() {
        const fact = {id: "core:automations", generation: 2, kind: "core", state: "running",
            title: "Automations", line: "Open Firefox, Notes and Mail when you sign in?",
            detail: "You've started with these three times", actionText: "Yes, each time",
            asks: true, choices: [], dismissText: "No thanks", capabilities: {open: true, "not-now": true}};
        const surface = createSurface(640, [fact]);
        settle();
        const opened = openIsland(surface, "core");
        const answers = findChild(opened.contentItem, "ambient-island-core-answers");
        let pills = 0;
        for (let i = 0; i < answers.children.length; ++i)
            if (answers.children[i].visible && answers.children[i].label !== undefined) ++pills;
        compare(pills, 2);
        compare(findChild(opened.contentItem, "ambient-island-core-open").label, "Yes, each time");
        compare(findChild(opened.contentItem, "ambient-island-core-not-now").label, "No thanks");
        const invoked = spyOn(surface, "invokeRequested");
        const yes = findChild(opened.contentItem, "ambient-island-core-open");
        mouseClick(yes, yes.width / 2, yes.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][2], "open");

        const reopened = openIsland(surface, "core");
        const gone = spyOn(reopened, "closed");
        surface.activities = [];
        tryCompare(gone, "count", 1);
    }

    // Layouts opens in place: its title and count, each saved layout drawn
    // small with its Open pill, the first filled, "Opens when you sign in"
    // where that is on, then Save what's open and Close. Open asks for that
    // layout and closes the island.
    function test_layouts_open_in_place() {
        const host = createTemporaryObject(layoutsComponent, testCase);
        const opened = openLayouts(host);
        const list = findChild(opened.contentItem, "ambient-island-layouts");
        verify(list.visible);
        verify(!findChild(opened.contentItem, "ambient-island-layout-form").visible);
        verify(!findChild(opened.contentItem, "ambient-island-kinds").visible);
        compare(findChild(opened.contentItem, "ambient-island-layouts-title").text, "Layouts");
        compare(findChild(opened.contentItem, "ambient-island-layouts-count").text, " · 2 saved");
        verify(!findChild(opened.contentItem, "ambient-island-layouts-none").visible);
        verify(findChild(opened.contentItem, "ambient-island-layout-at-sign-in-1").visible);
        verify(!findChild(opened.contentItem, "ambient-island-layout-at-sign-in-2").visible);
        // Each group a card in the miniature, three for Coding.
        const miniature = findChild(opened.contentItem, "ambient-island-layout-miniature-1");
        let cards = 0;
        for (let i = 0; i < miniature.children.length; ++i)
            if (miniature.children[i].names !== undefined) ++cards;
        compare(cards, 3);
        const first = findChild(opened.contentItem, "ambient-island-layout-open-1");
        const second = findChild(opened.contentItem, "ambient-island-layout-open-2");
        compare(first.label, "Open");
        verify(first.filled);
        verify(!second.filled);
        for (const pill of [first, second]) {
            compare(pill.height, 32);
            compare(pill.radius, 16);
        }
        const save = findChild(opened.contentItem, "ambient-island-layouts-save");
        const close = findChild(opened.contentItem, "ambient-island-layouts-close");
        compare(save.label, "Save what's open");
        verify(save.filled);
        compare(close.label, "Close");
        compare(save.height, 40);

        const closed = spyOn(opened, "closed");
        tap(second);
        compare(host.calls.length, 1);
        compare(host.calls[0], ["open", "2"]);
        tryCompare(closed, "count", 1);
    }

    // With none saved, the island says how to make one.
    function test_layouts_with_none_saved() {
        const host = createTemporaryObject(layoutsComponent, testCase, {layouts: []});
        const opened = openLayouts(host);
        verify(findChild(opened.contentItem, "ambient-island-layouts-none").visible);
        verify(!findChild(opened.contentItem, "ambient-island-layouts-count").visible);
        verify(findChild(opened.contentItem, "ambient-island-layouts-save").visible);
    }

    // A tap on a saved layout's row shows its own switch and Remove; each
    // goes to Core.
    function test_a_saved_layouts_switch_and_remove() {
        const host = createTemporaryObject(layoutsComponent, testCase);
        const opened = openLayouts(host);
        const row = findChild(opened.contentItem, "ambient-island-layout-1");
        const toggle = findChild(opened.contentItem, "ambient-island-layout-switch-1");
        verify(!toggle.visible);
        mouseClick(row, 20, 20);
        settle();
        verify(toggle.visible);
        verify(toggle.on);
        tap(toggle);
        compare(host.calls[0], ["atSignIn", "1", false]);
        const remove = findChild(opened.contentItem, "ambient-island-layout-remove-1");
        compare(remove.label, "Remove");
        tap(remove);
        compare(host.calls[1], ["remove", "1"]);
        verify(opened.expanded);
    }

    // Save what's open turns the island into the form: a name, what Core
    // reads as open, group by group with Remove, the sign-in switch off, then
    // Save and Not now. Save needs a name and a group, and closes the island.
    function test_saving_whats_open() {
        const host = createTemporaryObject(layoutsComponent, testCase);
        const opened = openLayouts(host);
        tap(findChild(opened.contentItem, "ambient-island-layouts-save"));
        settle();
        const form = findChild(opened.contentItem, "ambient-island-layout-form");
        verify(form.visible);
        verify(!findChild(opened.contentItem, "ambient-island-layouts").visible);
        compare(host.calls[0], ["read"]);
        compare(findChild(opened.contentItem, "ambient-island-layout-form-empty").text, "Looking at what's open…");

        host.currentLayout = {available: true, workspace: "d-1", workspaceName: "Work", groups: [
            {apps: ["ghostty", "claude"], names: ["Ghostty", "Claude"], stack: true},
            {apps: ["zen"], names: ["Zen"], stack: false},
            {apps: ["mail", "notes", "files"], names: ["Mail", "Notes", "Files"], stack: true}]};
        settle();
        verify(!findChild(opened.contentItem, "ambient-island-layout-form-empty").visible);
        compare(findChild(opened.contentItem, "ambient-island-layout-form-where").text, " · what's open on Work");
        compare(findChild(opened.contentItem, "ambient-island-layout-group-title-0").text, "Stack");
        compare(findChild(opened.contentItem, "ambient-island-layout-group-line-0").text, "Ghostty, Claude");
        compare(findChild(opened.contentItem, "ambient-island-layout-group-title-1").text, "Zen");
        compare(findChild(opened.contentItem, "ambient-island-layout-group-line-1").text, "On its own");
        const toggle = findChild(opened.contentItem, "ambient-island-layout-form-switch");
        verify(!toggle.on);
        const save = findChild(opened.contentItem, "ambient-island-layout-form-save");
        compare(save.label, "Save");
        compare(findChild(opened.contentItem, "ambient-island-layout-form-not-now").label, "Not now");

        // Without a name, Save does nothing.
        tap(save);
        compare(host.calls.length, 1);
        verify(opened.expanded);

        tap(findChild(opened.contentItem, "ambient-island-layout-group-remove-2"));
        settle();
        verify(findChild(opened.contentItem, "ambient-island-layout-group-1").visible);
        verify(findChild(opened.contentItem, "ambient-island-layout-group-2") === null);
        tap(toggle);
        verify(toggle.on);
        const name = findChild(opened.contentItem, "ambient-island-layout-name");
        name.text = "Coding";
        const closed = spyOn(opened, "closed");
        tap(save);
        compare(host.calls.length, 2);
        compare(host.calls[1][0], "save");
        compare(host.calls[1][1], "Coding");
        compare(host.calls[1][2].length, 2);
        compare(host.calls[1][2][1].apps, ["zen"]);
        compare(host.calls[1][3], true);
        tryCompare(closed, "count", 1);
    }

    // Not now leaves without saving; with nothing open, Save stays idle.
    function test_not_now_saves_nothing() {
        const host = createTemporaryObject(layoutsComponent, testCase);
        const opened = openLayouts(host);
        tap(findChild(opened.contentItem, "ambient-island-layouts-save"));
        settle();
        host.currentLayout = {available: false};
        settle();
        compare(findChild(opened.contentItem, "ambient-island-layout-form-empty").text,
            "Nothing open here to save. Arrange your apps, then come back.");
        findChild(opened.contentItem, "ambient-island-layout-name").text = "Coding";
        tap(findChild(opened.contentItem, "ambient-island-layout-form-save"));
        compare(host.calls.length, 1);
        verify(opened.expanded);
        const closed = spyOn(opened, "closed");
        tap(findChild(opened.contentItem, "ambient-island-layout-form-not-now"));
        compare(host.calls.length, 1);
        tryCompare(closed, "count", 1);
    }

    // A layout that opened without some of its apps says so once on Core's
    // island; a tap takes it away and opens Layouts.
    function test_a_layout_that_missed_says_which_app() {
        const missed = {id: "core:layout-missed", generation: 4, kind: "core", state: "running",
            icon: "view-grid", missed: ["Mail"], layout: "Coding", capabilities: {open: true}};
        const surface = createSurface(640, [missed]);
        settle();
        compare(findChild(surface, "ambient-core-name").text, "Mail didn't open");
        compare(findChild(surface, "ambient-core-detail").text, "The rest of Coding is in place");
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        const shape = island(surface, "core");
        mouseClick(shape, shape.width - 12, shape.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "core:layout-missed");
        compare(invoked.signalArguments[0][2], "open");
        compare(opens.count, 1);
        compare(opens.signalArguments[0][0], "layouts");

        surface.activities = [Object.assign({}, missed, {missed: ["Mail", "Notes"], layout: ""})];
        compare(findChild(surface, "ambient-core-name").text, "Mail and Notes didn't open");
        compare(findChild(surface, "ambient-core-detail").text, "The rest is in place");
        surface.activities = [Object.assign({}, missed, {missed: ["Mail", "Notes", "Files"]})];
        compare(findChild(surface, "ambient-core-name").text, "Mail and 2 more didn't open");
    }

    // The quick note's island: a dot with a plus that opens the quick note,
    // and the pinned note beside it, its colour's bead and first words, which
    // opens that note. Narrow, the pinned note goes first.
    function test_the_quick_note_island() {
        const door = {id: "note", generation: 1, kind: "note", state: "running", capabilities: {}};
        const pinned = {id: "note", generation: 2, kind: "note", state: "running", capabilities: {},
            noteId: "n1", title: "Milk, eggs, bread", colourHex: "#F5C542"};
        const surface = createSurface(460, [door]);
        settle();
        const shape = island(surface, "note");
        verify(shape.visible);
        compare(shown(surface, "note"), ["dot"]);
        compare(shape.Accessible.name, "New quick note");
        const dot = findChild(surface, "ambient-note-dot");
        verify(dot.visible);
        verify(shape.height >= 44 && carrier(surface, "note").width >= 44);
        const drawers = spyOn(surface, "drawerRequested");
        const invoked = spyOn(surface, "invokeRequested");
        const opens = spyOn(surface, "openRequested");
        mouseClick(dot, dot.width / 2, dot.height / 2);
        compare(drawers.count, 1);
        compare(drawers.signalArguments[0][0], "note");
        compare(opens.count, 0);

        surface.activities = [pinned];
        settle();
        compare(shown(surface, "note"), ["dot", "pinned"]);
        const note = findChild(surface, "ambient-note-pinned");
        verify(note.visible);
        verify(note.width >= 44 && note.height >= 44);
        verify(leftOf(surface, note) >= rightOf(surface, dot));
        verify(Qt.colorEqual(findChild(surface, "ambient-note-bead").color, "#F5C542"));
        compare(findChild(surface, "ambient-note-title").text, "Milk, eggs, bread");
        compare(note.Accessible.name, "Pinned note: Milk, eggs, bread");
        mouseClick(note, note.width / 2, note.height / 2);
        compare(drawers.count, 2);
        compare(drawers.signalArguments[1][0], "note:n1");
        mouseClick(dot, dot.width / 2, dot.height / 2);
        compare(drawers.count, 3);
        compare(drawers.signalArguments[2][0], "note");

        // It stays: a drag does not carry it, and nothing sets it aside.
        const at = slowDrag(surface, "note", -120);
        compare(carrier(surface, "note").peel, 0);
        verify(!carrier(surface, "note").peeling);
        mouseRelease(surface, at.x - 120, at.y);
        settle();
        verify(island(surface, "note").visible);
        surface.setAside("note");
        compare(invoked.count, 0);

        // It stands first, and beside other islands, narrow, it keeps its dot
        // and lets the pinned note go.
        surface.activities = [media, pinned];
        settle();
        verify(rightOf(surface, island(surface, "note")) <= leftOf(surface, island(surface, "media")));
        surface.width = 300;
        settle();
        compare(shown(surface, "note"), ["dot"]);
        verify(shown(surface, "media").length > 1);
    }

    // The window in use's notes join the island as Gooseberry's dot, with
    // their count, after the pinned note; ringed while they are up, and a
    // tap asks for them either way. Narrow, the pinned note goes first.
    function test_the_window_notes_on_the_quick_note_island() {
        const pinned = {id: "note", generation: 2, kind: "note", state: "running", capabilities: {},
            noteId: "n1", title: "Milk", colourHex: "#F5C542"};
        const away = {id: "note", generation: 3, kind: "note", state: "running",
            capabilities: {windowNotes: true}, noteId: "n1", title: "Milk", colourHex: "#F5C542",
            windowCount: 2, windowColourHex: "#7FB8F0", windowShown: false};
        const surface = createSurface(460, [pinned]);
        settle();
        compare(shown(surface, "note"), ["dot", "pinned"]);
        verify(!findChild(surface, "ambient-note-window").visible);

        surface.activities = [away];
        settle();
        compare(shown(surface, "note"), ["dot", "window", "pinned"]);
        const button = findChild(surface, "ambient-note-window");
        verify(button.visible);
        verify(button.width >= 44 && button.height >= 44);
        verify(leftOf(surface, button) >= rightOf(surface, findChild(surface, "ambient-note-pinned")));
        const dot = findChild(surface, "ambient-note-window-dot");
        compare(dot.width, 18);
        verify(Qt.colorEqual(dot.color, "#7FB8F0"));
        compare(findChild(surface, "ambient-note-window-ring").opacity, 0);
        compare(button.Accessible.name, "Show the 2 notes");
        const invoked = spyOn(surface, "invokeRequested");
        mouseClick(button, button.width / 2, button.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][2], "windowNotes");

        surface.activities = [Object.assign({}, away, {windowShown: true})];
        settle();
        tryCompare(findChild(surface, "ambient-note-window-ring"), "opacity", 1);
        compare(findChild(surface, "ambient-note-window").Accessible.name, "Put away the 2 notes");

        surface.width = 130;
        settle();
        compare(shown(surface, "note"), ["dot", "window"]);
    }

    // The quick note's island on a light style takes the style's ink.
    function test_the_quick_note_island_on_a_light_style() {
        const pinned = {id: "note", generation: 2, kind: "note", state: "running", capabilities: {},
            noteId: "n1", title: "Milk", colourHex: "#F5C542"};
        const surface = createSurface(460, [pinned]);
        settle();
        colors(surface).theme = darkStyle;
        const dot = findChild(surface, "ambient-note-dot");
        tryVerify(() => Qt.colorEqual(Qt.rgba(dot.color.r, dot.color.g, dot.color.b, 1), "#F8F8FF"));
        colors(surface).theme = lightStyle;
        tryVerify(() => Qt.colorEqual(Qt.rgba(dot.color.r, dot.color.g, dot.color.b, 1), "#102729"));
        verify(Qt.colorEqual(findChild(surface, "ambient-note-title").color, "#102729"));
        verify(Qt.colorEqual(findChild(surface, "ambient-note-bead").color, "#F5C542"));
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
