/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.icon: "studio.warbler.tettegouche-logo"
    Plasmoid.status: Plasmoid.launcherActive
        ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    activationTogglesExpanded: false
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool animateIndicator: Plasmoid.configuration.animateIndicator !== false
    readonly property int endpointWidth: 42
    readonly property int ambientCoreWidth: ambient.minimumUsefulWidth
    property int responsiveMeasuredWidth: endpointWidth
    property var detailActivity: null
    property var detailAnchor: null
    property bool detailOpen: false

    Connections {
        target: Plasmoid
        function onInvocationRequested() {
            // Use Plasma's panel focus lifecycle, not minimization/show-desktop.
            // The launcher subsequently takes focus on its overlay surface.
            Plasmoid.status = PlasmaCore.Types.AcceptingInputStatus;
            launcherButton.forceActiveFocus(Qt.ShortcutFocusReason);
            if (root.Window.window) root.Window.window.requestActivate();
        }
        function onLauncherActiveChanged() {
            Plasmoid.status = Plasmoid.launcherActive
                ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.ActiveStatus;
        }
    }

    // This launcher has one panel surface and opens a separate application.
    // As in Temperance, render direct contents and size the root itself.
    // A compactRepresentation alone is never instantiated by Plasma.
    implicitWidth: vertical ? endpointWidth : responsiveMeasuredWidth
    implicitHeight: 42
    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.minimumWidth: vertical ? endpointWidth : endpointWidth + ambientCoreWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    toolTipMainText: i18n("Tettegouche")
    toolTipSubText: Plasmoid.launcherActive
        ? i18n("Launcher is open")
        : i18n("Find an application")

    function refreshResponsiveWidth() {
        if (vertical) {
            responsiveMeasuredWidth = endpointWidth;
            return;
        }
        Plasmoid.watchPanelGeometry(root);
        const minimum = endpointWidth + ambientCoreWidth;
        const measured = Plasmoid.availablePanelWidth(root, minimum, 6);
        if (Math.abs(measured - responsiveMeasuredWidth) > 1)
            responsiveMeasuredWidth = measured;
    }

    onVerticalChanged: Qt.callLater(refreshResponsiveWidth)
    onAmbientCoreWidthChanged: Qt.callLater(refreshResponsiveWidth)
    onVisibleChanged: Qt.callLater(refreshResponsiveWidth)
    Component.onCompleted: Qt.callLater(refreshResponsiveWidth)

    Connections {
        target: Plasmoid
        function onPanelGeometryChanged() { Qt.callLater(root.refreshResponsiveWidth); }
    }

    AmbientSurface {
        id: ambient
        objectName: "tettegouche-ambient-surface"
        visible: !root.vertical && width > 0
        anchors.left: launcherButton.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        activities: Plasmoid.ambientActivities
        monotonicClock: () => Plasmoid.monotonicNowUs()
        onInvokeRequested: (activityId, generation, action) =>
            Plasmoid.invokeActivity(activityId, generation, action)
        onDetailsRequested: (activity, anchorItem) => {
            root.detailActivity = activity;
            root.detailAnchor = anchorItem;
            root.detailOpen = true;
        }
    }

    PlasmaCore.Dialog {
        id: ambientDetailsDialog
        visualParent: root.detailAnchor || ambient
        location: Plasmoid.location
        type: PlasmaCore.Dialog.AppletPopup
        floating: 10
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: true
        visible: root.detailOpen && root.detailActivity !== null
        appletInterface: root
        onVisibleChanged: {
            if (!visible) root.detailOpen = false;
            else requestActivate();
        }
        mainItem: ActivityDetails {
            activity: root.detailActivity
            monotonicNowUs: ambient.clockNowUs
            onCloseRequested: root.detailOpen = false
            onInvokeRequested: (activityId, generation, action) =>
                Plasmoid.invokeActivity(activityId, generation, action)
        }
    }

    Item {
        id: launcherButton
        objectName: "tettegouche-launcher-button"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.endpointWidth
        activeFocusOnTab: true
        Accessible.name: i18n("Open Tettegouche")
        Accessible.role: Accessible.Button
        Accessible.onPressAction: Plasmoid.launch(Plasmoid.configuration.useKadunce)
        Keys.onReturnPressed: Plasmoid.launch(Plasmoid.configuration.useKadunce)
        Keys.onEnterPressed: Plasmoid.launch(Plasmoid.configuration.useKadunce)
        Keys.onSpacePressed: Plasmoid.launch(Plasmoid.configuration.useKadunce)

        Rectangle {
            objectName: "tettegouche-launcher-active-ring"
            anchors.centerIn: parent
            width: 24
            height: width
            radius: width / 2
            color: "transparent"
            border.color: "#F8F8FF"
            border.width: 1
            scale: Plasmoid.launcherActive ? 1 : 16 / 24
            opacity: Plasmoid.launcherActive ? 0.85 : 0

            // Ripple outward once, then remain as the open-launcher indicator.
            Behavior on scale {
                enabled: root.animateIndicator
                NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                enabled: root.animateIndicator
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            objectName: "tettegouche-launcher-dimple"
            anchors.centerIn: parent
            width: 16
            height: 16
            radius: width / 2
            color: "#F8F8FF"
            scale: launcherHover.hovered ? 1.06 : 1

            Behavior on scale {
                enabled: root.animateIndicator
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        HoverHandler { id: launcherHover }
        TapHandler { onTapped: Plasmoid.launch(Plasmoid.configuration.useKadunce) }
    }
}
