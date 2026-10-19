/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// Under the field while the Helpers chip is shown and nothing is typed:
// every upkeep card Split Rock's Core lists, as one row of tiles in Core's
// own order, so nobody has to remember a Helper's name to find it. A tap
// opens that Helper on its own, as Enter on its row in Search does.
Item {
    id: helpersRow
    objectName: "helpers-row"
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item searchField

    readonly property var helpers: launcher.helpers
    // The Visual sheet's steps: the label 24 over the tiles, 20 under the
    // field; the tiles 96 by 88 and 12 apart, narrower only when more than
    // fit the sheet in one row.
    readonly property real gap: 20
    readonly property real labelHeight: 24
    readonly property real tileGap: 12
    readonly property real tileHeight: 88
    readonly property real tileWidth: helpers.length > 0
        ? Math.min(96, Math.floor((width - tileGap * (helpers.length - 1)) / helpers.length)) : 96
    // How tall it is, which sizes the sheet at rest.
    readonly property real naturalHeight: labelHeight + tileHeight

    x: 0
    y: searchField.y + searchField.height + gap
    width: parent.width
    height: naturalHeight
    opacity: launcher.helpersShown && launcher.query.text.length === 0
        && !launcher.drawerOpen && !launcher.modeOpen && !launcher.applicationLaunchPending ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
    visible: opacity > 0
    enabled: opacity > 0.5

    Text {
        objectName: "helpers-label"
        x: 12
        height: helpersRow.labelHeight
        verticalAlignment: Text.AlignTop
        text: words.i18n("Helpers")
        color: launcher.secondaryText
        font.pixelSize: 12
    }

    Row {
        y: helpersRow.labelHeight
        spacing: helpersRow.tileGap
        Repeater {
            model: helpersRow.helpers
            Item {
                id: tile
                required property int index
                required property var modelData
                objectName: "helper-" + modelData.id
                width: helpersRow.tileWidth
                height: helpersRow.tileHeight
                activeFocusOnTab: helpersRow.visible
                Accessible.role: Accessible.Button
                Accessible.name: tile.modelData.title
                Accessible.description: tile.modelData.sub || ""
                Accessible.onPressAction: launcher.openHelper(tile.modelData.id)
                Keys.onReturnPressed: launcher.openHelper(tile.modelData.id)
                Keys.onEnterPressed: launcher.openHelper(tile.modelData.id)
                Keys.onSpacePressed: launcher.openHelper(tile.modelData.id)
                Rectangle {
                    id: tileFace
                    anchors.fill: parent
                    radius: launcher.paperRadius
                    color: tileTap.pressed ? tone.tilePressed : tileHover.hovered ? tone.tileHover : tone.subtle
                    scale: tileTap.pressed ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
                    Kirigami.Icon {
                        x: (parent.width - 24) / 2
                        y: 16
                        width: 24
                        height: 24
                        source: tile.modelData.icon || "preferences-system"
                    }
                    Text {
                        x: 4
                        y: 16 + 24 + 8
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 14
                        lineHeightMode: Text.FixedHeight
                        text: tile.modelData.title
                        color: launcher.primaryText
                        font.pixelSize: 12
                    }
                }
                // Keyboard focus alone gets an outline.
                Rectangle {
                    anchors.fill: tileFace
                    anchors.margins: -2
                    radius: launcher.paperRadius + 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: tone.focusRing
                    visible: tile.activeFocus
                }
                HoverHandler {
                    id: tileHover
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: tileTap
                    enabled: !launcher.guestDragged && !launcher.applicationLaunchPending
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: launcher.openHelper(tile.modelData.id)
                }
            }
        }
    }
}
