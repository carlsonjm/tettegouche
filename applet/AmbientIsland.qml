/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import QtQuick.Window
import org.kde.kirigami as Kirigami

// The island opened: a clear surface over the whole display with the island
// grown out of its place in the band into a black card. A tap outside it or
// Esc closes it back into the band. The applet places the surface; this file
// draws it and asks the surface below to act.
Window {
    id: overlay
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)); }
    // Its words come from the panel widget's catalog, the one Plasma gives
    // the widget, so they translate in the panel and in tests alike.
    KI18nContext {
        id: words
        translationDomain: "plasma_applet_co.goodinput.tettegouche"
    }

    // The closed island this one grew from, which holds the activities.
    property var surface: null
    property string kind: "media"
    // Where the closed island sits, and the side of the band it belongs to,
    // in this surface's coordinates.
    property rect start: Qt.rect(0, 0, 44, 44)
    property real sideLeft: 0
    property real sideRight: width
    property bool expanded: false
    signal closed()

    title: words.i18n("Ambient")
    color: "transparent"
    flags: Qt.FramelessWindowHint

    AmbientColors {
        id: tone
        theme: card.Kirigami.Theme
    }
    readonly property color ink: tone.text
    readonly property real openWidth: Math.min(384, width - 16)
    // The card grows up from the band, and no taller than the room above it;
    // what does not fit scrolls. A band reaching past the display's bottom,
    // as a panel tucked away under another surface does, is taken as ending
    // at the display's edge, so the card's foot stays on it.
    readonly property real bandFoot: Math.min(start.y + start.height, height)
    // Every card, Layouts' too, drops out of the island it grew from.
    readonly property real cardFoot: bandFoot
    readonly property real openRoom: Math.max(120, cardFoot - 8)
    readonly property real openHeight: Math.min(content.implicitHeight + 36, openRoom)
    readonly property real openX: Math.max(8, Math.min(width - 8 - openWidth,
        Math.max(sideLeft, Math.min(sideRight - openWidth, start.x + start.width / 2 - openWidth / 2))))
    readonly property real openY: Math.max(8, cardFoot - openHeight)
    readonly property var activity: kind === "media" ? (surface ? surface.player : null) : null
    // The fact from Core the card answers, while Core still asks it.
    readonly property var question: kind === "core" && surface && surface.coreAsks ? surface.coreShown : null
    onQuestionChanged: if (kind === "core" && question === null) dismiss()
    // An answer goes to Core, which takes the fact off the island.
    function answer(action) {
        if (question) surface.invoke(question, action);
        dismiss();
    }

    // The keeper of saved layouts, for Layouts: the widget, which asks Split
    // Rock's Core. It lists `layouts`, reads `currentLayout` on
    // readCurrentLayout(), and saves, opens, and removes them.
    property var layouts: null
    // Shuffle's dock is there to pin a layout to, and what it pins.
    readonly property bool dockPinsLayouts: !!layouts && layouts.dockPinsLayouts === true
    readonly property var dockLayouts: layouts && layouts.dockLayouts ? layouts.dockLayouts : []
    readonly property var savedLayouts: kind === "layouts" && layouts && layouts.layouts ? layouts.layouts : []
    // Saved layouts waiting for a display that isn't connected, out of the list.
    readonly property int layoutsAway: layouts && layouts.layoutsAway ? layouts.layoutsAway : 0
    // Quick actions, asked for from Search's Helpers: each action Search
    // offers by its name, with what to type for it; the kinds the settings
    // leave out are left out here. Try asks the keeper to open Search with
    // those words in its field.
    property var quickLeftOut: []
    readonly property var quickExamples: [
        {kind: "reminder", title: words.i18nc("@title a quick action", "Reminder"),
         typed: words.i18nc("@info what to type for a reminder", "remind me to call the bank at 3")},
        {kind: "note", title: words.i18nc("@title a quick action", "Note"),
         typed: words.i18nc("@info what to type for a note", "note router password is on the box")},
        {kind: "keepAwake", title: words.i18nc("@title a quick action", "Keep awake"),
         typed: words.i18nc("@info what to type to keep the computer awake", "keep awake 1h")},
        {kind: "doNotDisturb", title: words.i18nc("@title a quick action", "Do not disturb"),
         typed: words.i18nc("@info what to type for do not disturb", "do not disturb until 3")},
        {kind: "bluetooth", title: words.i18nc("@title a quick action", "Bluetooth"),
         typed: words.i18nc("@info what to type to turn Bluetooth off", "bluetooth off")}
    ].filter(example => (quickLeftOut || []).indexOf(example.kind) < 0)
    function tryQuickAction(typed) {
        if (layouts) layouts.typeInSearch(typed);
        dismiss();
    }
    // The quick note the notes application keeps, for the + island's card:
    // the same note Search's Notes writes. Null where there is none, when
    // the + opens Search instead.
    property var quickNote: null
    readonly property bool noteWritable: quickNote !== null && quickNote.open && !quickNote.readOnly
    readonly property color noteHex: quickNote && quickNote.colourHex !== "" ? quickNote.colourHex : "#F2D98A"
    // Which of the note's choices shows under it: "", "colour", "remind" or "window".
    property string noteChoosing: ""
    // The note opened on the + resumes the one left open, or starts one.
    // Whether anything has been typed since the card opened: until then the
    // note Start resumes or begins is drawn as it arrives.
    property bool noteTyped: false
    function startNote() {
        noteChoosing = "";
        noteTyped = false;
        if (!quickNote) return;
        quickNote.start();
        notePad.text = quickNote.text;
        overlay.syncNoteLines();
        notePadFocus.restart();
    }
    // Done finishes the note, kept as it was written.
    function finishNote() {
        if (quickNote) {
            quickNote.flush();
            quickNote.done();
        }
        dismiss();
    }
    // The full note, on the notes application's own card; where it can't
    // take it, on Search's Notes page.
    function noteInNotes() {
        if (!quickNote) return;
        quickNote.flush();
        const id = quickNote.noteId;
        handingNote = id;
        quickNote.openOnCard(id, "");
    }
    property string handingNote: ""
    Connections {
        target: overlay.quickNote
        ignoreUnknownSignals: true
        function onCardAnswered(opened) {
            if (overlay.handingNote === "") return;
            const id = overlay.handingNote;
            overlay.handingNote = "";
            if (!opened && overlay.layouts) overlay.layouts.openDrawer("note:" + id);
            overlay.dismiss();
        }
        // A change kept elsewhere shows while the pad isn't typed into.
        function onNoteChanged() {
            if (overlay.kind !== "note") return;
            if ((!notePad.activeFocus || !overlay.noteTyped) && notePad.text !== overlay.quickNote.text)
                notePad.text = overlay.quickNote.text;
            if (!noteLines.typing) overlay.syncNoteLines();
        }
    }
    Timer {
        id: notePadFocus
        interval: 1
        onTriggered: {
            if (overlay.quickNote && overlay.quickNote.checklist && noteLineModel.count > 0) noteLines.focusRow(noteLineModel.count - 1);
            else notePad.forceActiveFocus();
        }
    }
    // The checklist, one row per line, kept here while it is typed into, as
    // Search's Notes keeps it: "- [ ] " and "- [x] " lines.
    ListModel { id: noteLineModel }
    function syncNoteLines() {
        const lines = quickNote && quickNote.checklist ? quickNote.lines || [] : [];
        let same = lines.length === noteLineModel.count;
        for (let i = 0; same && i < lines.length; ++i) {
            const row = noteLineModel.get(i);
            same = row.text === (lines[i].text || "") && row.item === !!lines[i].item && row.checked === !!lines[i].checked;
        }
        if (same) return;
        noteLineModel.clear();
        for (const line of lines)
            noteLineModel.append({ text: line.text || "", item: !!line.item, checked: !!line.checked });
    }
    function sendNoteLines() {
        const out = [];
        for (let i = 0; i < noteLineModel.count; ++i) {
            const row = noteLineModel.get(i);
            out.push(row.item ? (row.checked ? "- [x] " : "- [ ] ") + row.text : row.text);
        }
        quickNote.setText(out.join("\n"));
    }

    // Layouts shows the saved layouts, or the form that saves what's open.
    property bool savingLayout: false
    // The saved layout whose Remove shows, by its id.
    property string chosenLayout: ""
    // The form: what is open, less the groups taken out; whether Core has
    // answered; and the workspace's name.
    property var keptGroups: []
    property bool currentRead: false
    property string workspaceName: ""
    readonly property bool canSave: layoutName.text.trim().length > 0 && keptGroups.length > 0
    onKindChanged: {
        savingLayout = false;
        chosenLayout = "";
        if (kind === "note") startNote();
    }
    Component.onCompleted: if (kind === "note") startNote()
    function saveWhatsOpen() {
        keptGroups = [];
        currentRead = false;
        workspaceName = "";
        layoutName.text = "";
        savingLayout = true;
        layoutName.forceActiveFocus();
        if (layouts) layouts.readCurrentLayout();
    }
    function takeCurrent() {
        const current = layouts ? layouts.currentLayout : null;
        if (!savingLayout || !current || current.available === undefined) return;
        keptGroups = current.available && current.groups ? current.groups.slice() : [];
        workspaceName = current.workspaceName || "";
        currentRead = true;
    }
    Connections {
        target: overlay.layouts
        ignoreUnknownSignals: true
        function onCurrentLayoutChanged() { overlay.takeCurrent(); }
    }
    // Open, Save and Not now close the island; Core and Cards do the rest.
    // A layout's apps in one line, group by group: "Zen Browser · Stack of
    // Mail, Ghostty · Claude".
    function appsLine(groups) {
        return groups.map(group => {
            const names = group.names && group.names.length ? group.names : (group.apps || []);
            return names.length > 1 && group.stack
                ? words.i18nc("@info a Stack of apps in a saved layout", "Stack of %1", names.join(words.i18nc("@info between apps in a Stack", ", ")))
                : names.join(words.i18nc("@info between apps in a Stack", ", "));
        }).join(words.i18nc("@info between a saved layout's groups", " · "));
    }

    function openLayout(id) {
        if (layouts) layouts.openLayout(id);
        dismiss();
    }
    function saveLayout() {
        if (!canSave) return;
        if (layouts) layouts.saveLayout(layoutName.text.trim(), keptGroups, false);
        dismiss();
    }

    // Not close(): that is the window's own, and would drop it at once.
    function dismiss() {
        if (!expanded) return;
        // A note left open is kept as written, to carry on from the + or
        // Search's Notes.
        if (kind === "note" && quickNote) quickNote.flush();
        expanded = false;
        closing.restart();
    }
    Timer {
        id: opening
        interval: 30
        onTriggered: overlay.expanded = true
    }
    Timer {
        id: closing
        interval: overlay.ms(320)
        onTriggered: overlay.closed()
    }
    onVisibleChanged: if (visible) opening.restart()
    onActiveChanged: if (!active && expanded && visible) dismiss()

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.dismiss()
    }

    // A tap anywhere outside the card closes the island.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.dismiss()
    }

    // ---------------------------------------------------------------- pieces

    component Label: Text {
        color: overlay.ink
        font.pixelSize: 13
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // Every open island's first line: its picture, its name, and after a
    // dot what it holds, as "Layouts · 5 saved".
    component CardTitle: Row {
        id: cardTitle
        property string name
        property string after
        // A theme icon, a suite glyph, or a colour, in that order.
        property string icon
        property string glyph
        property color swatch: "transparent"
        spacing: 8
        Kirigami.Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: cardTitle.icon !== ""
            width: 20
            height: 20
            source: cardTitle.icon
        }
        SuiteIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: cardTitle.icon === "" && cardTitle.glyph !== ""
            width: 18
            height: 18
            glyph: cardTitle.glyph !== "" ? cardTitle.glyph : "plus"
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: cardTitle.icon === "" && cardTitle.glyph === "" && cardTitle.swatch.a > 0
            width: 18
            height: 18
            radius: 5
            color: cardTitle.swatch
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            Label {
                id: cardName
                objectName: cardTitle.objectName + "-name"
                text: cardTitle.name
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Label {
                objectName: cardTitle.objectName + "-after"
                anchors.baseline: cardName.baseline
                visible: text !== ""
                text: cardTitle.after
                opacity: 0.66
            }
        }
    }

    component GlyphButton: Item {
        id: button
        property string glyph
        property real size: 22
        property string label
        signal activated()
        width: 44
        height: 44
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        SuiteIcon {
            anchors.centerIn: parent
            width: button.size
            height: button.size
            glyph: button.glyph
            scale: buttonArea.pressed ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
        }
        Rectangle {
            anchors.centerIn: parent
            width: button.size + 14
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: overlay.ink
            opacity: 0.6
            visible: button.activeFocus
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            onClicked: button.activated()
        }
    }

    component PillButton: Rectangle {
        id: pill
        property string label
        property bool filled: false
        signal activated()
        height: 40
        width: Math.max(40, pillText.implicitWidth + 28)
        radius: height / 2
        color: filled ? overlay.ink : tone.wash(pillArea.pressed ? 0.22 : 0.12)
        scale: pillArea.pressed ? 1.04 : 1
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        border.width: activeFocus ? 1 : 0
        border.color: overlay.ink
        Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.filled ? tone.textOnInk : overlay.ink
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            onClicked: pill.activated()
        }
    }

    // A saved layout drawn small: each group a card, a Stack's cards fanned
    // 5 px behind its front one, and its apps' names beneath.
    // A saved layout's desk, drawn small: each display it stood on, left to
    // right, with the windows that were seen there, as shares of it. A layout
    // kept without places is one display, its groups side by side.
    component LayoutPicture: Item {
        id: picture
        property var groups: []
        readonly property var desk: {
            const displays = [];
            for (const g of groups) {
                if (!g.display || !(g.displayWidth > 0) || !(g.displayHeight > 0)) return [];
                let on = displays.find(d => d.name === g.display);
                if (!on) {
                    on = { name: g.display, x: Number(g.displayX) || 0, y: Number(g.displayY) || 0,
                           w: g.displayWidth, h: g.displayHeight, windows: [] };
                    displays.push(on);
                }
                if (g.shown && g.pictureWidth > 0 && g.pictureHeight > 0)
                    on.windows.push({ x: g.pictureX, y: g.pictureY, w: g.pictureWidth, h: g.pictureHeight,
                                      icon: g.icons && g.icons[0] ? g.icons[0] : "" });
            }
            return displays.sort((a, b) => a.x - b.x);
        }
        readonly property real deskLeft: desk.length ? Math.min(...desk.map(d => d.x)) : 0
        readonly property real deskTop: desk.length ? Math.min(...desk.map(d => d.y)) : 0
        readonly property real across: desk.length ? Math.max(...desk.map(d => d.x + d.w)) - deskLeft : 1
        readonly property real down: desk.length ? Math.max(...desk.map(d => d.y + d.h)) - deskTop : 1
        readonly property real fit: Math.min(width / across, height / down)
        Repeater {
            model: picture.desk
            delegate: Rectangle {
                id: shown
                required property var modelData
                x: (picture.width - picture.across * picture.fit) / 2 + (modelData.x - picture.deskLeft) * picture.fit
                y: (picture.height - picture.down * picture.fit) / 2 + (modelData.y - picture.deskTop) * picture.fit
                width: Math.max(4, modelData.w * picture.fit - 2)
                height: Math.max(4, modelData.h * picture.fit - 2)
                radius: 3
                color: tone.over(0.10)
                border.width: 1
                border.color: tone.wash(0.30)
                Repeater {
                    model: shown.modelData.windows
                    delegate: Rectangle {
                        required property var modelData
                        // Kept as shares of its display.
                        x: 1 + modelData.x * (shown.width - 2)
                        y: 1 + modelData.y * (shown.height - 2)
                        width: Math.max(2, modelData.w * (shown.width - 2) - 1)
                        height: Math.max(2, modelData.h * (shown.height - 2) - 1)
                        radius: 2
                        color: tone.wash(0.40)
                        // The app in front there, by its icon, as Settings' map shows it.
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Math.min(16, parent.width - 2, parent.height - 2)
                            height: width
                            visible: width >= 6 && parent.modelData.icon !== ""
                            source: parent.modelData.icon
                        }
                    }
                }
            }
        }
        // Kept without places: one display, a column for each group.
        Rectangle {
            visible: picture.desk.length === 0
            anchors.fill: parent
            radius: 3
            color: tone.over(0.10)
            border.width: 1
            border.color: tone.wash(0.30)
            Row {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 2
                Repeater {
                    model: Math.max(1, Math.min(4, picture.groups.length))
                    delegate: Rectangle {
                        required property int index
                        readonly property var group: picture.groups[index] || ({})
                        width: (parent.width - 2 * (Math.max(1, Math.min(4, picture.groups.length)) - 1)) / Math.max(1, Math.min(4, picture.groups.length))
                        height: parent.height
                        radius: 2
                        color: tone.wash(0.40)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Math.min(16, parent.width - 2, parent.height - 2)
                            height: width
                            visible: width >= 6 && !!(parent.group.icons && parent.group.icons[0])
                            source: parent.group.icons && parent.group.icons[0] ? parent.group.icons[0] : ""
                        }
                    }
                }
            }
        }
    }

    component Art: Item {
        id: art
        property var activity: null
        property real corner: 10
        Rectangle {
            anchors.fill: parent
            radius: art.corner
            color: tone.art
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.6)
                height: width
                source: art.activity && art.activity.icon ? art.activity.icon : "audio-x-generic-symbolic"
            }
        }
        Kirigami.ShadowedImage {
            anchors.fill: parent
            radius: art.corner
            color: "transparent"
            source: art.activity && art.activity.artUrl ? art.activity.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    component Progress: Item {
        id: progressMark
        property var activity: null
        property bool showNumber: false
        readonly property bool known: activity !== null && activity !== undefined
            && activity.progress !== undefined && activity.progress !== null
        Canvas {
            id: ring
            anchors.fill: parent
            visible: progressMark.known
            readonly property real value: progressMark.known ? Number(progressMark.activity.progress) : 0
            readonly property color ink: overlay.ink
            onValueChanged: requestPaint()
            onInkChanged: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.reset();
                const thickness = 3.5;
                const radius = Math.min(width, height) / 2 - thickness / 2 - 0.5;
                context.lineWidth = thickness;
                context.lineCap = "round";
                context.strokeStyle = tone.wash(0.22);
                context.beginPath();
                context.arc(width / 2, height / 2, radius, 0, 2 * Math.PI, false);
                context.stroke();
                context.strokeStyle = ring.ink;
                context.beginPath();
                context.arc(width / 2, height / 2, radius, -Math.PI / 2,
                    -Math.PI / 2 + 2 * Math.PI * Math.max(0, Math.min(1, value)), false);
                context.stroke();
            }
        }
        Text {
            anchors.centerIn: parent
            visible: progressMark.known && progressMark.showNumber
            text: progressMark.known ? Math.round(Number(progressMark.activity.progress) * 100) : ""
            color: overlay.ink
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
        }
        SuiteIcon {
            anchors.centerIn: parent
            visible: !progressMark.known
            width: Math.round(parent.width * 0.55)
            height: width
            glyph: "download"
        }
    }

    // ---------------------------------------------------------------- card

    Rectangle {
        id: card
        objectName: "ambient-island-open"
        x: overlay.expanded ? overlay.openX : overlay.start.x
        y: overlay.expanded ? overlay.openY : overlay.start.y
        width: overlay.expanded ? overlay.openWidth : overlay.start.width
        height: overlay.expanded ? overlay.openHeight : overlay.start.height
        // A pill in the band, and a note once open: Shuffle's 12 px for what
        // floats above everything and closes.
        radius: Math.min(height / 2, 12)
        color: tone.card
        border.width: 1
        border.color: tone.wash(0.12)
        clip: true
        Behavior on x { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on y { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on width { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on height { NumberAnimation { duration: overlay.ms(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

        // Taps on the card itself stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            id: scroller
            objectName: "ambient-island-scroll"
            x: 18
            y: 18
            width: overlay.openWidth - 36
            height: Math.max(0, card.height - 36)
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            interactive: contentHeight > height + 0.5
            boundsBehavior: Flickable.StopAtBounds
            // A wheel notch scrolls 80 pixels at Plasma's usual three lines per notch.
            Kirigami.WheelHandler { target: scroller; verticalStepSize: Qt.styleHints.wheelScrollLines * 80 / 3 }

            Column {
                id: content
                width: overlay.openWidth - 36
                spacing: 14
                opacity: overlay.expanded ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: overlay.ms(overlay.expanded ? 260 : 90)
                        easing.type: overlay.expanded ? Easing.InQuad : Easing.Linear
                    }
                }

                // With more than one kind going on, a row to move between them.
                Row {
                    objectName: "ambient-island-kinds"
                    visible: overlay.kind !== "core" && overlay.kind !== "layouts" && overlay.kind !== "quickActions" && overlay.kind !== "note"
                        && overlay.surface !== null
                        && overlay.surface.kinds.length > 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: overlay.surface ? overlay.surface.kinds : []
                        delegate: Item {
                            id: choice
                            required property string modelData
                            width: 44
                            height: 40
                            activeFocusOnTab: true
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData === "media" ? words.i18n("Media") : words.i18n("Transfers")
                            Keys.onReturnPressed: overlay.kind = modelData
                            Keys.onSpacePressed: overlay.kind = modelData
                            Item {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                opacity: overlay.kind === choice.modelData ? 1 : 0.45
                                scale: overlay.kind === choice.modelData ? 1.12 : 1
                                Behavior on scale { NumberAnimation { duration: overlay.ms(160); easing.type: Easing.OutBack } }
                                Art {
                                    anchors.fill: parent
                                    visible: choice.modelData === "media"
                                    activity: overlay.surface ? overlay.surface.player : null
                                    corner: width / 2
                                }
                                Progress {
                                    anchors.fill: parent
                                    visible: choice.modelData === "transfer"
                                    activity: overlay.surface ? overlay.surface.firstTransfer : null
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: overlay.kind = choice.modelData }
                        }
                    }
                }

                // Music.
                Column {
                    objectName: "ambient-island-media"
                    visible: overlay.kind === "media" && overlay.activity !== null
                    width: parent.width
                    spacing: 10

                    CardTitle {
                        objectName: "ambient-island-media-title"
                        name: words.i18nc("@title the open music island", "Music")
                        after: overlay.activity && overlay.activity.source
                            ? words.i18nc("@title after Music: the player", " · %1", overlay.activity.source) : ""
                        icon: overlay.activity && overlay.activity.icon ? overlay.activity.icon : ""
                        glyph: "play"
                    }

                    Row {
                        spacing: 14
                        Art {
                            width: 64
                            height: 64
                            activity: overlay.activity
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: content.width - 78
                            spacing: 2
                            Label {
                                width: parent.width
                                text: overlay.activity ? overlay.activity.title || overlay.activity.source || words.i18n("Media") : ""
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Label {
                                width: parent.width
                                visible: text.length > 0
                                text: overlay.activity ? [overlay.activity.artist, overlay.activity.album]
                                    .filter(Boolean).join(" · ") : ""
                                font.pixelSize: 14
                                opacity: 0.66
                            }
                        }
                    }

                    // Where the track is, and a place to move it to.
                    Item {
                        id: seek
                        objectName: "ambient-island-seek"
                        readonly property real lengthUs: overlay.activity && overlay.activity.durationUs !== undefined
                            ? Number(overlay.activity.durationUs) : 0
                        readonly property bool movable: lengthUs > 0 && overlay.surface
                            && overlay.surface.capability(overlay.activity, "seekTo")
                        readonly property real positionUs: seekArea.pressed ? dragUs
                            : overlay.surface ? overlay.surface.mediaPositionUs(overlay.activity) : 0
                        property real dragUs: 0
                        visible: lengthUs > 0
                        width: parent.width
                        height: 40
                        Accessible.role: Accessible.Slider
                        Accessible.name: words.i18n("Position")
                        // Focused, the arrows move the media five seconds at a time.
                        activeFocusOnTab: movable
                        function step(byUs) {
                            overlay.surface.invoke(overlay.activity, "seekTo",
                                Math.round(Math.max(0, Math.min(lengthUs, positionUs + byUs))));
                        }
                        Keys.onLeftPressed: if (movable) step(-5000000)
                        Keys.onRightPressed: if (movable) step(5000000)
                        Rectangle {
                            y: 12
                            width: parent.width
                            height: 4
                            radius: 2
                            color: tone.wash(0.22)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, seek.positionUs / Math.max(1, seek.lengthUs)))
                                height: parent.height
                                radius: 2
                                color: overlay.ink
                            }
                            Rectangle {
                                visible: seek.movable
                                x: parent.width * Math.max(0, Math.min(1, seek.positionUs / Math.max(1, seek.lengthUs))) - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: overlay.ink
                                scale: seekArea.pressed || seek.activeFocus ? 1.5 : 1
                                Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
                            }
                        }
                        Label {
                            y: 22
                            text: overlay.surface ? overlay.surface.formatTime(seek.positionUs) : ""
                            font.pixelSize: 11
                            opacity: 0.66
                            font.features: ({ "tnum": 1 })
                        }
                        Label {
                            y: 22
                            anchors.right: parent.right
                            text: overlay.surface ? "−" + overlay.surface.formatTime(Math.max(0, seek.lengthUs - seek.positionUs)) : ""
                            font.pixelSize: 11
                            opacity: 0.66
                            font.features: ({ "tnum": 1 })
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            enabled: seek.movable
                            preventStealing: true
                            function place(x) { seek.dragUs = Math.max(0, Math.min(1, x / width)) * seek.lengthUs; }
                            onPressed: mouse => place(mouse.x)
                            onPositionChanged: mouse => place(mouse.x)
                            onReleased: overlay.surface.invoke(overlay.activity, "seekTo", Math.round(seek.dragUs))
                        }
                    }

                    Row {
                        objectName: "ambient-island-transport"
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        GlyphButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "previous")
                            glyph: "skip-back"
                            label: words.i18n("Previous")
                            onActivated: overlay.surface.invoke(overlay.activity, "previous")
                        }
                        Rectangle {
                            id: bigToggle
                            objectName: "ambient-island-toggle"
                            readonly property bool playing: overlay.activity !== null && overlay.activity.state === "playing"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, playing ? "pause" : "play")
                            width: 56
                            height: 56
                            radius: 28
                            color: tone.wash(0.14)
                            border.width: activeFocus ? 1 : 0
                            border.color: overlay.ink
                            scale: toggleArea.pressed ? 1.1 : 1
                            activeFocusOnTab: visible
                            Accessible.role: Accessible.Button
                            Accessible.name: playing ? words.i18n("Pause") : words.i18n("Play")
                            Accessible.onPressAction: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Keys.onReturnPressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Keys.onSpacePressed: overlay.surface.invoke(overlay.activity, playing ? "pause" : "play")
                            Behavior on scale { NumberAnimation { duration: overlay.ms(90) } }
                            SuiteIcon {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                glyph: bigToggle.playing ? "pause" : "play"
                            }
                            MouseArea {
                                id: toggleArea
                                anchors.fill: parent
                                onClicked: overlay.surface.invoke(overlay.activity, bigToggle.playing ? "pause" : "play")
                            }
                        }
                        GlyphButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "next")
                            glyph: "skip-forward"
                            label: words.i18n("Next")
                            onActivated: overlay.surface.invoke(overlay.activity, "next")
                        }
                    }

                    // The other players, waiting here rather than in the band.
                    Repeater {
                        model: overlay.surface ? overlay.surface.otherPlayers : []
                        delegate: Item {
                            id: other
                            required property var modelData
                            width: content.width
                            height: 40
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: words.i18n("Show %1 here", modelData.source || modelData.title || "")
                            Keys.onReturnPressed: overlay.surface.chosenPlayer = String(modelData.id)
                            Keys.onSpacePressed: overlay.surface.chosenPlayer = String(modelData.id)
                            readonly property bool playing: modelData.state === "playing"
                            MouseArea { anchors.fill: parent; onClicked: overlay.surface.chosenPlayer = String(other.modelData.id) }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Kirigami.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    height: 18
                                    source: other.modelData.icon || "audio-x-generic-symbolic"
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: content.width - 30 - 44
                                    text: [other.modelData.source, other.modelData.title,
                                        other.playing ? words.i18n("playing") : words.i18n("paused")]
                                        .filter(Boolean).join(" · ")
                                    font.pixelSize: 12
                                    opacity: 0.66
                                }
                            }
                            // A waiting player plays or pauses from here, without
                            // taking the island.
                            GlyphButton {
                                objectName: "ambient-island-other-toggle-" + other.modelData.id
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: overlay.surface !== null
                                    && overlay.surface.capability(other.modelData, other.playing ? "pause" : "play")
                                glyph: other.playing ? "pause" : "play"
                                size: 18
                                label: other.playing ? words.i18n("Pause %1", other.modelData.source || other.modelData.title || "")
                                    : words.i18n("Play %1", other.modelData.source || other.modelData.title || "")
                                onActivated: overlay.surface.invoke(other.modelData, other.playing ? "pause" : "play")
                            }
                        }
                    }

                    // The card's buttons: the player, then Close, last as on
                    // every card.
                    Flow {
                        objectName: "ambient-island-media-actions"
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-raise"
                            filled: true
                            visible: overlay.surface !== null && overlay.surface.capability(overlay.activity, "raise")
                            label: words.i18n("Show %1", overlay.activity ? overlay.activity.source || words.i18n("player") : "")
                            onActivated: {
                                overlay.surface.invoke(overlay.activity, "raise");
                                overlay.dismiss();
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-media-close"
                            label: words.i18n("Close")
                            onActivated: overlay.dismiss()
                        }
                    }
                }

                // A question from Core: its icon, the question and its detail,
                // then its answers as pills, the tap's own first and Not now
                // last, with the choices Core lists between them.
                Column {
                    objectName: "ambient-island-core"
                    visible: overlay.question !== null
                    width: parent.width
                    spacing: 14
                    Row {
                        width: parent.width
                        spacing: 12
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 10
                            color: tone.art
                            Kirigami.Icon {
                                objectName: "ambient-island-core-icon"
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: overlay.surface ? overlay.surface.coreIcon : ""
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 52
                            spacing: 2
                            Label {
                                objectName: "ambient-island-core-line"
                                width: parent.width
                                text: overlay.question ? overlay.question.line || overlay.question.title || "" : ""
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                            }
                            Label {
                                objectName: "ambient-island-core-detail"
                                width: parent.width
                                visible: text.length > 0
                                text: overlay.question ? overlay.question.detail || "" : ""
                                opacity: 0.66
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                            }
                        }
                    }
                    Flow {
                        objectName: "ambient-island-core-answers"
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-core-open"
                            filled: true
                            label: overlay.question ? overlay.question.actionText || words.i18n("Open") : ""
                            onActivated: overlay.answer("open")
                        }
                        Repeater {
                            model: overlay.surface ? overlay.surface.coreChoices : []
                            delegate: PillButton {
                                required property var modelData
                                objectName: "ambient-island-core-choice-" + modelData.action
                                label: modelData.text
                                onActivated: overlay.answer(modelData.action)
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-core-not-now"
                            label: overlay.surface ? overlay.surface.coreNotNow : ""
                            onActivated: overlay.answer("not-now")
                        }
                    }
                }

                // Quick actions, asked for from Search: each action with
                // what to type for it and a Try pill, then Close.
                Column {
                    objectName: "ambient-island-quick-actions"
                    visible: overlay.kind === "quickActions"
                    width: parent.width
                    spacing: 12
                    CardTitle {
                        objectName: "ambient-island-quick-actions-title"
                        name: words.i18nc("@title what Search does from typed words", "Quick actions")
                        after: words.i18nc("@title after Quick actions", " · what to type in Search")
                        glyph: "sparkles"
                    }
                    Label {
                        objectName: "ambient-island-quick-actions-none"
                        width: parent.width
                        visible: overlay.quickExamples.length === 0
                        text: words.i18n("Every quick action is turned off in Search's settings.")
                        opacity: 0.66
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.kind === "quickActions" ? overlay.quickExamples : []
                            delegate: Rectangle {
                                id: example
                                required property var modelData
                                objectName: "ambient-island-quick-action-" + modelData.kind
                                width: parent.width
                                height: exampleWords.implicitHeight + 24
                                radius: 10
                                color: tone.wash(exampleArea.pressed ? 0.12 : 0.075)
                                Accessible.role: Accessible.ListItem
                                Accessible.name: modelData.title
                                Accessible.description: exampleTyped.text
                                // A tap anywhere on the row tries it, as
                                // its pill does.
                                MouseArea {
                                    id: exampleArea
                                    anchors.fill: parent
                                    onClicked: overlay.tryQuickAction(example.modelData.typed)
                                }
                                Column {
                                    id: exampleWords
                                    x: 12
                                    y: 12
                                    width: parent.width - 24 - tryExample.width - 12
                                    spacing: 2
                                    Label {
                                        width: parent.width
                                        text: example.modelData.title
                                        font.pixelSize: 15
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        id: exampleTyped
                                        objectName: example.objectName + "-typed"
                                        width: parent.width
                                        text: words.i18nc("@info what to type, in quotation marks", "“%1”", example.modelData.typed)
                                        opacity: 0.66
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                                PillButton {
                                    id: tryExample
                                    objectName: example.objectName + "-try"
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 32
                                    label: words.i18nc("@action:button puts a quick action's words in Search", "Try")
                                    Accessible.name: words.i18nc("@action:button a quick action's name", "Try %1", example.modelData.title)
                                    onActivated: overlay.tryQuickAction(example.modelData.typed)
                                }
                            }
                        }
                    }
                    PillButton {
                        objectName: "ambient-island-quick-actions-close"
                        label: words.i18n("Close")
                        onActivated: overlay.dismiss()
                    }
                }

                // Layouts, asked for from Search: each saved layout drawn
                // small with its Open pill, then Save what's open and Close.
                Column {
                    objectName: "ambient-island-layouts"
                    visible: overlay.kind === "layouts" && !overlay.savingLayout
                    width: parent.width
                    spacing: 12
                    CardTitle {
                        objectName: "ambient-island-layouts-title"
                        name: words.i18nc("@title the saved layouts", "Layouts")
                        after: overlay.savedLayouts.length > 0
                            ? words.i18ncp("@title after Layouts", " · %1 saved", " · %1 saved", overlay.savedLayouts.length) : ""
                        glyph: "panels-top-left"
                    }
                    Label {
                        objectName: "ambient-island-layouts-none"
                        width: parent.width
                        visible: overlay.savedLayouts.length === 0
                        text: overlay.layoutsAway > 0
                            ? words.i18np("Your layout needs a display that isn't connected. It comes back when the display does.",
                                          "Your %1 layouts need a display that isn't connected. They come back when the display does.",
                                          overlay.layoutsAway)
                            : words.i18n("Nothing saved yet. Arrange your apps, then save what's open.")
                        opacity: 0.66
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.savedLayouts
                            // One line each: the layout's picture, its name
                            // with its apps by icon and name, and Open.
                            delegate: Rectangle {
                                id: saved
                                required property var modelData
                                required property int index
                                readonly property bool chosen: overlay.chosenLayout === modelData.id
                                objectName: "ambient-island-layout-" + modelData.id
                                width: parent.width
                                height: Math.max(56, savedColumn.implicitHeight + 16)
                                radius: 10
                                color: tone.wash(savedArea.pressed ? 0.12 : 0.075)
                                Accessible.role: Accessible.ListItem
                                Accessible.name: modelData.name
                                // A tap on the row, off its pill, shows its own
                                // Remove.
                                MouseArea {
                                    id: savedArea
                                    anchors.fill: parent
                                    onClicked: overlay.chosenLayout = saved.chosen ? "" : saved.modelData.id
                                }
                                LayoutPicture {
                                    id: savedPicture
                                    objectName: "ambient-island-layout-miniature-" + saved.modelData.id
                                    x: 10
                                    y: 8
                                    width: 56
                                    height: 40
                                    groups: saved.modelData.groups || []
                                }
                                Column {
                                    id: savedColumn
                                    x: savedPicture.x + savedPicture.width + 10
                                    y: 8
                                    width: parent.width - x - 12 - openSaved.width - 10
                                    spacing: 4
                                    Label {
                                        objectName: "ambient-island-layout-name-" + saved.modelData.id
                                        width: parent.width
                                        text: saved.modelData.name
                                        font.pixelSize: 15
                                        elide: Text.ElideRight
                                    }
                                    Row {
                                        width: parent.width
                                        spacing: 4
                                        Repeater {
                                            model: (saved.modelData.groups || []).slice(0, 4)
                                            delegate: Kirigami.Icon {
                                                required property var modelData
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 16
                                                height: 16
                                                source: modelData.icons && modelData.icons[0] ? modelData.icons[0] : "application-x-executable"
                                            }
                                        }
                                        Label {
                                            objectName: "ambient-island-layout-apps-" + saved.modelData.id
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.max(0, parent.width - x)
                                            text: overlay.appsLine(saved.modelData.groups || [])
                                            font.pixelSize: 12
                                            opacity: 0.66
                                            elide: Text.ElideRight
                                        }
                                    }
                                    // Chosen: Pin to dock, where Shuffle's
                                    // dock is there, then Remove.
                                    // Under Open too, so both fit on one line.
                                    Flow {
                                        width: saved.width - savedColumn.x - 12
                                        spacing: 8
                                        visible: saved.chosen
                                        PillButton {
                                            readonly property bool pinned: overlay.dockLayouts.indexOf(saved.modelData.id) >= 0
                                            objectName: "ambient-island-layout-pin-" + saved.modelData.id
                                            visible: overlay.dockPinsLayouts
                                            height: 32
                                            label: pinned ? words.i18nc("@action:button takes a saved layout off the dock", "Unpin from dock")
                                                          : words.i18nc("@action:button puts a saved layout on the dock", "Pin to dock")
                                            onActivated: overlay.layouts.pinLayoutToDock(saved.modelData.id, !pinned)
                                        }
                                        PillButton {
                                            objectName: "ambient-island-layout-remove-" + saved.modelData.id
                                            height: 32
                                            label: words.i18nc("@action:button forgets a saved layout", "Remove")
                                            onActivated: {
                                                overlay.chosenLayout = "";
                                                if (overlay.layouts) overlay.layouts.removeLayout(saved.modelData.id);
                                            }
                                        }
                                    }
                                }
                                PillButton {
                                    id: openSaved
                                    objectName: "ambient-island-layout-open-" + saved.modelData.id
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    y: 12
                                    height: 32
                                    filled: saved.index === 0
                                    label: words.i18nc("@action:button opens a saved layout", "Open")
                                    Accessible.name: words.i18nc("@action:button a saved layout's name", "Open %1", saved.modelData.name)
                                    onActivated: overlay.openLayout(saved.modelData.id)
                                }
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-layouts-save"
                            filled: true
                            label: words.i18n("Save what's open")
                            onActivated: overlay.saveWhatsOpen()
                        }
                        PillButton {
                            objectName: "ambient-island-layouts-close"
                            label: words.i18n("Close")
                            onActivated: overlay.dismiss()
                        }
                    }
                }

                // The same island as a form: a name, what is open on this
                // workspace group by group, each with Remove; then Save and
                // Not now.
                Column {
                    objectName: "ambient-island-layout-form"
                    visible: overlay.kind === "layouts" && overlay.savingLayout
                    width: parent.width
                    spacing: 12
                    Row {
                        width: parent.width
                        Label {
                            id: formTitle
                            text: words.i18n("Save this layout")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Label {
                            objectName: "ambient-island-layout-form-where"
                            anchors.baseline: formTitle.baseline
                            width: parent.width - formTitle.width
                            text: overlay.workspaceName.length > 0
                                ? words.i18nc("@title after Save this layout, a workspace's name", " · what's open on %1", overlay.workspaceName)
                                : words.i18nc("@title after Save this layout", " · what's open")
                            opacity: 0.66
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 10
                        color: tone.wash(0.075)
                        border.width: layoutName.activeFocus ? 1 : 0
                        border.color: tone.wash(0.35)
                        TextInput {
                            id: layoutName
                            objectName: "ambient-island-layout-name"
                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            color: overlay.ink
                            font.pixelSize: 15
                            clip: true
                            selectByMouse: true
                            Accessible.role: Accessible.EditableText
                            Accessible.name: words.i18n("Name")
                            onAccepted: overlay.saveLayout()
                        }
                        Label {
                            anchors.left: layoutName.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: layoutName.text.length === 0
                            text: words.i18n("Name it, such as Coding")
                            font.pixelSize: 15
                            opacity: 0.45
                        }
                    }
                    Label {
                        objectName: "ambient-island-layout-form-empty"
                        width: parent.width
                        visible: overlay.keptGroups.length === 0
                        text: overlay.currentRead ? words.i18n("Nothing open here to save. Arrange your apps, then come back.")
                            : words.i18n("Looking at what's open…")
                        opacity: 0.66
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.keptGroups
                            delegate: Rectangle {
                                id: kept
                                required property var modelData
                                required property int index
                                readonly property var names: modelData.names || modelData.apps || []
                                objectName: "ambient-island-layout-group-" + index
                                width: parent.width
                                height: Math.max(44, keptWords.implicitHeight + 24)
                                radius: 10
                                color: tone.wash(0.075)
                                Column {
                                    id: keptWords
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24 - removeGroup.width - 12
                                    spacing: 2
                                    Label {
                                        objectName: "ambient-island-layout-group-title-" + kept.index
                                        width: parent.width
                                        text: kept.modelData.stack ? words.i18nc("@info apps together in one Stack", "Stack") : kept.names[0] || ""
                                        font.pixelSize: 15
                                    }
                                    Label {
                                        objectName: "ambient-island-layout-group-line-" + kept.index
                                        width: parent.width
                                        text: kept.modelData.stack ? kept.names.join(words.i18nc("@info between apps in a Stack", ", "))
                                            : words.i18nc("@info an app not in a Stack", "On its own")
                                        opacity: 0.66
                                    }
                                }
                                PillButton {
                                    id: removeGroup
                                    objectName: "ambient-island-layout-group-remove-" + kept.index
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 32
                                    label: words.i18nc("@action:button takes a group out of the layout", "Remove")
                                    onActivated: overlay.keptGroups = overlay.keptGroups.filter((group, at) => at !== kept.index)
                                }
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-layout-form-save"
                            filled: true
                            opacity: overlay.canSave ? 1 : 0.4
                            label: words.i18nc("@action:button saves the layout", "Save")
                            onActivated: overlay.saveLayout()
                        }
                        PillButton {
                            objectName: "ambient-island-layout-form-not-now"
                            label: words.i18n("Not now")
                            onActivated: overlay.dismiss()
                        }
                    }
                }

                // The quick note, grown from the + where Search's Notes used
                // to take the screen: the paper in the note's colour, its
                // choices under it, then Done and Open in Notes. It writes
                // through the notes application as Search does, so either
                // carries on the same note.
                Column {
                    objectName: "ambient-island-note"
                    visible: overlay.kind === "note"
                    width: parent.width
                    spacing: 12

                    CardTitle {
                        objectName: "ambient-island-note-title"
                        name: words.i18nc("@title the open quick note island", "Quick note")
                        after: overlay.quickNote && overlay.quickNote.offersFolders && overlay.quickNote.folderLabel
                            ? words.i18nc("@title after Quick note: where it is kept", " · %1", overlay.quickNote.folderLabel) : ""
                        swatch: overlay.noteHex
                    }

                    Rectangle {
                        id: paper
                        objectName: "ambient-island-note-paper"
                        width: parent.width
                        height: Math.min(220, Math.max(120, (overlay.quickNote && overlay.quickNote.checklist
                            ? noteLineColumn.height : notePad.contentHeight) + 28))
                        radius: 10
                        color: overlay.noteHex
                        clip: true
                        Behavior on color { ColorAnimation { duration: overlay.ms(160) } }
                        readonly property color ink: "#1A1A1A"

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 14
                            visible: !overlay.quickNote || !overlay.quickNote.checklist
                            contentHeight: notePad.contentHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: notePad
                                objectName: "ambient-island-note-pad"
                                width: parent.width
                                color: paper.ink
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                selectByMouse: true
                                selectionColor: "#40000000"
                                selectedTextColor: paper.ink
                                readOnly: !overlay.noteWritable
                                Accessible.role: Accessible.EditableText
                                Accessible.name: words.i18n("Note")
                                // Typing is the person's; a change kept
                                // elsewhere arrives only while it isn't typed.
                                onTextChanged: {
                                    if (!activeFocus || !overlay.noteWritable || text === overlay.quickNote.text) return;
                                    overlay.noteTyped = true;
                                    overlay.quickNote.setText(text);
                                }
                                Text {
                                    visible: notePad.text.length === 0
                                    text: words.i18n("Write it down…")
                                    color: "#73000000"
                                    font: notePad.font
                                }
                            }
                        }

                        Flickable {
                            id: noteLines
                            objectName: "ambient-island-note-checklist"
                            anchors.fill: parent
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            visible: !!overlay.quickNote && overlay.quickNote.checklist
                            contentHeight: noteLineColumn.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            readonly property bool typing: {
                                for (let i = 0; i < noteLineRepeater.count; ++i) {
                                    const item = noteLineRepeater.itemAt(i);
                                    if (item && item.typing) return true;
                                }
                                return false;
                            }
                            function focusRow(index, at) {
                                Qt.callLater(() => {
                                    const item = noteLineRepeater.itemAt(index);
                                    if (item) item.focusAt(at === undefined ? -1 : at);
                                });
                            }
                            Column {
                                id: noteLineColumn
                                width: parent.width
                                Repeater {
                                    id: noteLineRepeater
                                    model: noteLineModel
                                    delegate: Item {
                                        id: line
                                        required property int index
                                        required property string text
                                        required property bool item
                                        required property bool checked
                                        readonly property bool typing: lineInput.activeFocus
                                        function focusAt(position) {
                                            lineInput.forceActiveFocus();
                                            lineInput.cursorPosition = position < 0 ? lineInput.length : position;
                                        }
                                        objectName: "ambient-island-note-line-" + index
                                        width: noteLineColumn.width
                                        height: Math.max(40, lineInput.contentHeight + 12)
                                        Item {
                                            objectName: "ambient-island-note-box-" + line.index
                                            visible: line.item
                                            x: 4
                                            width: 40
                                            height: 40
                                            Accessible.role: Accessible.CheckBox
                                            Accessible.name: line.text
                                            Accessible.checked: line.checked
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 20
                                                height: 20
                                                radius: 6
                                                color: line.checked ? paper.ink : "transparent"
                                                border.width: 2
                                                border.color: paper.ink
                                                SuiteIcon {
                                                    anchors.centerIn: parent
                                                    visible: line.checked
                                                    width: 14
                                                    height: 14
                                                    glyph: "check"
                                                }
                                            }
                                            TapHandler {
                                                enabled: overlay.noteWritable
                                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                                onTapped: {
                                                    noteLineModel.setProperty(line.index, "checked", !line.checked);
                                                    overlay.quickNote.setLineChecked(line.index, line.checked);
                                                }
                                            }
                                        }
                                        TextEdit {
                                            id: lineInput
                                            x: line.item ? 48 : 14
                                            width: parent.width - x - 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: line.text
                                            color: paper.ink
                                            opacity: line.checked ? 0.5 : 1
                                            font.pixelSize: 16
                                            font.weight: Font.DemiBold
                                            font.strikeout: line.checked
                                            wrapMode: TextEdit.Wrap
                                            textFormat: TextEdit.PlainText
                                            selectByMouse: true
                                            readOnly: !overlay.noteWritable
                                            Accessible.role: Accessible.EditableText
                                            Accessible.name: words.i18n("Line")
                                            onTextChanged: {
                                                if (!activeFocus || text === line.text) return;
                                                noteLineModel.setProperty(line.index, "text", text);
                                                overlay.sendNoteLines();
                                            }
                                            // Enter makes a new item of what follows the cursor.
                                            Keys.onReturnPressed: event => line.split(event)
                                            Keys.onEnterPressed: event => line.split(event)
                                            Keys.onPressed: event => {
                                                if (event.key !== Qt.Key_Backspace || lineInput.cursorPosition > 0
                                                    || lineInput.selectedText !== "" || line.index === 0) return;
                                                event.accepted = true;
                                                const before = noteLineModel.get(line.index - 1).text;
                                                const at = line.index - 1;
                                                noteLineModel.setProperty(at, "text", before + lineInput.text);
                                                noteLineModel.remove(line.index);
                                                overlay.sendNoteLines();
                                                noteLines.focusRow(at, before.length);
                                            }
                                        }
                                        function split(event) {
                                            event.accepted = true;
                                            const head = lineInput.text.slice(0, lineInput.cursorPosition);
                                            const tail = lineInput.text.slice(lineInput.cursorPosition);
                                            noteLineModel.setProperty(line.index, "text", head);
                                            noteLineModel.insert(line.index + 1, { text: tail, item: true, checked: false });
                                            overlay.sendNoteLines();
                                            noteLines.focusRow(line.index + 1, 0);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The note's choices, as on Search's note page: its
                    // colour, the checklist, a reminder and the window it is
                    // stuck to. Picking a time, folders and More stay on the
                    // full note.
                    Flow {
                        objectName: "ambient-island-note-choices"
                        width: parent.width
                        spacing: 8
                        enabled: overlay.noteWritable
                        PillButton {
                            objectName: "ambient-island-note-colour"
                            height: 32
                            label: words.i18n("Colour")
                            onActivated: overlay.noteChoosing = overlay.noteChoosing === "colour" ? "" : "colour"
                        }
                        PillButton {
                            objectName: "ambient-island-note-checklist-toggle"
                            height: 32
                            visible: !!overlay.quickNote && overlay.quickNote.offersReminders
                            label: words.i18n("Checklist")
                            filled: !!overlay.quickNote && overlay.quickNote.checklist
                            onActivated: {
                                overlay.noteChoosing = "";
                                overlay.quickNote.flush();
                                overlay.quickNote.setChecklist(!overlay.quickNote.checklist);
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-note-remind"
                            height: 32
                            visible: !!overlay.quickNote && overlay.quickNote.offersReminders
                            label: overlay.quickNote && overlay.quickNote.remindLabel !== ""
                                ? overlay.quickNote.remindLabel : words.i18n("Remind")
                            onActivated: overlay.noteChoosing = overlay.noteChoosing === "remind" ? "" : "remind"
                        }
                        PillButton {
                            objectName: "ambient-island-note-window"
                            height: 32
                            visible: !!overlay.quickNote && (overlay.quickNote.windows || []).length > 0
                            label: {
                                if (!overlay.quickNote || !overlay.quickNote.stuck) return words.i18n("Stick to a window");
                                const windows = overlay.quickNote.windows || [];
                                for (const window of windows)
                                    if (window.chosen) return words.i18n("Stuck to %1", window.label || window.window || "");
                                return words.i18n("Stuck to %1", overlay.quickNote.stuckWindow);
                            }
                            onActivated: overlay.noteChoosing = overlay.noteChoosing === "window" ? "" : "window"
                        }
                    }

                    // The choices of the one asked for.
                    Flow {
                        objectName: "ambient-island-note-colours"
                        visible: overlay.noteChoosing === "colour"
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: overlay.quickNote ? overlay.quickNote.colours : []
                            delegate: Item {
                                id: swatch
                                required property string modelData
                                required property int index
                                readonly property bool chosen: overlay.quickNote !== null && overlay.quickNote.colour === modelData
                                objectName: "ambient-island-note-swatch-" + modelData
                                width: 40
                                height: 40
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData
                                Accessible.checked: chosen
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: "transparent"
                                    border.width: 2
                                    border.color: overlay.ink
                                    visible: swatch.chosen
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: overlay.quickNote ? (overlay.quickNote.colourHexes[swatch.index] || "#888888") : "#888888"
                                }
                                TapHandler {
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: {
                                        overlay.quickNote.setColour(swatch.modelData);
                                        overlay.noteChoosing = "";
                                    }
                                }
                            }
                        }
                    }
                    Flow {
                        objectName: "ambient-island-note-remind-choices"
                        visible: overlay.noteChoosing === "remind"
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.quickNote ? (overlay.quickNote.remindChoices || []).filter(choice => choice.kind !== "pick") : []
                            delegate: PillButton {
                                required property var modelData
                                objectName: "ambient-island-note-remind-" + (modelData.kind || "")
                                height: 32
                                label: modelData.label || ""
                                onActivated: {
                                    overlay.quickNote.setReminder(modelData.kind === "opens" ? "opens" : (modelData.time || ""));
                                    overlay.noteChoosing = "";
                                }
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-note-no-reminder"
                            height: 32
                            visible: !!overlay.quickNote && overlay.quickNote.remindLabel !== ""
                            label: words.i18n("No reminder")
                            onActivated: {
                                overlay.quickNote.setReminder("");
                                overlay.noteChoosing = "";
                            }
                        }
                    }
                    Flow {
                        objectName: "ambient-island-note-window-choices"
                        visible: overlay.noteChoosing === "window"
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: overlay.quickNote ? overlay.quickNote.windows || [] : []
                            delegate: PillButton {
                                required property var modelData
                                required property int index
                                objectName: "ambient-island-note-window-" + index
                                height: 32
                                filled: !!modelData.chosen
                                label: modelData.label || modelData.window || ""
                                onActivated: {
                                    overlay.quickNote.setStuck(modelData.window || "", modelData.app || "");
                                    overlay.noteChoosing = "";
                                }
                            }
                        }
                        PillButton {
                            objectName: "ambient-island-note-dont-stick"
                            height: 32
                            visible: !!overlay.quickNote && overlay.quickNote.stuck
                            label: words.i18n("Don't stick to a window")
                            onActivated: {
                                overlay.quickNote.setStuck("", "");
                                overlay.noteChoosing = "";
                            }
                        }
                    }

                    // Done first and filled, then the full note.
                    Flow {
                        objectName: "ambient-island-note-actions"
                        width: parent.width
                        spacing: 8
                        PillButton {
                            objectName: "ambient-island-note-done"
                            filled: true
                            label: words.i18n("Done")
                            onActivated: overlay.finishNote()
                        }
                        PillButton {
                            objectName: "ambient-island-note-in-notes"
                            label: words.i18n("Open in Notes")
                            onActivated: overlay.noteInNotes()
                        }
                    }
                }

                // Transfers, each with its own progress and actions.
                Column {
                    objectName: "ambient-island-transfers"
                    visible: overlay.kind === "transfer"
                    width: parent.width
                    spacing: 6
                    CardTitle {
                        objectName: "ambient-island-transfers-title"
                        name: words.i18nc("@title the open transfers island", "Transfers")
                        after: overlay.surface && overlay.surface.transfers.length > 0
                            ? words.i18ncp("@title after Transfers", " · %1 file", " · %1 files", overlay.surface.transfers.length) : ""
                        glyph: "download"
                    }
                    // Counted rather than listed: each update is a new list, and a
                    // Repeater given a new list makes every row again, whose ring
                    // then draws from blank. Rows stay while the count holds.
                    Repeater {
                        model: overlay.surface ? overlay.surface.transfers.length : 0
                        delegate: Column {
                            id: row
                            required property int index
                            readonly property var modelData: overlay.surface && overlay.surface.transfers[index]
                                ? overlay.surface.transfers[index] : ({})
                            objectName: "ambient-island-transfer-" + modelData.id
                            readonly property bool suspended: modelData.state === "suspended"
                            width: content.width
                            spacing: 4
                            Row {
                                width: parent.width
                                height: 56
                                spacing: 10
                                Progress {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40
                                    height: 40
                                    activity: row.modelData
                                    showNumber: true
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: row.width - 50 - (pauseButton.visible ? 54 : 0) - (cancelButton.visible ? 54 : 0)
                                    Label {
                                        width: parent.width
                                        text: overlay.surface ? overlay.surface.transferTitle(row.modelData) : ""
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        width: parent.width
                                        text: row.suspended ? words.i18n("Paused")
                                            : overlay.surface && overlay.surface.ended(row.modelData) ? row.modelData.description || ""
                                            : row.modelData.evidence === "filesystem" ? words.i18n("Incoming file · completion unknown")
                                            : overlay.surface ? overlay.surface.transferBytes(row.modelData) || overlay.surface.percentage(row.modelData) : ""
                                        color: row.suspended ? tone.waitingText : overlay.ink
                                        opacity: row.suspended ? 1 : 0.66
                                        font.pixelSize: 12
                                    }
                                }
                                GlyphButton {
                                    id: pauseButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: overlay.surface !== null && overlay.surface.capability(row.modelData, row.suspended ? "resume" : "suspend")
                                    glyph: row.suspended ? "play" : "pause"
                                    label: row.suspended ? words.i18n("Resume") : words.i18n("Pause transfer")
                                    onActivated: overlay.surface.invoke(row.modelData, row.suspended ? "resume" : "suspend")
                                }
                                GlyphButton {
                                    id: cancelButton
                                    objectName: "ambient-island-cancel-" + row.modelData.id
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "cancel")
                                    glyph: "x"
                                    label: words.i18n("Cancel %1", overlay.surface ? overlay.surface.transferTitle(row.modelData) : "")
                                    onActivated: overlay.surface.invoke(row.modelData, "cancel")
                                }
                            }
                            PillButton {
                                objectName: "ambient-island-show-" + row.modelData.id
                                anchors.right: parent.right
                                visible: overlay.surface !== null && overlay.surface.capability(row.modelData, "showInFiles")
                                label: words.i18n("Show in Files")
                                onActivated: {
                                    overlay.surface.invoke(row.modelData, "showInFiles");
                                    overlay.dismiss();
                                }
                            }
                        }
                    }
                    PillButton {
                        objectName: "ambient-island-transfers-close"
                        label: words.i18n("Close")
                        onActivated: overlay.dismiss()
                    }
                }
            }
        }
    }
}
