/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtTest
import "../applet" as Applet

TestCase {
    id: testCase
    name: "AmbientSurface"
    when: windowShown
    width: 640
    height: 180
    visible: true

    readonly property var transfer: ({
        id: "transfer-1", generation: 3, kind: "transfer", state: "running",
        source: "Files", icon: "folder-download-symbolic", title: "Fedora.iso",
        progress: 0.68, processedBytes: 3200000000, totalBytes: 4700000000,
        capabilities: {cancel: true}
    })
    readonly property var unknownFile: ({
        id: "file-1", generation: 1, kind: "transfer", state: "running",
        source: "Incoming file", title: "archive.part", progress: null,
        observedSizeBytes: 2048, evidence: "filesystem",
        capabilities: {showInFiles: true}
    })
    readonly property var media: ({
        id: "media-1", generation: 8, kind: "media", state: "playing",
        source: "Player", title: "Houdini", artist: "Dua Lipa",
        positionUs: 10000000, sampledAtMonotonicUs: 1000000,
        durationUs: 180000000, rate: 1,
        capabilities: {play: true, pause: true, previous: true, next: true}
    })

    Component {
        id: surfaceComponent
        Applet.AmbientSurface { height: 42; monotonicClock: () => 2000000 }
    }
    Component {
        id: detailsComponent
        Applet.ActivityDetails { width: 340; height: 200 }
    }

    function createSurface(width, activities) {
        const surface = createTemporaryObject(surfaceComponent, testCase,
            {width: width, activities: activities});
        verify(surface !== null);
        wait(0);
        return surface;
    }

    function test_empty_is_quiet() {
        const surface = createSurface(300, []);
        compare(surface.minimumUsefulWidth, 0);
        compare(surface.children[0].visible, true);
    }

    function test_transfer_and_media_keep_cores() {
        const surface = createSurface(130, [transfer, media]);
        compare(surface.density, "core");
        compare(surface.transfersGrouped, false);
        verify(findChild(surface, "ambient-transfer-transfer-1").visible);
        verify(findChild(surface, "ambient-media-media-1").visible);
        verify(findChild(surface, "ambient-transfer-cancel").visible);
        verify(findChild(surface, "ambient-media-toggle").visible);
    }

    function test_density_reveals_context() {
        const core = createSurface(130, [transfer, media]);
        compare(core.showTransferTitle, false);
        compare(core.showMediaTitle, false);
        compare(core.showSecondary, false);

        const narrow = createSurface(220, [transfer, media]);
        compare(narrow.density, "narrow");
        compare(narrow.showTransferTitle, true);
        compare(narrow.showMediaTitle, false);

        const medium = createSurface(340, [transfer, media]);
        compare(medium.showMediaTitle, true);
        compare(medium.showSecondary, false);

        const wide = createSurface(560, [transfer, media]);
        compare(wide.showSecondary, true);
        verify(findChild(wide, "ambient-transfer-transfer-1").visible);
        verify(findChild(wide, "ambient-media-media-1").visible);
        verify(findChild(wide, "ambient-media-title").visible);
        verify(findChild(wide, "ambient-media-artist").visible);
        verify(findChild(wide, "ambient-media-time").visible);
    }

    function test_similar_transfers_group_only_at_core_overflow() {
        const second = Object.assign({}, transfer, {id: "transfer-2", progress: 0.2});
        const grouped = createSurface(160, [transfer, second, media]);
        compare(grouped.transfersGrouped, true);
        verify(findChild(grouped, "ambient-transfer-group").visible);

        const individual = createSurface(240, [transfer, second, media]);
        compare(individual.transfersGrouped, false);
        verify(findChild(individual, "ambient-transfer-transfer-1").visible);
        verify(findChild(individual, "ambient-transfer-transfer-2").visible);
    }

    function test_unknown_filesystem_evidence_stays_honest() {
        const surface = createSurface(560, [unknownFile]);
        compare(surface.percentage(unknownFile), "—");
        compare(surface.transferBytes(unknownFile), "File size 2.0 KB");
        verify(!surface.capability(unknownFile, "cancel"));
        verify(surface.capability(unknownFile, "showInFiles"));
    }

    function test_paused_media_clock_stops() {
        const surface = createSurface(300, [media]);
        surface.clockNowUs = 2000000;
        compare(surface.mediaPositionUs(media), 11000000);
        const paused = Object.assign({}, media, {state: "paused"});
        compare(surface.mediaPositionUs(paused), 10000000);
    }

    function test_action_and_local_details() {
        const surface = createSurface(300, [transfer, media]);
        const spy = createTemporaryQmlObject(
            'import QtTest; SignalSpy {}', testCase);
        spy.target = surface;
        spy.signalName = "invokeRequested";
        surface.invoke(transfer, "cancel");
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "transfer-1");
        compare(spy.signalArguments[0][1], 3);
        compare(spy.signalArguments[0][2], "cancel");
    }

    function test_details_select_one_activity_at_a_time() {
        const surface = createSurface(300, [transfer, media]);
        const spy = createTemporaryQmlObject(
            'import QtTest; SignalSpy {}', testCase);
        spy.target = surface;
        spy.signalName = "detailsRequested";
        surface.openDetails(transfer, surface);
        surface.openDetails(media, surface);
        compare(spy.count, 2);
        compare(spy.signalArguments[0][0].id, "transfer-1");
        compare(spy.signalArguments[1][0].id, "media-1");
    }

    function test_details_keep_supported_actions_reachable() {
        const details = createTemporaryObject(detailsComponent, testCase,
            {activity: unknownFile});
        verify(details !== null);
        wait(0);
        const showInFiles = findChild(details, "ambient-detail-showInFiles");
        const cancel = findChild(details, "ambient-detail-cancel");
        verify(showInFiles.visible);
        verify(!cancel.visible);
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy {}', testCase);
        spy.target = details;
        spy.signalName = "invokeRequested";
        showInFiles.clicked();
        compare(spy.count, 1);
        compare(spy.signalArguments[0][0], "file-1");
        compare(spy.signalArguments[0][2], "showInFiles");
    }
}
