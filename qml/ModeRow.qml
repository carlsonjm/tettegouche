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
// dot for Search's first screen, then Apps, Files, where
// Gooseberry is installed Notes, and where Split Rock's Core lists
// them the Helpers, and where a people provider is installed People,
// before the Helpers. The grey pill marks the one
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

    // One of Search's modes along its top, Apps, Files or Notes: its word,
    // quiet until the pointer comes and bright once its mode is shown. The
    // highlight under the one shown is the row's own, and glides between
    // them; a mode only washes faintly as it is pressed.
    component FirstPill: Item {
        id: pill
        property string label
        // Whether its mode is the one shown.
        property bool selected: false
        // How far it has arrived, 0 to 1.
        property real reveal: 1
        readonly property bool pressed: pillTap.pressed
        signal activated()
        // Held at the bolder weight, so a mode's width never changes as it
        // is chosen and the highlight lands where the word is.
        width: boldWidth.advanceWidth + 32
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
        TextMetrics {
            id: boldWidth
            text: pill.label
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Rectangle {
            id: pillFace
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: modeRow.keyHeight
            radius: height / 2
            color: pill.selected ? "transparent"
                : pillTap.pressed ? tone.modePressed
                : pillHover.hovered ? tone.modeHover : "transparent"
            Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
            Text {
                id: pillLabel
                anchors.centerIn: parent
                text: pill.label
                color: pill.selected ? launcher.primaryText
                    : pillHover.hovered || pill.activeFocus ? tone.modeTextHover : tone.modeText
                font.pixelSize: 14
                font.weight: pill.selected ? Font.DemiBold : Font.Medium
                Behavior on color { ColorAnimation { duration: launcher.ms(180) } }
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

    // The mode shown: "apps", "files", "notes", "helpers", or "" on
    // the first screen.
    readonly property string current: launcher.notesOpen ? "notes"
        : launcher.drawerOpen ? (launcher.filesMode ? "files" : "apps")
        : launcher.helpersShown ? "helpers"
        : launcher.peopleShown ? "people" : ""
    readonly property real pillGap: 4
    // The height of the highlight and of a mode's wash, inside the row's 44.
    readonly property real keyHeight: 34
    // The mode whose word the highlight sits under, or null on the first
    // screen, where the dot is the one shown.
    readonly property Item selectedPill: {
        const at = order.indexOf(current)
        return at >= 0 && pills.count === order.length ? pills.itemAt(at) : null
    }
    // The modes in the order Settings gives them: each known mode once,
    // any it leaves out after the rest in their first order.
    readonly property var order: {
        const first = ["apps", "files", "notes", "people", "helpers"]
        const given = (launcher.modeOrder || []).filter((mode, i, all) =>
            first.indexOf(mode) >= 0 && all.indexOf(mode) === i)
        return given.concat(first.filter(mode => given.indexOf(mode) < 0))
    }
    // Whether a mode shows: Apps always; Files where there is a file
    // browser; Notes, People and the Helpers or Ask by their settings and
    // what is installed.
    function offered(mode) {
        if (mode === "files") return launcher.fileBrowser !== null && launcher.filesPillShown
        if (mode === "notes") return launcher.notesPillShown && !!launcher.notesDoor && launcher.notesDoor.available
        if (mode === "people") return launcher.peopleOffered
        if (mode === "helpers") return launcher.helpersPillShown && launcher.helpers.length > 0
        return true
    }
    function show(mode) {
        if (mode === current) return
        if (mode === "") {
            launcher.goBack()
            return
        }
        // The Helpers are Search's first screen with only the Helpers on it:
        // whatever is open closes, and what was typed stays.
        if (mode === "helpers") {
            if (launcher.drawerOpen) launcher.setDrawerOpen(false)
            if (launcher.modeOpen) launcher.closeMode()
            launcher.showHelpers(true)
            return
        }
        // People are a first screen of their own, as the Helpers are.
        if (mode === "people") {
            launcher.showPeople(true)
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
    opacity: launcher.applicationLaunchPending ? 0 : launcher.openingControls
    visible: opacity > 0
    enabled: opacity > 0.5 && !launcher.modeGrowing && !launcher.choosingFolder
    transform: Translate { y: (1 - launcher.openingControls) * 6 }
    z: 6

    // The highlight under the mode shown: one raised key that glides and
    // stretches from the mode left to the mode chosen, and settles without
    // a bounce. From the first screen it fades in where it lands, and it
    // fades out there as the dot is chosen. A press on the mode shown
    // squeezes it a little.
    Item {
        id: modeKey
        objectName: "mode-highlight"
        property Item target: modeRow.selectedPill
        // The mode it last sat under, which it stays over as it fades.
        property Item resting: null
        // Whether it moves to the next mode or appears there.
        property bool glides: false
        readonly property var settle: [0.32, 0.72, 0, 1, 1, 1]
        z: 0
        y: (modeRow.height - height) / 2
        height: modeRow.keyHeight
        x: resting ? resting.x : 0
        width: resting ? resting.width : 0
        opacity: target && target.visible ? 1 : 0
        visible: opacity > 0
        scale: target && target.pressed ? 0.96 : 1
        onTargetChanged: {
            glides = opacity > 0 && !!target && !!resting
            if (target) resting = target
        }
        Behavior on x {
            enabled: modeKey.glides
            NumberAnimation { duration: launcher.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: modeKey.settle }
        }
        Behavior on width {
            enabled: modeKey.glides
            NumberAnimation { duration: launcher.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: modeKey.settle }
        }
        Behavior on opacity { NumberAnimation { duration: launcher.ms(160); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: launcher.ms(140); easing.type: Easing.OutCubic } }

        Rectangle {
            id: modeFace
            objectName: "mode-highlight-face"
            anchors.fill: parent
            radius: height / 2
            border.width: 1
            border.color: tone.modeKeyEdge
            gradient: Gradient {
                GradientStop { position: 0; color: tone.modeKeyTop }
                GradientStop { position: 1; color: tone.modeKeyBottom }
            }
            // Its shade drawn again with a fine grain, so no lines show
            // between its greys.
            GrainFill {
                anchors.fill: parent
                anchors.margins: 1
                upper: tone.modeKeyTop
                lower: tone.modeKeyBottom
                keyHeight: modeFace.height
                topInset: 1
                widest: modeRow.width
                round: Math.max(0, modeFace.height / 2 - 1)
            }
            // No shadow: the fade and the fine rim raise it, and nothing is
            // laid over it to draw as Search opens.
        }
    }

    Row {
        z: 1
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
                        || modeRow.current === "helpers" || modeRow.current === "people"
                    glyph: modeRow.current === "notes" ? "notes"
                        : modeRow.current === "helpers" ? "sparkles"
                        : modeRow.current === "people" ? "users" : "folder-open"
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
        // The modes, in the order Settings gives them.
        Repeater {
            id: pills
            model: modeRow.order
            delegate: FirstPill {
                required property string modelData
                objectName: modelData + "-pill"
                label: modelData === "apps" ? words.i18n("Apps")
                    : modelData === "files" ? words.i18n("Files")
                    : modelData === "notes" ? words.i18n("Notes")
                    : modelData === "people" ? words.i18n("People")
                    : launcher.askOffered ? words.i18n("Ask") : words.i18n("Helpers")
                selected: modeRow.current === modelData
                visible: modeRow.offered(modelData)
                onActivated: modeRow.show(modelData)
            }
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
