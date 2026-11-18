/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n

pragma ComponentBehavior: Bound

// People, under the field while its chip is shown: everyone the people
// provider knows, by name, or those the words typed find, each person once.
// A tap or Enter opens a person's page over the field: every number and
// address, each handed to the application that takes it, and the provider's
// question about a likely match. Search keeps no people and sends nothing.
Item {
    id: pane
    objectName: "people-pane"
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item searchField

    readonly property var client: launcher.peopleClient
    readonly property var people: client ? client.people : []
    readonly property var person: client ? client.person : ({})
    readonly property bool personOpen: !!client && client.personOpen
    // The Visual sheet's steps, as Search's results keep them: the label 24
    // over the rows, rows 56 tall and 4 apart, the 32 mark 12 from each edge.
    readonly property int labelHeight: 24
    readonly property int rowHeight: 56
    readonly property int rowGap: 4

    // Down and Up choose a person; Enter opens the one chosen, or the first.
    function move(direction) {
        if (personOpen || list.count === 0) return
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + direction))
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
    function submit() {
        if (personOpen || list.count === 0) return
        client.open(people[Math.max(0, list.currentIndex)].id)
    }
    // Leaves the page for the list; false when no page was open.
    function back() {
        if (!personOpen) return false
        client.close()
        return true
    }
    onPeopleChanged: list.currentIndex = launcher.query.text.length > 0 && people.length > 0 ? 0 : -1
    onPersonOpenChanged: {
        if (personOpen) page.forceActiveFocus()
        else if (visible) launcher.query.forceActiveFocus()
    }

    x: 0
    y: searchField.y + searchField.height + 16
    width: parent.width
    height: parent.height - y
    visible: launcher.peopleShown
    opacity: launcher.applicationLaunchPending ? 0 : 1

    Text {
        objectName: "people-label"
        height: pane.labelHeight
        verticalAlignment: Text.AlignTop
        x: 12
        visible: !pane.personOpen
        text: !pane.client ? ""
            : pane.client.count === 0 ? words.i18n("No one here yet")
            : launcher.query.text.length > 0 && pane.people.length === 0 ? words.i18n("No one by that name")
            : words.i18np("%1 person", "%1 people", pane.client.count)
        color: launcher.secondaryText
        font.pixelSize: 12
    }
    // With no one to show, where people come from.
    Text {
        objectName: "people-empty"
        y: pane.labelHeight
        x: 12
        width: parent.width - 24
        visible: !pane.personOpen && !!pane.client && pane.client.count === 0
        text: words.i18n("People come from your phone's contacts. Pair the phone in KDE Connect and turn on Contacts there.")
        color: launcher.primaryText
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }

    ListView {
        id: list
        objectName: "people-list"
        y: pane.labelHeight
        width: parent.width
        height: parent.height - y
        visible: !pane.personOpen
        clip: true
        spacing: pane.rowGap
        boundsBehavior: Flickable.StopAtBounds
        model: pane.people
        currentIndex: -1
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            objectName: "person-row"
            width: list.width
            height: pane.rowHeight
            Accessible.role: Accessible.ListItem
            Accessible.name: row.modelData.name + ", " + row.modelData.summary
            Accessible.onPressAction: pane.client.open(row.modelData.id)
            Rectangle {
                anchors.fill: parent
                radius: launcher.paperRadius
                color: rowTap.pressed ? tone.tilePressed
                    : list.currentIndex === row.index ? tone.current
                    : rowHover.hovered ? tone.hover : "transparent"
            }
            Mark {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                size: 32
                letters: row.modelData.initials
            }
            Column {
                x: 56
                width: parent.width - x - 12
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: row.modelData.name
                    color: launcher.primaryText
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.modelData.summary
                    color: launcher.secondaryText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            HoverHandler {
                id: rowHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: rowTap
                enabled: !launcher.guestDragged
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: pane.client.open(row.modelData.id)
            }
        }
    }

    // A person's page, over the field and all under it: the modes stay.
    Rectangle {
        id: page
        objectName: "person-page"
        y: -pane.y
        width: parent.width
        height: pane.y + pane.height
        visible: pane.personOpen
        color: launcher.surfaceColor
        focus: pane.personOpen
        readonly property var handles: pane.person.handles || []
        readonly property var match: pane.person.match || null
        readonly property string joined: pane.person.joined || ""
        // Nothing under the page takes a tap meant for it.
        TapHandler { onTapped: event => event.accepted = true }

        Pill {
            id: backPill
            objectName: "person-back"
            x: -6
            y: 1
            glyph: "chevron-left"
            label: words.i18n("People")
            onActivated: pane.back()
        }
        Mark {
            id: face
            x: backPill.x + backPill.width + 20
            y: 0
            size: 56
            letters: pane.person.initials || ""
        }
        Column {
            x: face.x + face.width + 16
            width: parent.width - x
            anchors.verticalCenter: face.verticalCenter
            Text {
                objectName: "person-name"
                width: parent.width
                text: pane.person.name || ""
                color: launcher.primaryText
                font.pixelSize: 22
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: page.joined === "hand" ? words.i18np("%1 card, joined by you", "%1 cards, joined by you", pane.person.cards || 0)
                    : page.joined === "same" ? words.i18np("%1 card with the same number or address", "%1 cards with the same number or address", pane.person.cards || 0)
                    : pane.person.summary || ""
                color: launcher.secondaryText
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }

        Flickable {
            id: ways
            objectName: "person-ways"
            y: face.height + 20
            width: parent.width
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: waysColumn.height
            Column {
                id: waysColumn
                width: ways.width
                spacing: pane.rowGap
                Repeater {
                    model: page.handles
                    Item {
                        id: way
                        required property var modelData
                        objectName: "person-way"
                        width: waysColumn.width
                        height: pane.rowHeight
                        readonly property bool phone: way.modelData.kind === "tel"
                        Column {
                            x: 12
                            width: parent.width - x - actions.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: way.modelData.shown
                                color: launcher.primaryText
                                font.pixelSize: 16
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: parent.width
                                text: way.modelData.label === "Mobile" ? words.i18n("Mobile")
                                    : way.modelData.label === "Email" ? words.i18n("Email")
                                    : way.modelData.label === "Phone" ? words.i18n("Phone")
                                    : words.i18n("Home or work")
                                color: launcher.secondaryText
                                font.pixelSize: 12
                            }
                        }
                        Row {
                            id: actions
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Pill {
                                objectName: "person-text"
                                visible: way.phone && pane.client.canText && way.modelData.label !== "Home or work"
                                light: true
                                label: words.i18n("Text")
                                onActivated: if (pane.client.reach("text", way.modelData.value)) launcher.launcherController.finishLaunch()
                            }
                            Pill {
                                objectName: "person-call"
                                visible: way.phone && pane.client.canCall
                                label: words.i18n("Call")
                                onActivated: if (pane.client.reach("call", way.modelData.value)) launcher.launcherController.finishLaunch()
                            }
                            Pill {
                                objectName: "person-email"
                                visible: !way.phone && pane.client.canEmail
                                light: true
                                label: words.i18n("Email")
                                onActivated: if (pane.client.reach("email", way.modelData.value)) launcher.launcherController.finishLaunch()
                            }
                            Pill {
                                id: copyPill
                                objectName: "person-copy"
                                property bool done: false
                                label: done ? words.i18n("Copied") : words.i18n("Copy")
                                onActivated: {
                                    pane.client.copy(way.modelData.shown)
                                    done = true
                                    copied.restart()
                                }
                                Timer {
                                    id: copied
                                    interval: 1600
                                    onTriggered: copyPill.done = false
                                }
                            }
                        }
                    }
                }
                // The provider's question about a likely match: one tap
                // joins them, the other is remembered and not asked again.
                Rectangle {
                    objectName: "person-match"
                    visible: !!page.match
                    width: waysColumn.width
                    height: 72
                    radius: launcher.paperRadius
                    color: tone.subtle
                    Mark {
                        id: matchMark
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        size: 32
                        letters: page.match ? page.match.initials : ""
                    }
                    Column {
                        x: 60
                        width: parent.width - x - answers.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: page.match ? words.i18n("Is “%1” the same person?", page.match.name) : ""
                            color: launcher.primaryText
                            font.pixelSize: 16
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: page.match ? words.i18n("The same name, with %1", page.match.summary.toLowerCase()) : ""
                            color: launcher.secondaryText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: answers
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Pill {
                            objectName: "person-not-same"
                            label: words.i18n("Not the same")
                            onActivated: pane.client.notSame(page.match.id)
                        }
                        Pill {
                            objectName: "person-join"
                            light: true
                            label: words.i18n("Join")
                            onActivated: pane.client.join(page.match.id)
                        }
                    }
                }
                // A person made of several cards can be taken apart again.
                Item {
                    visible: page.joined !== ""
                    width: waysColumn.width
                    height: 52
                    Pill {
                        objectName: "person-separate"
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.bottom: parent.bottom
                        label: words.i18n("Separate these cards")
                        onActivated: pane.client.separate()
                    }
                }
            }
        }
    }

    // A person's mark: the first letters of the name on a quiet round.
    component Mark: Rectangle {
        property int size: 32
        property string letters: ""
        width: size
        height: size
        radius: size / 2
        color: pane.tone.control
        Text {
            anchors.centerIn: parent
            text: parent.letters
            color: pane.launcher.primaryText
            font.pixelSize: Math.round(parent.size * 0.375)
            font.weight: Font.DemiBold
        }
    }
    component Pill: ModePill {
        primaryText: pane.launcher.primaryText
        surfaceColor: pane.launcher.surfaceColor
        controlColor: pane.tone.control
    }
}
