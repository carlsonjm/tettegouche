/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// Before anything is typed, under the field: the applications and
// the files used lately, each in a labelled section of its own,
// eight of each, and none pinned, open or hidden. Each section has
// its setting, and what is on sets how tall Search rests: the
// field alone, one section, or both filling the sheet.
Item {
    id: firstRow
    objectName: "first-row"
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item modeRow
    required property Item searchField
    required property Item sheet

    // Under the finger a piece lifts, as an object would: a little larger, a
    // step lighter, with a soft shadow beneath it.
    component LiftShadow: Item {
        id: shadow
        property bool lifted: false
        property real cornerRadius: launcher.paperRadius
        anchors.fill: parent
        z: -1
        opacity: lifted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
        Repeater {
            model: [{ grow: 6, drop: 7, alpha: 0.10 }, { grow: 3, drop: 4, alpha: 0.16 }, { grow: 1, drop: 2, alpha: 0.22 }]
            Rectangle {
                required property var modelData
                x: -modelData.grow
                y: -modelData.grow + modelData.drop
                width: shadow.width + 2 * modelData.grow
                height: shadow.height + 2 * modelData.grow
                radius: shadow.cornerRadius + modelData.grow
                // A shadow is dark on any ground.
                color: Qt.rgba(0, 0, 0, modelData.alpha)
            }
        }
    }

    // An application used lately: its icon, large, and its whole name on up
    // to two lines.
    component RecentApp: Item {
        id: tile
        required property int index
        required property var model
        readonly property bool mine: tile.model.kind === "application"
        objectName: mine ? "recent-" + index : ""
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: tile.model.name
        Keys.onReturnPressed: launcher.runRecent(tile.index, tile.model.name)
        Keys.onEnterPressed: launcher.runRecent(tile.index, tile.model.name)
        Keys.onSpacePressed: launcher.runRecent(tile.index, tile.model.name)
        Rectangle {
            id: tileFace
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: launcher.paperRadius
            color: tileTap.pressed ? tone.tilePressed : tileHover.hovered ? tone.tileHover : "transparent"
            scale: tileTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
            LiftShadow { lifted: tileTap.pressed }
            Kirigami.Icon {
                x: (parent.width - 56) / 2
                y: 12
                width: 56
                height: 56
                source: tile.model.icon
            }
            Text {
                x: 6
                y: 12 + 56 + 8
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
                text: tile.model.name
                color: launcher.primaryText
                font.pixelSize: 13
            }
        }
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
            onTapped: launcher.runRecent(tile.index, tile.model.name)
        }
    }

    // A file used lately, as a card of paper: its picture, or its kind's icon
    // where it has none, its name, and the folder it is in with when.
    component RecentFile: Item {
        id: card
        required property int index
        required property var model
        readonly property bool mine: card.model.kind === "file"
        readonly property bool pictured: (card.model.thumbnail || "").length > 0
        objectName: mine ? "recent-" + index : ""
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: card.model.name
        Keys.onReturnPressed: launcher.runRecent(card.index, card.model.name)
        Keys.onEnterPressed: launcher.runRecent(card.index, card.model.name)
        Keys.onSpacePressed: launcher.runRecent(card.index, card.model.name)
        Rectangle {
            id: cardFace
            anchors.fill: parent
            radius: launcher.paperRadius
            color: cardTap.pressed ? tone.tilePressed : cardHover.hovered ? tone.tileHover : tone.subtle
            scale: cardTap.pressed ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
            LiftShadow { lifted: cardTap.pressed }
            Rectangle {
                id: preview
                x: 8
                y: 8
                width: parent.width - 16
                height: Math.max(24, parent.height - 8 - 50)
                radius: 6
                color: tone.subtle
                clip: true
                Image {
                    anchors.fill: parent
                    visible: card.pictured
                    source: card.pictured ? card.model.thumbnail : ""
                    sourceSize: Qt.size(Math.ceil(preview.width * 2), Math.ceil(preview.height * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: !card.pictured
                    width: Math.min(48, preview.height - 16)
                    height: width
                    source: card.model.icon
                }
            }
            Text {
                id: cardName
                x: 12
                y: preview.y + preview.height + 8
                width: parent.width - 24
                elide: Text.ElideMiddle
                text: card.model.name
                color: launcher.primaryText
                font.pixelSize: 15
            }
            Text {
                x: 12
                y: cardName.y + cardName.height + 2
                width: parent.width - 24
                elide: Text.ElideRight
                text: launcher.usedWhere(card.model.where || "", card.model.when)
                color: launcher.secondaryText
                font.pixelSize: 12
            }
        }
        Rectangle {
            anchors.fill: cardFace
            anchors.margins: -2
            radius: launcher.paperRadius + 2
            color: "transparent"
            border.width: 1.5
            border.color: tone.focusRing
            visible: card.activeFocus
        }
        HoverHandler {
            id: cardHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: cardTap
            enabled: !launcher.guestDragged && !launcher.applicationLaunchPending
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: launcher.runRecent(card.index, card.model.name)
        }
    }

    // A section's heading on the first screen, and See all at its end, which
    // opens the mode that holds everything of its kind.
    component SectionHead: Item {
        id: head
        property string title
        property string prefix
        property bool seeAllShown: true
        signal seeAll()
        height: 40
        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: launcher.secondaryText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Item {
            objectName: head.prefix + "-see-all"
            anchors.right: parent.right
            width: seeAllRow.implicitWidth + 24
            height: 40
            visible: head.seeAllShown
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: words.i18nc("opens everything of a recent section's kind", "See all %1", head.title)
            Accessible.onPressAction: head.seeAll()
            Keys.onReturnPressed: head.seeAll()
            Keys.onEnterPressed: head.seeAll()
            Keys.onSpacePressed: head.seeAll()
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 32
                radius: height / 2
                color: seeAllTap.pressed ? tone.doorPressed : seeAllHover.hovered ? tone.doorHover : "transparent"
                border.width: parent.activeFocus ? 1.5 : 0
                border.color: tone.focusRing
                Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
            }
            Row {
                id: seeAllRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: words.i18n("See all")
                    color: launcher.secondaryText
                    font.pixelSize: 13
                }
                SuiteIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "chevron-right"
                    width: 14
                    height: 14
                    opacity: 0.66
                }
            }
            HoverHandler {
                id: seeAllHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: seeAllTap
                enabled: !launcher.guestDragged
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: head.seeAll()
            }
        }
    }

    readonly property bool appsShown: launcher.recentApps && !!launcher.recentUse
    readonly property bool filesShown: launcher.recentFiles && !!launcher.recentUse
    readonly property int sections: (appsShown ? 1 : 0) + (filesShown ? 1 : 0)
    // The Visual sheet's steps: a section apart by the surface's
    // 24, cards by the standard 12.
    readonly property real gap: 24
    readonly property real headHeight: 40
    readonly property real appHeight: 116
    readonly property real cardGap: 12
    // The files' cards, two rows of them, when the files rest
    // alone; with the applications above, they share what is left.
    readonly property real cardHeight: 150
    readonly property int offered: launcher.recentUse ? launcher.recentUse.count : 0
    readonly property int appsOffered: launcher.recentUse
        ? Math.max(0, Math.min(offered, launcher.recentUse.applicationCount || 0)) : 0
    readonly property int filesOffered: offered - appsOffered
    // Eight applications where they fit at 72 each, fewer on a
    // narrow sheet; four columns of files, at least two.
    readonly property int appColumns: Math.max(1, Math.min(8, Math.floor(width / 72)))
    readonly property real appWidth: width / appColumns
    readonly property int fileColumns: Math.max(2, Math.min(4, Math.floor((width + cardGap) / (136 + cardGap))))
    readonly property real fileWidth: (width - cardGap * (fileColumns - 1)) / fileColumns
    readonly property real appsReach: appsShown ? headHeight + appHeight : 0
    // How tall its sections are at rest, which sizes the sheet.
    readonly property real naturalHeight: (appsShown ? appsReach : 0)
        + (sections === 2 ? gap : 0)
        + (filesShown ? headHeight + 2 * cardHeight + cardGap : 0)
    readonly property real filesY: appsShown ? appsReach + gap : 0
    readonly property real filesRoom: Math.max(0, height - filesY - headHeight)
    readonly property int fileRows: filesRoom >= 2 * 96 + cardGap ? 2 : filesRoom >= 96 ? 1 : 0
    readonly property real fileHeight: fileRows > 0
        ? Math.min(176, (filesRoom - cardGap * (fileRows - 1)) / fileRows) : 0
    readonly property real reach: gap + height
    readonly property bool fits: sections > 0
    // The row arrives as one group. Typing sends it away, sinking
    // a little, and clearing the field brings it back the same way
    // it first came.
    readonly property int doors: 0
    readonly property int step: 260
    readonly property int stagger: 45
    readonly property int span: step + doors * stagger
    // 1 while the first screen rests under the field.
    property real rest: 1
    // How far the arrival has come, across every piece.
    property real arrival: 1
    function reveal(order) {
        if (launcher.reducedMotion) return arrival
        const t = Math.max(0, Math.min(1, (arrival * span - order * stagger) / step))
        return 1 - Math.pow(1 - t, 3)
    }
    function arrive(delay, again) {
        leaving.stop()
        // Caught on its way out, it comes straight back.
        if (!again && rest > 0 && arrival >= 1) {
            returning.restart()
            return
        }
        arriving.stop()
        returning.stop()
        arrival = 0
        rest = 1
        arriving.delay = Math.max(1, delay)
        arriving.start()
    }
    function leave() {
        arriving.stop()
        returning.stop()
        leaving.restart()
    }
    SequentialAnimation {
        id: arriving
        property int delay: 1
        PauseAnimation { duration: arriving.delay }
        NumberAnimation {
            target: firstRow
            property: "arrival"
            to: 1
            duration: launcher.reducedMotion ? 120 : firstRow.span
        }
    }
    NumberAnimation {
        id: returning
        target: firstRow
        property: "rest"
        to: 1
        duration: launcher.own(140)
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: leaving
        target: firstRow
        property: "rest"
        to: 0
        duration: launcher.reducedMotion ? 90 : 150
        easing.type: Easing.InCubic
    }
    // Typing ahead, what was used lately holds still, faded back, until the
    // list takes its place.
    readonly property bool resting: searchField.idle || launcher.typingAhead
    onRestingChanged: resting ? arrive(1) : leave()
    x: 0
    y: searchField.y + searchField.height + gap
    width: parent.width
    height: Math.max(0, parent.height - y)
    opacity: fits && !launcher.applicationLaunchPending
        ? rest * (launcher.typingAhead ? 0.66 : 1) * Math.max(0, 1 - launcher.drawerProgress * 3)
            * Math.max(0, 1 - launcher.modeProgress * 3) : 0
    visible: opacity > 0
    enabled: resting && opacity > 0.5 && !launcher.drawerOpen && !launcher.modeOpen
    transform: Translate { y: launcher.reducedMotion ? 0 : (1 - firstRow.rest) * 6 }

    SectionHead {
        id: appsHead
        objectName: "recent-apps"
        visible: firstRow.appsShown
        width: parent.width
        title: words.i18n("Recent apps")
        prefix: "recent-apps"
        opacity: firstRow.reveal(firstRow.doors)
        onSeeAll: modeRow.show("apps")
    }
    Text {
        objectName: "recent-apps-empty"
        x: 12
        y: firstRow.headHeight + (firstRow.appHeight - height) / 2
        visible: firstRow.appsShown && firstRow.appsOffered === 0
        text: words.i18n("The apps you open show up here.")
        color: launcher.secondaryText
        font.pixelSize: 13
    }
    Repeater {
        model: firstRow.appsShown ? launcher.recentUse : null
        delegate: RecentApp {
            id: recentApp
            readonly property real reveal: firstRow.reveal(firstRow.doors)
            x: index * firstRow.appWidth
            y: firstRow.headHeight
            width: firstRow.appWidth
            height: firstRow.appHeight
            visible: mine && index < Math.min(firstRow.appColumns, firstRow.appsOffered)
            opacity: reveal
            transform: Translate { y: launcher.reducedMotion ? 0 : (1 - recentApp.reveal) * 10 }
        }
    }
    SectionHead {
        id: filesHead
        objectName: "recent-files"
        visible: firstRow.filesShown && firstRow.fileRows > 0
        y: firstRow.filesY
        width: parent.width
        title: words.i18n("Recent files")
        prefix: "recent-files"
        seeAllShown: launcher.fileBrowser !== null
        opacity: firstRow.reveal(firstRow.doors)
        onSeeAll: modeRow.show("files")
    }
    Text {
        objectName: "recent-files-empty"
        x: 12
        y: firstRow.filesY + firstRow.headHeight + 12
        visible: filesHead.visible && firstRow.filesOffered === 0
        text: words.i18n("The files you open show up here.")
        color: launcher.secondaryText
        font.pixelSize: 13
    }
    Repeater {
        model: firstRow.filesShown ? launcher.recentUse : null
        delegate: RecentFile {
            id: recentFile
            readonly property int place: index - firstRow.appsOffered
            readonly property real reveal: firstRow.reveal(firstRow.doors)
            x: (place % firstRow.fileColumns) * (firstRow.fileWidth + firstRow.cardGap)
            y: firstRow.filesY + firstRow.headHeight
                + Math.floor(place / firstRow.fileColumns) * (firstRow.fileHeight + firstRow.cardGap)
            width: firstRow.fileWidth
            height: firstRow.fileHeight
            visible: mine && place >= 0 && place < firstRow.fileColumns * firstRow.fileRows
            opacity: reveal
            transform: Translate { y: launcher.reducedMotion ? 0 : (1 - recentFile.reveal) * 10 }
        }
    }
}
