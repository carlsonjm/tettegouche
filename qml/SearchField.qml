/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.ki18n
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

Rectangle {
    id: searchField
    objectName: "search-field"
    // The launcher whose state this draws, and the parts of its sheet it
    // lines up with.
    required property Item launcher
    required property SearchColors tone
    required property KI18nContext words
    required property Item applicationGrid
    required property Loader filesLoader
    required property Item firstRow
    required property ListView resultList
    readonly property alias query: query
    readonly property alias trailingAction: trailingAction

    // Nothing typed and nothing found: the first screen.
    readonly property bool idle:
        query.text.length === 0
        && resultList.count === 0
        && !launcher.searchResults.querying
        && !launcher.applicationLaunchPending
    // Lit while it holds the keys or what was typed.
    // Opened to type, the ring is up from the first frame, before the window
    // is given the keys.
    readonly property bool lit: query.activeFocus || query.text.length > 0 || launcher.typingAwaitsWindow
    // One field, in one place, on every screen: under the modes,
    // on the same edges as they are, 44 tall. Only what is under
    // it changes. In a room
    // taller than it needs, with nothing under it, it rests in
    // the middle, and rises as a drawer or a mode opens. The
    // Helpers' row sits under it, so it stays at the top for them.
    readonly property real restY: idle && !firstRow.fits && !launcher.helpersShown && !launcher.peopleShown
        ? Math.max(0, Math.round((parent.height - height) / 2)) : 0
    x: 0
    y: Math.round(restY * (1 - launcher.drawerProgress) * (1 - launcher.modeProgress))
    Behavior on y {
        enabled: (launcher.drawerProgress <= 0 || launcher.drawerProgress >= 1)
            && (launcher.modeProgress <= 0 || launcher.modeProgress >= 1)
        // In step with the sheet as it grows or shrinks about its centre, so
        // the field travels on screen in one even motion.
        NumberAnimation { duration: launcher.ms(220); easing.type: Easing.OutCubic }
    }
    // As the sheet grows or shrinks the field spans what shows of it, so its
    // ends stay in view; only the field moves with the sheet's edge.
    width: Math.min(parent.width, launcher.sheetInnerWidth)
    height: launcher.fieldHeight
    radius: height / 2
    // The face below draws it.
    color: "transparent"
    opacity: (launcher.applicationLaunchPending ? 0 : 1)
        * Math.max(0, 1 - launcher.modeProgress * 2)
        * launcher.openingControls
    enabled: !launcher.applicationLaunchPending && (!launcher.modeOpen || launcher.keysHandOver)

    // The highlight's material: its shade falling gently from top to
    // bottom, with a hairline round it. While it holds the keys or what was
    // typed it brightens a step, with no ring; its hairline brightens a
    // little under the pointer.
    Rectangle {
        id: fieldFace
        objectName: "search-field-face"
        anchors.fill: parent
        radius: searchField.radius
        border.width: 1
        border.color: searchField.lit || fieldHover.hovered ? tone.fieldEdgeHover : tone.fieldEdge
        gradient: Gradient {
            GradientStop { position: 0; color: searchField.lit ? tone.fieldLitTop : tone.fieldTop }
            GradientStop { position: 1; color: searchField.lit ? tone.fieldLitBottom : tone.fieldBottom }
        }
        // Its shade drawn again with a fine grain, so no lines show
        // between its greys.
        GrainFill {
            objectName: "search-field-grain"
            anchors.fill: parent
            anchors.margins: 1
            upper: searchField.lit ? tone.fieldLitTop : tone.fieldTop
            lower: searchField.lit ? tone.fieldLitBottom : tone.fieldBottom
            keyHeight: fieldFace.height
            topInset: 1
            widest: searchField.parent ? searchField.parent.width - 2 : width
            round: Math.max(0, Math.min(searchField.radius, fieldFace.height / 2) - 1)
        }
        // It lifts on the mode highlight's own shadow, the same in every
        // state.
        layer.enabled: true
        layer.effect: MultiEffect {
            objectName: "search-field-shadow"
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: searchField.tone.modeKeyShadow
            shadowBlur: 0.45
            shadowOpacity: 0.6
            shadowVerticalOffset: 1
        }
    }
    HoverHandler {
        id: fieldHover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        cursorShape: Qt.IBeamCursor
    }

    Behavior on opacity {
        // Notes' own field takes this one's place; the mode's
        // motion carries the fade.
        enabled: launcher.modeProgress <= 0 || launcher.modeProgress >= 1
        NumberAnimation { duration: launcher.ms(140); easing.type: Easing.OutCubic }
    }

    SuiteIcon {
        id: searchGlyph
        glyph: "search"
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        // As quiet as a mode not chosen until the pointer comes, and full
        // while it is lit.
        opacity: (searchField.lit ? 1 : fieldHover.hovered ? 0.9 : 0.62) * launcher.openingIcon
        Behavior on opacity { NumberAnimation { duration: launcher.ms(180) } }
    }

    // Clears what was typed; with nothing typed, a hint of what
    // Enter does takes its place.
    Item {
        id: trailingAction
        objectName: "search-clear"
        Accessible.role: Accessible.Button
        Accessible.name: words.i18n("Clear search")
        Accessible.onPressAction: { launcher.searchEngaged = true; query.text = ""; query.forceActiveFocus() }
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        visible: query.text.length > 0
        // A faint wash under the pointer and a small squeeze when pressed,
        // as on a mode.
        Rectangle {
            anchors.centerIn: parent
            width: 30
            height: 30
            radius: 15
            scale: clearTap.pressed ? 0.96 : 1
            color: clearTap.pressed ? tone.modePressed : clearHover.hovered ? tone.modeHover : "transparent"
            Behavior on color { ColorAnimation { duration: launcher.ms(120) } }
            Behavior on scale { NumberAnimation { duration: launcher.ms(140); easing.type: Easing.OutCubic } }
        }
        SuiteIcon {
            anchors.centerIn: parent
            glyph: "x"
            width: 18
            height: 18
            opacity: clearHover.hovered || clearTap.pressed ? 0.9 : 0.62
            Behavior on opacity { NumberAnimation { duration: launcher.ms(180) } }
        }
        HoverHandler {
            id: clearHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        }
        TapHandler {
            id: clearTap
            onTapped: {
                launcher.searchEngaged = true
                query.text = ""
                query.forceActiveFocus()
                launcher.launcherController.showInputMethod()
            }
        }
    }

    TextInput {
        id: query
        objectName: "search-query"
        anchors.left: searchGlyph.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        // Clear, and an open drawer's eye, sit at its end.
        anchors.rightMargin: 20 + (trailingAction.visible ? 36 : 0) + 42 * launcher.drawerProgress
        anchors.verticalCenter: parent.verticalCenter
        color: launcher.primaryText
        selectionColor: tone.selection
        selectedTextColor: tone.selectedText
        font.pixelSize: 16
        font.weight: Font.Medium
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText

        onTextChanged: {
            launcher.selectedChildKey = ""
            launcher.childLaunchFailed = false
            if (text.length > 0) {
                launcher.searchEngaged = true
            }
            launcher.pendingLaunch = false
            launcher.applicationCatalog.filterText = launcher.drawerOpen && !launcher.filesMode
                ? text : ""
            if (launcher.fileBrowser && launcher.filesMode) launcher.fileBrowser.filter = text
            launcher.searchResults.queryString = launcher.drawerOpen
                ? "" : text
            resultList.currentIndex = resultList.count > 0 ? 0 : -1
            resultList.settleAtBeginning()
            applicationGrid.reset()
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                launcher.searchEngaged = true
            } else {
                launcher.keysHandOver = false
            }
        }

        Keys.onPressed: event => {
            if (launcher.quickActionKey(event)) {
                event.accepted = true
                return
            }
            if (launcher.drawerOpen && !launcher.filesMode && event.key === Qt.Key_Down
                    && applicationGrid.choices.length > 0) {
                applicationGrid.step(0, 1)
                event.accepted = true
            } else if (launcher.drawerOpen && !launcher.filesMode && event.key === Qt.Key_Up
                       && applicationGrid.choices.length > 0) {
                applicationGrid.step(0, -1)
                event.accepted = true
            } else if (launcher.drawerOpen && launcher.filesMode && event.key === Qt.Key_Down
                       && filesLoader.item) {
                // From the filter into the files: the keys move there.
                filesLoader.item.focusFiles()
                event.accepted = true
            } else if (launcher.peopleShown && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                launcher.movePerson(event.key === Qt.Key_Down ? 1 : -1)
                event.accepted = true
            } else if (event.key === Qt.Key_Down
                       && resultList.count > 0) {
                launcher.moveResultSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Up
                       && resultList.count > 0) {
                launcher.moveResultSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right && !launcher.drawerOpen && !launcher.arrowModified(event)
                       && resultList.count > 0 && query.selectedText.length === 0
                       && query.cursorPosition === query.text.length
                       && launcher.enterResultChildren()) {
                event.accepted = true
            } else if (event.key === Qt.Key_Left && !launcher.drawerOpen && !launcher.arrowModified(event)
                       && launcher.leaveResultChildren()) {
                event.accepted = true
            } else if (event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter) {
                launcher.submit()
                event.accepted = true
            }
        }

        Text {
            id: placeholder
            objectName: "just-type-placeholder"
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: query.text.length === 0
            text: launcher.drawerOpen
                ? (launcher.filesMode ? words.i18n("Find a file") : words.i18n("Find an app"))
                : launcher.askShown ? words.i18n("Ask a question, or find a Helper")
                : launcher.helpersShown ? words.i18n("Look over the computer, free up space…")
                : launcher.peopleShown ? words.i18n("Find a person")
                : words.i18n("Just type")
            // As large as what is typed, so typing changes nothing but
            // the words.
            color: tone.modeText
            font.pixelSize: 16
            font.weight: Font.Medium
            opacity: launcher.openingText
            transform: Translate { y: (1 - launcher.openingText) * 3 }

            // A single soft light pass, clipped to copies of the
            // glyphs rather than a rectangle crossing the field.
            Repeater {
                model: 7
                delegate: Item {
                    required property int index
                    x: launcher.openingShine * (placeholder.implicitWidth + 35)
                        - 35 + index * 5
                    width: 5
                    height: placeholder.height
                    clip: true
                    visible: launcher.openingShine > 0 && launcher.openingShine < 1
                    opacity: [0.08, 0.18, 0.34, 0.5, 0.34, 0.18, 0.08][index]
                    Text {
                        x: -parent.x
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: placeholder.text
                        font: placeholder.font
                        color: tone.shine
                    }
                }
            }
        }
    }

    TapHandler {
        enabled: !launcher.guestDragged
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            launcher.searchEngaged = true
            query.forceActiveFocus()
            launcher.launcherController.showInputMethod()
        }
    }
}
