/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

FocusScope {
    id: details

    property var activities: []
    property double monotonicNowUs: 0
    signal closeRequested()
    signal invokeRequested(string activityId, int generation, string action)

    implicitWidth: 340
    implicitHeight: Math.min(420, detailsColumn.implicitHeight + 20)
    Accessible.name: qsTr("Ambient activity details")

    function capability(activity, name) {
        return Boolean(activity.capabilities && activity.capabilities[name]);
    }

    function actionAvailable(activity, name) {
        if (!capability(activity, name)) return false;
        if (name === "play") return activity.state !== "playing";
        if (name === "pause") return activity.state === "playing";
        if (name === "suspend") return activity.state === "running";
        if (name === "resume") return activity.state === "suspended";
        return true;
    }

    function invoke(activity, action) {
        invokeRequested(String(activity.id), Number(activity.generation), action);
    }

    Keys.onEscapePressed: closeRequested()

    ColumnLayout {
        id: detailsColumn
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label {
                text: qsTr("What matters now")
                font.bold: true
                Layout.fillWidth: true
            }
            PlasmaComponents.ToolButton {
                objectName: "ambient-details-close"
                icon.name: "dialog-close-symbolic"
                text: qsTr("Close")
                display: PlasmaComponents.AbstractButton.IconOnly
                Accessible.name: qsTr("Close activity details")
                onClicked: details.closeRequested()
            }
        }

        Repeater {
            model: details.activities
            delegate: ColumnLayout {
                id: activityDetails
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Icon {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        source: activityDetails.modelData.icon || (activityDetails.modelData.kind === "media"
                            ? "audio-x-generic-symbolic" : "folder-download-symbolic")
                    }
                    PlasmaComponents.Label {
                        text: activityDetails.modelData.title || activityDetails.modelData.source
                            || (activityDetails.modelData.kind === "media" ? qsTr("Media") : qsTr("Transfer"))
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: activityDetails.modelData.kind === "transfer"
                        text: activityDetails.modelData.progress === undefined
                            || activityDetails.modelData.progress === null
                            ? qsTr("Progress unknown")
                            : Math.round(Number(activityDetails.modelData.progress) * 100) + "%"
                        opacity: 0.72
                    }
                }

                PlasmaComponents.Label {
                    visible: Boolean(activityDetails.modelData.artist)
                    text: activityDetails.modelData.artist || ""
                    opacity: 0.72
                }
                PlasmaComponents.Label {
                    visible: activityDetails.modelData.evidence === "filesystem"
                    text: qsTr("Incoming file · completion unknown")
                    opacity: 0.72
                }

                RowLayout {
                    spacing: 4
                    Repeater {
                        model: [
                            {name: "previous", label: qsTr("Previous")},
                            {name: "play", label: qsTr("Play")},
                            {name: "pause", label: qsTr("Pause")},
                            {name: "next", label: qsTr("Next")},
                            {name: "suspend", label: qsTr("Pause transfer")},
                            {name: "resume", label: qsTr("Resume")},
                            {name: "cancel", label: qsTr("Cancel")},
                            {name: "seek", label: qsTr("Seek")},
                            {name: "showInFiles", label: qsTr("Show in Files")}
                        ]
                        delegate: PlasmaComponents.Button {
                            required property var modelData
                            objectName: "ambient-detail-" + modelData.name
                            visible: details.actionAvailable(activityDetails.modelData, modelData.name)
                            text: modelData.label
                            Accessible.name: text
                            onClicked: details.invoke(activityDetails.modelData, modelData.name)
                        }
                    }
                }
            }
        }
    }
}
