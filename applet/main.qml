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
    // The launcher is a touch square at the panel's start with its dot centred
    // in it. The dot is the size of a panel's status icons, and starts 10 px
    // from the square's edge.
    readonly property int endpointWidth: 44
    readonly property int ambientCoreWidth: ambient.minimumUsefulWidth
    property int responsiveMeasuredWidth: endpointWidth
    // Plasma's own word for a panel drawn black, which Shuffle's band gives
    // while a card is up; the island turns black with it.
    readonly property bool bandOpaque: (Plasmoid.containmentDisplayHints
        & PlasmaCore.Types.ContainmentPrefersOpaqueBackground) !== 0
    property var island: null

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
        opaque: root.bandOpaque
        monotonicClock: () => Plasmoid.monotonicNowUs()
        onInvokeRequested: (activityId, generation, action, value) =>
            Plasmoid.invokeActivity(activityId, generation, action, value)
        onOpenRequested: kind => root.openIsland(kind)
        onKindsChanged: if (root.island && kinds.length === 0) root.island.dismiss()
    }

    // The island opens on a surface of its own over the whole display, grown
    // from where it sits in the band; the band's own island steps aside
    // until it closes.
    Component {
        id: islandComponent
        AmbientIsland {}
    }

    function openIsland(kind) {
        if (island) {
            island.kind = kind;
            return;
        }
        const from = kind === ambient.mainKind ? ambient.islandItem : ambient.bubbleItem;
        const side = Plasmoid.screenRect(ambient);
        const opened = islandComponent.createObject(null, {
            surface: ambient,
            kind: kind,
            start: Plasmoid.screenRect(from),
            sideLeft: side.x,
            sideRight: side.x + side.width,
        });
        if (!opened) return;
        // Held from the start, so a surface that fails to open is closed
        // rather than left for the collector.
        island = opened;
        opened.closed.connect(() => {
            ambient.opened = false;
            ambient.chosenPlayer = "";
            if (root.island === opened) root.island = null;
            opened.destroy();
        });
        opened.frameSwapped.connect(function stepAside() {
            opened.frameSwapped.disconnect(stepAside);
            if (root.island === opened) ambient.opened = true;
        });
        if (!Plasmoid.prepareIslandSurface(opened, ambient)) {
            island = null;
            opened.destroy();
            return;
        }
        opened.show();
        opened.requestActivate();
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
            width: 36
            height: width
            radius: width / 2
            color: "transparent"
            border.color: "#F8F8FF"
            border.width: 1
            scale: Plasmoid.launcherActive ? 1 : launcherDimple.width / width
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
            id: launcherDimple
            objectName: "tettegouche-launcher-dimple"
            anchors.centerIn: parent
            width: 24
            height: 24
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
