/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.ki18n
import org.kde.kirigami as Kirigami

pragma ComponentBehavior: Bound

// Notes, one of Search's modes, in two views. The board is a search over
// every note: a field that finds or starts a note, a row of filters and the
// notes grouped under them. A note is the page: paper of its colour filling
// the room, its colour a dot in its corner, and one quiet line under it with
// where it is kept, the window it is stuck to, Checklist, Remind and More.
// The notes application keeps every note; this draws them.
Item {
    id: pane

    required property var quickNote
    // How far the mode has opened, 0 to 1, on the drawer's own easing.
    required property real progress
    // Where the search field rests, which the mode grows out of.
    required property rect fieldRest
    SearchColors {
        id: tone
        theme: pane.Kirigami.Theme
    }
    property color surfaceColor: tone.surface
    property color surfaceOutline: tone.outline
    property color controlColor: tone.control
    property color primaryText: tone.primaryText
    property bool growing: false
    // Whether Search fills the screen, which Expand changes.
    property bool expanded: false

    signal expand()
    signal grow()
    signal dismiss()
    signal finished()

    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp(v) { return Math.max(0, Math.min(1, v)) }

    KI18nContext {
        id: words
        translationDomain: "tettegouche"
    }

    // "board" or "page".
    property string view: "board"
    // Whether the page was opened from the board, so Back returns to it.
    property bool fromBoard: false
    // 0 on the board, 1 on the page, eased between them.
    property real pageShown: view === "page" ? 1 : 0
    Behavior on pageShown {
        enabled: pane.progress > 0.99
        NumberAnimation { duration: Math.max(1, Kirigami.Units.longDuration); easing.type: Easing.OutCubic }
    }

    // Opens the mode on a view: the board, or the page with the note Start
    // began or resumed.
    function enter(which) {
        closeOpen()
        fromBoard = false
        view = which
        if (which === "page") {
            // The note Start resumes is drawn at once; a new one once it
            // arrives.
            loading = quickNote && !quickNote.open ? "open" : ""
            if (loading === "" && quickNote) {
                pad.text = quickNote.text
                syncLines()
            }
            focusPad()
        } else {
            find.text = ""
            filter = "everything"
            picked = -1
            if (quickNote) quickNote.findNotes("")
            focusFind()
        }
    }
    function showBoard() {
        closeOpen()
        if (quickNote) {
            quickNote.flush()
            quickNote.findNotes(find.text.trim())
        }
        view = "board"
        focusFind()
    }
    // A note from the board, or a new one with the words typed, goes to
    // Gooseberry's own card and Search closes; where the card cannot take
    // it, it opens on the page here. From the board, the card leads back to
    // Notes.
    property var handing: null
    function openNote(noteId, alone) {
        if (!quickNote || noteId === "") return
        handing = { id: noteId, alone: !!alone }
        quickNote.openOnCard(noteId, alone ? "" : words.i18n("Notes"))
    }
    function startNote(text, alone) {
        if (!quickNote) return
        handing = { text: text, alone: !!alone }
        quickNote.startOnCard(text, alone ? "" : words.i18n("Notes"))
    }
    Connections {
        target: pane.quickNote
        ignoreUnknownSignals: true
        function onCardAnswered(opened) {
            const handed = pane.handing
            if (!handed) return
            pane.handing = null
            if (opened) {
                find.text = ""
                pane.finished()
            } else if (handed.id !== undefined) {
                pane.openHere(handed.id, handed.alone)
            } else {
                pane.startHere(handed.text, handed.alone)
            }
        }
    }
    // A note from the board, made the open one. Alone, as the panel's pinned
    // note opens it, the page has no Back and leaving it closes Search.
    function openHere(noteId, alone) {
        if (!quickNote || noteId === "") return
        closeOpen()
        loading = "id:" + noteId
        fromBoard = !alone
        view = "page"
        quickNote.edit(noteId)
        focusPad()
    }
    // A new note, with the words typed into the find field, or alone, empty,
    // as the panel's dot starts one.
    function startHere(text, alone) {
        if (!quickNote) return
        closeOpen()
        loading = "text:" + text
        fromBoard = !alone
        view = "page"
        pad.text = text
        quickNote.startWith(text)
        focusPad()
    }
    function focusPad() {
        if (pane.quickNote && pane.quickNote.checklist && checkModel.count > 0) checkRows.focusRow(checkModel.count - 1)
        else {
            pad.forceActiveFocus()
            pad.cursorPosition = pad.length
        }
    }
    function focusFind() { find.forceActiveFocus() }

    // What is open over or under the page: "colour", "folder", "window",
    // "remind", "pick", "more" or nothing.
    property string choosing: ""
    function choose(which) {
        choosing = choosing === which ? "" : which
        newFolder.text = ""
        pickDay = -1
    }
    // Closes whatever is open; true when something was.
    function closeOpen() {
        const open = choosing !== ""
        choosing = ""
        newFolder.text = ""
        pickDay = -1
        return open
    }
    function closeChoices() {
        closeOpen()
        focusPad()
    }

    // The note being opened, until its state arrives: "open", "id:<note>"
    // or "text:<words>"; the pad takes no typing meanwhile.
    property string loading: ""
    function noteArrived() {
        if (!quickNote || !quickNote.open) return
        if (loading.startsWith("id:") && quickNote.noteId !== loading.slice(3)) return
        if (loading.startsWith("text:") && quickNote.text !== loading.slice(5)) return
        loading = ""
        pad.text = quickNote.text
        syncLines()
        focusPad()
    }

    // A note that never arrives, refused or lost, leaves the page as the
    // application last gave it, with what is wrong under it.
    onLoadingChanged: if (loading !== "") loadingWait.restart()
    Timer {
        id: loadingWait
        interval: 3000
        onTriggered: {
            if (pane.loading === "") return
            pane.loading = ""
            if (pane.quickNote) pad.text = pane.quickNote.text
            pane.syncLines()
        }
    }

    readonly property real headerHeight: 44
    readonly property real bodyTop: headerHeight + 14
    // Folder and Stuck to, where Gooseberry offers them; an older one offers
    // Belongs to instead.
    readonly property bool chips: !!quickNote && quickNote.offersFolders
    readonly property string stuckLabel: {
        if (!quickNote || !quickNote.stuck) return ""
        const windows = quickNote.windows || []
        for (let i = 0; i < windows.length; ++i)
            if (windows[i].chosen) return windows[i].label || windows[i].window || ""
        return quickNote.stuckWindow
    }
    readonly property bool trouble: !!quickNote && (quickNote.problem !== "" || quickNote.readOnly)
    readonly property bool writable: !!quickNote && !quickNote.readOnly && loading === ""

    // Under the page: a row of choices when one is open, Belongs to with an
    // older Gooseberry, and the quiet line.
    readonly property bool rowOpen: ["folder", "window", "remind", "pick"].indexOf(choosing) >= 0
    readonly property real lowerHeight: 8 + (rowOpen ? 40 + 8 : 0) + (chips ? 0 : 40 + 8) + 44
    readonly property rect pageEnd: Qt.rect(0, bodyTop, width, Math.max(60, height - bodyTop - lowerHeight))
    // The find field stands where Search's field does, so only what is
    // under it changes.
    readonly property rect findEnd: Qt.rect(fieldRest.x, fieldRest.y, fieldRest.width, Math.max(56, fieldRest.height))
    // The note is paper of its own colour on any ground, with dark ink.
    readonly property string noteHex: quickNote && quickNote.colourHex !== "" ? quickNote.colourHex : "#F2D98A"
    readonly property color ink: "#1A1A1A"

    visible: progress > 0.001
    enabled: progress > 0.9 && !growing
    onProgressChanged: if (progress < 0.001) closeOpen()
    onChipsChanged: if (!chips && (choosing === "folder" || choosing === "window")) choosing = ""

    // Esc closes what is open on the page, then returns from the page to the
    // board it came from, and then is Search's.
    Keys.onEscapePressed: event => {
        if (closeOpen()) {
            if (view === "page") focusPad()
            return
        }
        if (view === "page" && fromBoard) {
            showBoard()
            return
        }
        event.accepted = false
    }

    Connections {
        target: pane.quickNote
        function onNoteChanged() {
            if (pane.loading !== "") {
                pane.noteArrived()
                return
            }
            if (!pad.activeFocus && pad.text !== pane.quickNote.text) pad.text = pane.quickNote.text
            if (!checkRows.typing) pane.syncLines()
        }
    }

    // ── The board ────────────────────────────────────────────────────────

    // "everything", "today", "windows", "tucked" or "folder:<name>".
    property string filter: "everything"
    // The row chosen with the arrow keys, which Enter opens; -1 is none, and
    // Enter starts a note.
    property int picked: -1

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function remindTime(note) {
        if (!note.remind || note.remind === "opens") return null
        const at = new Date(note.remind)
        return isNaN(at.getTime()) ? null : at
    }
    function isToday(note) {
        const now = new Date()
        const at = remindTime(note)
        if (at && sameDay(at, now)) return true
        const changed = new Date(note.changed)
        return !isNaN(changed.getTime()) && sameDay(changed, now)
    }
    function when(note) {
        const now = new Date()
        const at = remindTime(note)
        if (at && sameDay(at, now)) return Qt.formatTime(at, Qt.locale().timeFormat(Locale.ShortFormat))
        const changed = new Date(note.changed)
        if (isNaN(changed.getTime())) return ""
        if (sameDay(changed, now)) return words.i18n("Today")
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate())
            - new Date(changed.getFullYear(), changed.getMonth(), changed.getDate())) / 86400000)
        if (days === 1) return words.i18n("Yesterday")
        if (days < 7) return Qt.locale().dayName(changed.getDay(), Locale.LongFormat)
        if (changed.getFullYear() === now.getFullYear()) return Qt.locale().monthName(changed.getMonth(), Locale.LongFormat)
        return String(changed.getFullYear())
    }
    function detail(note) {
        const parts = []
        const at = remindTime(note)
        const today = at && sameDay(at, new Date())
        if (today) parts.push(when(note))
        parts.push(note.folderLabel || words.i18n("Inbox"))
        if (note.stuck) parts.push(words.i18n("Stuck to %1", note.window || ""))
        else if (!today) parts.push(when(note))
        return parts.join(" · ")
    }
    function escaped(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // The words found, underlined where the search found them.
    // Styled text in a colour of its own.
    function tinted(styled, colour) {
        return "<font color='%1'>%2</font>".arg(colour).arg(styled)
    }
    function marked(text, needle) {
        if (needle === "") return escaped(text)
        const at = text.toLowerCase().indexOf(needle.toLowerCase())
        if (at < 0) return escaped(text)
        return escaped(text.slice(0, at)) + "<u>" + escaped(text.slice(at, at + needle.length)) + "</u>"
            + escaped(text.slice(at + needle.length))
    }

    // The folders the notes are kept in, in the order their newest notes
    // came; Inbox among them where a note is kept there.
    readonly property var folderList: {
        const seen = {}
        const list = []
        const notes = quickNote ? quickNote.notes || [] : []
        for (let i = 0; i < notes.length; ++i) {
            const note = notes[i]
            if (note.tucked) continue
            const name = note.folder || ""
            if (seen[name] === undefined) {
                seen[name] = list.length
                list.push({ name: name, label: note.folderLabel || words.i18n("Inbox"), count: 0 })
            }
            list[seen[name]].count++
        }
        return list
    }
    // The board's rows: a heading, a note, or a folder the words name.
    readonly property var rows: {
        const notes = quickNote ? quickNote.notes || [] : []
        const needle = quickNote ? quickNote.notesWords : ""
        const chosen = notes.filter(note => {
            if (filter === "tucked") return note.tucked
            if (note.tucked) return false
            if (filter === "today") return isToday(note)
            if (filter === "windows") return note.stuck
            if (filter.startsWith("folder:")) return (note.folder || "") === filter.slice(7)
            return true
        })
        const groups = filter === "everything" || filter.startsWith("folder:")
            ? [{ label: words.i18n("Today"), take: n => isToday(n) },
               { label: words.i18n("On windows"), take: n => n.stuck },
               { label: words.i18n("Notes"), take: n => true }]
            : [{ label: "", take: n => true }]
        const out = []
        const placed = {}
        for (const group of groups) {
            const members = chosen.filter(n => !placed[n.id] && group.take(n))
            if (members.length === 0) continue
            if (group.label !== "" && (groups.length > 1)) out.push({ kind: "heading", label: group.label })
            for (const note of members) {
                placed[note.id] = true
                out.push({ kind: "note", note: note, needle: needle })
            }
        }
        if (needle !== "" && filter === "everything") {
            const named = folderList.filter(f => f.label.toLowerCase().indexOf(needle.toLowerCase()) >= 0)
            if (named.length > 0) out.push({ kind: "heading", label: words.i18n("Folders") })
            for (const folder of named) out.push({ kind: "folder", folder: folder, needle: needle })
        }
        return out
    }
    onRowsChanged: picked = -1
    function pickable(index) { return index >= 0 && index < rows.length && rows[index].kind !== "heading" }
    function movePick(step) {
        let at = picked
        do { at += step } while (at >= 0 && at < rows.length && !pickable(at))
        if (pickable(at)) {
            picked = at
            list.positionViewAtIndex(at, ListView.Contain)
        } else if (step < 0) {
            picked = -1
        }
    }
    function activate(row) {
        if (!row) return
        if (row.kind === "note") openNote(row.note.id)
        else if (row.kind === "folder") {
            filter = "folder:" + row.folder.name
            find.text = ""
        }
    }

    Item {
        id: board
        objectName: "notes-board"
        anchors.fill: parent
        visible: pane.pageShown < 0.999
        opacity: 1 - pane.pageShown
        enabled: pane.view === "board"

        // The find field: from the search field's place to its own.
        Rectangle {
            id: findFrame
            objectName: "notes-find-frame"
            x: pane.lerp(pane.fieldRest.x, pane.findEnd.x, pane.progress)
            y: pane.lerp(pane.fieldRest.y, pane.findEnd.y, pane.progress)
            width: pane.lerp(pane.fieldRest.width, pane.findEnd.width, pane.progress)
            height: pane.lerp(pane.fieldRest.height, pane.findEnd.height, pane.progress)
            radius: height / 2
            color: pane.controlColor
            SuiteIcon {
                id: findGlyph
                glyph: "search"
                x: 20
                anchors.verticalCenter: parent.verticalCenter
            }
            QQC2.TextField {
                id: find
                objectName: "notes-find"
                anchors.left: findGlyph.right
                anchors.leftMargin: 12
                anchors.right: findHint.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: pane.primaryText
                font.pixelSize: 20
                font.weight: Font.Medium
                placeholderText: words.i18n("Find or start a note")
                placeholderTextColor: tone.placeholderText
                Accessible.name: words.i18n("Find or start a note")
                onTextChanged: findPause.restart()
                Keys.onDownPressed: pane.movePick(1)
                Keys.onUpPressed: pane.movePick(-1)
                onAccepted: {
                    if (pane.pickable(pane.picked)) pane.activate(pane.rows[pane.picked])
                    else pane.startNote(text.trim())
                }
            }
            Text {
                id: findHint
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: pane.pickable(pane.picked) ? words.i18n("Enter opens") : ""
                color: tone.edgeText
                font.pixelSize: 13
                font.weight: Font.DemiBold
                opacity: pane.clamp((pane.progress - 0.72) / 0.28)
            }
            Timer {
                id: findPause
                interval: 120
                onTriggered: if (pane.quickNote) pane.quickNote.findNotes(find.text.trim())
            }
        }

        // The filters: everything, today, on windows, each folder, and
        // Tucked away, quieter, last.
        Flickable {
            id: filters
            objectName: "notes-filters"
            x: 0
            y: pane.findEnd.y + pane.findEnd.height + 12
            width: pane.width
            height: 44
            contentWidth: filterRow.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            opacity: pane.clamp((pane.progress - 0.5) / 0.5)
            transform: Translate { y: 20 * (1 - pane.progress) }
            Row {
                id: filterRow
                spacing: 4
                Filter { key: "everything"; label: words.i18n("Everything") }
                Filter { key: "today"; label: words.i18n("Today") }
                Filter { key: "windows"; label: words.i18n("On windows") }
                Repeater {
                    model: pane.folderList
                    delegate: Filter {
                        required property var modelData
                        key: "folder:" + modelData.name
                        label: modelData.label
                    }
                }
                Filter { key: "tucked"; label: words.i18n("Tucked away"); quiet: true }
            }
        }

        ListView {
            id: list
            objectName: "notes-list"
            x: 0
            y: filters.y + filters.height + 16
            width: pane.width
            // Wide, a row shows more: the note's words under its title, and
            // where it is and when at its end.
            readonly property bool wide: width >= 640
            // Clear of the floating New note.
            footer: Item { width: 1; height: 80 }
            height: Math.max(0, pane.height - y)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pane.rows
            opacity: pane.clamp((pane.progress - 0.5) / 0.5)
            transform: Translate { y: 20 * (1 - pane.progress) }
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool heading: modelData.kind === "heading"
                readonly property bool isNote: modelData.kind === "note"
                objectName: isNote ? "notes-row-" + modelData.note.id
                    : heading ? "notes-heading-" + index : "notes-folder-row-" + (modelData.folder.name || "inbox")
                width: ListView.view.width
                height: heading ? 36 : list.wide && isNote ? 72 : 56
                Accessible.role: heading ? Accessible.Heading : Accessible.Button
                Accessible.name: heading ? modelData.label : isNote ? modelData.note.title : modelData.folder.label
                Accessible.onPressAction: pane.activate(row.modelData)

                Text {
                    visible: row.heading
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: row.heading ? row.modelData.label : ""
                    color: tone.edgeText
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                Rectangle {
                    visible: !row.heading
                    anchors.fill: parent
                    radius: 8
                    color: pane.picked === row.index ? tone.current : rowTap.pressed ? tone.tilePressed
                        : rowHover.hovered ? tone.hover : "transparent"
                }
                Rectangle {
                    visible: row.isNote
                    x: list.wide ? 12 : 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: list.wide ? 28 : 24; height: width; radius: 6
                    color: row.isNote ? (row.modelData.note.colourHex || "#D9D4CC") : "transparent"
                }
                Rectangle {
                    visible: row.modelData.kind === "folder"
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 6
                    color: pane.controlColor
                    SuiteIcon {
                        anchors.centerIn: parent
                        glyph: "folder"
                        width: 16; height: 16
                    }
                }
                Column {
                    visible: !row.heading
                    x: 52
                    width: parent.width - x - (rowEnd.visible ? rowEnd.width + 24 : 12)
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: row.isNote ? pane.marked(row.modelData.note.title || words.i18n("Empty note"), row.modelData.needle)
                            : row.heading ? "" : pane.marked(row.modelData.folder.label, row.modelData.needle)
                                + " " + pane.tinted(words.i18np("%1 note", "%1 notes", row.modelData.folder.count), tone.edgeText)
                        color: pane.primaryText
                        opacity: row.isNote && row.modelData.note.done ? 0.6 : 1
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }
                    Text {
                        visible: row.isNote
                        width: parent.width
                        elide: Text.ElideRight
                        text: !row.isNote ? ""
                            : list.wide ? (row.modelData.note.excerpt || "")
                            : (row.modelData.note.excerpt ? row.modelData.note.excerpt + " · " : "")
                                + pane.detail(row.modelData.note)
                        color: list.wide ? tone.secondaryText : tone.edgeText
                        font.pixelSize: list.wide ? 13 : 12
                    }
                }
                Column {
                    id: rowEnd
                    objectName: "notes-row-end"
                    visible: row.isNote && list.wide
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 220
                    spacing: 2
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: row.isNote ? [row.modelData.note.folderLabel || words.i18n("Inbox"),
                            row.modelData.note.stuck ? words.i18n("Stuck to %1", row.modelData.note.window || "") : ""]
                            .filter(part => part.length > 0).join(" · ") : ""
                        color: tone.edgeText
                        font.pixelSize: 12
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: row.isNote ? pane.when(row.modelData.note) : ""
                        color: tone.edgeText
                        font.pixelSize: 12
                    }
                }
                HoverHandler {
                    id: rowHover
                    enabled: !row.heading
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: rowTap
                    enabled: !row.heading
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: pane.activate(row.modelData)
                }
            }
            Text {
                objectName: "notes-empty"
                visible: pane.rows.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24
                text: find.text.trim() !== "" ? words.i18n("No note says that. Enter starts one.")
                    : pane.filter === "tucked" ? words.i18n("Nothing is tucked away.")
                    : words.i18n("No notes yet. Type to start one.")
                color: tone.edgeText
                font.pixelSize: 14
            }
        }
    }

    // New note floats in the board's corner, in the highlight colour, and
    // starts a note with any words typed, as Enter does.
    QQC2.AbstractButton {
        id: newNote
        objectName: "notes-new"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        implicitHeight: 56
        implicitWidth: newNoteRow.implicitWidth + 48
        visible: opacity > 0
        opacity: pane.clamp((pane.progress - 0.72) / 0.28) * (1 - pane.pageShown)
        enabled: pane.view === "board" && !!pane.quickNote && !pane.quickNote.readOnly
        focusPolicy: Qt.NoFocus
        Accessible.name: words.i18n("New note")
        onClicked: pane.startNote(find.text.trim())
        background: Rectangle {
            radius: height / 2
            color: newNote.down ? Qt.darker(pane.Kirigami.Theme.highlightColor, 1.15) : pane.Kirigami.Theme.highlightColor
        }
        contentItem: Item {
            Row {
                id: newNoteRow
                anchors.centerIn: parent
                spacing: 8
                // A plus in the highlight's own text colour.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: pane.Kirigami.Theme.highlightedTextColor }
                    Rectangle { anchors.centerIn: parent; width: 2; height: 14; radius: 1; color: pane.Kirigami.Theme.highlightedTextColor }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: words.i18n("New note")
                    color: pane.Kirigami.Theme.highlightedTextColor
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
            }
        }
    }

    // ── The page ─────────────────────────────────────────────────────────

    // The checklist, one row per line, kept here while it is typed into.
    ListModel { id: checkModel }
    function syncLines() {
        const lines = quickNote && quickNote.checklist ? quickNote.lines || [] : []
        let same = lines.length === checkModel.count
        for (let i = 0; same && i < lines.length; ++i) {
            const row = checkModel.get(i)
            same = row.text === (lines[i].text || "") && row.item === !!lines[i].item && row.checked === !!lines[i].checked
        }
        if (same) return
        checkModel.clear()
        for (const line of lines)
            checkModel.append({ text: line.text || "", item: !!line.item, checked: !!line.checked })
    }
    function sendLines() {
        const out = []
        for (let i = 0; i < checkModel.count; ++i) {
            const row = checkModel.get(i)
            out.push(row.item ? (row.checked ? "- [x] " : "- [ ] ") + row.text : row.text)
        }
        quickNote.setText(out.join("\n"))
    }

    // A day for Pick a time, counted from today; -1 before one is chosen.
    property int pickDay: -1
    function remindAt(hour) {
        const now = new Date()
        const at = new Date(now.getFullYear(), now.getMonth(), now.getDate() + pickDay, hour, 0, 0)
        const offset = -at.getTimezoneOffset()
        const sign = offset >= 0 ? "+" : "-"
        const pad2 = n => (n < 10 ? "0" : "") + n
        return Qt.formatDateTime(at, "yyyy-MM-ddTHH:mm:ss") + sign + pad2(Math.floor(Math.abs(offset) / 60))
            + ":" + pad2(Math.abs(offset) % 60)
    }

    Item {
        id: pageView
        objectName: "notes-page-view"
        anchors.fill: parent
        visible: pane.pageShown > 0.001
        opacity: pane.pageShown
        enabled: pane.view === "page"

        // The page: from the search field's place and shape to its own.
        Item {
            id: padFrame
            readonly property real from: pane.fromBoard ? 1 : pane.progress
            x: pane.lerp(pane.fieldRest.x, pane.pageEnd.x, from)
            y: pane.lerp(pane.fieldRest.y, pane.pageEnd.y, from)
            width: pane.lerp(pane.fieldRest.width, pane.pageEnd.width, from)
            height: pane.lerp(pane.fieldRest.height, pane.pageEnd.height, from)
            readonly property real cornerRadius: pane.lerp(pane.fieldRest.height / 2, 8, from)

            Rectangle {
                id: paper
                objectName: "notes-paper"
                anchors.fill: parent
                radius: padFrame.cornerRadius
                color: pane.noteHex
                opacity: pane.clamp(padFrame.from * 2)
            }
            Rectangle {
                anchors.fill: parent
                radius: padFrame.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: pane.surfaceOutline
                opacity: 1 - padFrame.from
            }
            QQC2.ScrollView {
                id: padScroll
                anchors.fill: parent
                anchors.rightMargin: 44
                visible: !pane.quickNote || !pane.quickNote.checklist
                opacity: pane.clamp((padFrame.from - 0.5) / 0.5)
                QQC2.TextArea {
                    id: pad
                    objectName: "notes-pad"
                    leftPadding: 24
                    rightPadding: 16
                    topPadding: 22
                    bottomPadding: 22
                    background: null
                    color: pane.ink
                    selectionColor: "#40000000"
                    selectedTextColor: pane.ink
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    readOnly: !pane.writable
                    placeholderText: words.i18n("Write it down…")
                    placeholderTextColor: "#73000000"
                    Accessible.name: words.i18n("Note")
                    // Typing is the person's; a change kept elsewhere arrives
                    // only while it is not being typed into.
                    onTextChanged: if (activeFocus && pane.writable && text !== pane.quickNote.text) pane.quickNote.setText(text)
                    Component.onCompleted: if (pane.quickNote) text = pane.quickNote.text
                }
            }
            Flickable {
                id: checkRows
                objectName: "notes-checklist"
                anchors.fill: parent
                anchors.rightMargin: 44
                anchors.topMargin: 14
                visible: !!pane.quickNote && pane.quickNote.checklist
                contentHeight: checkColumn.height + 14
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A row has the keys: its typing is sent, and kept from being
                // overwritten, until it lets them go.
                readonly property bool typing: {
                    for (let i = 0; i < checkRepeater.count; ++i) {
                        const item = checkRepeater.itemAt(i)
                        if (item && item.typing) return true
                    }
                    return false
                }
                function focusRow(index) {
                    Qt.callLater(() => {
                        const item = checkRepeater.itemAt(index)
                        if (item) item.focusEnd()
                    })
                }
                Column {
                    id: checkColumn
                    width: parent.width
                    Repeater {
                        id: checkRepeater
                        model: checkModel
                        delegate: Item {
                            id: line
                            required property int index
                            required property string text
                            required property bool item
                            required property bool checked
                            readonly property bool typing: lineInput.activeFocus
                            function focusEnd() {
                                lineInput.forceActiveFocus()
                                lineInput.cursorPosition = lineInput.length
                            }
                            objectName: "notes-line-" + index
                            width: checkColumn.width
                            height: Math.max(44, lineInput.contentHeight + 16)
                            Item {
                                id: box
                                objectName: "notes-box-" + line.index
                                visible: line.item
                                x: 12
                                width: 44; height: 44
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: line.text
                                Accessible.checked: line.checked
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22; height: 22; radius: 6
                                    color: line.checked ? pane.ink : "transparent"
                                    border.width: 2
                                    border.color: pane.ink
                                    Image {
                                        anchors.centerIn: parent
                                        visible: line.checked
                                        width: 16; height: 16
                                        source: Qt.resolvedUrl("../assets/icons/lucide/check.svg")
                                        sourceSize: Qt.size(32, 32)
                                    }
                                }
                                TapHandler {
                                    enabled: pane.writable
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: {
                                        checkModel.setProperty(line.index, "checked", !line.checked)
                                        pane.quickNote.setLineChecked(line.index, line.checked)
                                    }
                                }
                            }
                            TextEdit {
                                id: lineInput
                                x: line.item ? 60 : 24
                                width: parent.width - x - 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.text
                                color: pane.ink
                                opacity: line.checked ? 0.5 : 1
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                                font.strikeout: line.checked
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                selectByMouse: true
                                selectionColor: "#40000000"
                                selectedTextColor: pane.ink
                                readOnly: !pane.writable
                                Accessible.name: words.i18n("Line")
                                onTextChanged: {
                                    if (!activeFocus || text === line.text) return
                                    checkModel.setProperty(line.index, "text", text)
                                    pane.sendLines()
                                }
                                Keys.onReturnPressed: event => line.split(event)
                                Keys.onEnterPressed: event => line.split(event)
                                Keys.onPressed: event => {
                                    if (event.key !== Qt.Key_Backspace || lineInput.cursorPosition > 0
                                        || lineInput.selectedText !== "" || line.index === 0) return
                                    event.accepted = true
                                    const before = checkModel.get(line.index - 1).text
                                    const joined = before + lineInput.text
                                    const at = line.index - 1
                                    checkModel.setProperty(at, "text", joined)
                                    checkModel.remove(line.index)
                                    pane.sendLines()
                                    Qt.callLater(() => {
                                        const item = checkRepeater.itemAt(at)
                                        if (item) item.focusAt(before.length)
                                    })
                                }
                            }
                            function focusAt(position) {
                                lineInput.forceActiveFocus()
                                lineInput.cursorPosition = position
                            }
                            // Enter makes a new item of what follows the cursor.
                            function split(event) {
                                event.accepted = true
                                const head = lineInput.text.slice(0, lineInput.cursorPosition)
                                const tail = lineInput.text.slice(lineInput.cursorPosition)
                                checkModel.setProperty(line.index, "text", head)
                                checkModel.insert(line.index + 1, { text: tail, item: true, checked: false })
                                pane.sendLines()
                                const next = line.index + 1
                                Qt.callLater(() => {
                                    const item = checkRepeater.itemAt(next)
                                    if (item) item.focusAt(0)
                                })
                            }
                        }
                    }
                }
            }

            // The note's colour: a dot in the page's corner, opening the
            // colours beside it.
            QQC2.AbstractButton {
                id: colourDot
                objectName: "notes-colour"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                width: 44
                height: 44
                opacity: pane.clamp((padFrame.from - 0.72) / 0.28)
                enabled: pane.writable
                focusPolicy: Qt.NoFocus
                Accessible.name: words.i18n("Colour")
                background: null
                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 22; radius: 11
                        color: pane.noteHex
                        border.width: 2
                        border.color: Qt.rgba(0.1, 0.1, 0.1, colourDot.hovered || pane.choosing === "colour" ? 0.7 : 0.4)
                    }
                }
                onClicked: pane.choose("colour")
            }
            Rectangle {
                id: colourTray
                objectName: "notes-colours"
                visible: pane.choosing === "colour"
                anchors.top: parent.top
                anchors.right: colourDot.left
                anchors.topMargin: 4
                height: 44
                width: swatchRow.width + 12
                radius: 22
                color: Qt.rgba(0.1, 0.1, 0.1, 0.85)
                Row {
                    id: swatchRow
                    anchors.centerIn: parent
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.colours : []
                        delegate: Item {
                            id: swatch
                            required property string modelData
                            required property int index
                            readonly property bool chosen: !!pane.quickNote && pane.quickNote.colour === modelData
                            objectName: "notes-colour-" + modelData
                            width: 40
                            height: 44
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData
                            Accessible.checked: chosen
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 14
                                color: "transparent"
                                border.width: 2
                                border.color: "#F8F8FF"
                                visible: swatch.chosen
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20; height: 20; radius: 10
                                // A swatch is the paper's own colour; a mid grey
                                // stands in for one the notes application does
                                // not name.
                                color: pane.quickNote ? (pane.quickNote.colourHexes[swatch.index] || "#888888") : "#888888"
                            }
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: {
                                    pane.quickNote.setColour(swatch.modelData)
                                    pane.closeChoices()
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            id: lower
            objectName: "notes-lower"
            x: 0
            y: pane.pageEnd.y + pane.pageEnd.height + 8
            width: pane.width
            spacing: 8
            opacity: pane.fromBoard ? 1 : pane.progress
            transform: Translate { y: pane.fromBoard ? 0 : 20 * (1 - pane.progress) }

            // Folder's choices: the folders, the workspace's own marked, and a
            // field for a new one.
            Flickable {
                objectName: "notes-folder-choices"
                visible: pane.choosing === "folder"
                width: parent.width
                height: 40
                contentWidth: folderRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: folderRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.folders : []
                        delegate: Chip {
                            required property var modelData
                            objectName: "notes-folder-" + (modelData.name || "inbox")
                            label: modelData.workspace ? words.i18n("%1 · this workspace", modelData.label || "")
                                : (modelData.label || "")
                            radio: true
                            chosen: !!modelData.chosen
                            onActivated: {
                                pane.quickNote.setFolder(modelData.name || "")
                                pane.closeChoices()
                            }
                        }
                    }
                    QQC2.TextField {
                        id: newFolder
                        objectName: "notes-new-folder"
                        width: 200
                        height: 40
                        leftPadding: 16
                        rightPadding: 16
                        color: pane.primaryText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        placeholderText: words.i18n("New folder")
                        placeholderTextColor: tone.hintText
                        Accessible.name: words.i18n("New folder")
                        background: Rectangle {
                            radius: 20
                            color: pane.controlColor
                            border.width: 1
                            border.color: newFolder.activeFocus ? pane.primaryText : pane.surfaceOutline
                        }
                        onAccepted: {
                            const name = text.trim()
                            if (name === "") return
                            pane.quickNote.setFolder(name)
                            pane.closeChoices()
                        }
                    }
                }
            }
            // Stuck to's choices: the windows, and Don't stick to a window.
            Flickable {
                objectName: "notes-window-choices"
                visible: pane.choosing === "window"
                width: parent.width
                height: 40
                contentWidth: windowRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: windowRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.windows : []
                        delegate: Chip {
                            required property var modelData
                            required property int index
                            objectName: "notes-window-" + index
                            label: modelData.label || modelData.window || ""
                            radio: true
                            chosen: !!modelData.chosen
                            onActivated: {
                                pane.quickNote.setStuck(modelData.window || "", modelData.app || "")
                                pane.closeChoices()
                            }
                        }
                    }
                    Chip {
                        objectName: "notes-dont-stick"
                        label: words.i18n("Don't stick to a window")
                        radio: true
                        chosen: !!pane.quickNote && !pane.quickNote.stuck
                        onActivated: {
                            pane.quickNote.setStuck("", "")
                            pane.closeChoices()
                        }
                    }
                }
            }
            // Remind's choices, as Gooseberry offers them, Pick a time, and
            // No reminder where one is set.
            Flickable {
                objectName: "notes-remind-choices"
                visible: pane.choosing === "remind"
                width: parent.width
                height: 40
                contentWidth: remindRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: remindRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.remindChoices : []
                        delegate: Chip {
                            required property var modelData
                            objectName: "notes-remind-" + (modelData.kind || "")
                            label: modelData.label || ""
                            onActivated: {
                                if (modelData.kind === "pick") {
                                    pane.choosing = "pick"
                                    pane.pickDay = -1
                                    return
                                }
                                pane.quickNote.setReminder(modelData.kind === "opens" ? "opens" : (modelData.time || ""))
                                pane.closeChoices()
                            }
                        }
                    }
                    Chip {
                        objectName: "notes-no-reminder"
                        visible: !!pane.quickNote && pane.quickNote.remindLabel !== ""
                        label: words.i18n("No reminder")
                        onActivated: {
                            pane.quickNote.setReminder("")
                            pane.closeChoices()
                        }
                    }
                }
            }
            // Pick a time: a day, then an hour.
            Flickable {
                objectName: "notes-pick"
                visible: pane.choosing === "pick"
                width: parent.width
                height: 40
                contentWidth: pickRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: pickRow
                    spacing: 8
                    Repeater {
                        model: pane.pickDay < 0 ? 7 : 0
                        delegate: Chip {
                            required property int index
                            objectName: "notes-pick-day-" + index
                            label: index === 0 ? words.i18n("Today") : index === 1 ? words.i18n("Tomorrow")
                                : Qt.locale().dayName(new Date(Date.now() + index * 86400000).getDay(), Locale.LongFormat)
                            onActivated: pane.pickDay = index
                        }
                    }
                    Repeater {
                        model: pane.pickDay < 0 ? [] : [9, 12, 15, 18, 20]
                        delegate: Chip {
                            required property int modelData
                            objectName: "notes-pick-hour-" + modelData
                            visible: pane.pickDay > 0 || modelData > new Date().getHours()
                            label: Qt.formatTime(new Date(2000, 0, 1, modelData, 0), Qt.locale().timeFormat(Locale.ShortFormat))
                            onActivated: {
                                pane.quickNote.setReminder(pane.remindAt(modelData))
                                pane.closeChoices()
                            }
                        }
                    }
                }
            }

            // An older Gooseberry offers Belongs to instead of Folder and
            // Stuck to.
            Flickable {
                objectName: "notes-belongs"
                visible: !pane.chips
                width: parent.width
                height: 40
                contentWidth: belongsRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: belongsRow
                    spacing: 8
                    Repeater {
                        model: pane.quickNote ? pane.quickNote.choices : []
                        delegate: Chip {
                            required property var modelData
                            required property int index
                            objectName: "notes-belongs-" + index
                            label: modelData.label || ""
                            radio: true
                            chosen: !!modelData.chosen
                            onActivated: pane.quickNote.setBelongs(modelData.kind || "", modelData.project || "")
                        }
                    }
                }
            }

            // The quiet line: where the note is kept and what it is stuck
            // to, whether it is kept, and the note's few actions.
            Item {
                id: tray
                objectName: "notes-tray"
                width: parent.width
                height: 44
                Row {
                    id: context
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    visible: pane.chips
                    enabled: pane.writable
                    TrayButton {
                        id: folderChip
                        objectName: "notes-folder"
                        glyph: "folder"
                        showText: true
                        quiet: true
                        maxWidth: tray.width * 0.32
                        text: pane.quickNote ? pane.quickNote.folderLabel : ""
                        spokenText: pane.quickNote ? words.i18n("Folder: %1", pane.quickNote.folderLabel) : ""
                        checked: pane.choosing === "folder"
                        onActivated: pane.choose("folder")
                    }
                    TrayButton {
                        id: stuckChip
                        objectName: "notes-stuck"
                        showText: true
                        quiet: true
                        maxWidth: tray.width * 0.32
                        text: pane.quickNote && pane.quickNote.stuck ? pane.stuckLabel : words.i18n("Not stuck")
                        spokenText: pane.quickNote && pane.quickNote.stuck ? words.i18n("Stuck to %1", pane.stuckLabel)
                            : words.i18n("Not stuck to a window")
                        checked: pane.choosing === "window"
                        onActivated: pane.choose("window")
                    }
                }
                Row {
                    id: status
                    objectName: "notes-status"
                    anchors.left: pane.chips ? context.right : parent.left
                    anchors.leftMargin: 8
                    anchors.right: actions.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Accessible.role: Accessible.StaticText
                    Accessible.name: statusText.text !== "" ? statusText.text : words.i18n("Saved as you go")
                    SuiteIcon {
                        glyph: pane.trouble ? "triangle-alert" : "check"
                        width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: pane.trouble ? 1 : 0.55
                    }
                    Text {
                        id: statusText
                        width: Math.max(0, status.width - 22)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: !pane.quickNote ? ""
                            : pane.quickNote.readOnly ? words.i18n("Kept by a newer Gooseberry; not changed here")
                            : pane.quickNote.problem !== "" ? words.i18n("Not kept yet: %1", pane.quickNote.problem)
                            : ""
                        color: tone.troubleText
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                }
                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    enabled: pane.writable
                    TrayButton {
                        objectName: "notes-checklist-toggle"
                        visible: !!pane.quickNote && pane.quickNote.offersReminders
                        glyph: "list-checks"
                        text: words.i18n("Checklist")
                        checked: !!pane.quickNote && pane.quickNote.checklist
                        onActivated: {
                            pane.closeOpen()
                            pane.quickNote.setChecklist(!pane.quickNote.checklist)
                            Qt.callLater(pane.focusPad)
                        }
                    }
                    TrayButton {
                        objectName: "notes-remind"
                        visible: !!pane.quickNote && pane.quickNote.offersReminders
                        glyph: "bell"
                        readonly property string set: pane.quickNote ? pane.quickNote.remindLabel : ""
                        showText: set !== ""
                        text: set !== "" ? set : words.i18n("Remind")
                        checked: pane.choosing === "remind" || pane.choosing === "pick"
                        onActivated: pane.choose("remind")
                    }
                    TrayButton {
                        id: more
                        objectName: "notes-more"
                        visible: !!pane.quickNote && pane.quickNote.kept
                        glyph: "ellipsis"
                        text: words.i18n("More")
                        checked: pane.choosing === "more"
                        onActivated: pane.choose("more")
                    }
                }
            }
        }

        // More: Copy all, Tuck away and Remove, over the line under the page.
        Rectangle {
            id: moreMenu
            objectName: "notes-more-menu"
            visible: pane.choosing === "more"
            z: 2
            width: 220
            height: moreColumn.height + 12
            x: pane.width - width
            y: lower.y + tray.y - height - 4
            radius: 12
            color: tone.sheet
            border.width: 1
            border.color: tone.line
            Column {
                id: moreColumn
                x: 6
                y: 6
                width: parent.width - 12
                MenuRow {
                    objectName: "notes-copy-all"
                    label: words.i18n("Copy all")
                    onActivated: {
                        copier.text = pane.quickNote.text
                        copier.selectAll()
                        copier.copy()
                        pane.closeChoices()
                    }
                }
                MenuRow {
                    objectName: "notes-pin"
                    // Where the notes application offers it: the note kept
                    // in sight on the panel, one at a time.
                    visible: !!pane.quickNote && pane.quickNote.offersPin
                    label: pane.quickNote && pane.quickNote.pinned ? words.i18n("Unpin") : words.i18n("Pin")
                    onActivated: {
                        pane.quickNote.setPinned(!pane.quickNote.pinned)
                        pane.closeChoices()
                    }
                }
                MenuRow {
                    objectName: "notes-tuck-away"
                    label: words.i18n("Tuck away")
                    onActivated: {
                        pane.closeOpen()
                        pane.quickNote.tuckAway()
                        if (pane.fromBoard) pane.showBoard()
                        else pane.finished()
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: tone.line
                }
                MenuRow {
                    objectName: "notes-remove"
                    label: words.i18n("Remove")
                    quiet: true
                    onActivated: {
                        pane.closeOpen()
                        pane.quickNote.remove()
                        if (pane.fromBoard) pane.showBoard()
                        else pane.finished()
                    }
                }
            }
        }
        TextEdit {
            id: copier
            visible: false
            textFormat: TextEdit.PlainText
        }
    }

    // ── Shared ───────────────────────────────────────────────────────────

    // Header: the corner, as Apps and Files place theirs, from 72% of the
    // way; on a page opened from the board, Back to it. Search's own row of
    // modes, above, leads everywhere else.
    Item {
        id: header
        width: pane.width
        height: pane.headerHeight

        Pill {
            id: backPill
            objectName: "notes-back"
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: words.i18n("Back")
            glyph: "chevron-left"
            visible: pane.view === "page" && pane.fromBoard
            opacity: pane.pageShown
            onActivated: pane.showBoard()
        }
    }

    // A filter over the board's notes, filled when chosen.
    component Filter: Rectangle {
        id: filterItem
        property string key
        property string label
        property bool quiet: false
        readonly property bool chosen: pane.filter === key
        objectName: "notes-filter-" + key
        height: 44
        width: filterText.implicitWidth + 28
        radius: 22
        color: chosen ? tone.chosen : filterHover.hovered ? tone.hover : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: chosen
        Accessible.onPressAction: filterItem.pick()
        Keys.onReturnPressed: filterItem.pick()
        Keys.onSpacePressed: filterItem.pick()
        function pick() {
            pane.filter = key
            pane.focusFind()
        }
        Text {
            id: filterText
            anchors.centerIn: parent
            text: filterItem.label
            color: filterItem.chosen ? pane.primaryText : filterItem.quiet ? tone.edgeText : tone.secondaryText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        HoverHandler {
            id: filterHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: filterItem.pick()
        }
    }

    // A quiet round control under the page: a glyph, and its words beside it
    // only where they say something. It has no face at rest.
    component TrayButton: Item {
        id: trayButton
        property string glyph: ""
        property string text
        property string spokenText: text
        property bool showText: false
        property bool quiet: false
        property bool checked: false
        property real maxWidth: 260
        signal activated()
        height: 44
        width: showText ? Math.min(maxWidth, trayRow.implicitWidth + 28) : 44
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: spokenText
        Accessible.checked: checked
        Accessible.onPressAction: trayButton.activated()
        Keys.onReturnPressed: trayButton.activated()
        Keys.onSpacePressed: trayButton.activated()
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: trayTap.pressed ? tone.controlPressed : trayButton.checked ? tone.chosen
                : trayHover.hovered ? tone.hover : "transparent"
            border.width: trayButton.activeFocus ? 1.5 : 0
            border.color: tone.focusRing
        }
        Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: 8
            SuiteIcon {
                visible: trayButton.glyph !== ""
                glyph: trayButton.glyph === "" ? "circle" : trayButton.glyph
                anchors.verticalCenter: parent.verticalCenter
                opacity: trayButton.quiet ? 0.7 : 1
            }
            Text {
                visible: trayButton.showText
                width: Math.min(implicitWidth, trayButton.maxWidth - 28 - (trayButton.glyph !== "" ? 28 : 0))
                anchors.verticalCenter: parent.verticalCenter
                text: trayButton.text
                elide: Text.ElideMiddle
                color: trayButton.quiet ? tone.secondaryText : pane.primaryText
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
        HoverHandler {
            id: trayHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: trayTap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: trayButton.activated()
        }
    }

    // A row in More.
    component MenuRow: Rectangle {
        id: menuRow
        property string label
        property bool quiet: false
        signal activated()
        width: parent ? parent.width : 0
        height: 44
        radius: 8
        color: menuTap.pressed ? tone.controlPressed : menuHover.hovered ? tone.hover : "transparent"
        Accessible.role: Accessible.MenuItem
        Accessible.name: label
        Accessible.onPressAction: menuRow.activated()
        Text {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.label
            color: menuRow.quiet ? tone.secondaryText : pane.primaryText
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        HoverHandler {
            id: menuHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: menuTap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: menuRow.activated()
        }
    }

    // A choice in a row under the page, filled when chosen.
    component Chip: Rectangle {
        id: chipItem
        property string label
        property string spokenLabel: label
        property bool chosen: false
        // A choice among others rather than an action.
        property bool radio: false
        signal activated()
        height: 40
        width: Math.min(chipText.implicitWidth + 32, pane.width)
        radius: 20
        color: chosen ? pane.primaryText : pane.controlColor
        border.width: activeFocus ? 2 : 1
        border.color: chosen || activeFocus ? pane.primaryText : pane.surfaceOutline
        activeFocusOnTab: true
        Accessible.role: radio ? Accessible.RadioButton : Accessible.Button
        Accessible.name: spokenLabel
        Accessible.checked: chosen
        Accessible.onPressAction: chipItem.activated()
        Keys.onReturnPressed: chipItem.activated()
        Keys.onEnterPressed: chipItem.activated()
        Keys.onSpacePressed: chipItem.activated()
        Text {
            id: chipText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, chipItem.width - 32)
            elide: Text.ElideRight
            text: chipItem.label
            color: chipItem.chosen ? pane.surfaceColor : pane.primaryText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: chipItem.activated()
        }
    }

    component Pill: ModePill {
        primaryText: pane.primaryText
        surfaceColor: pane.surfaceColor
        controlColor: pane.controlColor
    }
}
