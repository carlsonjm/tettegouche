/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

FocusScope {
    id: details

    property var activity: null
    property double monotonicNowUs: 0
    signal closeRequested()
    signal invokeRequested(string activityId, int generation, string action)

    readonly property int surfaceWidth: 360
    readonly property int surfaceHeight: Math.max(132, content.implicitHeight + 32)
    implicitWidth: surfaceWidth
    implicitHeight: surfaceHeight
    Layout.minimumWidth: surfaceWidth
    Layout.preferredWidth: surfaceWidth
    Layout.maximumWidth: surfaceWidth
    Layout.minimumHeight: surfaceHeight
    Layout.preferredHeight: surfaceHeight
    Layout.maximumHeight: surfaceHeight
    Accessible.name: qsTr("Ambient activity details")

    function capability(name) {
        return Boolean(activity && activity.capabilities && activity.capabilities[name]);
    }

    function actionAvailable(name) {
        if (!capability(name)) return false;
        if (name === "play") return activity.state !== "playing";
        if (name === "pause") return activity.state === "playing";
        if (name === "suspend") return activity.state === "running";
        if (name === "resume") return activity.state === "suspended";
        return true;
    }

    function invoke(action) {
        if (activity)
            invokeRequested(String(activity.id), Number(activity.generation), action);
    }

    Keys.onEscapePressed: closeRequested()

    Rectangle {
        anchors.fill: parent
        color: "#141414"
        radius: 18
        border.width: 1
        border.color: "#333333"
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Icon {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                source: details.activity && details.activity.icon
                    ? details.activity.icon
                    : details.activity && details.activity.kind === "media"
                        ? "audio-x-generic-symbolic" : "folder-download-symbolic"
            }
            Kirigami.Heading {
                level: 2
                text: details.activity
                    ? details.activity.title || details.activity.source
                        || (details.activity.kind === "media" ? qsTr("Media") : qsTr("Transfer"))
                    : ""
                elide: Text.ElideRight
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

        PlasmaComponents.Label {
            visible: details.activity && details.activity.kind === "transfer"
            text: !details.activity || details.activity.progress === undefined
                || details.activity.progress === null
                ? qsTr("Progress unknown")
                : qsTr("%1% complete").arg(Math.round(Number(details.activity.progress) * 100))
            opacity: 0.72
        }
        PlasmaComponents.Label {
            visible: details.activity && Boolean(details.activity.artist)
            text: details.activity ? details.activity.artist || "" : ""
            opacity: 0.72
        }
        PlasmaComponents.Label {
            visible: details.activity && details.activity.evidence === "filesystem"
            text: qsTr("Incoming file · completion unknown")
            opacity: 0.72
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 6
            Repeater {
                model: [
                    {name: "previous", label: qsTr("Previous")},
                    {name: "play", label: qsTr("Play")},
                    {name: "pause", label: qsTr("Pause")},
                    {name: "next", label: qsTr("Next")},
                    {name: "suspend", label: qsTr("Pause transfer")},
                    {name: "resume", label: qsTr("Resume")},
                    {name: "cancel", label: qsTr("Cancel")},
                    {name: "seek", label: qsTr("Forward 10 s")},
                    {name: "showInFiles", label: qsTr("Show in Files")}
                ]
                delegate: PlasmaComponents.Button {
                    required property var modelData
                    objectName: "ambient-detail-" + modelData.name
                    visible: details.actionAvailable(modelData.name)
                    text: modelData.label
                    Accessible.name: text
                    onClicked: details.invoke(modelData.name)
                }
            }
        }
    }
}
