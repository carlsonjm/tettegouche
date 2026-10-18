/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// Search's modes along its top, on every screen, as one row: the
// dot for Search's first screen, then Apps, Files and, where
// Gooseberry is installed, Notes. The grey pill marks the one
// shown, the dot while none is, and a tap moves between them. The
// field and whatever the mode shows sit below it.
Item {
    id: modeRow
    objectName: "mode-row"
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property NumberAnimation drawerSettle

    // One of Search's modes along its top, Apps, Files or Notes: its glyph
    // and its word on a pill, filled behind the one shown.
    component FirstPill: Item {
        id: pill
        property string label
        // Whether its mode is the one shown.
        property bool selected: false
        // How far it has arrived, 0 to 1.
        property real reveal: 1
        signal activated()
        width: pillLabel.implicitWidth + 28
        height: 44
        opacity: reveal
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checkable: true
        Accessible.checked: selected
        Keys.onReturnPressed: pill.activated()
        Keys.onEnterPressed: pill.activated()
        Keys.onSpacePressed: pill.activated()
        Rectangle {
            id: pillFace
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 40
            radius: height / 2
            color: pillTap.pressed ? tone.doorPressed
                : pill.selected ? tone.current
                : pillHover.hovered ? tone.doorHover : "transparent"
            scale: pillTap.pressed ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: launcher.ms(120); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: launcher.ms(90) } }
            Text {
                id: pillLabel
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.selected ? launcher.primaryText : launcher.secondaryText
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: launcher.ms(90) } }
            }
        }
        // Keyboard focus alone gets an outline.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width + 6
            height: pillFace.height + 6
            x: -3
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: tone.focusRing
            visible: pill.activeFocus
        }
        HoverHandler {
            id: pillHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: pillTap
            enabled: !launcher.guestDragged
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: pill.activated()
        }
    }

    // The mode shown: "apps", "files", "notes", or "" on the
    // first screen.
    readonly property string current: launcher.notesOpen ? "notes"
        : launcher.drawerOpen ? (launcher.filesMode ? "files" : "apps") : ""
    readonly property real pillGap: 4
    function show(mode) {
        if (mode === current) return
        if (mode === "") {
            launcher.goBack()
            return
        }
        // From one to another, Search keeps the size chosen.
        if (mode === "notes") {
            if (launcher.drawerOpen) launcher.setDrawerOpen(false, "", true)
            launcher.openNotes()
            if (!launcher.modeOpen && launcher.launcherController.drawerExpanded)
                launcher.launcherController.setDrawerExpanded(false)
            return
        }
        const fromMode = launcher.modeOpen
        if (fromMode) launcher.closeMode(true)
        launcher.setDrawerOpen(true, mode, fromMode)
        // From Notes the drawer is there at once, over Notes as
        // it fades, so the first screen never shows between them.
        if (fromMode) {
            drawerSettle.stop()
            launcher.drawerProgress = 1
        }
    }
    // The dot's pill starts on the field's left edge.
    x: -2
    y: -launcher.modeRowReach - 2
    width: parent.width + 2
    height: 44
    opacity: launcher.applicationLaunchPending || !launcher.modeRowShown ? 0 : launcher.openingControls
    visible: opacity > 0
    enabled: opacity > 0.5 && !launcher.modeGrowing && !launcher.choosingFolder
    transform: Translate { y: (1 - launcher.openingControls) * 6 }
    z: 6

    Row {
        spacing: modeRow.pillGap
        // The dot: Search's first screen, from any mode.
        Item {
            id: homeDot
            objectName: "home-dot"
            readonly property bool selected: modeRow.current === ""
            width: 44
            height: 44
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: words.i18n("Search")
            Accessible.checkable: true
            Accessible.checked: selected
            Accessible.onPressAction: modeRow.show("")
            Keys.onReturnPressed: modeRow.show("")
            Keys.onEnterPressed: modeRow.show("")
            Keys.onSpacePressed: modeRow.show("")
            // The Tette Dot, as the panel draws it while Search is up: a
            // ring holding the mark of the mode shown, or a new small dot
            // on the first screen. It clears into the ring as Search's controls arrive.
            // Hover and press show on the mark itself.
            DotMark {
                objectName: "home-dot-mark"
                anchors.centerIn: parent
                openness: launcher.openingControls > 0.5 ? 1 : 0
                seed: modeRow.current === ""
                speed: launcher.ms(1000) / 1000
                pearl: tone.dark
                ink: launcher.primaryText
                opacity: homeTap.pressed ? 0.7 : homeDot.selected || homeHover.hovered ? 1 : 0.8
                scale: homeHover.hovered && !homeTap.pressed ? 1.06 : 1
                Behavior on openness { NumberAnimation { duration: launcher.ms(360); easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: launcher.ms(140); easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: launcher.ms(90) } }

                // Apps: four squares, as on the panel's ring.
                Grid {
                    objectName: "home-dot-apps"
                    anchors.centerIn: parent
                    visible: modeRow.current === "apps"
                    columns: 2
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle {
                            width: 5
                            height: 5
                            radius: 1
                            color: launcher.primaryText
                        }
                    }
                }
                SuiteIcon {
                    objectName: "home-dot-glyph"
                    anchors.centerIn: parent
                    // An open folder carries its weight on the left; half a pixel
                    // right sets it in the middle of the ring to the eye.
                    anchors.horizontalCenterOffset: modeRow.current === "files" ? 0.5 : 0
                    visible: modeRow.current === "files" || modeRow.current === "notes"
                    glyph: modeRow.current === "notes" ? "notes" : "folder-open"
                    width: 12
                    height: 12
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 46
                height: 46
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: tone.focusRing
                visible: homeDot.activeFocus
            }
            HoverHandler {
                id: homeHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: homeTap
                enabled: !launcher.guestDragged
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: modeRow.show("")
            }
        }
        FirstPill {
            id: appsPill
            objectName: "apps-pill"
            label: words.i18n("Apps")
            selected: modeRow.current === "apps"
            onActivated: modeRow.show("apps")
        }
        FirstPill {
            id: filesPill
            objectName: "files-pill"
            label: words.i18n("Files")
            selected: modeRow.current === "files"
            visible: launcher.fileBrowser !== null
            onActivated: modeRow.show("files")
        }
        FirstPill {
            id: notesPill
            objectName: "notes-pill"
            label: words.i18n("Notes")
            selected: modeRow.current === "notes"
            visible: launcher.notesPillShown && !!launcher.notesDoor && launcher.notesDoor.available
            onActivated: modeRow.show("notes")
        }
    }

    // The window's own buttons share the row, at its other end:
    // Expand while a drawer or Notes is open, Pop out where Files
    // has a window of its own and in Notes, which opens the notes
    // application's own window, and Close, last, as a window's is.
    WindowActions {
        id: windowActions
        prefix: "window"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Every screen has them, so they hold still between
        // screens; only the buttons each one offers change.
        enabled: !launcher.modeOpen || (launcher.notesOpen && !launcher.modeGrowing)
        expanded: launcher.launcherController.drawerExpanded
        expandShown: launcher.drawerOpen || launcher.notesOpen
        popOutShown: (launcher.drawerOpen && launcher.filesMode && launcher.filesWindowOffered) || launcher.notesOpen
        popOutName: launcher.notesOpen ? words.i18n("Open in Notes") : words.i18n("Open Files in its own window")
        onExpand: launcher.toggleExpanded()
        onPopOut: launcher.notesOpen ? launcher.growNotes() : launcher.popOutFiles()
        onDismiss: launcher.launcherController.close()
    }
}
