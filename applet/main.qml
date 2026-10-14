/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)); }

    Plasmoid.icon: "co.goodinput.tettegouche-logo"
    Plasmoid.status: Plasmoid.launcherActive
        ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    activationTogglesExpanded: false
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool animateIndicator: Plasmoid.configuration.animateIndicator !== false
    // The launcher is a touch square at the panel's start with its dot centred
    // in it. A filled disc weighs more than an outlined status icon, so the dot
    // is a little smaller than one.
    readonly property int endpointWidth: 44
    // With Ambient off the widget is the launcher's dot alone.
    readonly property bool showAmbient: Plasmoid.configuration.showAmbient !== false
    readonly property int ambientCoreWidth: showAmbient ? ambient.minimumUsefulWidth : 0
    property int responsiveMeasuredWidth: endpointWidth
    // Plasma's own word for a panel drawn black, which Shuffle's band gives
    // while a card is up; the island turns black with it.
    readonly property bool bandOpaque: (Plasmoid.containmentDisplayHints
        & PlasmaCore.Types.ContainmentPrefersOpaqueBackground) !== 0
    property var island: null
    AmbientColors {
        id: tone
        theme: root.Kirigami.Theme
    }

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

    toolTipMainText: Plasmoid.productName
    toolTipSubText: Plasmoid.launcherActive
        ? i18n("Launcher is open")
        : i18n("Find an application")

    function refreshResponsiveWidth() {
        if (vertical || !showAmbient) {
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
    onShowAmbientChanged: {
        if (!showAmbient && island) island.dismiss();
        Qt.callLater(refreshResponsiveWidth);
    }
    Component.onCompleted: Qt.callLater(refreshResponsiveWidth)

    Connections {
        target: Plasmoid
        function onPanelGeometryChanged() { Qt.callLater(root.refreshResponsiveWidth); }
    }

    AmbientSurface {
        id: ambient
        objectName: "tettegouche-ambient-surface"
        visible: root.showAmbient && !root.vertical && width > 0
        anchors.left: launcherButton.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // The doors take the band while a slide from the dot is on it.
        opacity: root.scrubbing ? 0 : 1
        Behavior on opacity {
            enabled: root.animateIndicator
            NumberAnimation { duration: root.ms(140); easing.type: Easing.OutCubic }
        }
        activities: Plasmoid.ambientActivities
        opaque: root.bandOpaque
        rises: Plasmoid.location !== PlasmaCore.Types.TopEdge
        monotonicClock: () => Plasmoid.monotonicNowUs()
        onInvokeRequested: (activityId, generation, action, value) =>
            Plasmoid.invokeActivity(activityId, generation, action, value)
        onOpenRequested: kind => root.openIsland(kind)
        onKindsChanged: if (root.island && kinds.length === 0) root.island.dismiss()
    }

    // A slide from the dot: press it and move right, and Search's doors,
    // Apps, Files, Notes and Ask, line up in the band; the one under the
    // finger or pointer is chosen and opens when it lets go. Held still,
    // the doors come up as well, to look before choosing. Let go back on the
    // dot opens nothing. A panel down a side of the screen keeps the tap.
    readonly property bool canScrub: !vertical
    property bool scrubbing: false
    property string scrubChoice: ""
    readonly property int holdMs: 300

    function beginScrub() {
        if (scrubbing || !canScrub) return;
        if (island) island.dismiss();
        scrubChoice = "";
        scrubbing = true;
    }
    function endScrub() {
        scrubbing = false;
        scrubChoice = "";
    }
    // The door at a point on the dot's own item: none over the dot itself,
    // otherwise the one nearest, so the gaps between doors and the space past
    // the last keep a choice.
    function doorAt(x) {
        const local = pearlDoors.mapFromItem(launcherButton, x, 0).x;
        if (x < launcherButton.width) return "";
        let chosen = "";
        let distance = Infinity;
        for (let i = 0; i < pearlDoorsRepeater.count; ++i) {
            const door = pearlDoorsRepeater.itemAt(i);
            if (!door) continue;
            const away = local < door.x ? door.x - local
                : local > door.x + door.width ? local - door.x - door.width : 0;
            if (away < distance) {
                distance = away;
                chosen = door.door;
            }
        }
        return chosen;
    }

    Row {
        id: pearlDoors
        objectName: "tettegouche-pearl-doors"
        anchors.left: launcherButton.right
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        visible: opacity > 0
        opacity: root.scrubbing ? 1 : 0
        Behavior on opacity {
            enabled: root.animateIndicator
            NumberAnimation { duration: root.ms(140); easing.type: Easing.OutCubic }
        }
        Repeater {
            id: pearlDoorsRepeater
            model: Plasmoid.pearlDoors
            delegate: Item {
                id: doorItem
                required property string modelData
                required property int index
                readonly property string door: modelData
                readonly property bool chosen: root.scrubChoice === door
                objectName: "tettegouche-pearl-door-" + door
                width: doorFace.implicitWidth + 24
                height: 30
                Accessible.role: Accessible.Button
                Accessible.name: doorLabel.text
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: doorItem.chosen ? tone.text : tone.over(root.bandOpaque ? 0.2 : 0.16)
                    scale: doorItem.chosen ? 1.06 : 1
                    // Each door arrives a moment after the one before it.
                    opacity: root.scrubbing ? 1 : 0
                    Behavior on scale {
                        enabled: root.animateIndicator
                        NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        enabled: root.animateIndicator
                        SequentialAnimation {
                            PauseAnimation { duration: root.scrubbing ? root.ms(30) * doorItem.index : 0 }
                            NumberAnimation { duration: root.ms(120); easing.type: Easing.OutCubic }
                        }
                    }
                    Row {
                        id: doorFace
                        anchors.centerIn: parent
                        spacing: 6
                        // Apps: four squares, as on Search's own pill.
                        Grid {
                            visible: doorItem.door === "apps"
                            anchors.verticalCenter: parent.verticalCenter
                            columns: 2
                            spacing: 2
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 1
                                    color: doorItem.chosen ? tone.textOnInk : tone.text
                                }
                            }
                        }
                        SuiteIcon {
                            visible: doorItem.door !== "apps"
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: doorItem.door === "notes" ? "notes" : "folder-open"
                            ink: doorItem.chosen ? tone.textOnInk : tone.text
                            width: 15
                            height: 15
                        }
                        Text {
                            id: doorLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: doorItem.door === "apps" ? i18n("Apps")
                                : doorItem.door === "files" ? i18n("Files")
                                : doorItem.door === "notes" ? i18n("Notes") : i18n("Ask")
                            color: doorItem.chosen ? tone.textOnInk : tone.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
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
        const from = ambient.islandFor(kind);
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
        Accessible.name: i18nc("@action:button %1 is the widget's name", "Open %1", Plasmoid.productName)
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
            border.color: tone.text
            border.width: 1
            scale: Plasmoid.launcherActive ? 1 : launcherDimple.width / width
            opacity: Plasmoid.launcherActive ? 0.85 : 0

            // Ripple outward once, then remain as the open-launcher indicator.
            Behavior on scale {
                enabled: root.animateIndicator
                NumberAnimation { duration: root.ms(360); easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                enabled: root.animateIndicator
                NumberAnimation { duration: root.ms(180); easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            id: launcherDimple
            objectName: "tettegouche-launcher-dimple"
            anchors.centerIn: parent
            width: 20
            height: 20
            radius: width / 2
            // Pearl: lit from above and a shade deeper toward its lower edge,
            // so it reads as a piece that rises rather than a flat disc.
            // The Tette Dot is the same Ghost White pearl on every Plasma style.
            gradient: Gradient {
                GradientStop { position: 0; color: "#FFFFFF" }
                GradientStop { position: 0.55; color: "#F4F4FA" }
                GradientStop { position: 1; color: "#DCDCE4" }
            }
            scale: launcherHover.hovered ? 1.06 : 1

            Behavior on scale {
                enabled: root.animateIndicator
                NumberAnimation { duration: root.ms(140); easing.type: Easing.OutCubic }
            }
        }

        HoverHandler { id: launcherHover }
        // A tap opens Search; a slide or a hold brings the doors (above).
        // The press stays the dot's until it lets go, wherever it travels.
        MouseArea {
            id: pearlPress
            objectName: "tettegouche-launcher-press"
            anchors.fill: parent
            preventStealing: true
            property real pressX: 0
            onPressed: mouse => {
                pressX = mouse.x;
                root.endScrub();
                if (!root.canScrub) return;
                Plasmoid.refreshPearlDoors();
                pearlHold.restart();
            }
            onPositionChanged: mouse => {
                if (!root.canScrub) return;
                if (!root.scrubbing && mouse.x - pressX > Qt.styleHints.startDragDistance) {
                    pearlHold.stop();
                    root.beginScrub();
                }
                if (root.scrubbing) root.scrubChoice = root.doorAt(mouse.x);
            }
            onReleased: mouse => {
                pearlHold.stop();
                if (root.scrubbing) {
                    const chosen = root.scrubChoice;
                    root.endScrub();
                    if (chosen) Plasmoid.openDrawer(chosen);
                    return;
                }
                if (mouse.x >= 0 && mouse.x <= width && mouse.y >= 0 && mouse.y <= height)
                    Plasmoid.launch(Plasmoid.configuration.useKadunce);
            }
            onCanceled: {
                pearlHold.stop();
                root.endScrub();
            }
            Timer {
                id: pearlHold
                interval: root.holdMs
                onTriggered: root.beginScrub()
            }
        }
    }
}
