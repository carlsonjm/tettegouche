import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "LauncherControls"
    width: 1000
    height: 800
    visible: true
    when: windowShown
    function init() {
        launcher.filesMode = false
        results.helpers = []
        results.helpersOnly = false
        results.helpersOpened = []
        catalog.tileSize = 1
        launcher.fileBrowser = null
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        recentStub.clear()
        recentStub.applicationCount = 0
        launcher.recentUse = recentStub
        launcher.recentApps = true
        launcher.recentFiles = true
        recentStub.opened = []
        launcher.notesDoor = null
        notesStub.available = true
        notesStub.opened = 0
        launcher.quickNote = null
        quickStub.reset()
        controller.notesLaunches = 0
        controller.guestLaunches = 0
        controller.availableArea = Qt.rect(0, 0, 1000, 740)
        controller.drawerExpanded = false
        controller.expansionChosen = false
        controller.guestMode = false
        controller.filesWindowOpen = false
        controller.filesWindowShows = true
        controller.filesWindows = 0
        controller.filesLaunches = 0
        controller.opened()
        wait(300)
    }
    QtObject {
        id: controller
        property bool guestMode: false
        property bool drawerExpanded: false
        property bool expansionChosen: false
        function setDrawerExpanded(expanded, chosen) { drawerExpanded = expanded; expansionChosen = !!chosen }
        readonly property bool filesWindowOffered: true
        property bool filesWindowOpen: false
        property bool filesWindowShows: true
        property int filesWindows: 0
        function popOutFilesWindow() { filesWindows++; if (filesWindowShows) filesWindowOpen = true; return filesWindowShows }
        property int filesLaunches: 0
        function beginGuestFilesLaunch() { filesLaunches++; return guestMode }
        property rect availableArea: Qt.rect(0, 0, 1000, 740)
        property bool contextAvailable: false
        property real guestX: 140
        property real guestY: 160
        property real guestWidth: 720
        property real guestHeight: 480
        property int closes: 0
        property int activatedRow: -1
        property int activationResult: 1
        function activateIfOpen(row) { activatedRow = row; return activationResult }
        property int guestLaunches: 0
        function beginGuestApplicationLaunch(row, catalog) { guestLaunches++; return false }
        function beginGuestRecentLaunch(row) { guestLaunches++; return false }
        property int catalogActivated: -1
        function activateCatalogIfOpen(row) { catalogActivated = row; return 1 }
        function finishLaunch() { closes++ }
        property var showing: []
        function reportShowing(mode, loading) { showing = [mode, loading] }
        property bool dockPresent: false
        property var pinnedRows: []
        function catalogPinned(row) { return pinnedRows.indexOf(row) >= 0 }
        property var pinAsks: []
        function pinCatalog(row, pin) {
            pinAsks = pinAsks.concat([[row, pin]])
            pinnedRows = pin ? pinnedRows.concat([row]) : pinnedRows.filter(r => r !== row)
        }
        property int webSearches: 0
        property bool bluetoothResult: false
        property int relatedRevision: 0
        property QtObject bluetoothContext: QtObject {
            property var connectedDevices: []
        }
        signal opened()
        signal filesRequested()
        signal guestLaunchReady()
        signal guestNavigationReady(int slot)
        signal guestBridgeLost()
        signal drawerRequested(string drawer)
        function close() { closes++ }
        property int keyRequests: 0
        function showInputMethod() { keyRequests++ }
        property bool toType: false
        function openedToType() { return toType }
        function relatedOptionLabel(row) { return "Open Bluetooth settings" }
        function updateGuestDrag(value) {}
        function relatedItems(row) {
            return bluetoothResult ? bluetoothContext.connectedDevices.map(function(name) {
                return { label: name, status: "Connected" }
            }) : []
        }
        property var carried: []
        property rect carriedSheet
        function carryOut(paths, sheet) { carried = paths; carriedSheet = sheet }
        property int carriedApplication: -1
        function carryApplication(row, sheet) { carriedApplication = row; carriedSheet = sheet }
        property int carriedFolder: -1
        function carryFolder(row, sheet) { carriedFolder = row; carriedSheet = sheet }
        function beginGuestWebLaunch() { return false }
        property int notesLaunches: 0
        property bool notesLaunchAccepted: true
        function beginGuestNotesLaunch() { notesLaunches++; return guestMode && notesLaunchAccepted }
        property int launchCancels: 0
        function cancelGuestApplicationLaunch() { launchCancels++ }
        property int handoffs: 0
        function completeGuestHandoff() { handoffs++ }
        function searchWeb(text) { webSearches++; return true }
        function resultApplicationId(row) { return row >= 0 && row < results.count ? (results.get(row).applicationId || "") : "" }
    }
    ListModel {
        id: results
        property string queryString: ""
        property bool allFiles: false
        property string quietFolders: ""
        property bool querying: false
        property int launches: 0
        property bool launchSucceeds: true
        function run(index) { launches++; return launchSucceeds }
        property int pinnedRow: -1
        property bool hasPinnedSelection: false
        function pinSelection(row) { pinnedRow = row; hasPinnedSelection = true; selectionChanged() }
        function selectionPinned() { return hasPinnedSelection }
        function selectedRow() { return pinnedRow }
        signal selectionChanged()
        onQueryStringChanged: { pinnedRow = -1; hasPinnedSelection = false }
        // Split Rock's Core's upkeep cards, as the Helpers chip shows them.
        property var helpers: []
        property bool helpersOnly: false
        property var helpersOpened: []
        function openHelper(id) { helpersOpened = helpersOpened.concat([id]); return true }
    }
    ListModel {
        id: catalog
        property string filterText: ""
        property int sortOrder: 0
        property int tileSize: 1
        property int useReads: 0
        function refreshUse() { useReads++ }
        property int installChecks: 0
        function checkInstalled() { installChecks++ }
        property bool showHidden: false
        property bool softwareReady: false
        property bool softwareAsked: false
        property var hiddenSet: ({})
        property var ran: []
        property int uninstalled: -1
        function applicationName(row) { return row >= 0 && row < count ? get(row).name : "" }
        function actions(row) { return row === 1 ? [{index: 0, name: "New Window", icon: ""}, {index: 2, name: "New Private Window", icon: ""}] : [] }
        function runAction(row, action) { ran = [row, action]; return true }
        function isHidden(row) { return !!hiddenSet[row] }
        function setHidden(row, hidden) { const next = Object.assign({}, hiddenSet); next[row] = hidden; hiddenSet = next }
        function prepareSoftware() { softwareAsked = true }
        function canUninstall(row) { return softwareReady && row === 1 }
        function uninstall(row) { uninstalled = row; return true }
        property var removable: []
        property string uninstalledApplication: ""
        function canUninstallApplication(id) { return removable.indexOf(id) >= 0 }
        function uninstallApplication(id) { uninstalledApplication = id; return true }
        property int edited: -1
        function canEdit(row) { return row === 1 }
        function edit(row) { edited = row; return true }
        // Folders: a row whose isFolder is true is one, by its folderId; a
        // row's kind says what it is, an application where none is given.
        property var openSet: ({})
        property var renamed: []
        property string removed: ""
        property var putIn: []
        property int takenOut: -1
        readonly property int folderCount: 0
        function isFolder(row) { return row >= 0 && row < count && get(row).isFolder === true }
        function folderId(row) { return isFolder(row) ? get(row).folderId : "" }
        function folderName(row) { return isFolder(row) ? get(row).name : "" }
        function folderOf(row) { return row >= 0 && row < count && !isFolder(row) ? (get(row).inFolder || "") : "" }
        function folderList() {
            const list = []
            for (let i = 0; i < count; ++i) if (isFolder(i)) list.push({id: get(i).folderId, name: get(i).name})
            return list
        }
        function kind(row) {
            if (row < 0 || row >= count) return ""
            const at = get(row)
            return at.kind ? at.kind : at.isFolder === true ? "folder" : "application"
        }
        function item(row) { return row >= 0 && row < count ? get(row) : ({}) }
        function isOpen(row) { return isFolder(row) && !!openSet[get(row).folderId] }
        function folderRow(id) {
            for (let i = 0; i < count; ++i) if (isFolder(i) && get(i).folderId === id) return i
            return -1
        }
        // Opening a folder draws the applications in it as its own.
        function setFolderOpen(id, open) {
            const next = Object.assign({}, openSet)
            next[id] = open
            openSet = next
            for (let i = 0; i < count; ++i)
                if (get(i).inFolder === id) setProperty(i, "kind", open ? "member" : "application")
        }
        // An application is known by its appId where it has one, else by
        // its row.
        function applicationId(row) {
            if (row < 0 || row >= count || (kind(row) !== "application" && kind(row) !== "member")) return ""
            return get(row).appId ? get(row).appId : "app" + row
        }
        function applicationRow(id) {
            for (let i = 0; i < count; ++i) if (applicationId(i) === id) return i
            return -1
        }
        property var made: []
        function makeFolder(ids) { made = ids; return ids.length >= 2 ? "made" : "" }
        function gather(row, id) { return "" }
        function putInFolder(row, id) { putIn = [row, id] }
        function takeOut(row) { takenOut = row }
        function renameFolder(id, name) { renamed = [id, name] }
        function removeFolder(id) { removed = id }
    }
    // What was used lately, as the launcher's model offers it.
    ListModel {
        id: recentStub
        property var opened: []
        // The rows before the files, as the launcher's model counts them.
        property int applicationCount: 0
        function open(row) { opened = opened.concat([row]); return true }
    }
    // Gooseberry's quick note, as the launcher's door offers it.
    QtObject {
        id: notesStub
        property bool available: true
        property int opened: 0
        function open() { if (!available) return false; opened++; return true }
    }
    // Gooseberry's quick-note interface, as Search speaks it.
    QtObject {
        id: quickStub
        property bool available: true
        property bool open: false
        property string text: ""
        property string colour: "yellow"
        property var colours: ["yellow", "rose", "teal", "green", "stone"]
        property var colourHexes: ["#F2D98A", "#E8B4A8", "#9ED6CB", "#C9D89A", "#D9D4CC"]
        readonly property string colourHex: colourHexes[colours.indexOf(colour)] || ""
        property var choices: [{ kind: "window", label: "This window · Kate", project: "", chosen: false },
                               { kind: "loose", label: "Loose", project: "", chosen: true }]
        // Folder and Stuck to, from a Gooseberry that offers them.
        property bool offersFolders: true
        property string folder: ""
        property string folderLabel: ""
        property var folders: []
        property bool stuck: false
        property string stuckWindow: ""
        property var windows: []
        property var folderSets: []
        property var stucks: []
        property string noteId: "note-1"
        property bool kept: false
        property bool readOnly: false
        property string problem: ""
        property int starts: 0
        property var texts: []
        property int flushes: 0
        property string belongs: ""
        property int dones: 0
        property int tucks: 0
        property var boards: []
        property bool boardOpens: true
        property bool offersReminders: true
        property string remindLabel: ""
        property var remindChoices: [{ kind: "later", label: "Later today", time: "2026-10-17T18:00:00+00:00" },
                                     { kind: "pick", label: "Pick a time", time: "" }]
        property var reminders: []
        property bool checklist: false
        property var lines: []
        property var ticks: []
        // Every note, as Find gives them, and the words last asked for.
        property var notes: []
        property string notesWords: ""
        property var finds: []
        property var edits: []
        property var startsWith: []
        property bool offersPin: true
        property bool pinned: false
        property var pins: []
        // Gooseberry's own card: taking a note handed to it, or, as an older
        // Gooseberry, not, so the note opens on the page here.
        property bool cardTakes: false
        property var cards: []
        // The way back each hand-over asked the card for.
        property var backs: []
        signal cardAnswered(bool opened)
        function openOnCard(noteId, back) { cards = cards.concat(["id:" + noteId]); backs = backs.concat([back]); cardAnswered(cardTakes) }
        function startOnCard(words, back) { cards = cards.concat(["text:" + words]); backs = backs.concat([back]); cardAnswered(cardTakes) }
        readonly property var store: [
            { id: "note-1", title: "Plan the kitchen", excerpt: "", colour: "yellow", colourHex: "#F2D98A",
              folder: "Kitchen", folderLabel: "Kitchen", stuck: true, window: "plan.txt", app: "org.kde.kate",
              tucked: false, changed: new Date().toISOString(), remind: "", done: false },
            { id: "note-2", title: "Receipts for the taxes", excerpt: "", colour: "teal", colourHex: "#9ED6CB",
              folder: "Taxes", folderLabel: "Taxes", stuck: false, window: "", app: "",
              tucked: false, changed: "2026-01-02T10:00:00+00:00", remind: "", done: false },
            { id: "note-3", title: "Old list", excerpt: "", colour: "stone", colourHex: "#D9D4CC",
              folder: "", folderLabel: "Inbox", stuck: false, window: "", app: "",
              tucked: true, changed: "2025-12-01T10:00:00+00:00", remind: "", done: false }]
        signal noteChanged()
        signal boardShown(string requestToken)
        function reset() {
            available = true; open = false; text = ""; colour = "yellow"; starts = 0; texts = []
            flushes = 0; belongs = ""; dones = 0; tucks = 0; boards = []; boardOpens = true
            offersFolders = true; folderSets = []; stucks = []
            kept = false; offersReminders = true; remindLabel = ""; reminders = []; checklist = false; lines = []; ticks = []
            notes = []; notesWords = ""; finds = []; edits = []; startsWith = []
            offersPin = true; pinned = false; pins = []; cardTakes = false; cards = []; backs = []
            folder = "Kitchen"; folderLabel = "Kitchen"
            folders = [{ name: "Kitchen", label: "Kitchen", chosen: true, workspace: true },
                       { name: "", label: "Inbox", chosen: false, workspace: false },
                       { name: "Taxes", label: "Taxes", chosen: false, workspace: false }]
            stuck = true; stuckWindow = "plan.txt"
            windows = [{ window: "plan.txt", app: "org.kde.kate", label: "Kate · plan.txt", chosen: true },
                       { window: "Inbox", app: "org.kde.kmail2", label: "KMail · Inbox", chosen: false }]
        }
        function refresh() {}
        function start() { starts++; open = true; noteChanged() }
        function setText(value) { texts = texts.concat([value]); text = value }
        function flush() { flushes++ }
        function setColour(name) { colour = name; noteChanged() }
        function setBelongs(kind, project) { belongs = kind; noteChanged() }
        function setFolder(name) {
            folderSets = folderSets.concat([name])
            folder = name
            folderLabel = name === "" ? "Inbox" : name
            noteChanged()
        }
        function setStuck(window, app) {
            stucks = stucks.concat([[window, app]])
            stuck = window !== ""
            stuckWindow = window
            windows = windows.map(w => ({ window: w.window, app: w.app, label: w.label,
                                          chosen: w.window === window && w.app === app }))
            noteChanged()
        }
        function done() { dones++; open = false }
        function tuckAway() { tucks++; open = false }
        function setPinned(on) { pins = pins.concat([on]); pinned = on; noteChanged() }
        function remove() {}
        function openBoard(token) { if (!boardOpens) return false; boards = boards.concat([token]); return true }
        function setReminder(when) { reminders = reminders.concat([when]); remindLabel = when === "" ? "" : "6:00 PM"; noteChanged() }
        function setChecklist(on) {
            checklist = on
            lines = on ? [{ text: "oats", item: true, checked: false }, { text: "milk", item: true, checked: false }] : []
            text = on ? "- [ ] oats\n- [ ] milk" : "oats\nmilk"
            noteChanged()
        }
        function setLineChecked(line, checked) { ticks = ticks.concat([[line, checked]]) }
        function findNotes(words) {
            finds = finds.concat([words])
            const needle = words.toLowerCase()
            notes = store.filter(note => needle === "" || note.title.toLowerCase().indexOf(needle) >= 0)
            notesWords = words
        }
        function edit(id) {
            edits = edits.concat([id])
            const note = store.filter(n => n.id === id)[0]
            noteId = id; open = true; text = note.title; kept = true
            noteChanged()
        }
        function startWith(words) {
            startsWith = startsWith.concat([words])
            noteId = "note-new"; open = true; text = words
            noteChanged()
        }
    }
    // Half applications, then the files, as the launcher's model lists them.
    function fillRecent(n) {
        recentStub.clear()
        const applications = Math.ceil(n / 2)
        for (let i = 0; i < n; ++i)
            recentStub.append({name: "Used " + i, icon: "application-x-executable", thumbnail: "",
                               kind: i < applications ? "application" : "file",
                               where: i < applications ? "" : "Documents", when: new Date(Date.now() - i * 60000)})
        recentStub.applicationCount = applications
    }
    // Stand-ins for a dark and a light colour scheme, so the colours do not
    // depend on the scheme the test happens to run under.
    QtObject {
        id: darkScheme
        property color backgroundColor: "#141414"
        property color textColor: "#E0E0E0"
    }
    QtObject {
        id: lightScheme
        property color backgroundColor: "#F2F2F2"
        property color textColor: "#102729"
        property color negativeTextColor: "#C0392B"
        property color positiveTextColor: "#1E7A4C"
        property color neutralTextColor: "#B65C00"
        property color highlightColor: "#2A6FB0"
        property color highlightedTextColor: "#FFFFFF"
    }
    Component {
        id: colorsComponent
        App.SearchColors {}
    }
    App.Launcher {
        id: launcher
        anchors.fill: parent
        launcherController: controller
        searchResults: results
        applicationCatalog: catalog
        recentUse: recentStub
    }
    // On a dark scheme Search keeps the suite's values; on a light one its
    // ground and ink are the scheme's, and every wash and grey is that ink.
    function test_coloursFollowTheScheme() {
        const dark = createTemporaryObject(colorsComponent, test, {theme: darkScheme})
        verify(dark.dark)
        const kept = {
            text: "#F8F8FF", primaryText: "#f2ffffff", secondaryText: "#A8FFFFFF",
            bodyText: "#A8F8F8FF", edgeText: "#88ffffff", placeholderText: "#86ffffff",
            disabledText: "#6BF8F8FF", surface: "#141414", sheet: "#1B1B1B",
            outline: "#5a5a5a", line: "#333333", control: "#242424",
            controlHover: "#333333", controlPressed: "#4A4A4A", hover: "#22ffffff",
            current: "#3dffffff", focusRing: "#b0ffffff", openTag: "#ff71e6be",
            errorText: "#ffb5a8", troubleText: "#E08A80",
            selection: "#6da9ddff", textOnInk: "#141414"
        }
        for (const role in kept)
            verify(Qt.colorEqual(dark[role], kept[role]), role + " is " + dark[role])

        const light = createTemporaryObject(colorsComponent, test, {theme: lightScheme})
        verify(!light.dark)
        verify(Qt.colorEqual(light.text, "#102729"))
        verify(Qt.colorEqual(light.primaryText, "#102729"))
        verify(Qt.colorEqual(light.surface, "#F2F2F2"))
        verify(Qt.colorEqual(light.textOnInk, "#F2F2F2"))
        verify(Qt.colorEqual(light.troubleText, "#C0392B"))
        verify(Qt.colorEqual(light.openTag, "#1E7A4C"))
        verify(Qt.colorEqual(light.selection, "#2A6FB0"))
        // Washes are the ink, see-through; greys are the ink laid on the
        // ground, darker than it and lighter than the ink.
        for (const role of ["secondaryText", "edgeText", "hover", "current", "focusRing"]) {
            const wash = light[role]
            verify(Qt.colorEqual(Qt.rgba(wash.r, wash.g, wash.b, 1), "#102729"), role)
            verify(wash.a > 0 && wash.a < 1, role)
        }
        let previous = light.surface.hslLightness
        for (const role of ["control", "controlHover", "controlPressed", "outline"]) {
            const grey = light[role]
            compare(grey.a, 1, role)
            verify(grey.hslLightness < previous && grey.hslLightness > 0.4, role)
            previous = grey.hslLightness
        }

        // Search's sheet follows the colours it is given.
        const tone = findChild(launcher, "searchColors")
        verify(tone)
        const ambient = tone.theme
        tone.theme = lightScheme
        verify(Qt.colorEqual(launcher.surfaceColor, "#F2F2F2"))
        verify(Qt.colorEqual(launcher.primaryText, "#102729"))
        tone.theme = darkScheme
        verify(Qt.colorEqual(launcher.surfaceColor, "#141414"))
        verify(Qt.colorEqual(launcher.surfaceOutline, "#5a5a5a"))
        verify(Qt.colorEqual(launcher.controlColor, "#242424"))
        verify(Qt.colorEqual(launcher.primaryText, "#f2ffffff"))
        tone.theme = ambient
    }

    // The arrow keys choose an application in Apps, which Enter
    // opens: the chosen one rises and stays in view as the choice moves on.
    // The arrow keys choose an application in Apps, typed into
    // or not: the first press shows the one Enter would open, Left and Right
    // step by one, Up and Down by a row, and the choice stays in view.
    function test_browseShowsTheKeyChoice() {
        controller.opened()
        for (let i = 0; i < 40; ++i) catalog.append({name: "App " + i, icon: "application-x-executable"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        const grid = findChild(launcher, "application-grid")
        const query = findChild(launcher, "search-query")
        const columns = Math.max(1, Math.floor(grid.width / grid.cellWidth))
        query.forceActiveFocus()
        verify(!findChild(grid, "application-tile-0").chosen)
        keyClick(Qt.Key_Down)
        compare(grid.currentIndex, 0)
        verify(findChild(grid, "application-tile-0").chosen)
        const rows = Math.min(4, Math.floor(39 / columns))
        for (let i = 0; i < rows; ++i) keyClick(Qt.Key_Down)
        compare(grid.currentIndex, rows * columns)
        const tile = findChild(grid, "application-tile-" + rows * columns)
        verify(tile && tile.chosen)
        const top = tile.mapToItem(grid, 0, 0).y
        verify(top >= -0.5 && top + tile.height <= grid.height + 0.5)
        keyClick(Qt.Key_Up)
        verify(findChild(grid, "application-tile-" + (rows - 1) * columns).chosen)
        verify(!tile.chosen)
        // Typing starts the choice over, unshown.
        query.text = "App"
        verify(!findChild(grid, "application-tile-0").chosen)
        query.text = ""
        // With nothing typed and the keys not in the box, as when the drawer
        // has just opened, the arrows still choose, and Enter opens.
        launcher.forceActiveFocus()
        verify(!query.activeFocus)
        keyClick(Qt.Key_Right)
        verify(findChild(grid, "application-tile-0").chosen)
        keyClick(Qt.Key_Right)
        compare(grid.currentIndex, 1)
        controller.catalogActivated = -1
        keyClick(Qt.Key_Return)
        compare(controller.catalogActivated, 1)
        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // Holding an application, or right-clicking it, opens its sheet: its own
    // actions, which start afresh, Hide, Edit Application… where KDE's menu
    // editor can open it, and Uninstall once the software catalog can show it.
    function test_applicationSheet() {
        controller.opened()
        for (let i = 0; i < 6; ++i) catalog.append({name: "App " + i, icon: "application-x-executable"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(600)
        const grid = findChild(launcher, "application-grid")
        const sheet = findChild(launcher, "application-sheet")
        const tile = findChild(grid, "application-tile-1")
        verify(!sheet.opened)
        const touch = touchEvent(launcher)
        touch.press(0, tile, tile.width / 2, tile.height / 2).commit()
        wait(700)
        touch.release(0, tile, tile.width / 2, tile.height / 2).commit()
        tryCompare(sheet, "opened", true)
        verify(catalog.softwareAsked)
        compare(controller.catalogActivated, -1)
        const hide = findChild(launcher, "application-sheet-hide")
        const uninstall = findChild(launcher, "application-sheet-uninstall")
        compare(hide.text, "Hide")
        verify(!uninstall.visible)
        catalog.softwareReady = true
        verify(uninstall.visible)
        // Its own actions come first, each by its own index.
        const lines = []
        for (const line of sheet.contentItem.children) if (line.isSheetMenuItem && line.visible) lines.push(line.text)
        compare(lines, ["New Window", "New Private Window", "Hide", "Edit Application…", "Uninstall…"])
        verify(!findChild(launcher, "application-sheet-pin").visible)
        let privateWindow = null
        for (const line of sheet.contentItem.children) if (line.text === "New Private Window") privateWindow = line
        const closes = controller.closes
        mouseClick(privateWindow, privateWindow.width / 2, privateWindow.height / 2)
        compare(catalog.ran, [1, 2])
        compare(controller.closes, closes + 1)
        tryCompare(sheet, "opened", false)

        // A right-click opens it too; Hide hides, and the sheet then offers Unhide.
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        mouseClick(hide, hide.width / 2, hide.height / 2)
        verify(catalog.isHidden(1))
        tryCompare(sheet, "opened", false)
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        compare(hide.text, "Unhide")
        mouseClick(uninstall, uninstall.width / 2, uninstall.height / 2)
        compare(catalog.uninstalled, 1)
        tryCompare(sheet, "opened", false)

        // Edit Application… opens the menu editor on it, and Search steps aside.
        const edit = findChild(launcher, "application-sheet-edit")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        verify(edit.visible)
        const closesBeforeEdit = controller.closes
        mouseClick(edit, edit.width / 2, edit.height / 2)
        compare(catalog.edited, 1)
        compare(controller.closes, closesBeforeEdit + 1)
        tryCompare(sheet, "opened", false)

        // With Shuffle's dock there, the sheet pins to it and then unpins.
        controller.dockPresent = true
        const pin = findChild(launcher, "application-sheet-pin")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        verify(pin.visible)
        compare(pin.text, "Pin to dock")
        mouseClick(pin, pin.width / 2, pin.height / 2)
        compare(controller.pinAsks, [[1, true]])
        tryCompare(sheet, "opened", false)
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        compare(pin.text, "Unpin from dock")
        mouseClick(pin, pin.width / 2, pin.height / 2)
        compare(controller.pinAsks, [[1, true], [1, false]])
        tryCompare(sheet, "opened", false)
        controller.dockPresent = false
        controller.pinAsks = []
        controller.pinnedRows = []

        catalog.clear()
        catalog.hiddenSet = ({})
        catalog.softwareReady = false
        catalog.softwareAsked = false
        catalog.ran = []
        catalog.uninstalled = -1
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // Apps read again while it is open, as when an application is installed
    // or removed meanwhile, keeps the person's place: where Apps is scrolled
    // to, the application the keys chose, and an open sheet on its own
    // application. A sheet whose application has gone closes.
    function test_appsReadAgainKeepsThePlace() {
        controller.opened()
        for (let i = 0; i < 40; ++i)
            catalog.append({name: "App " + i, icon: "application-x-executable", appId: "app-" + i + ".desktop"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(600)
        const grid = findChild(launcher, "application-grid")
        const lines = findChild(launcher, "application-lines")
        const query = findChild(launcher, "search-query")
        const sheet = findChild(launcher, "application-sheet")
        // Right in the search box moves its cursor, so the keys choose from
        // Search itself, as when the drawer has just opened.
        launcher.forceActiveFocus()
        verify(!query.activeFocus)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Right)
        compare(grid.currentIndex, 2)
        lines.contentY = lines.originY + 120
        const top = lines.contentY
        // Installed meanwhile, ahead of the rest.
        catalog.insert(0, {name: "Aardvark", icon: "application-x-executable", appId: "aardvark.desktop"})
        verify(Math.abs(lines.contentY - top) < 0.5)
        compare(catalog.applicationId(grid.currentIndex), "app-2.desktop")
        lines.contentY = lines.originY
        tryVerify(function() { const chosen = findChild(grid, "application-tile-3"); return chosen && chosen.chosen })

        // The sheet keeps to its application as rows move.
        const tile = findChild(grid, "application-tile-5")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        compare(sheet.applicationId, "app-4.desktop")
        catalog.remove(0)
        compare(sheet.row, 4)
        verify(sheet.opened)
        // Removed meanwhile, it closes rather than act on another.
        catalog.remove(4)
        tryCompare(sheet, "opened", false)

        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // New folder sits beside the order over Apps. It asks for applications;
    // a tap chooses one, and Make folder, from two, gathers them into a
    // folder that opens with its name ready. Esc or Cancel lets it go.
    function test_appsNewFolder() {
        controller.opened()
        for (let i = 0; i < 4; ++i) catalog.append({name: "App " + i, icon: "application-x-executable"})
        catalog.made = []
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const newFolder = findChild(launcher, "apps-new-folder")
        const sort = findChild(launcher, "sort-button")
        verify(newFolder.visible && sort.visible)
        compare(newFolder.y, sort.y)
        verify(newFolder.x + newFolder.width <= sort.x)
        mouseClick(newFolder, newFolder.width / 2, newFolder.height / 2)
        verify(launcher.choosingFolder)
        verify(!newFolder.visible && !sort.visible)
        const make = findChild(launcher, "apps-folder-make")
        verify(make.visible && !make.enabled)
        const launchesBefore = controller.catalogActivated
        const tile = i => findChild(launcher, "application-tile-" + i)
        mouseClick(tile(0), tile(0).width / 2, tile(0).height / 2)
        verify(!make.enabled)
        mouseClick(tile(2), tile(2).width / 2, tile(2).height / 2)
        compare(launcher.folderPicks, ["app0", "app2"])
        verify(tile(0).picked && !tile(1).picked && tile(2).picked)
        compare(controller.catalogActivated, launchesBefore)
        verify(make.enabled)
        mouseClick(make, make.width / 2, make.height / 2)
        compare(catalog.made, ["app0", "app2"])
        verify(!launcher.choosingFolder)
        compare(launcher.renamingFolder, "made")
        launcher.renamingFolder = ""

        mouseClick(newFolder, newFolder.width / 2, newFolder.height / 2)
        verify(launcher.choosingFolder)
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        verify(!launcher.choosingFolder)
        verify(launcher.drawerOpen)
        mouseClick(newFolder, newFolder.width / 2, newFolder.height / 2)
        const cancel = findChild(launcher, "apps-folder-cancel")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        verify(!launcher.choosingFolder)

        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // An application dragged from Apps leaves as a carry, which the dock
    // takes as a pin; a tap still opens it.
    function test_applicationCarry() {
        controller.opened()
        for (let i = 0; i < 4; ++i) catalog.append({name: "App " + i, icon: "application-x-executable"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(600)
        const grid = findChild(launcher, "application-grid")
        const tile = findChild(grid, "application-tile-2")
        controller.carriedApplication = -1
        mouseDrag(tile, tile.width / 2, tile.height / 2, 0, 120)
        tryCompare(controller, "carriedApplication", 2)
        const sheet = findChild(launcher, "launcher-sheet")
        compare(controller.carriedSheet.width, sheet.width)
        controller.carriedApplication = -1
        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // A folder is a single tile among Apps' applications that a tap or Enter
    // opens and closes in place, its applications on a line under its own;
    // its sheet renames it under its tile or removes it. An application's sheet puts it in a folder, or takes it out
    // of the one it is in. A folder carried leaves as one.
    function test_folders() {
        controller.opened()
        controller.catalogActivated = -1
        catalog.openSet = ({})
        catalog.append({name: "Games", icon: "", kind: "folder", isFolder: true, folderId: "f1", inFolder: ""})
        for (let i = 0; i < 3; ++i) catalog.append({name: "App " + i, icon: "application-x-executable", kind: "application", isFolder: false, folderId: "", inFolder: i === 2 ? "f1" : ""})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(600)
        const grid = findChild(launcher, "application-grid")
        const header = () => findChild(grid, "apps-folder-0")
        verify(header().visible)
        verify(findChild(header(), "apps-folder-tile").visible)
        compare(grid.lines[0].rows[0], 0)
        verify(grid.lines.every(line => !line.member))
        mouseClick(header(), header().width / 2, header().height / 2)
        verify(catalog.openSet.f1)
        compare(controller.catalogActivated, -1)
        verify(launcher.drawerOpen)
        verify(grid.lines[0].rows.indexOf(3) < 0)
        verify(grid.lines[1].member)
        compare(JSON.stringify(grid.lines[1].rows), JSON.stringify([3]))
        mouseClick(header(), header().width / 2, header().height / 2)
        verify(!catalog.openSet.f1)
        // Enter on a chosen folder opens it too.
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Down)
        compare(grid.currentIndex, 0)
        keyClick(Qt.Key_Return)
        verify(catalog.openSet.f1)
        compare(controller.catalogActivated, -1)
        compare(grid.currentIndex, 0)
        catalog.setFolderOpen("f1", false)

        // The folder's sheet.
        const folderSheet = findChild(launcher, "apps-folder-sheet")
        mouseClick(header(), header().width / 2, header().height / 2, Qt.RightButton)
        tryCompare(folderSheet, "opened", true)
        const rename = findChild(launcher, "apps-folder-sheet-rename")
        mouseClick(rename, rename.width / 2, rename.height / 2)
        tryCompare(launcher, "renamingFolder", "f1")
        const name = findChild(header(), "apps-folder-name")
        tryCompare(name, "activeFocus", true)
        for (const letter of "play") keyClick(letter)
        keyClick(Qt.Key_Return)
        compare(catalog.renamed, ["f1", "play"])
        compare(launcher.renamingFolder, "")
        tryCompare(folderSheet, "opened", false)
        mouseClick(header(), header().width / 2, header().height / 2, Qt.RightButton)
        tryCompare(folderSheet, "opened", true)
        const remove = findChild(launcher, "apps-folder-sheet-remove")
        mouseClick(remove, remove.width / 2, remove.height / 2)
        compare(catalog.removed, "f1")
        tryCompare(folderSheet, "opened", false)

        // An application's sheet: Put in the folder, or Take out of it.
        const sheet = findChild(launcher, "application-sheet")
        const loose = findChild(grid, "application-tile-1")
        mouseClick(loose, loose.width / 2, loose.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        let putIn = null
        for (const line of sheet.contentItem.children) if (line.text === "Put in “Games”") putIn = line
        verify(putIn && putIn.visible)
        verify(!findChild(launcher, "application-sheet-take-out").visible)
        mouseClick(putIn, putIn.width / 2, putIn.height / 2)
        compare(catalog.putIn, [1, "f1"])
        tryCompare(sheet, "opened", false)
        const inside = findChild(grid, "application-tile-3")
        mouseClick(inside, inside.width / 2, inside.height / 2, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        const takeOut = findChild(launcher, "application-sheet-take-out")
        verify(takeOut.visible)
        for (const line of sheet.contentItem.children) verify(line.text !== "Put in “Games”" || !line.visible)
        mouseClick(takeOut, takeOut.width / 2, takeOut.height / 2)
        compare(catalog.takenOut, 3)
        tryCompare(sheet, "opened", false)

        // Carried, the folder leaves as one.
        controller.carriedFolder = -1
        controller.carriedApplication = -1
        mouseDrag(header(), header().width / 2, header().height / 2, 0, 120)
        tryCompare(controller, "carriedFolder", 0)
        compare(controller.carriedApplication, -1)

        controller.carriedFolder = -1
        catalog.renamed = []
        catalog.removed = ""
        catalog.putIn = []
        catalog.takenOut = -1
        catalog.openSet = ({})
        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // A to Z is one run with no rows of its own, applications of different
    // letters sharing a line, and no letters down the edge: the arrow keys
    // start on its first application.
    // Apps' tiles come in four sizes, kept apart from Files': Ctrl with + or
    // −, Ctrl and the wheel, or a pinch; as many fit across as the width holds.
    function test_appsZoom() {
        controller.opened()
        for (let i = 0; i < 24; ++i) catalog.append({name: "App " + i, icon: "application-x-executable", kind: "application"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const grid = findChild(launcher, "application-grid")
        catalog.tileSize = 1
        compare(grid.columns, Math.max(3, Math.floor(grid.width / 126)))
        const standard = grid.cellHeight
        const across = grid.columns
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Minus, Qt.ControlModifier)
        compare(catalog.tileSize, 0)
        verify(grid.columns > across)
        verify(grid.cellHeight < standard)
        keyClick(Qt.Key_Equal, Qt.ControlModifier)
        keyClick(Qt.Key_Equal, Qt.ControlModifier)
        keyClick(Qt.Key_Equal, Qt.ControlModifier)
        keyClick(Qt.Key_Equal, Qt.ControlModifier)
        compare(catalog.tileSize, 3)
        verify(grid.columns < across)
        verify(grid.cellHeight > standard)
        keyClick(Qt.Key_0, Qt.ControlModifier)
        compare(catalog.tileSize, 1)
        // Ctrl and the wheel, a notch a size.
        const lines = findChild(launcher, "application-lines")
        mouseWheel(lines, lines.width / 2, lines.height / 2, 0, 120, Qt.NoButton, Qt.ControlModifier)
        compare(catalog.tileSize, 2)
        mouseWheel(lines, lines.width / 2, lines.height / 2, 0, -120, Qt.NoButton, Qt.ControlModifier)
        compare(catalog.tileSize, 1)
        // The − / + pill at the right of the row, after the order.
        const larger = findChild(launcher, "apps-size-larger")
        const smaller = findChild(launcher, "apps-size-smaller")
        mouseClick(larger, larger.width / 2, larger.height / 2)
        compare(catalog.tileSize, 2)
        mouseClick(smaller, smaller.width / 2, smaller.height / 2)
        mouseClick(smaller, smaller.width / 2, smaller.height / 2)
        compare(catalog.tileSize, 0)
        verify(!smaller.enabled)
        mouseClick(smaller, smaller.width / 2, smaller.height / 2)
        compare(catalog.tileSize, 0)
        catalog.tileSize = 1
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        catalog.clear()
    }
    function test_oneRun() {
        controller.opened()
        for (let i = 0; i < 4; ++i) catalog.append({name: "Apple " + i, icon: "application-x-executable", kind: "application"})
        for (let i = 0; i < 4; ++i) catalog.append({name: "Banana " + i, icon: "application-x-executable", kind: "application"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const grid = findChild(launcher, "application-grid")
        verify(grid.lines.every(line => line.kind === "tiles"))
        verify(!findChild(launcher, "apps-jump-strip"))
        compare(grid.lines.length, Math.ceil(8 / grid.columns))
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Down)
        compare(grid.currentIndex, 0)
        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // Most used and Newest installed have sections, each with a row of its
    // own, which the arrow keys pass over.
    function test_sections() {
        controller.opened()
        catalog.sortOrder = 2
        catalog.append({name: "Used today", icon: "", kind: "section"})
        for (let i = 0; i < 3; ++i) catalog.append({name: "Apple " + i, icon: "application-x-executable", kind: "application"})
        catalog.append({name: "Earlier", icon: "", kind: "section"})
        for (let i = 0; i < 3; ++i) catalog.append({name: "Banana " + i, icon: "application-x-executable", kind: "application"})
        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const grid = findChild(launcher, "application-grid")
        compare(grid.lines.filter(line => line.kind === "section").length, 2)
        verify(findChild(launcher, "apps-section-label"))
        verify(!findChild(grid, "application-tile-0"))
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Down)
        compare(grid.currentIndex, 1)
        keyClick(Qt.Key_Down)
        compare(grid.currentIndex, 5)
        catalog.sortOrder = 0
        catalog.clear()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    function test_browseAndSort_data() {
        return [{ tag: "standalone", guest: false }, { tag: "card-line", guest: true }]
    }
    function test_fileScopeToggle() {
        controller.opened()
        launcher.setDrawerOpen(false)
        const query = findChild(launcher, "search-query")
        query.text = "wi"
        const toggle = findChild(launcher, "file-scope-toggle")
        verify(toggle)
        results.allFiles = false
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        compare(results.allFiles, true)
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        compare(results.allFiles, false)
        query.text = ""
    }
    function test_cardFootprint() {
        const sheet = findChild(launcher, "launcher-sheet")
        verify(sheet)
        controller.guestMode = false
        // One size on every display: 840 wide, centred.
        tryCompare(sheet, "width", 840)
        compare(sheet.height, sheet.restingHeight)
        compare(sheet.x, 80)
        controller.guestMode = true
        tryCompare(sheet, "width", controller.guestWidth)
        compare(sheet.height, controller.guestHeight)
        tryCompare(sheet, "x", controller.guestX)
        controller.guestMode = false
    }
    function test_missingSelectionDoesNotSearchWeb() {
        controller.opened()
        launcher.setDrawerOpen(false)
        const query = findChild(launcher, "search-query")
        query.text = "missing destination"
        results.querying = false
        results.hasPinnedSelection = true
        results.pinnedRow = -1
        controller.webSearches = 0
        launcher.submit()
        compare(controller.webSearches, 0)
        query.text = ""
    }
    function test_freshSearchStartsAtTop() {
        controller.opened()
        launcher.setDrawerOpen(false)
        const query = findChild(launcher, "search-query")
        const list = findChild(launcher, "search-result-list")
        query.text = "window"
        for (let i = 0; i < 10; ++i)
            results.append({display: "Window " + i, decoration: "preferences-system-windows", subtext: "Settings"})
        list.forceLayout()
        list.currentIndex = 5
        list.positionViewAtIndex(5, ListView.Beginning)
        query.text = "wi"
        tryVerify(function() { return Math.abs(list.contentY - list.originY) < 0.5 })
        results.clear()
        query.text = ""
    }
    function test_webFallbackWaitsForLocalSearch() {
        controller.opened()
        controller.webSearches = 0
        const query = findChild(launcher, "search-query")
        query.text = "unmatched example"
        results.querying = true
        launcher.submit()
        compare(controller.webSearches, 0)
        results.querying = false
        compare(controller.webSearches, 1)
        query.text = ""
        launcher.submit()
        compare(controller.webSearches, 1)
    }
    // A found application's sheet uninstalls it; other results have none.
    function test_resultSheetUninstalls() {
        controller.opened()
        const query = findChild(launcher, "search-query")
        query.text = "vlc"
        results.launches = 0
        results.append({display: "VLC media player", decoration: "vlc", subtext: "Application", applicationId: "vlc.desktop"})
        results.append({display: "vlc-notes.txt", decoration: "text-plain", subtext: "Document"})
        catalog.removable = ["vlc.desktop"]
        tryVerify(function() { return findChild(launcher, "result-1") !== null })
        const sheet = findChild(launcher, "result-sheet")
        const app = findChild(launcher, "result-0")
        const file = findChild(launcher, "result-1")
        verify(!sheet.opened)
        mouseClick(file, file.width / 2, 31, Qt.RightButton)
        wait(100)
        verify(!sheet.opened)
        mouseClick(app, app.width / 2, 31, Qt.RightButton)
        tryCompare(sheet, "opened", true)
        verify(catalog.softwareAsked)
        compare(results.launches, 0)
        const uninstall = findChild(launcher, "result-sheet-uninstall")
        const closes = controller.closes
        mouseClick(uninstall, uninstall.width / 2, uninstall.height / 2)
        compare(catalog.uninstalledApplication, "vlc.desktop")
        compare(controller.closes, closes + 1)
        tryCompare(sheet, "opened", false)
        // A hold opens it too, and opens nothing else.
        const touch = touchEvent(launcher)
        touch.press(0, app, app.width / 2, 31).commit()
        wait(700)
        touch.release(0, app, app.width / 2, 31).commit()
        tryCompare(sheet, "opened", true)
        compare(results.launches, 0)
        sheet.close()
        tryCompare(sheet, "opened", false)
        // An application nothing can uninstall has no sheet.
        catalog.removable = []
        mouseClick(app, app.width / 2, 31, Qt.RightButton)
        wait(100)
        verify(!sheet.opened)
        catalog.uninstalledApplication = ""
        catalog.softwareAsked = false
        results.clear()
        query.text = ""
    }
    // Opened by its key, Search is ready to type with the cursor in the
    // field; by its button, nothing takes the cursor, so no keys rise.
    function test_openedToType() {
        const query = findChild(launcher, "search-query")
        controller.toType = true
        controller.opened()
        verify(query.activeFocus)
        keyClick("k")
        compare(query.text, "k")
        controller.toType = false
        controller.opened()
        verify(!query.activeFocus)
        compare(query.text, "")
    }
    function test_bluetoothChildrenCollapse() {
        controller.opened()
        controller.bluetoothResult = true
        const query = findChild(launcher, "search-query")
        query.text = "bluetooth"
        results.append({display: "Bluetooth", decoration: "preferences-system-bluetooth", subtext: "Settings"})
        controller.bluetoothContext.connectedDevices = ["Headphones", "Keyboard"]
        controller.relatedRevision++
        tryVerify(function() { return findChild(launcher, "result-0") !== null })
        const result = findChild(launcher, "result-0")
        tryCompare(result, "height", 140)
        const highlight = findChild(launcher, "parent-highlight-0")
        compare(highlight.height, 56)
        const list = findChild(launcher, "search-result-list")
        list.currentIndex = 0
        launcher.selectedChildKey = ""
        launcher.moveResultSelection(1)
        compare(launcher.selectedChildKey, launcher.childKey(controller.relatedItems(0)[0]))
        compare(highlight.color, Qt.rgba(0, 0, 0, 0))
        launcher.moveResultSelection(1)
        compare(launcher.selectedChildKey, launcher.childKey(controller.relatedItems(0)[1]))
        launcher.moveResultSelection(-1)
        compare(launcher.selectedChildKey, launcher.childKey(controller.relatedItems(0)[0]))
        controller.activationResult = 0
        results.launches = 0
        launcher.submit()
        compare(results.launches, 1)
        compare(launcher.childLaunchFailed, false)
        compare(findChild(launcher, "child-options"), null)
        launcher.moveResultSelection(-1)
        compare(launcher.selectedChildKey, "")
        // The modes take room above, so a short sheet may scroll to show
        // the whole of the result.
        list.positionViewAtIndex(0, ListView.End)
        const child = findChild(launcher, "child-0-1")
        mouseClick(child, child.width / 2, child.height / 2)
        compare(results.launches, 2)
        compare(controller.activatedRow, 0)
        results.launchSucceeds = false
        launcher.submit()
        compare(launcher.childLaunchFailed, true)
        results.launchSucceeds = true
        controller.activationResult = 1
        controller.bluetoothContext.connectedDevices = []
        controller.relatedRevision++
        tryCompare(result, "height", 56)
        results.clear()
        controller.bluetoothResult = false
        query.text = ""
    }
    function test_bridgeLossRecoversSearch() {
        controller.closes = 0
        controller.guestMode = true
        controller.opened()
        launcher.applicationLaunchPending = true
        launcher.launchingApplication = "Example"
        controller.guestMode = false
        controller.guestBridgeLost()
        compare(launcher.applicationLaunchPending, false)
        compare(launcher.launchingApplication, "")
        compare(launcher.guestExiting, false)
        compare(controller.closes, 0)
    }
    function test_expandedDrawerReturnsCompact() {
        const sheet = findChild(launcher, "launcher-sheet")
        launcher.setDrawerOpen(true)
        // A drawer opens at Search's size; Expand fills the screen.
        compare(controller.drawerExpanded, false)
        controller.setDrawerExpanded(true, true)
        tryCompare(sheet, "width", 980)
        // Above a dock, as above any edge, it keeps the cards' 10 px gutter.
        tryCompare(sheet, "height", 720)
        compare(sheet.y + sheet.height, 730)
        compare(controller.drawerExpanded, true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const back = findChild(launcher, "home-dot")
        verify(back && back.visible && back.enabled)
        const header = findChild(launcher, "drawer-header")
        const search = findChild(launcher, "search-field")
        const grid = findChild(launcher, "application-grid")
        compare(header.y,0)
        // Search keeps its place over the drawer, with the order's row over
        // the applications.
        compare(search.y,0)
        compare(grid.y-search.y-search.height,16+50)
        compare(grid.y, 44+16+50)
        const closesBefore = controller.closes
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "drawerOpen", false)
        compare(controller.closes, closesBefore)
        tryCompare(sheet, "width", 840)
        tryCompare(sheet, "height", sheet.restingHeight)
        compare(controller.drawerExpanded, false)
    }
    function test_expandedDrawerWithoutLocalDock() {
        const original=controller.availableArea
        controller.availableArea=Qt.rect(0,0,launcher.width,launcher.height)
        launcher.setDrawerOpen(true,"files")
        controller.setDrawerExpanded(true,true)
        const sheet=findChild(launcher,"launcher-sheet")
        tryCompare(sheet,"height",launcher.height-20)
        compare(sheet.y,10)
        compare(launcher.height-sheet.y-sheet.height,10)
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        controller.availableArea=original
    }
    // Before anything is typed, the applications and the files used lately
    // sit under search in two labelled sections, eight of each: the
    // applications in a row, the files as cards in two rows of four. Search
    // keeps the size it first had, centred under the modes.
    function test_firstRow() {
        launcher.fileBrowser = filesMock
        fillRecent(20)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const modes = findChild(launcher, "mode-row")
        const dot = findChild(launcher, "home-dot")
        const row = findChild(launcher, "first-row")
        const field = findChild(launcher, "search-field")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        const close = findChild(launcher, "window-close")
        const sheet = findChild(launcher, "launcher-sheet")
        verify(modes.visible && dot.visible && apps.visible && files.visible)
        verify(dot.selected && !apps.selected && !files.selected)
        // The modes lead, above the field, in one row from the left; the
        // window's Close ends it alone, and Expand waits for a drawer.
        const top = item => item.mapToItem(launcher, 0, 0).y
        const left = item => item.mapToItem(launcher, 0, 0).x
        const right = item => item.mapToItem(launcher, item.width, 0).x
        verify(top(dot) + dot.height <= top(field))
        compare(top(apps), top(dot))
        compare(top(files), top(dot))
        verify(left(dot) < left(apps) && left(apps) < left(files))
        verify(close.visible && right(files) < left(close))
        verify(!findChild(launcher, "window-expand").visible)
        verify(!findChild(launcher, "window-pop-out").visible)
        compare(field.y, 0)
        compare(field.height, 44)
        // The field holds the row's edges: the dot's pill starts on its left
        // edge, and it runs to the right edge as Close does.
        compare(field.width, field.parent.width)
        compare(Math.round(left(dot) + (dot.width - 40) / 2), Math.round(left(field)))
        verify(right(close) <= right(field) + 1)
        // Both on, the sheet has its full height.
        compare(sheet.height, sheet.fullHeight)
        verify(row.visible)
        compare(row.sections, 2)
        compare(row.y - field.y - field.height, 24)
        verify(findChild(launcher, "recent-apps").visible && findChild(launcher, "recent-files").visible)
        verify(findChild(launcher, "recent-apps-see-all").visible && findChild(launcher, "recent-files-see-all").visible)
        // Eight applications along one row, each its share of the width.
        compare(row.appColumns, 8)
        const first = findChild(launcher, "recent-0")
        for (let i = 0; i < 10; ++i)
            compare(findChild(launcher, "recent-" + i).visible, i < 8)
        compare(first.height, 116)
        compare(findChild(launcher, "recent-1").x - first.x, row.appWidth)
        compare(findChild(launcher, "recent-7").y, first.y)
        // Eight files as cards in two rows of four, under their heading.
        compare(row.fileColumns, 4)
        compare(row.fileRows, 2)
        for (let i = 10; i < 20; ++i)
            compare(findChild(launcher, "recent-" + i).visible, i < 18)
        const card = findChild(launcher, "recent-10")
        const nextCard = findChild(launcher, "recent-11")
        const below = findChild(launcher, "recent-14")
        compare(card.x, 0)
        compare(nextCard.x - card.x - card.width, 12)
        compare(below.x, card.x)
        compare(below.y - card.y - card.height, 12)
        verify(card.y > first.y + first.height)
        verify(below.y + below.height <= row.height + 0.5)
        // Typing hands the room to the results, and clearing brings it back;
        // the modes and search stay.
        const query = findChild(launcher, "search-query")
        query.text = "x"
        tryCompare(row, "opacity", 0)
        verify(modes.visible && apps.visible)
        compare(field.y, 0)
        query.text = ""
        tryCompare(row, "opacity", 1)
    }
    // What is on sets how tall Search rests: the field alone, one section,
    // or both. Typing gives the sheet its full height, still centred.
    function test_firstRowSections() {
        launcher.fileBrowser = filesMock
        fillRecent(20)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const sheet = findChild(launcher, "launcher-sheet")
        const field = findChild(launcher, "search-field")
        const query = findChild(launcher, "search-query")
        const area = controller.availableArea
        const small = 2 * 24 + 56 + 44
        launcher.recentFiles = false
        tryCompare(sheet, "height", small + 24 + 40 + 116)
        verify(findChild(launcher, "recent-0").visible)
        verify(!findChild(launcher, "recent-files").visible)
        launcher.recentFiles = true
        launcher.recentApps = false
        tryCompare(sheet, "height", Math.min(area.height - 40, small + 24 + 40 + 2 * 150 + 12))
        verify(!findChild(launcher, "recent-apps").visible)
        verify(findChild(launcher, "recent-10").visible)
        compare(findChild(launcher, "recent-10").y, 40)
        launcher.recentFiles = false
        tryCompare(sheet, "height", small)
        compare(row.sections, 0)
        tryCompare(field, "y", 0)
        // Centred at rest, and still centred as typing grows it, evenly up
        // and down.
        const full = sheet.fullHeight
        const centred = height => area.y + Math.round((area.height - height) / 2)
        compare(sheet.y, centred(small))
        query.text = "x"
        tryCompare(sheet, "height", full)
        tryCompare(sheet, "y", centred(full))
        query.text = ""
        tryCompare(sheet, "height", small)
        tryCompare(sheet, "y", centred(small))
        // Opening again after typing, it is at once where and as tall as it
        // rests: nothing drops in from where it closed.
        query.text = "x"
        tryCompare(sheet, "height", full)
        controller.opened()
        compare(sheet.height, small)
        compare(sheet.y, centred(small))
        tryCompare(launcher, "sheetSettled", true)
        // A drawer gives it its full height too.
        launcher.setDrawerOpen(true)
        tryCompare(sheet, "height", full)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        tryCompare(sheet, "height", small)
    }
    // What was used lately arrives as one group; typing sends it away, and
    // clearing the field brings it back.
    function test_firstRowArrivesInTurn() {
        launcher.fileBrowser = filesMock
        fillRecent(3)
        controller.opened()
        const row = findChild(launcher, "first-row")
        const recent = findChild(launcher, "recent-0")
        tryCompare(row, "arrival", 1)
        compare(recent.reveal, 1)
        const query = findChild(launcher, "search-query")
        query.text = "x"
        tryCompare(row, "rest", 0)
        query.text = ""
        tryVerify(function() { return recent.reveal < 1 }, 1000)
        tryCompare(row, "arrival", 1)
        compare(row.rest, 1)
    }
    // A narrower sheet shows fewer applications and fewer columns of files,
    // rather than smaller ones.
    function test_firstRowNarrow() {
        launcher.fileBrowser = filesMock
        fillRecent(20)
        controller.availableArea = Qt.rect(0, 0, 640, 740)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        tryCompare(row, "appColumns", Math.floor(row.width / 72))
        verify(row.appColumns < 8)
        compare(row.fileColumns, Math.max(2, Math.min(4, Math.floor((row.width + 12) / 148))))
        compare(findChild(launcher, "recent-" + row.appColumns).visible, false)
        verify(row.appWidth >= 72)
        verify(row.fileWidth >= 136)
        verify(findChild(launcher, "apps-pill").visible && findChild(launcher, "files-pill").visible)
        controller.availableArea = Qt.rect(0, 0, 1000, 740)
    }
    // With both sections on and nothing used lately, each says so and keeps
    // its room: Search's size never waits on the record.
    function test_firstRowWithNothingUsed() {
        launcher.fileBrowser = filesMock
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const field = findChild(launcher, "search-field")
        const sheet = findChild(launcher, "launcher-sheet")
        compare(row.offered, 0)
        compare(sheet.height, sheet.fullHeight)
        compare(field.y, 0)
        verify(findChild(launcher, "recent-apps-empty").visible)
        verify(findChild(launcher, "recent-files-empty").visible)
        fillRecent(4)
        verify(!findChild(launcher, "recent-apps-empty").visible)
        verify(!findChild(launcher, "recent-files-empty").visible)
        compare(sheet.height, sheet.fullHeight)
    }
    // With the setting off the launcher has no record at all: the modes
    // alone, and Tab goes from one to the next.
    function test_firstRowSettingOff() {
        launcher.fileBrowser = filesMock
        launcher.recentUse = null
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        verify(apps.visible && files.visible)
        compare(row.sections, 0)
        verify(!findChild(launcher, "recent-0"))
        // Search rests small, the field under the modes and nothing under it.
        const field = findChild(launcher, "search-field")
        const sheet = findChild(launcher, "launcher-sheet")
        tryCompare(sheet, "height", 2 * 24 + 56 + 44)
        tryCompare(field, "y", 0)
        // and only as wide as the field and 24 on each side.
        tryCompare(sheet, "width", Math.min(640, controller.availableArea.width - 40))
        compare(field.width, sheet.width - 2 * 24)
        launcher.forceActiveFocus()
        for (let i = 0; i < 6 && !apps.activeFocus; ++i) keyClick(Qt.Key_Tab)
        verify(apps.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(files.activeFocus)
        launcher.recentUse = recentStub
    }
    // A tap on another mode moves straight there, the grey pill with it, and
    // the dot comes back to the first screen with what was typed.
    function test_modesSwitch() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        controller.closes = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const dot = findChild(launcher, "home-dot")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        const notes = findChild(launcher, "notes-pill")
        // The dot is a ring holding the mark of the mode shown, a small
        // dot on the first screen, and the panel's dot is told which mode shows.
        const mark = findChild(launcher, "home-dot-mark")
        tryCompare(mark, "openness", 1)
        mouseClick(apps, apps.width / 2, apps.height / 2)
        tryCompare(launcher, "drawerProgress", 1)
        verify(apps.selected && !files.selected && !dot.selected)
        verify(apps.visible && files.visible && notes.visible)
        compare(mark.openness, 1)
        verify(findChild(launcher, "home-dot-apps").visible)
        verify(!findChild(launcher, "home-dot-glyph").visible)
        verify(!mark.seed)
        compare(controller.showing, ["apps", false])
        mouseClick(files, files.width / 2, files.height / 2)
        tryVerify(() => launcher.drawerOpen && launcher.filesMode)
        verify(files.selected && !apps.selected)
        compare(controller.showing[0], "files")
        verify(findChild(launcher, "home-dot-glyph").visible)
        verify(!findChild(launcher, "home-dot-apps").visible)
        mouseClick(notes, notes.width / 2, notes.height / 2)
        tryCompare(launcher, "notesProgress", 1)
        verify(!launcher.drawerOpen && notes.selected && !files.selected)
        compare(controller.showing[0], "notes")
        verify(notes.visible && apps.visible)
        mouseClick(apps, apps.width / 2, apps.height / 2)
        tryCompare(launcher, "drawerProgress", 1)
        tryCompare(launcher, "notesProgress", 0)
        verify(!launcher.modeOpen && apps.selected)
        // A tap on the mode shown leaves it as it is.
        mouseClick(apps, apps.width / 2, apps.height / 2)
        wait(100)
        verify(launcher.drawerOpen && !launcher.filesMode)
        const touch = touchEvent(launcher)
        touch.press(0, dot, dot.width / 2, dot.height / 2).commit()
        wait(40)
        touch.release(0, dot, dot.width / 2, dot.height / 2).commit()
        tryCompare(launcher, "drawerOpen", false)
        tryCompare(launcher, "drawerProgress", 0)
        verify(dot.selected)
        tryCompare(mark, "openness", 1)
        verify(!findChild(launcher, "home-dot-apps").visible && !findChild(launcher, "home-dot-glyph").visible)
        verify(mark.seed)
        compare(controller.showing[0], "")
        compare(controller.closes, 0)
        launcher.quickNote = null
    }
    // Apps and Files each open their drawer, by mouse and by touch.
    function test_firstRowDoors() {
        launcher.fileBrowser = filesMock
        fillRecent(3)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const apps = findChild(launcher, "apps-pill")
        mouseClick(apps, apps.width / 2, apps.height / 2)
        tryCompare(launcher, "drawerProgress", 1)
        verify(!launcher.filesMode)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        wait(300)
        const files = findChild(launcher, "files-pill")
        const touch = touchEvent(launcher)
        touch.press(0, files, files.width / 2, files.height / 2).commit()
        wait(40)
        touch.release(0, files, files.width / 2, files.height / 2).commit()
        tryCompare(launcher, "drawerProgress", 1)
        verify(launcher.filesMode)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        wait(300)
    }
    // Something used lately opens by a click, a tap or the keys, and Search
    // closes after it.
    function test_recentOpens() {
        launcher.fileBrowser = filesMock
        fillRecent(3)
        controller.closes = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        tryCompare(findChild(launcher, "first-row"), "arrival", 1)
        const second = findChild(launcher, "recent-1")
        mouseClick(second, second.width / 2, second.height / 2)
        compare(recentStub.opened, [1])
        compare(controller.closes, 1)
        const third = findChild(launcher, "recent-2")
        const touch = touchEvent(launcher)
        touch.press(0, third, third.width / 2, third.height / 2).commit()
        wait(40)
        touch.release(0, third, third.width / 2, third.height / 2).commit()
        tryCompare(recentStub, "opened", [1, 2])
        compare(controller.closes, 2)
        // Tab reaches the doors and then what was used; Enter opens.
        launcher.forceActiveFocus()
        const apps = findChild(launcher, "apps-pill")
        for (let i = 0; i < 6 && !apps.activeFocus; ++i) keyClick(Qt.Key_Tab)
        verify(apps.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "files-pill").activeFocus)
        // Then the window's Close, at the end of their row, and the
        // applications' See all before them.
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "window-close").activeFocus)
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "recent-apps-see-all").activeFocus)
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "recent-0").activeFocus)
        keyClick(Qt.Key_Return)
        compare(recentStub.opened, [1, 2, 0])
    }
    // Without Gooseberry, or with Notes off, the modes are Apps and Files
    // alone, as before.
    function test_notesAbsent() {
        launcher.fileBrowser = filesMock
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const modes = findChild(launcher, "mode-row")
        const files = findChild(launcher, "files-pill")
        const notes = findChild(launcher, "notes-pill")
        verify(!notes.visible)
        launcher.notesDoor = notesStub
        notesStub.available = false
        verify(!notes.visible)
        verify(files.visible)
    }
    // Where Gooseberry is installed, Notes follows Files in the row: the same
    // pill, the same height and gap, and its own word.
    function test_notesOffered() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        fillRecent(8)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const modes = findChild(launcher, "mode-row")
        const files = findChild(launcher, "files-pill")
        const notes = findChild(launcher, "notes-pill")
        verify(notes.visible)
        compare(notes.label, "Notes")
        compare(notes.height, files.height)
        compare(notes.mapToItem(modes, 0, 0).y, files.mapToItem(modes, 0, 0).y)
        compare(notes.mapToItem(modes, 0, 0).x - files.mapToItem(modes, files.width, 0).x, modes.pillGap)
    }
    // Notes brings the quick-note sheet by a click, a tap or Enter, and Search
    // closes straight away: nothing waits for a window, in Spread or out.
    function test_notesOpens() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        controller.closes = 0
        controller.guestMode = true
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const notes = findChild(launcher, "notes-pill")
        mouseClick(notes, notes.width / 2, notes.height / 2)
        compare(notesStub.opened, 1)
        compare(controller.closes, 1)
        verify(!launcher.applicationLaunchPending)
        const touch = touchEvent(launcher)
        touch.press(0, notes, notes.width / 2, notes.height / 2).commit()
        wait(40)
        touch.release(0, notes, notes.width / 2, notes.height / 2).commit()
        tryCompare(notesStub, "opened", 2)
        compare(controller.closes, 2)
        launcher.forceActiveFocus()
        const apps = findChild(launcher, "apps-pill")
        for (let i = 0; i < 6 && !apps.activeFocus; ++i) keyClick(Qt.Key_Tab)
        verify(apps.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "files-pill").activeFocus)
        keyClick(Qt.Key_Tab)
        verify(notes.activeFocus)
        keyClick(Qt.Key_Return)
        compare(notesStub.opened, 3)
        compare(controller.closes, 3)
        compare(controller.guestLaunches, 0)
        controller.guestMode = false
    }
    // Gooseberry gone between opening Search and the tap: Search stays.
    function test_notesGoneStaysOpen() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        controller.closes = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        notesStub.available = false
        verify(!launcher.openNotes())
        compare(controller.closes, 0)
    }
    // At rest a pull opens nothing: Apps and Files are their own pills. The
    // open drawer's header still pulls down to close (test_drawerTopEdgeCloses).
    function test_noPullAtRest() {
        launcher.fileBrowser = filesMock
        const touch = touchEvent(launcher)
        const sheet = findChild(launcher, "launcher-sheet")
        for (const edge of [sheet.height - 12, 12]) {
            const at = sheet.mapToItem(launcher, sheet.width / 2, edge)
            const toward = edge > sheet.height / 2 ? -1 : 1
            touch.press(0, launcher, at.x, at.y).commit()
            wait(30)
            touch.move(0, launcher, at.x, at.y + toward * 30).commit()
            wait(30)
            touch.move(0, launcher, at.x, at.y + toward * 220).commit()
            wait(30)
            touch.release(0, launcher, at.x, at.y + toward * 220).commit()
            wait(300)
            compare(launcher.drawerOpen, false)
            compare(launcher.drawerProgress, 0)
        }
    }
    QtObject {
        id: filesMock
        property var entries: [{name:"Projects",path:"/home/test/Projects",directory:true,icon:"folder",detail:"Folder"}, {name:"Notes.txt",path:"/home/test/Notes.txt",directory:false,icon:"text-plain",detail:"842 B"}]
        property var tabs: [{label:"Home",path:"/home/test"}]
        property var places: [{label:"Home",path:"/home/test",icon:"user-home"},{label:"Downloads",path:"/home/test/Downloads",icon:"folder-download"}]
        property var crumbs: [{label:"Home",path:"/home/test"}]
        property int currentTab: 0
        property string path: "/home/test"
        property string placeKind: "folder"
        readonly property bool inFolder: placeKind === "folder"
        property bool listingFailed: false
        readonly property bool canWrite: inFolder && !listingFailed && !readOnly
        property bool readOnly: false
        readonly property string homePath: "/home/test"
        property string folder: placeKind === "recent" ? "" : "/home/test"
        property string searchText: ""
        property bool searching: false
        readonly property bool searchOffered: filter.trim().length > 0 && placeKind !== "recent" && filter.trim() !== searchText
        property var question: ({})
        property var answers: []
        function answer(choice, forAll) { answers = answers.concat([choice + (forAll ? "+all" : "")]); question = ({}) }
        property var openedWith: []
        function openWithChoices(path) {
            return {path: path, name: "Notes.txt", kind: "Plain text document", hasDefault: true,
                suggested: [{id: "org.kde.kate.desktop", name: "Kate", icon: "kate", isDefault: true},
                            {id: "org.kde.kwrite.desktop", name: "KWrite", icon: "kwrite", isDefault: false}]}
        }
        function allApplications() {
            return [{id: "alpha.desktop", name: "Alpha", icon: "", isDefault: false},
                    {id: "org.kde.kate.desktop", name: "Kate", icon: "kate", isDefault: false},
                    {id: "zeta.desktop", name: "Zeta", icon: "", isDefault: false}]
        }
        function openWith(path, id, always) { openedWith = [path, id, always] }
        signal applicationChoiceNeeded(string path)
        property bool canCompress: false
        property bool canExtract: false
        property int compresses: 0
        property int extracts: 0
        function compressSelected() { compresses++ }
        function extractSelected() { extracts++ }
        property bool canHide: false
        property bool canUnhide: false
        property int hides: 0
        property int unhides: 0
        function hideSelected() { hides++ }
        function unhideSelected() { unhides++ }
        property int trashItems: 0
        property string trashSize: ""
        property int trashChecks: 0
        property int empties: 0
        function checkTrash() { trashChecks++ }
        function emptyTrash() { empties++ }
        property var details: ({})
        property string describedPath: ""
        property int stops: 0
        function describe(path) {
            describedPath = path
            details = {name: "Notes.txt", icon: "text-plain", thumbnail: "",
                rows: [{label: "Kind", value: "Plain text document"}, {label: "Size", value: "842 B"}]}
        }
        function stopDescribing() { stops++; details = ({}) }
        property var searchedFor: []
        function searchInside(text) { searchedFor = searchedFor.concat([text]) }
        signal filterCleared()
        property string selectedPath: ""
        property string focusedPath: ""
        property string pastedInto: ""
        function pasteInto(path) { pastedInto=path }
        property var droppedPaths: []
        function copyDropped(paths,destination) { droppedPaths=paths; pastedInto=destination }
        function paste() { pastedInto=path }
        function selectAll() {}
        property var boxedPaths: []
        function selectPaths(paths) { boxedPaths=paths }
        property string error: ""
        property string filter: ""
        property bool busy: false
        property bool opening: false
        property bool working: false
        property bool canRestoreTrash: false
        function renameSelected(name) { createdName=name }
        property int cutCalls: 0
        property int trashCalls: 0
        function cutSelected() { cutCalls++ }
        function trashSelected() { trashCalls++ }
        function restoreTrash() {}
        property bool selecting: false
        property bool canPaste: false
        property string operationStatus: ""
        property var selectedPaths: selectedPath.length ? [selectedPath] : []
        property int openCalls: 0
        property int toggles: 0
        property int ranges: 0
        property string createdName: ""
        function newFolder(name) { createdName=name }
        function toggleSelected(path) { toggles++ }
        function selectRange(path,additive) { ranges++ }
        property bool canBack: false
        property bool canForward: false
        property bool hidden: false
        property int sortMode: 0
        property real scroll: 0
        property int tileSize: 1
        property string revealPath: ""
        property bool revealProperties: false
        property var navigated: []
        function navigate(path) { navigated = navigated.concat([path]) }
        property var tabsOpened: []
        function openTab(path) { tabsOpened = tabsOpened.concat([path]) }
        property string shownInFolder: ""
        function showInFolder(path) { shownInFolder = path }
        property int searchStops: 0
        function stopSearch() { searching = false; searchStops++ }
        property var everyPlace: [{id:"/0",label:"Home",path:"/home/test",icon:"user-home",hidden:false,system:true},
            {id:"/1",label:"Downloads",path:"/home/test/Downloads",icon:"folder-download",hidden:false,system:true},
            {id:"/2",label:"Music",path:"/home/test/Music",icon:"folder-music",hidden:true,system:true}]
        property int placesWidth: 0
        property var placeCalls: []
        function isPlace(path) { return everyPlace.some(p => p.path === path) }
        function addPlace(path) { placeCalls = placeCalls.concat(["add " + path]) }
        function renamePlace(id, name) { placeCalls = placeCalls.concat(["rename " + id + " " + name]) }
        function setPlaceHidden(id, hidden) { placeCalls = placeCalls.concat(["hide " + id + " " + hidden]) }
        function removePlace(id) { placeCalls = placeCalls.concat(["remove " + id]) }
        function movePlace(id, before) { placeCalls = placeCalls.concat(["move " + id + " " + before]) }
        property var copiedToPlace: []
        function copyToPlace(paths, place) { copiedToPlace = [paths, place] }
        property int restores: 0
        property int deletes: 0
        function restoreSelected() { restores++ }
        function deleteSelected() { deletes++ }
        property int refreshes: 0
        function refresh() { refreshes++ }
        property int tabsAdded: 0
        function addTab() { tabsAdded++ }
        property var drivesOpened: []
        property var drivesEjected: []
        function openDrive(id) { drivesOpened = drivesOpened.concat([id]) }
        function ejectDrive(id) { drivesEjected = drivesEjected.concat([id]) }
        property var operations: []
        property int suspends: 0
        property int resumes: 0
        property int cancels: 0
        function suspendOperation(id) { suspends++ }
        function resumeOperation(id) { resumes++ }
        function cancelOperation(id) { cancels++ }
        signal operationChanged()
        signal changed()
        function open() {}
        function openSelected() { openCalls++ }
    }
    function test_filesDrawer() {
        launcher.fileBrowser=filesMock
        const entry=findChild(launcher,"files-pill")
        verify(entry.visible)
        // The pill takes its place in the row with the next frame.
        waitForRendering(launcher)
        mouseClick(entry,entry.width/2,entry.height/2)
        tryCompare(launcher,"drawerProgress",1)
        verify(launcher.filesMode)
        compare(controller.drawerExpanded,false)
        const pane=findChild(launcher,"files-pane")
        verify(pane.visible)
        verify(!findChild(launcher,"application-grid").visible)
        const opensBefore=filesMock.openCalls
        const entryFile=findChild(launcher,"file-entry-Notes.txt")
        verify(entryFile)
        const togglesBefore=filesMock.toggles
        const rangesBefore=filesMock.ranges
        mouseClick(entryFile,entryFile.width/2,40,Qt.LeftButton,Qt.ControlModifier)
        compare(filesMock.toggles,togglesBefore+1)
        mouseClick(entryFile,entryFile.width/2,40,Qt.LeftButton,Qt.ShiftModifier)
        compare(filesMock.ranges,rangesBefore+1)
        verify(!filesMock.selecting)
        const grid=findChild(launcher,"files-grid")
        // Empty room beside the tiles, clear of the scroll handle at the
        // right edge.
        const emptyX=grid.width-40
        filesMock.selectedPath="/home/test/Notes.txt"
        mouseClick(grid,emptyX,grid.height-10)
        compare(filesMock.selectedPath,"")
        const folderTile=findChild(launcher,"file-entry-Projects")
        filesMock.boxedPaths=[]
        mousePress(grid,emptyX,grid.height-10)
        mouseMove(grid,2,2,30)
        mouseRelease(grid,2,2)
        compare(filesMock.boxedPaths.length,2)
        verify(filesMock.boxedPaths.indexOf("/home/test/Projects")>=0)
        filesMock.selectedPath="/home/test/Projects"
        mousePress(grid,emptyX,grid.height-10,Qt.LeftButton,Qt.ControlModifier)
        mouseMove(grid,2,2,30)
        mouseRelease(grid,2,2,Qt.LeftButton,Qt.ControlModifier)
        compare(filesMock.boxedPaths.length,1)
        compare(filesMock.boxedPaths[0],"/home/test/Notes.txt")
        mousePress(grid,emptyX,grid.height-10,Qt.LeftButton,Qt.ShiftModifier)
        mouseMove(grid,2,2,30)
        mouseRelease(grid,2,2,Qt.LeftButton,Qt.ShiftModifier)
        compare(filesMock.boxedPaths.length,2)
        mouseClick(folderTile,folderTile.width/2,40)
        compare(filesMock.selectedPath,"/home/test/Projects")
        compare(filesMock.path,"/home/test")
        filesMock.canPaste=true
        mouseClick(folderTile,folderTile.width/2,40,Qt.RightButton)
        const context=findChild(launcher,"file-context-menu")
        tryCompare(context,"opened",true)
        compare(context.targetPath,"/home/test/Projects")
        const pasteItem=findChild(launcher,"context-paste")
        mouseClick(pasteItem,pasteItem.width/2,pasteItem.height/2)
        compare(filesMock.pastedInto,"/home/test/Projects")
        context.close()
        filesMock.canPaste=false
        grid.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(filesMock.selectedPath,"")
        verify(launcher.drawerOpen)
        launcher.submit() // Files Enter routes only to the Files backend.
        compare(filesMock.openCalls,opensBefore+1)
        filesMock.selectedPath="/home/test/Notes.txt"
        const openFile=findChild(launcher,"open-file")
        verify(openFile.enabled)
        mouseClick(openFile,openFile.width/2,openFile.height/2)
        compare(filesMock.openCalls,opensBefore+2)
        grid.forceActiveFocus()
        const cuts=filesMock.cutCalls
        keyClick(Qt.Key_X,Qt.ControlModifier)
        compare(filesMock.cutCalls,cuts+1)
        keyClick(Qt.Key_F2)
        const renameInput=findChild(launcher,"folder-name")
        verify(renameInput.visible)
        compare(renameInput.text,"Notes.txt")
        renameInput.text="Renamed.txt"
        keyClick(Qt.Key_Return)
        compare(filesMock.createdName,"Renamed.txt")
        grid.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        const confirm=findChild(launcher,"trash-confirm")
        tryCompare(confirm,"opened",true)
        const trashes=filesMock.trashCalls
        confirm.reject()
        compare(filesMock.trashCalls,trashes)
        filesMock.selectedPath=""
        const newFolder=findChild(launcher,"new-folder")
        mouseClick(newFolder,newFolder.width/2,newFolder.height/2)
        verify(findChild(launcher,"folder-name").visible)
        const folderInput=findChild(launcher,"folder-name")
        folderInput.text="Created folder"
        folderInput.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(filesMock.createdName,"Created folder")
        compare(filesMock.filter,"")
        mouseClick(newFolder,newFolder.width/2,newFolder.height/2)
        tryVerify(function(){ return findChild(launcher,"folder-name").visible })
        // The form's row is laid out with the next frame; Cancel is tapped
        // where it is drawn, not where it sat before.
        waitForRendering(launcher)
        const cancel=findChild(launcher,"cancel-folder")
        tryVerify(function(){ return cancel.width>0 && cancel.mapToItem(launcher,0,0).x>0 })
        mouseClick(cancel,cancel.width/2,cancel.height/2)
        tryVerify(function(){ return !findChild(launcher,"folder-name").visible })
        filesMock.operationStatus="Done"
        wait(20)
        verify(pane.showOperationSuccess)
        compare(pane.operationStatusText,"Done")
        wait(820)
        verify(!pane.showOperationSuccess)
        compare(pane.operationStatusText,"")
        filesMock.operationStatus="Copying"
        compare(pane.operationStatusText,"Copying")
        filesMock.operationStatus=""
        wait(300)
        grabImage(launcher).save("/tmp/tette-files-preview.png")
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        compare(controller.drawerExpanded,false)
        launcher.setDrawerOpen(true)
        tryCompare(launcher,"drawerProgress",1)
        verify(!launcher.filesMode)
        verify(!pane.visible)
    }
    function test_filesTouchSelection() {
        launcher.fileBrowser=filesMock
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        wait(600) // Let the previous test's gesture/tap sequence finish.
        const entry=findChild(launcher,"files-pill")
        mouseClick(entry,entry.width/2,entry.height/2)
        tryCompare(launcher,"drawerProgress",1)
        controller.setDrawerExpanded(true,true)
        wait(250)
        const folder=findChild(launcher,"file-entry-Projects")
        const file=findChild(launcher,"file-entry-Notes.txt")
        const menu=findChild(launcher,"file-context-menu")
        const grid=findChild(launcher,"files-grid")
        const touch=touchEvent(launcher)
        filesMock.selecting=false
        filesMock.selectedPath=""
        const before=filesMock.openCalls
        // A tap opens: a folder opens in place.
        touch.press(0,folder,folder.width/2,40).commit()
        wait(30)
        touch.release(0,folder,folder.width/2,40).commit()
        compare(filesMock.selectedPath,"/home/test/Projects")
        compare(filesMock.openCalls,before+1)
        verify(!menu.visible)
        // A second tap right after it belongs to the first, not to what is
        // now under the finger.
        wait(50)
        touch.press(0,folder,folder.width/2,40).commit()
        wait(30)
        touch.release(0,folder,folder.width/2,40).commit()
        compare(filesMock.openCalls,before+1)
        wait(600)
        touch.press(0,file,file.width/2,40).commit()
        wait(30)
        touch.release(0,file,file.width/2,40).commit()
        compare(filesMock.selectedPath,"/home/test/Notes.txt")
        compare(filesMock.openCalls,before+2)
        verify(!menu.visible)
        // A touch and hold starts choosing several, with no menu; the action
        // bar offers what to do.
        wait(600)
        filesMock.selectedPath=""
        touch.press(0,file,file.width/2,40).commit()
        wait(230)
        verify(!filesMock.selecting)
        wait(400)
        touch.release(0,file,file.width/2,40).commit()
        verify(filesMock.selecting)
        compare(filesMock.selectedPath,"/home/test/Notes.txt")
        compare(filesMock.openCalls,before+2)
        wait(100)
        verify(!menu.visible)
        verify(findChild(launcher,"done-selecting").visible)
        verify(findChild(launcher,"selection-copy").visible)
        verify(findChild(launcher,"selection-cut").visible)
        verify(findChild(launcher,"selection-rename").visible)
        verify(findChild(launcher,"selection-trash").visible)
        verify(!findChild(launcher,"new-folder").visible)
        // Choosing, a tap adds or removes rather than opening.
        const toggles=filesMock.toggles
        touch.press(0,folder,folder.width/2,40).commit()
        wait(30)
        touch.release(0,folder,folder.width/2,40).commit()
        compare(filesMock.toggles,toggles+1)
        compare(filesMock.openCalls,before+2)
        const cut=findChild(launcher,"selection-cut")
        const cuts=filesMock.cutCalls
        mouseClick(cut)
        compare(filesMock.cutCalls,cuts+1)
        touch.press(0,grid,grid.width-10,grid.height-10).commit()
        wait(30)
        touch.release(0,grid,grid.width-10,grid.height-10).commit()
        compare(filesMock.selectedPath,"")
        verify(!filesMock.selecting)
        verify(!menu.visible)
        const pane=findChild(launcher,"files-pane")
        filesMock.droppedPaths=[]; filesMock.pastedInto=""
        wait(600)
        touch.press(0,file,file.width/2,40).commit()
        wait(620)
        touch.move(0,file,file.width/2-30,40).commit()
        wait(30)
        touch.move(0,folder,folder.width/2,40).commit()
        wait(30)
        verify(pane.draggingFiles)
        compare(pane.dropFolder,"/home/test/Projects")
        verify(!menu.visible)
        touch.release(0,folder,folder.width/2,40).commit()
        tryCompare(pane,"draggingFiles",false)
        tryCompare(filesMock,"pastedInto","/home/test/Projects")
        const savedEntries=filesMock.entries
        let many=[]
        for(let i=0;i<100;i++)many.push({name:"Item"+i,path:"/home/test/Item"+i,directory:false,icon:"text-plain",detail:"file"})
        filesMock.entries=many
        wait(100)
        const first=findChild(launcher,"file-entry-Item0")
        verify(first)
        mousePress(first,first.width/2,40)
        mouseMove(first,first.width/2+30,40,30)
        mouseMove(grid,grid.width/2,grid.height-3,30)
        wait(160)
        verify(grid.contentY>0)
        keyClick(Qt.Key_Escape)
        verify(!pane.draggingFiles)
        mouseRelease(grid,grid.width/2,grid.height-3)
        grid.contentY=0
        mousePress(grid,1,20)
        mouseMove(grid,grid.width/2,grid.height-3,30)
        wait(160)
        verify(grid.contentY>0)
        mouseRelease(grid,grid.width/2,grid.height-3)
        filesMock.entries=savedEntries; grid.contentY=0
        compare(filesMock.droppedPaths[0],"/home/test/Notes.txt")
        verify(!menu.visible)
        filesMock.pastedInto=""
        wait(100)
        const fileAgain=findChild(launcher,"file-entry-Notes.txt")
        const folderAgain=findChild(launcher,"file-entry-Projects")
        mousePress(fileAgain,fileAgain.width/2,40)
        mouseMove(fileAgain,fileAgain.width/2-30,40,30)
        mouseMove(folderAgain,folderAgain.width/2,40,30)
        verify(pane.draggingFiles)
        mouseRelease(folderAgain,folderAgain.width/2,40)
        tryCompare(filesMock,"pastedInto","/home/test/Projects")
        // Past the sheet's edge the carried files leave for another
        // application, by mouse and by touch, and nothing is copied here.
        const sheet=findChild(launcher,"launcher-sheet")
        filesMock.pastedInto=""; controller.carried=[]
        wait(100)
        mousePress(fileAgain,fileAgain.width/2,40)
        mouseMove(fileAgain,fileAgain.width/2-30,40,30)
        verify(pane.draggingFiles)
        mouseMove(launcher,sheet.x-20,sheet.y+sheet.height/2,30)
        compare(controller.carried,["/home/test/Notes.txt"])
        compare(controller.carriedSheet,Qt.rect(sheet.x,sheet.y,sheet.width,sheet.height))
        verify(!pane.draggingFiles)
        mouseRelease(launcher,sheet.x-20,sheet.y+sheet.height/2)
        controller.carried=[]
        wait(600)
        touch.press(0,fileAgain,fileAgain.width/2,40).commit()
        wait(620)
        touch.move(0,fileAgain,fileAgain.width/2-30,40).commit()
        wait(30)
        verify(pane.draggingFiles)
        touch.move(0,launcher,sheet.x+sheet.width/2,sheet.y+sheet.height+20).commit()
        wait(30)
        compare(controller.carried,["/home/test/Notes.txt"])
        verify(!pane.draggingFiles)
        touch.release(0,launcher,sheet.x+sheet.width/2,sheet.y+sheet.height+20).commit()
        wait(100)
        compare(filesMock.pastedInto,"")
    }
    function test_filesTilesOperationsAndRename() {
        launcher.fileBrowser=filesMock
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        wait(600)
        const entry=findChild(launcher,"files-pill")
        mouseClick(entry,entry.width/2,entry.height/2)
        tryCompare(launcher,"drawerProgress",1)
        controller.setDrawerExpanded(true,true)
        wait(250)
        const grid=findChild(launcher,"files-grid")
        const pane=findChild(launcher,"files-pane")
        filesMock.tileSize=1
        const standard=grid.cellHeight
        // Ctrl with + or − resizes the tiles; Ctrl+0 returns them.
        grid.forceActiveFocus()
        keyClick(Qt.Key_Equal,Qt.ControlModifier)
        compare(filesMock.tileSize,2)
        verify(grid.cellHeight>standard)
        keyClick(Qt.Key_Minus,Qt.ControlModifier)
        keyClick(Qt.Key_Minus,Qt.ControlModifier)
        compare(filesMock.tileSize,0)
        verify(grid.cellHeight<standard)
        keyClick(Qt.Key_0,Qt.ControlModifier)
        compare(filesMock.tileSize,1)
        // Fingers spreading apart make the tiles larger.
        const touch=touchEvent(launcher)
        const cx=grid.width/2, cy=grid.height/2
        touch.press(0,grid,cx-40,cy).press(1,grid,cx+40,cy).commit()
        for(let i=1;i<=8;i++) {
            wait(16)
            touch.move(0,grid,cx-40-12*i,cy).move(1,grid,cx+40+12*i,cy).commit()
        }
        touch.release(0,grid,cx-136,cy).release(1,grid,cx+136,cy).commit()
        verify(filesMock.tileSize>1)
        filesMock.tileSize=1
        // A running copy has its own row: Pause and Cancel act on it alone.
        filesMock.operations=[{id:"op-1",label:"Copying…",title:"big.iso",progress:0.4,suspended:false,canSuspend:true,canCancel:true,copying:true}]
        filesMock.operationChanged()
        const pause=findChild(launcher,"operation-pause-op-1")
        verify(pause && pause.visible)
        mouseClick(pause)
        compare(filesMock.suspends,1)
        const cancel=findChild(launcher,"operation-cancel-op-1")
        mouseClick(cancel)
        compare(filesMock.cancels,1)
        filesMock.operations=[]
        filesMock.operationChanged()
        tryVerify(()=>findChild(launcher,"operation-pause-op-1")===null)
        // Rename selects the name and leaves its extension.
        filesMock.selectedPath="/home/test/Notes.txt"
        pane.renameForm()
        const name=findChild(launcher,"folder-name")
        compare(name.selectedText,"Notes")
        pane.creatingFolder=false
        // Show in Files brings the file into view, once.
        filesMock.revealPath="/home/test/Notes.txt"
        filesMock.changed()
        tryCompare(filesMock,"revealPath","")
        filesMock.selectedPath=""
    }
    // At a card's size the places fold to a rail of icons and the tiles come
    // one size smaller; filling the screen brings both back.
    function test_filesCard() {
        launcher.fileBrowser=filesMock
        filesMock.tileSize=2
        launcher.setDrawerOpen(true,"files")
        tryCompare(launcher,"drawerProgress",1)
        filesMock.places=[{label:"Home",path:"/home/test",icon:"user-home",section:"places"}]
        const pane=findChild(launcher,"files-pane")
        const places=findChild(launcher,"files-places")
        // Files opens as a card, the places a rail.
        compare(controller.drawerExpanded,false)
        verify(pane.card)
        tryCompare(places,"width",54)
        compare(pane.tile.cell,140)
        controller.drawerExpanded=true
        verify(!pane.card)
        tryCompare(places,"width",170)
        compare(pane.tile.cell,184)
        compare(filesMock.tileSize,2)
        controller.drawerExpanded=false
        tryCompare(places,"width",54)
        compare(pane.tile.cell,140)
        // Their own button opens the places at a card's size, and the first
        // touch on the folder folds them back.
        const fold=findChild(launcher,"files-places-fold")
        // Folded, the button is a circle among the icons; open, a pill that
        // says Fold beside its glyph.
        compare(fold.width,40)
        verify(!findChild(launcher,"files-places-fold-label").visible)
        mouseClick(fold)
        tryCompare(places,"width",170)
        compare(fold.height,40)
        verify(findChild(launcher,"files-places-fold-label").visible)
        verify(fold.width>40 && fold.width<places.width)
        mouseClick(pane,pane.width-40,pane.height/2)
        tryCompare(places,"width",54)
        // Filling the screen they stay open until their button folds them;
        // a touch on the folder leaves them as they are.
        controller.drawerExpanded=true
        tryCompare(places,"width",170)
        mouseClick(pane,pane.width-40,pane.height/2)
        compare(places.width,170)
        mouseClick(fold)
        tryCompare(places,"width",54)
        mouseClick(fold)
        // Open, they are as wide as the longest name, never more than 240.
        filesMock.places=[{label:"Home",path:"/home/test",icon:"user-home",section:"places"},
            {label:"Pictures from the phone",path:"/home/test/Phone",icon:"folder",section:"places"}]
        tryVerify(() => places.width>170 && places.width<240)
        filesMock.places=[{label:"A very long folder name that would never fit here at all",path:"/home/test/Long",icon:"folder",section:"places"}]
        tryCompare(places,"width",240)
        controller.drawerExpanded=false
        tryCompare(places,"width",54)
        filesMock.tileSize=1
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
    }
    // Files' one row: the size pill after the order, the path typed at the
    // empty end of the crumbs, and Refresh on F5.
    function test_filesRow() {
        launcher.fileBrowser=filesMock
        filesMock.selectedPath=""
        filesMock.selecting=false
        filesMock.placeKind="folder"
        filesMock.tileSize=1
        launcher.setDrawerOpen(true,"files")
        tryCompare(launcher,"drawerProgress",1)
        wait(250)
        const size=findChild(launcher,"files-size")
        const sort=findChild(launcher,"files-sort")
        verify(size.visible)
        verify(sort.mapToItem(null,sort.width,0).x <= size.mapToItem(null,0,0).x-7.5)
        const larger=findChild(launcher,"files-size-larger")
        mouseClick(larger,larger.width/2,larger.height/2)
        compare(filesMock.tileSize,2)
        verify(!findChild(launcher,"path-toggle"))
        const end=findChild(launcher,"path-open-area")
        const editor=findChild(launcher,"path-editor")
        verify(!editor.visible)
        mouseClick(end,end.width/2,end.height/2)
        tryVerify(() => editor.visible && editor.activeFocus)
        compare(editor.text,"/home/test")
        keyClick(Qt.Key_Escape)
        verify(!editor.visible)
        const refreshes=filesMock.refreshes
        findChild(launcher,"files-grid").forceActiveFocus()
        keyClick(Qt.Key_F5)
        compare(filesMock.refreshes,refreshes+1)
        // A chosen file's actions take the right side.
        filesMock.selectedPath="/home/test/Notes.txt"
        verify(!size.visible && !sort.visible)
        verify(findChild(launcher,"selection-copy").visible)
        filesMock.selectedPath=""
        filesMock.tileSize=1
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
    }
    // The places: + beside Fold, each place's own sheet, which show, the
    // edge dragged to a width, and Trash's own actions.
    function test_filesPlaces() {
        launcher.fileBrowser=filesMock
        filesMock.selectedPath=""
        filesMock.selecting=false
        filesMock.placeKind="folder"
        filesMock.placeCalls=[]
        filesMock.placesWidth=0
        filesMock.places=[{label:"Recent",path:"recentlyused:/",icon:"document-open-recent",section:"places"},
            {id:"/0",label:"Home",path:"/home/test",icon:"user-home",section:"places",system:true},
            {id:"/1",label:"Projects",path:"/home/test/Projects",icon:"folder",section:"places",system:false},
            {id:"/2",label:"Trash",path:"trash:/",icon:"user-trash",section:"places",system:true}]
        controller.drawerExpanded=true
        launcher.setDrawerOpen(true,"files")
        tryCompare(launcher,"drawerProgress",1)
        wait(250)
        const places=findChild(launcher,"files-places")
        findChild(launcher,"files-pane").placesOpen=true
        tryCompare(places,"width",170)
        // + opens its sheet; this folder is already a place.
        const add=findChild(launcher,"files-places-add")
        verify(add.visible)
        const fold=findChild(launcher,"files-places-fold")
        verify(fold.x+fold.width < add.x)
        mouseClick(add,add.width/2,add.height/2)
        const addSheet=findChild(launcher,"places-add-sheet")
        tryCompare(addSheet,"opened",true)
        verify(!findChild(launcher,"places-add-this").enabled)
        findChild(launcher,"places-show-hide").choose()
        const shown=findChild(launcher,"places-shown-sheet")
        tryCompare(shown,"opened",true)
        const shownList=findChild(launcher,"places-shown-list")
        verify(shownList)
        tryCompare(shownList,"count",3)
        const eye=findChild(shownList.itemAtIndex(2),"places-shown-eye-Music")
        verify(eye)
        compare(eye.glyph,"eye-off")
        mouseClick(eye,eye.width/2,eye.height/2)
        compare(filesMock.placeCalls,["hide /2 false"])
        shown.close()
        tryCompare(shown,"opened",false)
        // A place's sheet: KDE's own hide, the person's own also go.
        const home=findChild(launcher,"files-place-Home")
        mouseClick(home,home.width/2,home.height-20,Qt.RightButton)
        const sheet=findChild(launcher,"place-sheet")
        tryCompare(sheet,"opened",true)
        verify(findChild(launcher,"place-hide").visible)
        verify(!findChild(launcher,"place-remove").visible)
        findChild(launcher,"place-hide").choose()
        compare(filesMock.placeCalls[1],"hide /0 true")
        const projects=findChild(launcher,"files-place-Projects")
        mouseClick(projects,projects.width/2,projects.height-20,Qt.RightButton)
        tryCompare(sheet,"opened",true)
        verify(findChild(launcher,"place-remove").visible)
        findChild(launcher,"place-remove").choose()
        compare(filesMock.placeCalls[2],"remove /1")
        const trash=findChild(launcher,"files-place-Trash")
        mouseClick(trash,trash.width/2,trash.height-20,Qt.RightButton)
        tryCompare(sheet,"opened",true)
        verify(findChild(launcher,"place-empty-trash").visible)
        verify(!findChild(launcher,"place-remove").visible)
        sheet.close()
        // The edge: dragged out to a width it keeps, dragged in it folds.
        const edge=findChild(launcher,"files-places-edge")
        const at=edge.mapToItem(launcher,0,edge.height/2)
        mousePress(launcher,at.x,at.y)
        mouseMove(launcher,at.x+20,at.y)
        mouseMove(launcher,at.x+40,at.y)
        mouseRelease(launcher,at.x+40,at.y)
        tryCompare(filesMock,"placesWidth",210)
        filesMock.placesWidth=210
        tryCompare(places,"width",210)
        const at2=edge.mapToItem(launcher,0,edge.height/2)
        mousePress(launcher,at2.x,at2.y)
        mouseMove(launcher,at2.x-60,at2.y)
        mouseMove(launcher,at2.x-120,at2.y)
        mouseRelease(launcher,at2.x-120,at2.y)
        tryCompare(places,"width",54)
        compare(filesMock.placesWidth,210)
        mouseClick(fold)
        tryCompare(places,"width",210)
        filesMock.placesWidth=0
        // In Trash, chosen files go back or are deleted for good.
        filesMock.placeKind="trash"
        filesMock.selectedPath="/home/test/Notes.txt"
        verify(findChild(launcher,"selection-restore").visible)
        verify(findChild(launcher,"selection-delete").visible)
        verify(!findChild(launcher,"selection-copy").visible)
        verify(!findChild(launcher,"selection-trash").visible)
        wait(50)
        const restore=findChild(launcher,"selection-restore")
        mouseClick(restore,restore.width/2,restore.height/2)
        compare(filesMock.restores,1)
        const del=findChild(launcher,"selection-delete")
        mouseClick(del,del.width/2,del.height/2)
        const confirm=findChild(launcher,"delete-confirm")
        tryCompare(confirm,"opened",true)
        confirm.accept()
        compare(filesMock.deletes,1)
        tryCompare(confirm,"opened",false)
        filesMock.selectedPath=""
        filesMock.placeKind="folder"
        filesMock.places=[{label:"Home",path:"/home/test",icon:"user-home"},{label:"Downloads",path:"/home/test/Downloads",icon:"folder-download"}]
        controller.drawerExpanded=false
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
    }
    // Drives follow the places under a rule: a tap opens one, and one plugged
    // in ejects from its own button, by mouse and by touch. Busy, a drive says
    // what it is doing and takes no tap.
    function test_filesDrives() {
        launcher.fileBrowser=filesMock
        launcher.setDrawerOpen(true,"files")
        controller.setDrawerExpanded(true,true) // names and eject buttons show at full size
        tryCompare(launcher,"drawerProgress",1)
        wait(250) // the sheet's own growth settles before the rows are tapped
        const home={label:"Home",path:"/home/test",icon:"user-home",section:"places"}
        const root={label:"ROOTFS",path:"/",icon:"drive-harddisk",section:"drives",drive:"root",mounted:true,canEject:false,busy:false,note:""}
        const stick={label:"STICK",path:"/run/media/test/STICK",icon:"drive-removable-media",section:"drives",drive:"stick",mounted:true,canEject:true,busy:false,note:""}
        filesMock.places=[home,root,stick]
        const rootRow=findChild(launcher,"files-place-ROOTFS"), stickRow=findChild(launcher,"files-place-STICK")
        verify(rootRow && stickRow)
        verify(rootRow.firstDrive && !stickRow.firstDrive && !findChild(launcher,"files-place-Home").firstDrive)
        verify(!findChild(launcher,"files-eject-ROOTFS").visible)
        const eject=findChild(launcher,"files-eject-STICK")
        verify(eject.visible)
        filesMock.navigated=[]; filesMock.drivesOpened=[]; filesMock.drivesEjected=[]
        mouseClick(stickRow,30,stickRow.height-27)
        compare(filesMock.drivesOpened,["stick"])
        mouseClick(eject)
        compare(filesMock.drivesEjected,["stick"])
        compare(filesMock.drivesOpened,["stick"]) // the button opens nothing
        const touch=touchEvent(launcher)
        touch.press(0,eject,eject.width/2,eject.height/2).commit(); wait(20)
        touch.release(0,eject,eject.width/2,eject.height/2).commit(); wait(20)
        compare(filesMock.drivesEjected,["stick","stick"])
        mouseClick(findChild(launcher,"files-place-Home"),30,27)
        compare(filesMock.navigated,["/home/test"])
        filesMock.places=[home,root,Object.assign({},stick,{busy:true,note:"Ejects when done"})]
        const busyRow=findChild(launcher,"files-place-STICK")
        verify(!findChild(launcher,"files-eject-STICK").visible)
        const note=findChild(launcher,"files-place-note-STICK")
        verify(note.visible)
        compare(note.text,"Ejects when done")
        verify(!findChild(launcher,"files-place-note-ROOTFS").visible)
        mouseClick(busyRow,30,busyRow.height-27)
        compare(filesMock.drivesOpened,["stick"])
        // Another application's request for Properties opens them once the file shows.
        filesMock.places=[home]
        filesMock.describedPath=""
        filesMock.revealPath="/home/test/Notes.txt"
        filesMock.revealProperties=true
        filesMock.changed()
        tryCompare(filesMock,"revealPath","")
        compare(filesMock.revealProperties,false)
        compare(filesMock.describedPath,"/home/test/Notes.txt")
        findChild(launcher,"properties-sheet").close()
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
    }
    // The keys at their tallest (52%) and shortest (32%) in this 800-high window.
    readonly property rect tallKeys: Qt.rect(0, 384, 1000, 416)
    readonly property rect shortKeys: Qt.rect(0, 544, 1000, 256)
    function bottomOf(item) { return item.mapToItem(launcher, 0, item.height).y }
    function test_keysKeepSearchAbove() {
        const sheet = findChild(launcher, "launcher-sheet")
        const query = findChild(launcher, "search-query")
        const field = findChild(launcher, "search-field")
        const list = findChild(launcher, "search-result-list")
        results.clear()
        for (let i = 0; i < 12; ++i)
            results.append({display: "Window " + i, decoration: "preferences-system-windows", subtext: "Settings"})
        query.text = "window"
        // Both sections on, Search rests as tall as they are, as far as the
        // screen allows, and keeps that height for the results.
        tryCompare(sheet, "height", 700)
        tryCompare(sheet, "y", 20)
        // The tallest keys: the sheet rises to the top and shortens to fit.
        launcher.keysRect = tallKeys
        tryCompare(sheet, "height", 364)
        compare(sheet.y, 10)
        verify(bottomOf(sheet) <= 374.5)
        verify(bottomOf(field) < 374)
        verify(list.height >= 3 * 56)
        verify(bottomOf(list) <= 374.5)
        // The shortest keys: the sheet rises only as far as it must.
        launcher.keysRect = shortKeys
        tryCompare(sheet, "height", 524)
        compare(sheet.y, 10)
        verify(bottomOf(sheet) <= 534.5)
        // The keys go down and the sheet returns.
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        tryCompare(sheet, "height", 700)
        tryCompare(sheet, "y", 20)
        query.text = ""
        results.clear()
    }
    function test_keysKeepGuestInItsRoom() {
        const sheet = findChild(launcher, "launcher-sheet")
        controller.guestMode = true
        tryCompare(sheet, "y", controller.guestY)
        launcher.keysRect = tallKeys
        // A guest stays where Kadunce put it and shortens instead.
        tryCompare(sheet, "height", 374 - controller.guestY)
        compare(sheet.y, controller.guestY)
        compare(sheet.x, controller.guestX)
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        tryCompare(sheet, "height", controller.guestHeight)
        controller.guestMode = false
    }
    function test_keysKeepDrawersAbove() {
        const sheet = findChild(launcher, "launcher-sheet")
        launcher.setDrawerOpen(true)
        controller.setDrawerExpanded(true, true)
        tryCompare(sheet, "height", 720)
        launcher.keysRect = tallKeys
        tryCompare(sheet, "height", 364)
        compare(sheet.y, 10)
        const grid = findChild(launcher, "application-grid")
        // At least a row of applications.
        verify(grid.height > 112)
        verify(bottomOf(grid) <= 374.5)
        // Search, in the drawer's header, stays in view above the keys.
        tryCompare(launcher, "drawerProgress", 1)
        const field = findChild(launcher, "search-field")
        verify(field.mapToItem(launcher, 0, 0).y >= sheet.y)
        verify(bottomOf(field) < grid.mapToItem(launcher, 0, 0).y)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        // Files keeps its folder, path and actions; tabs and Open step aside.
        launcher.fileBrowser = filesMock
        filesMock.selecting = false
        filesMock.selectedPath = ""
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const tabs = findChild(launcher, "files-tabs")
        const openRow = findChild(launcher, "files-open-row")
        // One tab gives its row back to the folder.
        verify(!tabs.visible && openRow.visible)
        const navigation = findChild(launcher, "files-navigation")
        const actionRow = findChild(launcher, "files-actions")
        // One row under search: the path, then the actions at its end.
        compare(actionRow.mapToItem(launcher, 0, 0).y, navigation.mapToItem(launcher, 0, 0).y)
        launcher.keysRect = tallKeys
        tryCompare(sheet, "height", 364)
        const pane = findChild(launcher, "files-pane")
        verify(pane.compact)
        verify(!tabs.visible && !openRow.visible)
        const files = findChild(launcher, "files-grid")
        const actions = findChild(launcher, "new-folder")
        tryVerify(() => files.height >= 100)
        verify(actions.visible)
        verify(bottomOf(files) <= 374.5)
        verify(bottomOf(actions) < bottomOf(files))
        verify(field.mapToItem(launcher, 0, 0).y >= sheet.y)
        verify(bottomOf(field) < navigation.mapToItem(launcher, 0, 0).y)
        // Keys up, the same row.
        compare(actionRow.mapToItem(launcher, 0, 0).y, navigation.mapToItem(launcher, 0, 0).y)
        verify(actionRow.mapToItem(launcher, 0, 0).x >= navigation.mapToItem(launcher, navigation.width, 0).x)
        verify(actionRow.mapToItem(launcher, actionRow.width, 0).x <= pane.mapToItem(launcher, pane.width, 0).x + 0.5)
        // Menus open above the keys.
        compare(findChild(launcher, "file-context-menu").bottomMargin, launcher.keysReach)
        compare(launcher.keysReach, 426)
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        tryVerify(() => openRow.visible)
        // A second tab brings the tab row back.
        filesMock.tabs = [{label:"Home",path:"/home/test"}, {label:"Downloads",path:"/home/test/Downloads"}]
        verify(tabs.visible)
        filesMock.tabs = [{label:"Home",path:"/home/test"}]
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    function test_filesSearchInsideAndRecent() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.searchText = ""
        filesMock.searchedFor = []
        filesMock.selectedPath = ""
        filesMock.selecting = false
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const query = findChild(launcher, "search-query")
        const pill = findChild(launcher, "search-inside")
        // Nothing typed: no pill.
        verify(!pill.visible)
        // Typing narrows the folder and offers the deeper search.
        query.forceActiveFocus()
        query.text = "plan"
        compare(filesMock.filter, "plan")
        tryVerify(() => pill.visible)
        wait(50) // the row lays out the pill that came with the text
        mouseClick(pill, pill.width / 2, pill.height / 2)
        compare(filesMock.searchedFor, ["plan"])
        // Enter with nothing chosen searches too; with a file chosen it opens it.
        query.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(filesMock.searchedFor, ["plan", "plan"])
        filesMock.selectedPath = "/home/test/Notes.txt"
        verify(!pill.visible)
        const opens = filesMock.openCalls
        keyClick(Qt.Key_Return)
        compare(filesMock.openCalls, opens + 1)
        compare(filesMock.searchedFor.length, 2)
        filesMock.selectedPath = ""
        // Showing that search: the pill waits for different text.
        filesMock.placeKind = "search"
        filesMock.searchText = "plan"
        verify(!pill.visible)
        verify(!findChild(launcher, "new-folder").visible)
        query.text = "plans"
        tryVerify(() => pill.visible)
        // Opening a folder from the results sets the text aside.
        filesMock.filterCleared()
        compare(query.text, "")
        compare(filesMock.filter, "")
        // Recent: no pill, nothing to create or paste into, order fixed.
        filesMock.placeKind = "recent"
        filesMock.searchText = ""
        filesMock.canPaste = true
        query.text = "notes"
        wait(20)
        verify(!pill.visible)
        verify(!findChild(launcher, "new-folder").visible)
        verify(!findChild(launcher, "paste-here").visible)
        compare(findChild(launcher, "files-sort").fixed, true)
        filesMock.searching = true
        filesMock.entries = []
        compare(findChild(launcher, "files-empty").text, "Searching…")
        filesMock.searching = false
        compare(findChild(launcher, "files-empty").text, "Nothing used recently")
        filesMock.placeKind = "search"
        compare(findChild(launcher, "files-empty").text, "Nothing found")
        // Back in a folder, everything returns.
        filesMock.placeKind = "folder"
        filesMock.entries = [{name:"Projects",path:"/home/test/Projects",directory:true,icon:"folder",detail:"Folder"}, {name:"Notes.txt",path:"/home/test/Notes.txt",directory:false,icon:"text-plain",detail:"842 B"}]
        verify(findChild(launcher, "paste-here").visible)
        compare(findChild(launcher, "files-sort").fixed, false)
        filesMock.canPaste = false
        query.text = ""
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    function test_filesProperties() {
        launcher.fileBrowser = filesMock
        filesMock.selectedPath = ""
        filesMock.selecting = false
        filesMock.placeKind = "folder"
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const more = findChild(launcher, "more-actions")
        verify(!more.visible)
        // One file chosen: its properties are in its own menu.
        filesMock.selectedPath = "/home/test/Notes.txt"
        verify(more.visible)
        wait(50) // the row lays out the pills that came with the choice
        mouseClick(more, more.width / 2, more.height / 2)
        const properties = findChild(launcher, "context-properties")
        tryVerify(() => properties.visible && properties.enabled)
        properties.choose()
        compare(filesMock.describedPath, "/home/test/Notes.txt")
        const sheet = findChild(launcher, "properties-sheet")
        tryCompare(sheet, "opened", true)
        compare(findChild(launcher, "properties-name").text, "Notes.txt")
        const rows = findChild(launcher, "properties-rows")
        compare(rows.count, 2)
        compare(rows.itemAt(0).objectName, "properties-row-Kind")
        compare(rows.itemAt(1).objectName, "properties-row-Size")
        const stops = filesMock.stops
        const close = findChild(launcher, "properties-close")
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(sheet, "opened", false)
        compare(filesMock.stops, stops + 1)
        // Alt+Enter does the same.
        filesMock.describedPath = ""
        findChild(launcher, "files-grid").forceActiveFocus()
        keyClick(Qt.Key_Return, Qt.AltModifier)
        compare(filesMock.describedPath, "/home/test/Notes.txt")
        tryCompare(sheet, "opened", true)
        sheet.close()
        tryCompare(sheet, "opened", false)
        verify(findChild(launcher, "context-properties"))
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    function test_filesNameTaken() {
        launcher.fileBrowser = filesMock
        filesMock.answers = []
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const sheet = findChild(launcher, "name-taken-sheet")
        verify(!sheet.opened)
        filesMock.question = {name: "a.txt", folder: "dst", isFolder: false, several: true, canReplace: true,
            canSkip: true, canKeepBoth: true, existing: "5 bytes, modified Today", arriving: "5 bytes"}
        tryCompare(sheet, "opened", true)
        compare(findChild(launcher, "name-taken-title").text, "“a.txt” is already in dst")
        compare(findChild(launcher, "name-taken-existing").text, "5 bytes, modified Today")
        verify(findChild(launcher, "name-taken-skip").visible)
        compare(findChild(launcher, "name-taken-replace").text, "Replace")
        const keep = findChild(launcher, "name-taken-keep")
        // A sheet lays out its buttons before it is first drawn.
        const laidOut = () => keep.x !== findChild(launcher, "name-taken-replace").x
        tryVerify(laidOut)
        mouseClick(keep, keep.width / 2, keep.height / 2)
        compare(filesMock.answers, ["keep"])
        tryCompare(sheet, "opened", false)
        // For the rest.
        filesMock.question = {name: "b.txt", folder: "dst", isFolder: false, several: true, canReplace: true,
            canSkip: true, canKeepBoth: true, existing: "", arriving: ""}
        tryCompare(sheet, "opened", true)
        const rest = findChild(launcher, "name-taken-rest")
        compare(rest.checked, false)
        rest.checked = true
        tryVerify(laidOut)
        const replace = findChild(launcher, "name-taken-replace")
        mouseClick(replace, replace.width / 2, replace.height / 2)
        compare(filesMock.answers, ["keep", "replace+all"])
        tryCompare(sheet, "opened", false)
        // A folder is merged; Esc stops.
        filesMock.question = {name: "Photos", folder: "dst", isFolder: true, several: false, canReplace: true,
            canSkip: false, canKeepBoth: true, existing: "", arriving: ""}
        tryCompare(sheet, "opened", true)
        compare(findChild(launcher, "name-taken-replace").text, "Merge")
        verify(!findChild(launcher, "name-taken-skip").visible)
        keyClick(Qt.Key_Escape)
        tryCompare(sheet, "opened", false)
        compare(filesMock.answers, ["keep", "replace+all", "stop"])
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    function test_filesOpenWith() {
        launcher.fileBrowser = filesMock
        filesMock.openedWith = []
        filesMock.selectedPath = "/home/test/Notes.txt"
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        // A file nothing opens asks, as Open with… does.
        filesMock.applicationChoiceNeeded("/home/test/Notes.txt")
        const sheet = findChild(launcher, "open-with-sheet")
        tryCompare(sheet, "opened", true)
        compare(findChild(launcher, "open-with-title").text, "Open “Notes.txt” with")
        const list = findChild(launcher, "open-with-list")
        compare(list.count, 2)
        tryVerify(() => list.height > 0 && list.itemAtIndex(1) && list.itemAtIndex(1).y > 0)
        const all = findChild(launcher, "open-with-all")
        mouseClick(all, all.width / 2, all.height / 2)
        compare(list.count, 3)
        findChild(launcher, "open-with-filter").text = "ze"
        compare(list.count, 1)
        findChild(launcher, "open-with-always").checked = true
        tryVerify(() => list.itemAtIndex(0) && list.itemAtIndex(0).modelData.id === "zeta.desktop" && list.height > 0)
        const zeta = list.itemAtIndex(0)
        mouseClick(zeta, zeta.width / 2, zeta.height / 2)
        compare(filesMock.openedWith, ["/home/test/Notes.txt", "zeta.desktop", true])
        tryCompare(sheet, "opened", false)
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    // A place that cannot be opened says why where its files would be and
    // offers the way back; it, and a folder that cannot be written, offer no
    // new folder; a filter that matches nothing says so.
    function test_filesCannotOpen() {
        launcher.fileBrowser = filesMock
        const savedEntries = filesMock.entries
        filesMock.placeKind = "folder"
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const newFolder = findChild(launcher, "new-folder")
        verify(newFolder.visible)
        filesMock.readOnly = true
        verify(!newFolder.visible)
        filesMock.readOnly = false
        filesMock.entries = []
        filesMock.listingFailed = true
        filesMock.error = "You don't have permission to open “root”."
        const empty = findChild(launcher, "files-empty")
        compare(empty.text, "You don't have permission to open “root”.")
        verify(!newFolder.visible)
        const back = findChild(launcher, "files-way-back")
        verify(back.visible)
        compare(back.text, "Home")
        filesMock.navigated = []
        // The test runner's synthetic click does not reach a tap handler over
        // the grid; the pill's own action does, and a pointer's real click
        // was checked in a sealed session.
        back.activate()
        compare(filesMock.navigated, ["/home/test"])
        filesMock.listingFailed = false
        filesMock.error = ""
        verify(!back.visible)
        filesMock.filter = "zebra"
        compare(empty.text, "Nothing here matches “zebra”")
        filesMock.filter = ""
        compare(empty.text, "No files here")
        filesMock.entries = savedEntries
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // A folder opens in a new tab from its menu; a file from Recent or a
    // search is shown in its folder; a search still looking can be stopped.
    function test_filesNewTabShowInFolderAndStop() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const menu = findChild(launcher, "file-context-menu")
        const pane = findChild(launcher, "files-pane")
        pane.showActions("/home/test/Projects", true, Qt.point(40, 40))
        tryCompare(menu, "opened", true)
        const newTab = findChild(launcher, "context-new-tab")
        verify(newTab.visible)
        verify(!findChild(launcher, "context-show-in-folder").visible)
        filesMock.tabsOpened = []
        newTab.choose()
        compare(filesMock.tabsOpened, ["/home/test/Projects"])
        tryCompare(menu, "opened", false)
        filesMock.placeKind = "recent"
        pane.showActions("/home/test/Notes.txt", false, Qt.point(40, 40))
        tryCompare(menu, "opened", true)
        verify(!findChild(launcher, "context-new-tab").visible)
        const show = findChild(launcher, "context-show-in-folder")
        verify(show.visible)
        show.choose()
        compare(filesMock.shownInFolder, "/home/test/Notes.txt")
        filesMock.placeKind = "search"
        filesMock.searching = true
        const stop = findChild(launcher, "stop-search")
        verify(stop.visible)
        tryVerify(() => stop.width > 0 && stop.x >= 0)
        wait(50)
        mouseClick(stop, stop.width / 2, stop.height / 2)
        compare(filesMock.searchStops, 1)
        verify(!stop.visible)
        filesMock.placeKind = "folder"
        filesMock.selectedPath = ""
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // Files' order, beside New folder, opens under its pill and stays inside
    // the sheet, and a line sets the order. Hidden files are the eye's.
    function test_filesSortMenu() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.sortMode = 0
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const sort = findChild(launcher, "files-sort")
        const menu = findChild(launcher, "files-sort-menu")
        verify(sort.visible)
        const newFolder = findChild(launcher, "new-folder")
        verify(Math.abs(sort.mapToItem(null, 0, sort.height / 2).y
            - newFolder.mapToItem(null, 0, newFolder.height / 2).y) < 1)
        verify(newFolder.mapToItem(null, newFolder.width, 0).x <= sort.mapToItem(null, 0, 0).x + 0.5)
        mouseClick(sort, sort.width / 2, sort.height / 2)
        tryCompare(menu, "opened", true)
        const sheet = menu.parent
        verify(menu.x >= 0 && menu.x + menu.width <= sheet.width)
        // Below the button where the pane has room for it, and always
        // inside the pane.
        const sortBottom = sort.mapToItem(sheet, 0, sort.height).y
        verify(menu.y >= 0 && menu.y + menu.height <= sheet.height + 0.5)
        if (sortBottom + menu.height <= sheet.height) verify(menu.y > sortBottom - 1)
        verify(!findChild(launcher, "files-show-hidden"))
        menu.close()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // The eye inside search shows what is hidden, in either drawer: hidden
    // files in Files, hidden applications in Apps; again, it hides them.
    function test_hiddenEye() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.hidden = false
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const eye = findChild(launcher, "hidden-button")
        const field = findChild(launcher, "search-field")
        const query = findChild(launcher, "search-query")
        verify(eye.visible && eye.enabled)
        // The eye inside search, past what is typed.
        verify(eye.mapToItem(null, 0, 0).x >= query.mapToItem(null, query.width, 0).x - 0.5)
        verify(eye.mapToItem(null, eye.width, 0).x <= field.mapToItem(null, field.width, 0).x - 10)
        verify(!eye.showing)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        compare(filesMock.hidden, true)
        verify(eye.showing)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        compare(filesMock.hidden, false)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)

        launcher.setDrawerOpen(true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        verify(!catalog.showHidden)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        verify(catalog.showHidden)
        verify(eye.showing)
        compare(filesMock.hidden, false)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        verify(!catalog.showHidden)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // The window's buttons end the row of modes, over search: Expand and
    // Close in both drawers, Pop out in Files only, Close last. A drawer
    // opens at Search's size; Expand fills the screen and brings it back.
    function test_drawerCorner_data() {
        return [{ tag: "apps", mode: "apps" }, { tag: "files", mode: "files" }]
    }
    function test_drawerCorner(data) {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        launcher.setDrawerOpen(true, data.mode)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const expand = findChild(launcher, "window-expand")
        const popOut = findChild(launcher, "window-pop-out")
        const close = findChild(launcher, "window-close")
        const field = findChild(launcher, "search-field")
        const dot = findChild(launcher, "home-dot")
        const left = item => item.mapToItem(launcher, 0, 0).x
        const right = item => item.mapToItem(launcher, item.width, 0).x
        const top = item => item.mapToItem(launcher, 0, 0).y
        verify(expand.visible && close.visible)
        compare(popOut.visible, data.mode === "files")
        // In the row of modes, above search, at its other end.
        verify(top(expand) + expand.height <= top(field))
        verify(Math.abs(top(expand) + expand.height / 2 - top(dot) - dot.height / 2) < 1)
        verify(right(expand) <= left(data.mode === "files" ? popOut : close) + 0.5)
        verify(Math.abs(right(close) - right(field.parent)) < 1)
        compare(close.Accessible.name, "Close Search")
        compare(controller.drawerExpanded, false)
        compare(expand.Accessible.name, "Expand")
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.drawerExpanded, true)
        verify(controller.expansionChosen)
        compare(expand.Accessible.name, "Make smaller")
        // Moving to the other drawer keeps the size chosen.
        launcher.setDrawerOpen(true, data.mode === "files" ? "apps" : "files")
        compare(controller.drawerExpanded, true)
        launcher.setDrawerOpen(true, data.mode)
        compare(launcher.filesMode, data.mode === "files")
        wait(50)
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.drawerExpanded, false)
        compare(expand.Accessible.name, "Expand")
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        compare(controller.drawerExpanded, false)
    }

    // Close puts Search away from any drawer or mode.
    function test_close_data() {
        return [{ tag: "apps" }, { tag: "files" }, { tag: "notes" }]
    }
    function test_close(data) {
        let close
        if (data.tag === "notes") {
            openNotesMode()
            close = findChild(launcher, "window-close")
        } else {
            launcher.fileBrowser = filesMock
            filesMock.placeKind = "folder"
            launcher.setDrawerOpen(true, data.tag)
            tryCompare(launcher, "drawerProgress", 1)
            wait(250)
            close = findChild(launcher, "window-close")
        }
        verify(close.visible && close.opacity > 0.99)
        const before = controller.closes
        mouseClick(close, close.width / 2, close.height / 2)
        compare(controller.closes, before + 1)
        if (data.tag === "notes") launcher.closeNotes()
        else launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        tryCompare(launcher, "modeProgress", 0)
    }

    // Notes has the drawers' corner. Expand fills the screen and the mode
    // stays in Search; Back brings Search back to its size.
    function test_modeExpand() {
        openNotesMode()
        const sheet = findChild(launcher, "launcher-sheet")
        const expand = findChild(launcher, "window-expand")
        const popOut = findChild(launcher, "window-pop-out")
        const close = findChild(launcher, "window-close")
        verify(expand.opacity > 0.99 && popOut.visible && close.visible)
        verify(expand.mapToItem(sheet, 0, 0).x < popOut.mapToItem(sheet, 0, 0).x)
        verify(popOut.mapToItem(sheet, 0, 0).x < close.mapToItem(sheet, 0, 0).x)
        // They are Search's own buttons on the modes row, not a band of
        // their own under it.
        const home = findChild(launcher, "home-dot")
        const rowMid = home.mapToItem(sheet, 0, home.height / 2).y
        fuzzyCompare(close.mapToItem(sheet, 0, close.height / 2).y, rowMid, 2)
        verify(!findChild(launcher, "notes-close"))
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.drawerExpanded, true)
        verify(controller.expansionChosen)
        tryCompare(sheet, "width", 980)
        verify(launcher.notesOpen)
        compare(quickStub.boards.length, 0)
        compare(controller.closes, 0)
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.drawerExpanded, false)
        tryCompare(sheet, "width", 840)
        mouseClick(expand, expand.width / 2, expand.height / 2)
        tryCompare(sheet, "width", 980)
        const back = findChild(launcher, "home-dot")
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "modeProgress", 0)
        compare(controller.drawerExpanded, false)
        tryCompare(sheet, "width", 840)
    }

    // Moving between Notes and the drawers keeps the size chosen, as moving
    // between Apps and Files does.
    function test_modeKeepsExpandedSize() {
        openNotesMode()
        const sheet = findChild(launcher, "launcher-sheet")
        const expand = findChild(launcher, "window-expand")
        mouseClick(expand, expand.width / 2, expand.height / 2)
        tryCompare(sheet, "width", 980)
        const files = findChild(launcher, "files-pill")
        mouseClick(files, files.width / 2, files.height / 2)
        // From Notes the drawer is there at once: no first screen between,
        // and the window's buttons never fade out and back.
        compare(launcher.drawerProgress, 1)
        const windowRow = findChild(launcher, "window-close").parent
        compare(windowRow.opacity, 1)
        wait(60)
        compare(windowRow.opacity, 1)
        verify(findChild(launcher, "window-close").visible)
        verify(!launcher.notesOpen)
        compare(controller.drawerExpanded, true)
        compare(sheet.width, 980)
        const notes = findChild(launcher, "notes-pill")
        mouseClick(notes, notes.width / 2, notes.height / 2)
        tryCompare(launcher, "notesProgress", 1)
        compare(controller.drawerExpanded, true)
        compare(sheet.width, 980)
        launcher.closeNotes()
        tryCompare(launcher, "modeProgress", 0)
        compare(controller.drawerExpanded, false)
    }

    // Pop out moves Files into a window of its own and Search closes; in
    // Spread the window is awaited as Search's card, as a launch is. With
    // the window open, Files in Search brings the window forward instead.
    function openFilesDrawer() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        return findChild(launcher, "window-pop-out")
    }
    function test_filesPopOut() {
        controller.closes = 0
        let popOut = openFilesDrawer()
        verify(popOut.visible)
        mouseClick(popOut, popOut.width / 2, popOut.height / 2)
        compare(controller.filesWindows, 1)
        compare(controller.filesLaunches, 0)
        compare(controller.closes, 1)
        verify(controller.filesWindowOpen)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        // With a Files window open, the Files pill opens Files here, and
        // Search stays.
        const files = findChild(launcher, "files-pill")
        mouseClick(files, files.width / 2, files.height / 2)
        compare(controller.filesWindows, 1)
        compare(controller.closes, 1)
        tryVerify(() => launcher.drawerOpen && launcher.filesMode)
        // Pop out again opens another window.
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        popOut = findChild(launcher, "window-pop-out")
        verify(popOut.visible)
        mouseClick(popOut, popOut.width / 2, popOut.height / 2)
        compare(controller.filesWindows, 2)
        compare(controller.closes, 2)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        controller.filesWindowOpen = false

        controller.guestMode = true
        controller.handoffs = 0
        popOut = openFilesDrawer()
        mouseClick(popOut, popOut.width / 2, popOut.height / 2)
        compare(controller.filesLaunches, 1)
        compare(controller.filesWindows, 3)
        verify(launcher.filesHandoff)
        compare(controller.closes, 2)
        controller.guestLaunchReady()
        tryCompare(controller, "handoffs", 1)
        verify(!launcher.filesHandoff)
        controller.guestMode = false
        controller.filesWindowOpen = false

        // A window that cannot open leaves Files where it is.
        controller.filesWindowShows = false
        popOut = openFilesDrawer()
        mouseClick(popOut, popOut.width / 2, popOut.height / 2)
        verify(launcher.drawerOpen)
        compare(controller.closes, 2)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // Files' own window has Files' header, less Back and the corner: the eye
    // on search's left, the order on its right, and Files under them. What
    // is typed narrows the folder.
    Component {
        id: filesWindowComponent
        App.FilesWindow {
            width: 900
            height: 640
            launcherController: controller
        }
    }
    function test_filesWindow() {
        filesMock.filter = ""
        filesMock.hidden = false
        filesMock.placeKind = "folder"
        const window = createTemporaryObject(filesWindowComponent, test, {fileBrowser: filesMock})
        verify(window)
        const eye = findChild(window, "files-window-hidden")
        const field = findChild(window, "files-window-search")
        const pane = findChild(window, "files-window-pane")
        const header = findChild(window, "files-window-header")
        const left = item => item.mapToItem(window, 0, 0).x
        const right = item => item.mapToItem(window, item.width, 0).x
        verify(left(eye) >= left(field) && right(eye) <= right(field) - 40)
        // Search's own field: the words 46 in, and the same words.
        compare(findChild(window, "files-window-query").mapToItem(field, 0, 0).x, 46)
        verify(findChild(window, "files-sort"))
        verify(Math.abs(left(field) + field.width / 2 - window.width / 2) < 1)
        verify(pane.mapToItem(window, 0, 0).y >= header.mapToItem(window, 0, header.height).y)
        compare(findChild(window, "drawer-back"), null)
        compare(findChild(window, "window-pop-out"), null)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        compare(filesMock.hidden, true)
        mouseClick(eye, eye.width / 2, eye.height / 2)
        compare(filesMock.hidden, false)
        window.forceActiveFocus()
        keyClick("r")
        keyClick("e")
        compare(filesMock.filter, "re")
        keyClick(Qt.Key_Escape)
        compare(filesMock.filter, "")
    }

    function test_filesMenusAndEmptyTrash() {
        launcher.fileBrowser = filesMock
        filesMock.selectedPath = ""
        filesMock.trashItems = 3
        filesMock.trashSize = "12 MiB"
        filesMock.empties = 0
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250) // the sheet's own growth settles before the menu is measured
        const more = findChild(launcher, "more-actions")
        const menu = findChild(launcher, "file-context-menu")
        // Nothing chosen, no actions button: the folder's menu is a
        // right-click or a hold on the empty end of the path.
        verify(!more.visible)
        const pathEnd = findChild(launcher, "path-open-area")
        verify(pathEnd.visible && pathEnd.width >= 40)
        const checks = filesMock.trashChecks
        mouseClick(pathEnd, pathEnd.width / 2, pathEnd.height / 2, Qt.RightButton)
        tryCompare(menu, "opened", true)
        const filesPane = findChild(launcher, "files-pane")
        verify(menu.x >= 0 && menu.x + menu.width <= filesPane.width)
        verify(menu.y >= 0 && menu.y + menu.height <= filesPane.height)
        verify(filesMock.trashChecks > checks)
        // Refresh and New tab are in it too.
        verify(findChild(launcher, "context-refresh").visible)
        verify(findChild(launcher, "context-add-tab").visible)
        const empty = findChild(launcher, "context-empty-trash")
        verify(empty.visible && empty.enabled)
        verify(!findChild(launcher, "context-compress").visible)
        empty.triggered()
        menu.close()
        const confirm = findChild(launcher, "empty-trash-confirm")
        tryCompare(confirm, "opened", true)
        compare(findChild(launcher, "empty-trash-confirm-body").text, "3 items, 12 MiB, will be deleted for good. This can't be undone.")
        confirm.accept()
        compare(filesMock.empties, 1)
        tryCompare(confirm, "opened", false)
        // With files chosen, a pill opens their own menu.
        filesMock.selectedPath = "/home/test/Notes.txt"
        filesMock.canCompress = true
        compare(more.text, "More actions")
        wait(50)
        mouseClick(more, more.width / 2, more.height / 2)
        tryCompare(menu, "opened", true)
        verify(findChild(launcher, "context-open-with").visible)
        verify(findChild(launcher, "context-compress").enabled)
        verify(!findChild(launcher, "context-extract").visible)
        verify(!findChild(launcher, "context-empty-trash").visible)
        filesMock.canExtract = true
        verify(findChild(launcher, "context-extract").visible)
        // Hide waits in the same menu, and a file the list hides offers Unhide.
        const hide = findChild(launcher, "context-hide")
        verify(!hide.visible)
        filesMock.canHide = true
        verify(hide.visible)
        compare(hide.text, "Hide")
        hide.triggered()
        compare(filesMock.hides, 1)
        filesMock.canHide = false
        filesMock.canUnhide = true
        compare(hide.text, "Unhide")
        hide.triggered()
        compare(filesMock.unhides, 1)
        filesMock.canUnhide = false
        menu.close()
        tryCompare(menu, "opened", false)
        filesMock.selectedPath = ""
        filesMock.canCompress = false
        filesMock.canExtract = false
        filesMock.trashItems = 0
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }
    function test_drawerKeys() {
        // Meta+G opens Apps; again, it closes the launcher.
        controller.closes = 0
        controller.drawerRequested("apps")
        tryCompare(launcher, "drawerOpen", true)
        verify(!launcher.filesMode)
        // Asked for from outside Search, a drawer opens filling the screen.
        compare(controller.drawerExpanded, true)
        verify(controller.expansionChosen)
        controller.drawerRequested("apps")
        compare(controller.closes, 1)
        // Meta+E moves to Files, and again closes.
        launcher.fileBrowser = filesMock
        controller.drawerRequested("files")
        tryCompare(launcher, "filesMode", true)
        verify(launcher.drawerOpen)
        compare(controller.drawerExpanded, true)
        compare(controller.closes, 1)
        controller.drawerRequested("files")
        compare(controller.closes, 2)
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
        // Without Files, Meta+E leaves the launcher as it is.
        launcher.fileBrowser = null
        controller.drawerRequested("files")
        wait(50)
        verify(!launcher.drawerOpen)
        compare(controller.closes, 2)
    }
    // The dot's slide asks for Notes as Meta+G asks for Apps: Notes opens,
    // and asked again, Search closes.
    function test_modeRequests() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        controller.closes = 0
        controller.drawerRequested("apps")
        tryCompare(launcher, "drawerOpen", true)
        controller.drawerRequested("notes")
        verify(!launcher.drawerOpen)
        verify(launcher.notesOpen)
        compare(controller.drawerExpanded, true)
        compare(quickStub.starts, 0)
        compare(findChild(launcher, "notes-pane").view, "board")
        tryCompare(launcher, "notesProgress", 1)
        controller.drawerRequested("notes")
        compare(controller.closes, 1)
    }
    // Back from a note handed to the notes application's card opens Notes at
    // the size it had when the note left, not filling the screen.
    function test_notesBackKeepsSize() {
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const pane = findChild(launcher, "notes-pane")
        controller.drawerRequested("notes-back")
        verify(launcher.notesOpen)
        compare(controller.drawerExpanded, false)
        pane.finished()
        compare(launcher.notesLeftExpanded, false)
        controller.setDrawerExpanded(true, true)
        pane.finished()
        compare(launcher.notesLeftExpanded, true)
        launcher.closeNotes()
        tryCompare(launcher, "notesProgress", 0)
        controller.drawerExpanded = false
        controller.drawerRequested("notes-back")
        verify(launcher.notesOpen)
        compare(controller.drawerExpanded, true)
        launcher.notesLeftExpanded = false
    }
    // The panel's quick note island: its dot asks for a new quick note, and
    // its pinned note for that note, each alone at Search's size with no
    // Back to the board.
    function test_islandRequests() {
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        tryCompare(launcher, "openingControls", 1)
        controller.closes = 0
        controller.drawerRequested("note")
        verify(launcher.notesOpen)
        compare(controller.drawerExpanded, false)
        compare(quickStub.startsWith, [""])
        const pane = findChild(launcher, "notes-pane")
        compare(pane.view, "page")
        verify(!pane.fromBoard)
        tryCompare(pane, "pageShown", 1)
        verify(!findChild(launcher, "notes-back").visible)
        controller.drawerRequested("note:note-2")
        compare(quickStub.edits, ["note-2"])
        compare(pane.view, "page")
        verify(!pane.fromBoard)
        compare(controller.closes, 0)
    }
    // Both drawers share one header under the modes: search sits in the
    // middle and is typed into as before, and the sort button stays on the
    // right; the dot above returns to search. No Close drawer pill remains.
    function test_drawerHeader_data() {
        return [{ tag: "apps", mode: "apps" }, { tag: "files", mode: "files" }]
    }
    function test_drawerHeader(data) {
        launcher.fileBrowser = filesMock
        filesMock.filter = ""
        filesMock.selectedPath = ""
        controller.closes = 0
        launcher.setDrawerOpen(true, data.mode)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        compare(findChild(launcher, "close-drawer-button"), null)
        const header = findChild(launcher, "drawer-header")
        const back = findChild(launcher, "home-dot")
        const field = findChild(launcher, "search-field")
        const query = findChild(launcher, "search-query")
        const left = item => item.mapToItem(launcher, 0, 0).x
        const right = item => item.mapToItem(launcher, item.width, 0).x
        const middle = item => item.mapToItem(launcher, item.width / 2, item.height / 2)
        // Every search reads alike: Find an app, Find a file, Find a note.
        compare(findChild(launcher, "just-type-placeholder").text, data.mode === "files" ? "Find a file" : "Find an app")
        compare(query.mapToItem(field, 0, 0).x, 46)
        // The modes, then search, where it is on every screen, holding the
        // header's row; the order sits below, over the drawer.
        verify(back.visible && back.enabled)
        verify(back.mapToItem(launcher, 0, back.height).y <= header.mapToItem(launcher, 0, 0).y)
        compare(middle(field).y, middle(header).y)
        verify(Math.abs(middle(field).x - middle(header).x) < 1)
        compare(field.width, header.width)
        const appsSort = findChild(launcher, "sort-button")
        compare(appsSort.visible, data.mode === "apps")
        if (data.mode === "apps") {
            verify(appsSort.enabled)
            verify(appsSort.mapToItem(header, 0, 0).y >= header.height)
            // New folder, the order, then the size at the right edge.
            const appsSize = findChild(launcher, "apps-size")
            verify(appsSize.visible)
            verify(Math.abs(right(appsSize) - right(header)) < 1)
            compare(appsSize.y, appsSort.y)
            verify(right(appsSort) <= left(appsSize) - 7.5)
        }
        // The drawer reaches up to the row search held above it.
        tryVerify(() => findChild(launcher, data.mode === "files" ? "files-pane" : "application-grid") !== null)
        const drawer = findChild(launcher, data.mode === "files" ? "files-pane" : "application-grid")
        verify(drawer.visible)
        compare(drawer.mapToItem(header, 0, 0).y, header.height + 16 + (data.mode === "apps" ? 50 : 0))
        // A tap or click on search takes the keys, and a tap by its edge
        // asks for the on-screen ones; what is typed narrows the drawer,
        // from the field or from anywhere in the launcher.
        const tap = touchEvent(launcher)
        launcher.forceActiveFocus()
        tap.press(0, field, field.width / 2, field.height / 2).commit()
        wait(30)
        tap.release(0, field, field.width / 2, field.height / 2).commit()
        verify(query.activeFocus)
        wait(600)
        const asks = controller.keyRequests
        launcher.forceActiveFocus()
        tap.press(0, field, 8, field.height / 2).commit()
        wait(30)
        tap.release(0, field, 8, field.height / 2).commit()
        verify(query.activeFocus)
        verify(controller.keyRequests > asks)
        wait(600)
        launcher.forceActiveFocus()
        mouseClick(field, field.width / 2, field.height / 2)
        verify(query.activeFocus)
        keyClick("k")
        launcher.forceActiveFocus()
        keyClick("a")
        compare(query.text, "ka")
        verify(query.activeFocus)
        if (data.mode === "files") compare(filesMock.filter, "ka")
        else compare(catalog.filterText, "ka")
        compare(results.queryString, "")
        // The dot returns to search with what was typed, by mouse and by touch.
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "drawerOpen", false)
        compare(results.queryString, "ka")
        compare(controller.closes, 0)
        tryCompare(launcher, "drawerProgress", 0)
        query.text = ""
        launcher.setDrawerOpen(true, data.mode)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const touch = touchEvent(launcher)
        touch.press(0, back, back.width / 2, back.height / 2).commit()
        wait(30)
        touch.release(0, back, back.width / 2, back.height / 2).commit()
        tryCompare(launcher, "drawerOpen", false)
        compare(controller.closes, 0)
        tryCompare(launcher, "drawerProgress", 0)
        // With nothing typed, search returns to the first screen: at the top
        // over what was used lately, else in the middle.
        tryCompare(field, "y", field.restY)
        compare(field.height, 44)
        wait(600)
    }
    // Esc closes the sort menu if it is open, otherwise the drawer, while
    // search in the header holds the keys.
    function test_drawerHeaderEsc_data() {
        return [{ tag: "apps", mode: "apps" }, { tag: "files", mode: "files" }]
    }
    function test_drawerHeaderEsc(data) {
        launcher.fileBrowser = filesMock
        filesMock.selectedPath = ""
        controller.closes = 0
        launcher.setDrawerOpen(true, data.mode)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const query = findChild(launcher, "search-query")
        const sort = findChild(launcher, data.mode === "files" ? "files-sort" : "sort-button")
        query.forceActiveFocus()
        mouseClick(sort, sort.width / 2, sort.height / 2)
        const filesMenu = findChild(launcher, "files-sort-menu")
        if (data.mode === "files") tryCompare(filesMenu, "opened", true)
        else tryCompare(launcher, "sortMenuOpen", true)
        keyClick(Qt.Key_Escape)
        if (data.mode === "files") tryCompare(filesMenu, "opened", false)
        else compare(launcher.sortMenuOpen, false)
        verify(launcher.drawerOpen)
        query.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        tryCompare(launcher, "drawerOpen", false)
        compare(controller.closes, 0)
        tryCompare(launcher, "drawerProgress", 0)
    }
    // A pull down on search, the drawer's top edge, still closes it, by
    // touch or with the mouse.
    function test_drawerTopEdgeCloses_data() {
        return [
            { tag: "apps, on search", mode: "apps", on: "search" },
            { tag: "files, on search", mode: "files", on: "search" }]
    }
    function test_drawerTopEdgeCloses(data) {
        launcher.fileBrowser = filesMock
        filesMock.selectedPath = ""
        controller.closes = 0
        for (const device of ["touch", "mouse"]) {
            launcher.setDrawerOpen(true, data.mode)
            tryCompare(launcher, "drawerProgress", 1)
            wait(250)
            const field = findChild(launcher, "search-field")
            const header = findChild(launcher, "drawer-header")
            const start = data.on === "search" ? field.mapToItem(launcher, field.width / 2, field.height / 2)
                : header.mapToItem(launcher, 30, header.height / 2)
            if (data.on === "beside") verify(start.x < field.mapToItem(launcher, 0, 0).x)
            const steps = [0, 30, 120, 260, 420, 540]
            if (device === "touch") {
                const touch = touchEvent(launcher)
                touch.press(0, launcher, start.x, start.y).commit()
                for (let i = 1; i < steps.length; ++i) {
                    wait(20)
                    touch.move(0, launcher, start.x, start.y + steps[i]).commit()
                }
                wait(20)
                touch.release(0, launcher, start.x, start.y + 540).commit()
            } else {
                mousePress(launcher, start.x, start.y)
                for (let i = 1; i < steps.length; ++i)
                    mouseMove(launcher, start.x, start.y + steps[i], 20)
                mouseRelease(launcher, start.x, start.y + 540)
            }
            tryCompare(launcher, "drawerOpen", false)
            tryCompare(launcher, "drawerProgress", 0)
            compare(controller.closes, 0)
            wait(600)
        }
    }
    function test_browseAndSort(data) {
        controller.guestMode = data.guest
        controller.closes = 0
        catalog.sortOrder = 0
        catalog.useReads = 0
        catalog.installChecks = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const label = findChild(launcher, "apps-pill")
        verify(label)
        mouseClick(label, label.width / 2, label.height / 2)
        tryCompare(launcher, "drawerOpen", true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250) // wait for animated geometry before clicking the moved sort button
        const sort = findChild(launcher, "sort-button")
        mouseClick(sort, sort.width / 2, sort.height / 2)
        tryCompare(launcher, "sortMenuOpen", true)
        compare(controller.closes, 0)
        const menu = findChild(launcher, "sort-menu")
        tryCompare(menu, "opacity", 1)
        compare(menu.width, 160)
        // Three rows of 38 with 4 between, inside 6 on each side.
        compare(menu.height, 134)
        verify(catalog.useReads >= 1)
        // Opening Apps asks whether anything was installed meanwhile.
        verify(catalog.installChecks >= 1)
        // Each by its place in the menu and the catalog's number for it.
        const rows = [["Most used", 2, 1], ["Newest installed", 3, 2], ["A to Z", 0, 0]]
        for (let i = 0; i < rows.length; ++i) {
            if (i > 0) {
                mouseClick(sort, sort.width / 2, sort.height / 2)
                tryCompare(launcher, "sortMenuOpen", true)
                tryCompare(menu, "opacity", 1)
            }
            const order = rows[i][1]
            mouseClick(menu, menu.width / 2, 6 + rows[i][2] * 42 + 19)
            tryCompare(catalog, "sortOrder", order)
            compare(launcher.sortMenuOpen, false)
        }
        compare(controller.closes, 0)
    }
    // From a mode the dot's slide opened, the next slide goes straight to
    // the drawer or mode chosen, and Back from it leads to search.
    function test_slideMovesOnFromAMode() {
        openNotesMode()
        controller.drawerRequested("apps")
        verify(!launcher.notesOpen)
        tryCompare(launcher, "drawerOpen", true)
        compare(controller.drawerExpanded, true)
        controller.drawerRequested("notes")
        verify(launcher.notesOpen && !launcher.drawerOpen)
        compare(controller.drawerExpanded, true)
        tryCompare(launcher, "notesProgress", 1)
        controller.drawerRequested("files")
        verify(!launcher.modeOpen)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const back = findChild(launcher, "home-dot")
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "drawerProgress", 0)
        verify(!launcher.modeOpen && !launcher.drawerOpen)
        compare(controller.drawerExpanded, false)
    }
    function openNotesMode() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        controller.closes = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const notes = findChild(launcher, "notes-pill")
        mouseClick(notes, notes.width / 2, notes.height / 2)
        tryCompare(launcher, "notesProgress", 1)
    }
    // Notes opens in Search's own window with the drawer's motion, on the
    // board: the field becomes Find a note, with every note under
    // it, and the window keeps its size. Nothing is handed to Gooseberry's
    // own card, no note is started, and Search stays open.
    function test_notesModeOpensInSearch() {
        const sheet = findChild(launcher, "launcher-sheet")
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        launcher.quickNote = quickStub
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        controller.closes = 0
        const rest = Qt.size(sheet.width, sheet.height)
        const field = findChild(launcher, "search-field")
        const fieldAt = field.mapToItem(sheet, 0, 0)
        const notes = findChild(launcher, "notes-pill")
        mouseClick(notes, notes.width / 2, notes.height / 2)
        verify(launcher.notesOpen)
        // Notes' field is Search's own pill, under the modes from the first
        // frame: it does not rise or grow as Notes comes.
        const frame = findChild(launcher, "notes-find-frame")
        compare(frame.y, 0)
        compare(frame.height, 44)
        compare(quickStub.starts, 0)
        compare(quickStub.finds, [""])
        compare(notesStub.opened, 0)
        compare(controller.closes, 0)
        compare(controller.drawerExpanded, false)
        tryCompare(launcher, "notesProgress", 1)
        compare(sheet.width, rest.width)
        compare(sheet.height, rest.height)
        verify(field.opacity < 0.01)
        compare(frame.y, 0)
        compare(frame.height, 44)
        compare(frame.x, field.x)
        compare(frame.width, field.width)
        // The words start where Search's do, 46 in from the pill's edge,
        // the same size, so moving into Notes shifts nothing.
        const find = findChild(launcher, "notes-find")
        compare(find.leftPadding, 0)
        compare(find.mapToItem(frame, 0, 0).x, 46)
        compare(findChild(launcher, "search-query").mapToItem(field, 0, 0).x, 46)
        compare(find.font.pixelSize, findChild(launcher, "just-type-placeholder").font.pixelSize)
        compare(find.placeholderText, "Find a note")
        // The board holds the keys, not its field, so no on-screen keys
        // rise on a tablet; typing goes into the field.
        const pane = findChild(launcher, "notes-pane")
        verify(!find.activeFocus)
        verify(pane.activeFocus)
        verify(!findChild(launcher, "notes-back").visible)
        const grow = findChild(launcher, "window-pop-out")
        verify(grow.opacity > 0.99)
        verify(grow.mapToItem(sheet, grow.width, 0).x > sheet.width / 2)
        // Today's note first, then the rest; tucked away notes wait under
        // their own filter.
        compare(pane.rows[0].kind, "heading")
        compare(pane.rows[1].note.id, "note-1")
        verify(!pane.rows.some(row => row.kind === "note" && row.note.id === "note-3"))
        const row = findChild(launcher, "notes-row-note-1")
        verify(row.visible)
        // A note opens on the page, with Back to the board.
        mouseClick(row, row.width / 2, row.height / 2)
        compare(quickStub.edits, ["note-1"])
        compare(pane.view, "page")
        const pad = findChild(launcher, "notes-pad")
        compare(pad.text, "Plan the kitchen")
        verify(pad.activeFocus)
        const back = findChild(launcher, "notes-back")
        verify(back.visible)
        mouseClick(back, back.width / 2, back.height / 2)
        compare(pane.view, "board")
        verify(!find.activeFocus)
        keyClick(Qt.Key_K)
        verify(find.activeFocus)
        compare(find.text, "k")
        find.text = ""
        // The dot returns to Search, and nothing was finished.
        const dot = findChild(launcher, "home-dot")
        mouseClick(dot, dot.width / 2, dot.height / 2)
        tryCompare(launcher, "notesProgress", 0)
        verify(!launcher.notesOpen)
        tryCompare(field, "opacity", 1)
        compare(quickStub.dones, 0)
        compare(controller.closes, 0)
        compare(field.mapToItem(sheet, 0, 0).y, fieldAt.y)
    }
    // A note tapped on the board, or a new one from New note or Enter with
    // the words typed, goes to Gooseberry's own card, and Search closes.
    function test_notesOnCard() {
        openNotesMode()
        quickStub.cardTakes = true
        const pane = findChild(launcher, "notes-pane")
        const row = findChild(launcher, "notes-row-note-1")
        mouseClick(row, row.width / 2, row.height / 2)
        compare(quickStub.cards, ["id:note-1"])
        compare(quickStub.backs, ["Notes"])
        compare(quickStub.edits, [])
        compare(pane.view, "board")
        compare(controller.closes, 1)
    }
    function test_notesNewOnCard() {
        openNotesMode()
        quickStub.cardTakes = true
        keyClick(Qt.Key_F)
        keyClick(Qt.Key_E)
        keyClick(Qt.Key_R)
        keyClick(Qt.Key_N)
        const newNote = findChild(launcher, "notes-new")
        verify(newNote.visible)
        verify(newNote.height >= 44)
        // Under the pointer it lights, with a ring round it.
        const ring = findChild(newNote, "notes-new-ring")
        compare(ring.opacity, 0)
        mouseMove(newNote, newNote.width / 2, newNote.height / 2)
        tryCompare(ring, "opacity", 1)
        mouseClick(newNote, newNote.width / 2, newNote.height / 2)
        compare(quickStub.cards, ["text:fern"])
        compare(quickStub.backs, ["Notes"])
        compare(quickStub.startsWith, [])
        compare(controller.closes, 1)
    }
    // A Gooseberry whose card cannot take a note opens it on the page here.
    function test_notesNewHereWithoutCard() {
        openNotesMode()
        const pane = findChild(launcher, "notes-pane")
        keyClick(Qt.Key_Return)
        compare(quickStub.cards, ["text:"])
        compare(quickStub.startsWith, [""])
        compare(pane.view, "page")
        compare(controller.closes, 0)
    }
    // Words find notes; the filters narrow them; Tucked away shows only
    // what is tucked away.
    function test_notesBoardFinds() {
        openNotesMode()
        const pane = findChild(launcher, "notes-pane")
        keyClick(Qt.Key_T)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_X)
        compare(findChild(launcher, "search-query").text, "")
        tryCompare(quickStub, "notesWords", "tax")
        compare(pane.rows.filter(row => row.kind === "note").length, 1)
        verify(pane.rows.some(row => row.kind === "folder" && row.folder.name === "Taxes"))
        findChild(launcher, "notes-find").text = ""
        tryCompare(quickStub, "notesWords", "")
        const tucked = findChild(launcher, "notes-filter-tucked")
        // Smaller than the modes: a 32 tall pill touched across 40.
        compare(tucked.height, 40)
        compare(tucked.children[0].height, 32)
        mouseClick(tucked, tucked.width / 2, tucked.height / 2)
        compare(pane.rows.length, 1)
        compare(pane.rows[0].note.id, "note-3")
        const kitchen = findChild(launcher, "notes-filter-folder:Kitchen")
        mouseClick(kitchen, kitchen.width / 2, kitchen.height / 2)
        compare(pane.rows.filter(row => row.kind === "note").map(row => row.note.id), ["note-1"])
        // Down picks the first note and Enter opens it.
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(quickStub.edits, ["note-1"])
        compare(pane.view, "page")
        // Esc returns from the page to the board, then to Search.
        keyClick(Qt.Key_Escape)
        compare(pane.view, "board")
        keyClick(Qt.Key_Escape)
        tryCompare(launcher, "notesProgress", 0)
        compare(controller.closes, 0)
    }
    // Esc from the board steps back to Search, then closes Search.
    function test_notesModeEscape() {
        openNotesMode()
        keyClick(Qt.Key_Escape)
        tryCompare(launcher, "notesProgress", 0)
        compare(controller.closes, 0)
        keyClick(Qt.Key_Escape)
        compare(controller.closes, 1)
    }
    // A note, opened from the board, on its page.
    function openNotePage() {
        openNotesMode()
        const row = findChild(launcher, "notes-row-note-1")
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(findChild(launcher, "notes-pane"), "pageShown", 1)
    }
    // Words typed with Enter start a new note with them; typing goes to the
    // note, not to search; the colour is the dot in the page's corner.
    function test_notesModeWrites() {
        openNotesMode()
        keyClick(Qt.Key_H)
        keyClick(Qt.Key_I)
        keyClick(Qt.Key_Return)
        compare(quickStub.startsWith, ["hi"])
        tryCompare(findChild(launcher, "notes-pane"), "pageShown", 1)
        const pad = findChild(launcher, "notes-pad")
        compare(pad.text, "hi")
        verify(pad.activeFocus)
        keyClick(Qt.Key_A)
        compare(findChild(launcher, "search-query").text, "")
        compare(quickStub.texts[quickStub.texts.length - 1], "hia")
        const dot = findChild(launcher, "notes-colour")
        mouseClick(dot, dot.width / 2, dot.height / 2)
        const teal = findChild(launcher, "notes-colour-teal")
        verify(teal.visible)
        mouseClick(teal, teal.width / 2, teal.height / 2)
        compare(quickStub.colour, "teal")
        verify(!findChild(launcher, "notes-colours").visible)
        compare(controller.closes, 0)
    }
    // Checklist turns the note into boxes, each ticked where it stands;
    // Remind offers Gooseberry's times and says the one set.
    function test_notesChecklistAndRemind() {
        openNotePage()
        const checklist = findChild(launcher, "notes-checklist-toggle")
        mouseClick(checklist, checklist.width / 2, checklist.height / 2)
        verify(quickStub.checklist)
        verify(findChild(launcher, "notes-checklist").visible)
        verify(!findChild(launcher, "notes-pad").visible)
        const box = findChild(launcher, "notes-box-1")
        mouseClick(box, box.width / 2, box.height / 2)
        compare(quickStub.ticks, [[1, true]])
        const remind = findChild(launcher, "notes-remind")
        tapChip(remind)
        const later = findChild(launcher, "notes-remind-later")
        verify(later.visible)
        mouseClick(later, later.width / 2, later.height / 2)
        compare(quickStub.reminders, ["2026-10-17T18:00:00+00:00"])
        compare(remind.text, "6:00 PM")
        verify(remind.showText)
        tapChip(remind)
        const none = findChild(launcher, "notes-no-reminder")
        mouseClick(none, none.width / 2, none.height / 2)
        compare(quickStub.reminders, ["2026-10-17T18:00:00+00:00", ""])
        verify(!remind.showText)
    }
    // More, on a kept note: Copy all, Tuck away and Remove. Tuck away from
    // the board returns to it.
    function test_notesMore() {
        openNotePage()
        const more = findChild(launcher, "notes-more")
        verify(more.visible)
        mouseClick(more, more.width / 2, more.height / 2)
        const menu = findChild(launcher, "notes-more-menu")
        verify(menu.visible)
        // Pin keeps the note in sight on the panel; on the pinned note it
        // is Unpin.
        const pin = findChild(launcher, "notes-pin")
        verify(pin.visible)
        compare(pin.label, "Pin")
        waitForItemPolished(pin.parent)
        waitForRendering(launcher)
        mouseClick(pin, pin.width / 2, pin.height / 2)
        compare(quickStub.pins, [true])
        verify(!menu.visible)
        mouseClick(more, more.width / 2, more.height / 2)
        compare(pin.label, "Unpin")
        const tuck = findChild(launcher, "notes-tuck-away")
        mouseClick(tuck, tuck.width / 2, tuck.height / 2)
        compare(quickStub.tucks, 1)
        compare(findChild(launcher, "notes-pane").view, "board")
        verify(!menu.visible)
        compare(controller.closes, 0)
    }
    // A choice's row takes or leaves its place under the page at the next
    // layout; a tap before then would be let go where the line no longer is.
    function tapChip(chip) {
        const lower = findChild(launcher, "notes-lower")
        waitForItemPolished(lower)
        mouseClick(chip, chip.width / 2, chip.height / 2)
        waitForItemPolished(lower)
        waitForRendering(launcher)
    }
    // Folder and Stuck to, quiet under the page, each saying what is chosen
    // and opening its choices above it.
    function test_notesFolderChip() {
        openNotePage()
        verify(!findChild(launcher, "notes-belongs").visible)
        const chip = findChild(launcher, "notes-folder")
        verify(chip.visible)
        compare(chip.text, "Kitchen")
        const choices = findChild(launcher, "notes-folder-choices")
        verify(!choices.visible)
        tapChip(chip)
        verify(choices.visible)
        compare(findChild(launcher, "notes-folder-Kitchen").label, "Kitchen · this workspace")
        verify(findChild(launcher, "notes-folder-Kitchen").chosen)
        const inbox = findChild(launcher, "notes-folder-inbox")
        verify(inbox.x > findChild(launcher, "notes-folder-Kitchen").x)
        verify(findChild(launcher, "notes-folder-Taxes").x > inbox.x)
        mouseClick(inbox, inbox.width / 2, inbox.height / 2)
        compare(quickStub.folderSets, [""])
        compare(chip.text, "Inbox")
        verify(!choices.visible)
        verify(findChild(launcher, "notes-pad").activeFocus)
        // A new folder, by name.
        tapChip(chip)
        const field = findChild(launcher, "notes-new-folder")
        verify(field.visible)
        field.forceActiveFocus()
        field.text = "  Garden "
        keyClick(Qt.Key_Return)
        compare(quickStub.folderSets, ["", "Garden"])
        compare(chip.text, "Garden")
        verify(!choices.visible)
        compare(controller.closes, 0)
    }
    function test_notesStuckChip() {
        openNotePage()
        const chip = findChild(launcher, "notes-stuck")
        compare(chip.text, "Kate · plan.txt")
        const choices = findChild(launcher, "notes-window-choices")
        tapChip(chip)
        verify(choices.visible)
        verify(!findChild(launcher, "notes-folder-choices").visible)
        compare(findChild(launcher, "notes-window-0").label, "Kate · plan.txt")
        const mail = findChild(launcher, "notes-window-1")
        compare(mail.label, "KMail · Inbox")
        mouseClick(mail, mail.width / 2, mail.height / 2)
        compare(quickStub.stucks, [["Inbox", "org.kde.kmail2"]])
        compare(chip.text, "KMail · Inbox")
        verify(!choices.visible)
        tapChip(chip)
        const loose = findChild(launcher, "notes-dont-stick")
        verify(!loose.chosen)
        mouseClick(loose, loose.width / 2, loose.height / 2)
        compare(quickStub.stucks, [["Inbox", "org.kde.kmail2"], ["", ""]])
        compare(chip.text, "Not stuck")
        // Esc closes open choices first, and leaves the note open.
        tapChip(chip)
        verify(choices.visible)
        keyClick(Qt.Key_Escape)
        verify(!choices.visible)
        compare(findChild(launcher, "notes-pane").view, "page")
        compare(launcher.notesProgress, 1)
        compare(controller.closes, 0)
    }
    // An older Gooseberry offers no folders: Belongs to stays as it was.
    function test_notesOlderGooseberryBelongsTo() {
        quickStub.offersFolders = false
        openNotePage()
        verify(!findChild(launcher, "notes-folder").visible)
        verify(findChild(launcher, "notes-belongs").visible)
        const belongs = findChild(launcher, "notes-belongs-0")
        mouseClick(belongs, belongs.width / 2, belongs.height / 2)
        compare(quickStub.belongs, "window")
        compare(quickStub.folderSets, [])
    }
    // Over an Active card, Pop out grows the window as Apps does, opens the
    // board, and fades once the board has drawn in the card's place.
    function test_notesGrowOverActive() {
        openNotesMode()
        const grow = findChild(launcher, "window-pop-out")
        mouseClick(grow, grow.width / 2, grow.height / 2)
        verify(launcher.notesGrowing)
        compare(controller.drawerExpanded, true)
        compare(controller.notesLaunches, 0)
        compare(quickStub.boards.length, 1)
        compare(controller.closes, 0)
        quickStub.boardShown("not-this-one")
        wait(200)
        compare(controller.closes, 0)
        quickStub.boardShown(quickStub.boards[0])
        tryCompare(controller, "closes", 1)
    }
    // In Spread, Pop out grows the guest, Kadunce awaits the board's window,
    // and Search leaves as it does for any launch.
    function test_notesGrowInSpread() {
        controller.guestMode = true
        controller.handoffs = 0
        openNotesMode()
        const grow = findChild(launcher, "window-pop-out")
        mouseClick(grow, grow.width / 2, grow.height / 2)
        compare(controller.drawerExpanded, true)
        compare(controller.notesLaunches, 1)
        verify(launcher.notesHandoff)
        quickStub.boardShown(quickStub.boards[0])
        wait(200)
        compare(controller.handoffs, 0)
        controller.guestLaunchReady()
        tryCompare(controller, "handoffs", 1)
        controller.guestMode = false
    }
    // A board that cannot open brings the note back as it was.
    function test_notesGrowRefused() {
        openNotesMode()
        quickStub.boardOpens = false
        const grow = findChild(launcher, "window-pop-out")
        mouseClick(grow, grow.width / 2, grow.height / 2)
        verify(!launcher.notesGrowing)
        compare(controller.drawerExpanded, false)
        verify(launcher.notesOpen)
    }
    // Turned off in the settings, Notes is absent however the launcher was
    // told so, as null or as nothing at all. Search has no Ask pill.
    function test_doorsOffWhenNotOffered() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = undefined
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        verify(!findChild(launcher, "notes-pill").visible)
        verify(findChild(launcher, "genie-pill") === null)
    }

    // The Helpers chip: offered only while Core lists Helpers, it shows them
    // all as tiles, what is typed finds only Helpers, a tile opens one on its
    // own, and Escape leads back to Search's first screen.
    function test_helpersChipShowsEveryHelper() {
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const pill = findChild(launcher, "helpers-pill")
        verify(!pill.visible)
        results.helpers = [
            {id: "update", title: "Check for updates", sub: "Everything, with a restore point first", icon: "system-software-update"},
            {id: "space", title: "Free up space", sub: "Old copies, caches and the trash", icon: "drive-harddisk"},
            {id: "restore", title: "Restore points", sub: "Go back to an earlier state", icon: "document-revert"}
        ]
        tryCompare(pill, "visible", true)
        const files = findChild(launcher, "files-pill")
        const left = item => item.mapToItem(launcher, 0, 0).x
        verify(left(files) < left(pill))
        mouseClick(pill, pill.width / 2, pill.height / 2)
        verify(launcher.helpersShown)
        verify(pill.selected)
        verify(!findChild(launcher, "home-dot").selected)
        verify(results.helpersOnly)
        const row = findChild(launcher, "helpers-row")
        tryCompare(row, "opacity", 1)
        tryCompare(findChild(launcher, "first-row"), "visible", false)
        compare(findChild(launcher, "just-type-placeholder").text, "Look over the computer, free up space…")
        const update = findChild(launcher, "helper-update")
        const space = findChild(launcher, "helper-space")
        verify(update.visible && space.visible && findChild(launcher, "helper-restore").visible)
        compare(update.width, 96)
        compare(update.height, 88)
        compare(left(space) - left(update), 96 + 12)
        // At rest the sheet is as tall as the row of Helpers, at its full width.
        const sheet = findChild(launcher, "launcher-sheet")
        tryCompare(sheet, "height", 2 * launcher.contentInset + launcher.modeRowReach + launcher.fieldHeight + row.gap + row.naturalHeight)
        compare(sheet.width, sheet.universalWidth)
        const closes = controller.closes
        mouseClick(space, space.width / 2, space.height / 2)
        compare(results.helpersOpened, ["space"])
        compare(controller.closes, closes + 1)
        // Enter with nothing typed opens the first.
        launcher.submit()
        compare(results.helpersOpened, ["space", "update"])
        // What is typed is searched among the Helpers alone, and never on the web.
        const webSearches = controller.webSearches
        launcher.query.text = "zzz"
        launcher.submit()
        compare(controller.webSearches, webSearches)
        tryCompare(row, "visible", false)
        launcher.query.text = ""
        launcher.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        verify(!launcher.helpersShown)
        verify(!results.helpersOnly)
        tryCompare(findChild(launcher, "first-row"), "visible", true)
        // Apps closes the Helpers, and Core's leaving takes the chip with it.
        mouseClick(pill, pill.width / 2, pill.height / 2)
        verify(launcher.helpersShown)
        const apps = findChild(launcher, "apps-pill")
        mouseClick(apps, apps.width / 2, apps.height / 2)
        verify(!launcher.helpersShown && launcher.drawerOpen)
        launcher.goBack()
        mouseClick(pill, pill.width / 2, pill.height / 2)
        verify(launcher.helpersShown)
        results.helpers = []
        verify(!launcher.helpersShown)
        tryCompare(pill, "visible", false)
    }
}
