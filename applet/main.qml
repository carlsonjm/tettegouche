/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.icon: "studio.warbler.tettegouche"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    activationTogglesExpanded: false
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool animateIndicator: Plasmoid.configuration.animateIndicator !== false

    // This launcher has one panel surface and opens a separate application.
    // As in Temperance, render direct contents and size the root itself.
    // A compactRepresentation alone is never instantiated by Plasma.
    implicitWidth: vertical ? 42 : 26
    implicitHeight: vertical ? 26 : 42
    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    toolTipMainText: i18n("Tettegouche")
    toolTipSubText: Plasmoid.launcherActive
        ? i18n("Launcher is open")
        : i18n("Find an application")

    Item {
        id: launcherButton
        objectName: "tettegouche-launcher-button"
        anchors.fill: parent
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
