/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n

pragma ComponentBehavior: Bound

// Under the field while the Helpers chip is shown and nothing is typed:
// the upkeep cards Split Rock's Core lists, as tiles in Core's own order, so
// nobody has to remember a Helper's name to find it. The first row holds what
// fits at full size; the rest, those Core marks for it and Layouts among
// them, wait behind More, which adds rows of the same tiles under the first,
// as many as they take. A tap opens that Helper on its own, as Enter on its
// row in Search does.
Item {
    id: helpersRow
    objectName: "helpers-row"
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item searchField

    readonly property var helpers: launcher.helpers
    // The Visual sheet's steps: the label 24 over the tiles, 20 under the
    // field; the tiles 96 by 88 and 12 apart, in rows 12 apart.
    readonly property real gap: 20
    readonly property real labelHeight: 24
    readonly property real tileGap: 12
    readonly property real tileHeight: 88
    readonly property real tileWidth: 96
    // Whole tiles a row holds at this width.
    readonly property int perRow: Math.max(2, Math.floor((width + tileGap) / (tileWidth + tileGap)))
    // The first row, and what waits behind More: those Core marks for it,
    // and any the first row has no room for, More taking the last place.
    readonly property var split: {
        const first = helpers.filter(h => !h.more)
        const rest = helpers.filter(h => !!h.more)
        if (rest.length === 0 && first.length <= perRow) return {first: first, rest: []}
        const room = perRow - 1
        return {first: first.slice(0, room), rest: first.slice(room).concat(rest)}
    }
    readonly property var firstRow: split.first
    readonly property var behindMore: split.rest
    property bool expanded: false
    readonly property int moreRows: expanded ? Math.ceil(behindMore.length / perRow) : 0
    // How tall it is, which sizes the sheet at rest.
    readonly property real naturalHeight: labelHeight + tileHeight + moreRows * (tileGap + tileHeight)

    // Lucide's glyph for each Helper, all drawn alike; one Core lists that
    // has none of its own takes the wrench.
    readonly property var glyphs: ({
        "appstore": "shopping-bag",
        "install": "download",
        "apps": "layout-grid",
        "update": "refresh-cw",
        "space": "hard-drive",
        "health": "heart-pulse",
        "changes": "undo-2",
        "tidy": "folder-down",
        "restore": "history",
        "community": "users",
        "layouts": "panels-top-left"
    })
    function glyphFor(id) {
        return glyphs[id] || "wrench"
    }

    x: 0
    y: searchField.y + searchField.height + gap
    width: parent.width
    height: naturalHeight
    opacity: launcher.helpersShown && launcher.query.text.length === 0
        && !launcher.drawerOpen && !launcher.modeOpen && !launcher.applicationLaunchPending ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
    visible: opacity > 0
    enabled: opacity > 0.5

    // Each time the Helpers show, More starts closed.
    Connections {
        target: helpersRow.launcher
        function onHelpersShownChanged() {
            if (!helpersRow.launcher.helpersShown) helpersRow.expanded = false
        }
    }
    onBehindMoreChanged: if (behindMore.length === 0) expanded = false

    // One tile: a Helper, or More itself.
    component Tile: Item {
        id: tile
        // The row, whose sizes, colors and launcher the tile takes.
        required property var host
        property string tileId
        property string title
        property string sub
        property string glyph
        property bool selected: false
        signal activated()
        objectName: "helper-" + tileId
        width: tile.host.tileWidth
        height: tile.host.tileHeight
        activeFocusOnTab: tile.host.visible && tile.visible
        Accessible.role: Accessible.Button
        Accessible.name: tile.title
        Accessible.description: tile.sub
        Accessible.onPressAction: tile.activated()
        Keys.onReturnPressed: tile.activated()
        Keys.onEnterPressed: tile.activated()
        Keys.onSpacePressed: tile.activated()
        Rectangle {
            id: tileFace
            anchors.fill: parent
            radius: tile.host.launcher.paperRadius
            color: tileTap.pressed ? tile.host.tone.tilePressed : tile.selected ? tile.host.tone.current
                : tileHover.hovered ? tile.host.tone.tileHover : tile.host.tone.subtle
            scale: tileTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: tile.host.launcher.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: tile.host.launcher.ms(120) } }
            SuiteIcon {
                objectName: tile.objectName + "-glyph"
                x: (parent.width - 24) / 2
                y: 16
                width: 24
                height: 24
                glyph: tile.glyph
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
                text: tile.title
                color: tile.host.launcher.primaryText
                font.pixelSize: 12
            }
        }
        // Keyboard focus alone gets an outline.
        Rectangle {
            anchors.fill: tileFace
            anchors.margins: -2
            radius: tile.host.launcher.paperRadius + 2
            color: "transparent"
            border.width: 1.5
            border.color: tile.host.tone.focusRing
            visible: tile.activeFocus
        }
        HoverHandler {
            id: tileHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: tileTap
            enabled: !tile.host.launcher.guestDragged && !tile.host.launcher.applicationLaunchPending
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: tile.activated()
        }
    }

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
        objectName: "helpers-first-row"
        y: helpersRow.labelHeight
        spacing: helpersRow.tileGap
        Repeater {
            model: helpersRow.firstRow
            Tile {
                required property var modelData
                host: helpersRow
                tileId: modelData.id
                title: modelData.title
                sub: modelData.sub || ""
                glyph: helpersRow.glyphFor(modelData.id)
                onActivated: helpersRow.launcher.openHelper(modelData.id)
            }
        }
        Tile {
            host: helpersRow
            visible: helpersRow.behindMore.length > 0
            tileId: "more"
            title: helpersRow.expanded ? helpersRow.words.i18nc("@action:button shows fewer Helpers", "Less")
                : helpersRow.words.i18nc("@action:button shows the other Helpers", "More")
            sub: ""
            glyph: helpersRow.expanded ? "chevron-up" : "chevron-down"
            selected: helpersRow.expanded
            Accessible.role: Accessible.Button
            Accessible.description: helpersRow.expanded ? "" : helpersRow.behindMore.map(h => h.title).join(", ")
            onActivated: helpersRow.expanded = !helpersRow.expanded
        }
    }

    // Behind More: rows of the same tiles, left-packed, as many as they take.
    Flow {
        objectName: "helpers-more-rows"
        y: helpersRow.labelHeight + helpersRow.tileHeight + helpersRow.tileGap
        width: parent.width
        spacing: helpersRow.tileGap
        visible: helpersRow.expanded
        Repeater {
            model: helpersRow.expanded ? helpersRow.behindMore : []
            Tile {
                required property var modelData
                host: helpersRow
                tileId: modelData.id
                title: modelData.title
                sub: modelData.sub || ""
                glyph: helpersRow.glyphFor(modelData.id)
                onActivated: helpersRow.launcher.openHelper(modelData.id)
            }
        }
    }
}
