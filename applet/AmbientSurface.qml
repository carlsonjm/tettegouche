/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: surface

    property var activities: []
    property var monotonicClock: () => 0
    property double clockNowUs: 0
    // The panel's measured span can update before Plasma commits this item's
    // geometry. Drive disclosure from that allocation, not an old implicit width.
    property real allocatedWidth: width
    readonly property real availableContentWidth: Math.max(width, allocatedWidth)
    readonly property var transfers: activities.filter(activity => activity.kind === "transfer")
    readonly property var media: activities.filter(activity => activity.kind === "media")
    readonly property int individualCoreWidth: transfers.reduce((sum, activity) =>
        sum + transferCoreWidth(activity), 0) + media.length * 40
        + Math.max(0, activities.length - 1) * 4
    readonly property bool transfersGrouped: transfers.length > 1
        && individualCoreWidth > width
    readonly property int groupedCoreWidth: (transfers.length > 0 ? 72 : 0)
        + media.length * 40 + (transfers.length > 0 && media.length > 0 ? 4 : 0)
    readonly property int minimumUsefulWidth: activities.length === 0 ? 0
        : Math.min(individualCoreWidth,
            transfers.length > 1 ? groupedCoreWidth : individualCoreWidth)
    readonly property int mediaTransportExtraWidth: media.reduce((sum, activity) =>
        sum + (capability(activity, "previous") ? 28 : 0)
            + (capability(activity, "next") ? 28 : 0), 0)
    readonly property int transportThreshold: minimumUsefulWidth + mediaTransportExtraWidth
    readonly property int titleThreshold: Math.max(300, transportThreshold + 80)
    readonly property int artistThreshold: Math.max(480, titleThreshold + 90)
    readonly property int timeThreshold: Math.max(560, artistThreshold + 70)
    readonly property string density: availableContentWidth >= timeThreshold ? "wide"
        : availableContentWidth >= titleThreshold ? "medium"
        : availableContentWidth >= transportThreshold ? "narrow" : "core"
    readonly property bool showMediaTransport: availableContentWidth >= transportThreshold
    readonly property bool showTransferTitle: availableContentWidth >= Math.max(170, transportThreshold)
    readonly property bool showMediaTitle: availableContentWidth >= titleThreshold
    readonly property bool showMediaArtist: availableContentWidth >= artistThreshold
    readonly property bool showMediaTime: availableContentWidth >= timeThreshold
    readonly property bool showSecondary: showMediaArtist
    readonly property bool hasPlayingClock: media.some(activity =>
        activity.state === "playing" && activity.positionUs !== undefined)
    signal invokeRequested(string activityId, int generation, string action)
    signal detailsRequested(var activity, var anchorItem)

    clip: true

    function capability(activity, name) {
        return Boolean(activity.capabilities && activity.capabilities[name]);
    }

    function transferCoreWidth(activity) {
        return capability(activity, "cancel") ? 86 : 58;
    }

    function percentage(activity) {
        if (activity.progress === undefined || activity.progress === null)
            return "—";
        return Math.round(Math.max(0, Math.min(1, Number(activity.progress))) * 100) + "%";
    }

    function formatBytes(bytes) {
        if (bytes === undefined || bytes === null) return "";
        const value = Number(bytes);
        if (value >= 1000000000) return (value / 1000000000).toFixed(1) + " GB";
        if (value >= 1000000) return (value / 1000000).toFixed(1) + " MB";
        if (value >= 1000) return (value / 1000).toFixed(1) + " KB";
        return value + " B";
    }

    function transferBytes(activity) {
        if (activity.processedBytes !== undefined && activity.totalBytes !== undefined)
            return formatBytes(activity.processedBytes) + "/" + formatBytes(activity.totalBytes);
        if (activity.observedSizeBytes !== undefined)
            return qsTr("File size %1").arg(formatBytes(activity.observedSizeBytes));
        return "";
    }

    function mediaPositionUs(activity) {
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

    function mediaTime(activity) {
        if (activity.positionUs === undefined && activity.durationUs === undefined) return "";
        const elapsed = activity.positionUs === undefined ? "—" : formatTime(mediaPositionUs(activity));
        return activity.durationUs === undefined ? elapsed : elapsed + "/" + formatTime(activity.durationUs);
    }

    function invoke(activity, action) {
        invokeRequested(String(activity.id), Number(activity.generation), action);
    }

    function openDetails(activity, anchorItem) {
        if (activity) detailsRequested(activity, anchorItem);
    }

    Timer {
        interval: 1000
        repeat: true
        running: surface.visible && surface.hasPlayingClock
        triggeredOnStart: true
        onTriggered: surface.clockNowUs = Number(surface.monotonicClock())
    }

    RowLayout {
        id: activityRow
        anchors.fill: parent
        spacing: 4

        Item {
            id: transferGroup
            objectName: "ambient-transfer-group"
            visible: surface.transfersGrouped
            Layout.preferredWidth: visible ? 72 : 0
            Layout.minimumWidth: visible ? 72 : 0
            Layout.maximumWidth: visible ? 72 : 0
            Layout.fillHeight: true
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("%1 transfers, details").arg(surface.transfers.length)
            Keys.onReturnPressed: surface.openDetails(surface.transfers[0], transferGroup)
            Keys.onEnterPressed: surface.openDetails(surface.transfers[0], transferGroup)
            Keys.onSpacePressed: surface.openDetails(surface.transfers[0], transferGroup)

            Row {
                anchors.centerIn: parent
                spacing: 4
                Kirigami.Icon { width: 16; height: 16; source: "folder-download-symbolic" }
                PlasmaComponents.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("%1 transfers").arg(surface.transfers.length)
                }
            }
            TapHandler { onTapped: surface.openDetails(surface.transfers[0], transferGroup) }
        }

        Repeater {
            model: surface.transfersGrouped ? [] : surface.transfers
            delegate: Item {
                id: transferItem
                required property var modelData
                objectName: "ambient-transfer-" + modelData.id
                Layout.minimumWidth: surface.transferCoreWidth(modelData)
                Layout.preferredWidth: Layout.minimumWidth
                    + (surface.showTransferTitle ? Math.min(130, transferTitle.implicitWidth + 6) : 0)
                    + (surface.showSecondary && surface.transferBytes(modelData) ? 96 : 0)
                Layout.maximumWidth: Layout.preferredWidth
                Layout.fillHeight: true
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Transfer %1, %2").arg(modelData.title || modelData.source || "")
                    .arg(surface.percentage(modelData))
                Keys.onReturnPressed: surface.openDetails(transferItem.modelData, transferItem)
                Keys.onEnterPressed: surface.openDetails(transferItem.modelData, transferItem)
                Keys.onSpacePressed: surface.openDetails(transferItem.modelData, transferItem)

                RowLayout {
                    anchors.fill: parent
                    spacing: 3
                    Kirigami.Icon {
                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                        source: transferItem.modelData.icon || "folder-download-symbolic"
                    }
                    PlasmaComponents.Label {
                        objectName: "ambient-transfer-progress"
                        text: surface.percentage(transferItem.modelData)
                    }
                    PlasmaComponents.Label {
                        id: transferTitle
                        visible: surface.showTransferTitle
                        text: transferItem.modelData.title || transferItem.modelData.source || qsTr("Transfer")
                        elide: Text.ElideRight
                        Layout.maximumWidth: 130
                    }
                    PlasmaComponents.Label {
                        visible: surface.showSecondary && text.length > 0
                        text: surface.transferBytes(transferItem.modelData)
                        opacity: 0.72
                        elide: Text.ElideRight
                        Layout.maximumWidth: 96
                    }
                    PlasmaComponents.ToolButton {
                        objectName: "ambient-transfer-cancel"
                        visible: surface.capability(transferItem.modelData, "cancel")
                        icon.name: "dialog-cancel-symbolic"
                        text: qsTr("Cancel")
                        display: PlasmaComponents.AbstractButton.IconOnly
                        Accessible.name: qsTr("Cancel %1").arg(transferItem.modelData.title || qsTr("transfer"))
                        onClicked: surface.invoke(transferItem.modelData, "cancel")
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: surface.openDetails(transferItem.modelData, transferItem)
                }
            }
        }

        Repeater {
            model: surface.media
            delegate: Item {
                id: mediaItem
                required property var modelData
                readonly property string toggleAction: modelData.state === "playing" ? "pause" : "play"
                readonly property bool canToggle: surface.capability(modelData, toggleAction)
                objectName: "ambient-media-" + modelData.id
                Layout.minimumWidth: Math.max(40, transportCluster.implicitWidth)
                Layout.preferredWidth: mediaRow.implicitWidth
                Layout.maximumWidth: Layout.preferredWidth
                Layout.fillHeight: true
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Media %1 by %2").arg(modelData.title || modelData.source || "")
                    .arg(modelData.artist || "")
                Keys.onReturnPressed: surface.openDetails(mediaItem.modelData, mediaItem)
                Keys.onEnterPressed: surface.openDetails(mediaItem.modelData, mediaItem)
                Keys.onSpacePressed: surface.openDetails(mediaItem.modelData, mediaItem)

                Row {
                    id: mediaRow
                    anchors.fill: parent
                    spacing: 3
                    Kirigami.Icon {
                        visible: !mediaItem.canToggle
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        source: mediaItem.modelData.icon || "audio-x-generic-symbolic"
                    }
                    Row {
                        id: transportCluster
                        objectName: "ambient-media-transport-cluster"
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter

                        PlasmaComponents.ToolButton {
                            objectName: "ambient-media-previous"
                            visible: surface.showMediaTransport
                                && surface.capability(mediaItem.modelData, "previous")
                            icon.name: "media-skip-backward-symbolic"
                            display: PlasmaComponents.AbstractButton.IconOnly
                            Accessible.name: qsTr("Previous")
                            onClicked: surface.invoke(mediaItem.modelData, "previous")
                        }
                        PlasmaComponents.ToolButton {
                            objectName: "ambient-media-toggle"
                            visible: mediaItem.canToggle
                            icon.name: mediaItem.modelData.state === "playing"
                                ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                            text: mediaItem.modelData.state === "playing" ? qsTr("Pause") : qsTr("Play")
                            display: PlasmaComponents.AbstractButton.IconOnly
                            Accessible.name: text
                            onClicked: surface.invoke(mediaItem.modelData,
                                mediaItem.toggleAction)
                        }
                        PlasmaComponents.ToolButton {
                            objectName: "ambient-media-next"
                            visible: surface.showMediaTransport
                                && surface.capability(mediaItem.modelData, "next")
                            icon.name: "media-skip-forward-symbolic"
                            display: PlasmaComponents.AbstractButton.IconOnly
                            Accessible.name: qsTr("Next")
                            onClicked: surface.invoke(mediaItem.modelData, "next")
                        }
                    }
                    PlasmaComponents.Label {
                        id: mediaTitle
                        objectName: "ambient-media-title"
                        visible: surface.showMediaTitle
                        text: mediaItem.modelData.title || mediaItem.modelData.source || qsTr("Media")
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(120, implicitWidth)
                    }
                    PlasmaComponents.Label {
                        id: mediaArtist
                        objectName: "ambient-media-artist"
                        visible: surface.showMediaArtist && Boolean(mediaItem.modelData.artist)
                        text: mediaItem.modelData.artist || ""
                        opacity: 0.72
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(90, implicitWidth)
                    }
                    PlasmaComponents.Label {
                        objectName: "ambient-media-time"
                        visible: surface.showMediaTime && text.length > 0
                        text: surface.mediaTime(mediaItem.modelData)
                        opacity: 0.72
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: surface.openDetails(mediaItem.modelData, mediaItem)
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

}
