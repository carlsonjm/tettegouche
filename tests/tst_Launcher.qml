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
        launcher.fileBrowser = null
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        recentStub.clear()
        recentStub.opened = []
        launcher.notesDoor = null
        notesStub.available = true
        notesStub.opened = 0
        launcher.quickNote = null
        quickStub.reset()
        launcher.genie = null
        genieStub.reset()
        controller.notesLaunches = 0
        controller.genieLaunches = 0
        controller.guestLaunches = 0
        controller.availableArea = Qt.rect(0, 0, 1000, 740)
        controller.drawerExpanded = false
        controller.guestMode = false
        controller.opened()
        wait(300)
    }
    QtObject {
        id: controller
        property bool guestMode: false
        property bool drawerExpanded: false
        function setDrawerExpanded(expanded) { drawerExpanded = expanded }
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
        function beginGuestWebLaunch() { return false }
        property int notesLaunches: 0
        property bool notesLaunchAccepted: true
        function beginGuestNotesLaunch() { notesLaunches++; return guestMode && notesLaunchAccepted }
        property int launchCancels: 0
        function cancelGuestApplicationLaunch() { launchCancels++ }
        property int handoffs: 0
        function completeGuestHandoff() { handoffs++ }
        property int genieLaunches: 0
        function beginGuestGenieLaunch() { genieLaunches++; return guestMode }
        function searchWeb(text) { webSearches++; return true }
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
    }
    ListModel {
        id: catalog
        property string filterText: ""
        property bool descending: false
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
    }
    // What was used lately, as the launcher's model offers it.
    ListModel {
        id: recentStub
        property var opened: []
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
        signal noteChanged()
        signal boardShown(string requestToken)
        function reset() {
            available = true; open = false; text = ""; colour = "yellow"; starts = 0; texts = []
            flushes = 0; belongs = ""; dones = 0; tucks = 0; boards = []; boardOpens = true
            offersFolders = true; folderSets = []; stucks = []
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
        function remove() {}
        function openBoard(token) { if (!boardOpens) return false; boards = boards.concat([token]); return true }
    }
    // Split Rock's conversation interface, as Search speaks it.
    QtObject {
        id: genieStub
        property bool available: true
        property string phase: "ready"
        property string assistant: "Codex"
        property string question: ""
        property string answer: ""
        property var steps: []
        property var suggestions: ["Make the writing bigger", "Why is my battery draining?"]
        property bool canDoIt: false
        property string doItReason: "Changes come in a later version."
        property bool kept: false
        property var more: []
        property string remember: ""
        property bool fixed: false
        property string problem: ""
        property int starts: 0
        property var asked: []
        property var acts: []
        property int cancels: 0
        property var windows: []
        signal conversationChanged()
        signal windowShown(string requestToken)
        function reset() {
            available = true; phase = "ready"; question = ""; answer = ""; steps = []; kept = false
            more = []; remember = ""; fixed = false
            problem = ""; starts = 0; asked = []; acts = []; cancels = 0; windows = []
        }
        function refresh() {}
        function start() { starts++ }
        function ask(text) { asked = asked.concat([text]); question = text; phase = "answering"; conversationChanged() }
        function cancel() { cancels++; phase = "ready" }
        function act(action) {
            acts = acts.concat([action])
            if (action === "keep") kept = true
            if (action === "fixed") fixed = true
            if (action === "remember" || action === "dont-remember") remember = ""
        }
        function openWindow(token) { windows = windows.concat([token]); return true }
    }
    function fillRecent(n) {
        recentStub.clear()
        for (let i = 0; i < n; ++i)
            recentStub.append({name: "Used " + i, icon: "application-x-executable", thumbnail: "", kind: i % 2 ? "file" : "application"})
    }
    App.Launcher {
        id: launcher
        anchors.fill: parent
        launcherController: controller
        searchResults: results
        applicationCatalog: catalog
        recentUse: recentStub
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
    // actions, which start afresh, Hide, and Uninstall once the software
    // catalog can show it.
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
        compare(lines, ["New Window", "New Private Window", "Hide", "Uninstall…"])
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
        tryCompare(sheet, "width", 640)
        compare(sheet.height, Math.round(740 * 0.64))
        compare(sheet.x, 180)
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
        tryCompare(result, "height", 146)
        const highlight = findChild(launcher, "parent-highlight-0")
        compare(highlight.height, 62)
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
        tryCompare(result, "height", 62)
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
        tryCompare(sheet, "width", 980)
        tryCompare(sheet, "height", 710)
        compare(controller.drawerExpanded, true)
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const back = findChild(launcher, "drawer-back")
        verify(back && back.visible && back.enabled)
        const header = findChild(launcher, "drawer-header")
        const search = findChild(launcher, "search-field")
        const grid = findChild(launcher, "application-grid")
        compare(header.y,0)
        // The drawer reaches up under the header, to search's old row.
        compare(search.y,0)
        compare(grid.y-search.y-search.height,16)
        verify(grid.y < 64)
        const closesBefore = controller.closes
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "drawerOpen", false)
        compare(controller.closes, closesBefore)
        tryCompare(sheet, "width", 640)
        tryCompare(sheet, "height", Math.round(740 * 0.64))
        compare(controller.drawerExpanded, false)
    }
    function test_expandedDrawerWithoutLocalDock() {
        const original=controller.availableArea
        controller.availableArea=Qt.rect(0,0,launcher.width,launcher.height)
        launcher.setDrawerOpen(true,"files")
        const sheet=findChild(launcher,"launcher-sheet")
        tryCompare(sheet,"height",launcher.height-20)
        compare(sheet.y,10)
        compare(launcher.height-sheet.y-sheet.height,10)
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        controller.availableArea=original
    }
    // Before anything is typed: Apps and Files as pills centred under the
    // field, then what was used lately on its own row below them, as many as
    // fit and at most six, centred as one group; the field and the rows are
    // centred together.
    function test_firstRow() {
        launcher.fileBrowser = filesMock
        fillRecent(8)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const field = findChild(launcher, "search-field")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        verify(row.visible && apps.visible && files.visible)
        tryCompare(field, "width", row.width)
        compare(row.x, field.x)
        compare(row.y - field.y - field.height, 18)
        verify(Math.abs(field.y - (field.parent.height - row.y - row.height)) <= 1)
        const left = apps.mapToItem(row, 0, 0).x
        const right = row.width - files.mapToItem(row, files.width, 0).x
        verify(Math.abs(left - right) <= 1)
        const fit = Math.min(6, Math.floor(row.width / row.tileWidth))
        verify(fit >= 4)
        compare(row.shownCount, fit)
        for (let i = 0; i < 8; ++i)
            compare(findChild(launcher, "recent-" + i).visible, i < fit)
        const first = findChild(launcher, "recent-0")
        const last = findChild(launcher, "recent-" + (fit - 1))
        compare(findChild(launcher, "recent-1").x - first.x, row.cellWidth)
        compare(findChild(launcher, "recent-1").y, first.y)
        verify(first.y >= apps.mapToItem(row, 0, apps.height).y)
        verify(Math.abs(first.x - (row.width - last.x - last.width)) <= 1)
        compare(Math.round(first.y + first.height), Math.round(row.height))
        // Typing hands the room to the results, and clearing brings it back.
        const query = findChild(launcher, "search-query")
        query.text = "x"
        tryCompare(row, "opacity", 0)
        query.text = ""
        tryCompare(row, "opacity", 1)
    }
    // The doors arrive in turn, Apps before Files, and what was used lately
    // after them; typing sends the row away whole, and clearing the field
    // brings each back in turn.
    function test_firstRowArrivesInTurn() {
        launcher.fileBrowser = filesMock
        fillRecent(3)
        controller.opened()
        const row = findChild(launcher, "first-row")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        const recent = findChild(launcher, "recent-0")
        tryVerify(function() { return apps.reveal > files.reveal && files.reveal >= recent.reveal }, 1000)
        tryCompare(row, "arrival", 1)
        compare(apps.reveal, 1)
        compare(recent.reveal, 1)
        const query = findChild(launcher, "search-query")
        query.text = "x"
        tryCompare(row, "rest", 0)
        compare(apps.reveal, files.reveal)
        query.text = ""
        tryVerify(function() { return apps.reveal > files.reveal }, 1000)
        tryCompare(row, "arrival", 1)
        compare(row.rest, 1)
    }
    // A narrower sheet keeps the doors and as many of the rest as fit.
    function test_firstRowNarrow() {
        launcher.fileBrowser = filesMock
        fillRecent(8)
        controller.availableArea = Qt.rect(0, 0, 640, 740)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        verify(row.shownCount >= 1)
        compare(row.shownCount, Math.min(6, Math.floor(row.width / row.tileWidth)))
        verify(findChild(launcher, "apps-pill").visible && findChild(launcher, "files-pill").visible)
        controller.availableArea = Qt.rect(0, 0, 1000, 740)
    }
    // With nothing used lately the two doors sit centred under the field,
    // which keeps its usual width.
    function test_firstRowWithNothingUsed() {
        launcher.fileBrowser = filesMock
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const field = findChild(launcher, "search-field")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        compare(row.shownCount, 0)
        tryCompare(field, "width", Math.max(360, field.parent.width * 0.72))
        const left = apps.mapToItem(row, 0, 0).x
        const right = row.width - files.mapToItem(row, files.width, 0).x
        verify(Math.abs(left - right) <= 1)
    }
    // With the setting off the launcher has no record at all: the two doors
    // alone, centred, and Tab goes from one to the other.
    function test_firstRowSettingOff() {
        launcher.fileBrowser = filesMock
        launcher.recentUse = null
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        verify(row.visible && apps.visible && files.visible)
        compare(row.shownCount, 0)
        verify(!findChild(launcher, "recent-0"))
        const left = apps.mapToItem(row, 0, 0).x
        const right = row.width - files.mapToItem(row, files.width, 0).x
        verify(Math.abs(left - right) <= 1)
        launcher.recentUse = recentStub
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
        keyClick(Qt.Key_Tab)
        verify(findChild(launcher, "recent-0").activeFocus)
        keyClick(Qt.Key_Return)
        compare(recentStub.opened, [1, 2, 0])
    }
    // Without Gooseberry, or with Notes off, the first screen is Apps and
    // Files alone, as before.
    function test_notesAbsent() {
        launcher.fileBrowser = filesMock
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const apps = findChild(launcher, "apps-pill")
        const files = findChild(launcher, "files-pill")
        const notes = findChild(launcher, "notes-pill")
        verify(!notes.visible)
        compare(row.pillsWidth, apps.width + row.pillGap + files.width)
        launcher.notesDoor = notesStub
        notesStub.available = false
        verify(!notes.visible)
        compare(row.pillsWidth, apps.width + row.pillGap + files.width)
    }
    // Where Gooseberry is installed, Notes follows Files: the same pill, the
    // same height and gap, its own glyph and word, and the rest after it.
    function test_notesOffered() {
        launcher.fileBrowser = filesMock
        launcher.notesDoor = notesStub
        fillRecent(8)
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const files = findChild(launcher, "files-pill")
        const notes = findChild(launcher, "notes-pill")
        verify(notes.visible)
        compare(notes.label, "Notes")
        compare(notes.height, files.height)
        compare(notes.mapToItem(row, 0, 0).x - files.mapToItem(row, files.width, 0).x, row.pillGap)
        verify(findChild(launcher, "recent-0").y >= notes.mapToItem(row, 0, notes.height).y)
        compare(row.pillsWidth, findChild(launcher, "apps-pill").width + files.width + notes.width + 2 * row.pillGap)
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
        compare(controller.drawerExpanded,true)
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
        filesMock.selectedPath="/home/test/Notes.txt"
        mouseClick(grid,grid.width-10,grid.height-10)
        compare(filesMock.selectedPath,"")
        const folderTile=findChild(launcher,"file-entry-Projects")
        filesMock.boxedPaths=[]
        mousePress(grid,grid.width-10,grid.height-10)
        mouseMove(grid,2,2,30)
        mouseRelease(grid,2,2)
        compare(filesMock.boxedPaths.length,2)
        verify(filesMock.boxedPaths.indexOf("/home/test/Projects")>=0)
        filesMock.selectedPath="/home/test/Projects"
        mousePress(grid,grid.width-10,grid.height-10,Qt.LeftButton,Qt.ControlModifier)
        mouseMove(grid,2,2,30)
        mouseRelease(grid,2,2,Qt.LeftButton,Qt.ControlModifier)
        compare(filesMock.boxedPaths.length,1)
        compare(filesMock.boxedPaths[0],"/home/test/Notes.txt")
        mousePress(grid,grid.width-10,grid.height-10,Qt.LeftButton,Qt.ShiftModifier)
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
        const cancel=findChild(launcher,"cancel-folder")
        mouseClick(cancel,cancel.width/2,cancel.height/2)
        verify(!findChild(launcher,"folder-name").visible)
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
    // Drives follow the places under a rule: a tap opens one, and one plugged
    // in ejects from its own button, by mouse and by touch. Busy, a drive says
    // what it is doing and takes no tap.
    function test_filesDrives() {
        launcher.fileBrowser=filesMock
        launcher.setDrawerOpen(true,"files")
        tryCompare(launcher,"drawerProgress",1)
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
        tryCompare(sheet, "y", 133)
        compare(sheet.height, 474)
        // The tallest keys: the sheet rises to the top and shortens to fit.
        launcher.keysRect = tallKeys
        tryCompare(sheet, "height", 364)
        compare(sheet.y, 10)
        verify(bottomOf(sheet) <= 374.5)
        verify(bottomOf(field) < 374)
        verify(list.height >= 3 * 62)
        verify(bottomOf(list) <= 374.5)
        // The shortest keys: the sheet rises only as far as it must.
        launcher.keysRect = shortKeys
        tryCompare(sheet, "y", 60)
        compare(sheet.height, 474)
        verify(bottomOf(sheet) <= 534.5)
        // The keys go down and the sheet returns.
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        tryCompare(sheet, "y", 133)
        compare(sheet.height, 474)
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
        tryCompare(sheet, "height", 710)
        launcher.keysRect = tallKeys
        tryCompare(sheet, "height", 364)
        compare(sheet.y, 10)
        const grid = findChild(launcher, "application-grid")
        verify(grid.height > 150)
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
        verify(tabs.visible && openRow.visible)
        const navigation = findChild(launcher, "files-navigation")
        const actionRow = findChild(launcher, "files-actions")
        // Keys down: the actions sit under the path and its divider, as before.
        compare(actionRow.mapToItem(launcher, 0, 0).y - bottomOf(navigation), 25)
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
        // Keys up: the actions join the path's row, at its end.
        compare(actionRow.mapToItem(launcher, 0, 0).y, navigation.mapToItem(launcher, 0, 0).y)
        verify(actionRow.mapToItem(launcher, 0, 0).x >= navigation.mapToItem(launcher, navigation.width, 0).x)
        verify(actionRow.mapToItem(launcher, actionRow.width, 0).x <= pane.mapToItem(launcher, pane.width, 0).x + 0.5)
        // Menus open above the keys.
        compare(findChild(launcher, "file-context-menu").bottomMargin, launcher.keysReach)
        compare(launcher.keysReach, 426)
        launcher.keysRect = Qt.rect(0, 0, 0, 0)
        tryVerify(() => tabs.visible && openRow.visible)
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
        compare(findChild(launcher, "sort-button").fileOrderFixed, true)
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
        compare(findChild(launcher, "sort-button").fileOrderFixed, false)
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
        const pill = findChild(launcher, "selection-properties")
        verify(!pill.visible)
        // One file chosen: its properties are a pill away.
        filesMock.selectedPath = "/home/test/Notes.txt"
        verify(pill.visible)
        mouseClick(pill, pill.width / 2, pill.height / 2)
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

    // Files' order opens under its button and stays inside the sheet, and a
    // line sets the order. Hidden files are the eye's, not the menu's.
    function test_filesSortMenu() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.sortMode = 0
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const sort = findChild(launcher, "sort-button")
        const menu = findChild(launcher, "files-sort-menu")
        mouseClick(sort, sort.width / 2, sort.height / 2)
        tryCompare(menu, "opened", true)
        const sheet = menu.parent
        verify(menu.x >= 0 && menu.x + menu.width <= sheet.width)
        verify(menu.y > sort.mapToItem(sheet, 0, sort.height).y - 1)
        verify(!findChild(launcher, "files-show-hidden"))
        menu.close()
        launcher.setDrawerOpen(false)
        tryCompare(launcher, "drawerProgress", 0)
    }

    // The eye beside the sort button shows what is hidden, in either drawer:
    // hidden files in Files, hidden applications in Apps; again,
    // it hides them. It keeps clear of the search field.
    function test_hiddenEye() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.hidden = false
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        wait(250)
        const eye = findChild(launcher, "hidden-button")
        const sort = findChild(launcher, "sort-button")
        const field = findChild(launcher, "search-query")
        verify(eye.visible && eye.enabled)
        verify(eye.mapToItem(null, eye.width, 0).x <= sort.mapToItem(null, 0, 0).x + 0.5)
        verify(field.mapToItem(null, field.width, 0).x <= eye.mapToItem(null, 0, 0).x + 0.5)
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

    function test_filesMenusAndEmptyTrash() {
        launcher.fileBrowser = filesMock
        filesMock.selectedPath = ""
        filesMock.trashItems = 3
        filesMock.trashSize = "12 MiB"
        filesMock.empties = 0
        launcher.setDrawerOpen(true, "files")
        tryCompare(launcher, "drawerProgress", 1)
        const more = findChild(launcher, "more-actions")
        const menu = findChild(launcher, "file-context-menu")
        compare(more.text, "Folder actions")
        const checks = filesMock.trashChecks
        mouseClick(more, more.width / 2, more.height / 2)
        tryCompare(menu, "opened", true)
        // Opened from the actions button at the sheet's right edge, the menu
        // stays inside Files, its right edge level with the button's.
        const filesPane = findChild(launcher, "files-pane")
        verify(menu.x >= 0 && menu.x + menu.width <= filesPane.width)
        verify(menu.y >= 0 && menu.y + menu.height <= filesPane.height)
        const moreAt = more.mapToItem(filesPane, more.width, more.height)
        verify(Math.abs(menu.x + menu.width - moreAt.x) < 1 || menu.x + menu.width >= filesPane.width - 9)
        verify(filesMock.trashChecks > checks)
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
        // With files chosen, the same pill opens their own menu.
        filesMock.selectedPath = "/home/test/Notes.txt"
        filesMock.canCompress = true
        compare(more.text, "More actions")
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
        controller.drawerRequested("apps")
        compare(controller.closes, 1)
        // Meta+E moves to Files, and again closes.
        launcher.fileBrowser = filesMock
        controller.drawerRequested("files")
        tryCompare(launcher, "filesMode", true)
        verify(launcher.drawerOpen)
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
    // Both drawers share one header: Back on the left returns to search,
    // search sits in the middle and is typed into as before, and the sort
    // button stays on the right. No Close drawer pill remains.
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
        const back = findChild(launcher, "drawer-back")
        const sort = findChild(launcher, "sort-button")
        const field = findChild(launcher, "search-field")
        const query = findChild(launcher, "search-query")
        const left = item => item.mapToItem(launcher, 0, 0).x
        const right = item => item.mapToItem(launcher, item.width, 0).x
        const middle = item => item.mapToItem(launcher, item.width / 2, item.height / 2)
        // One row: Back, then search in the middle, then the sort button.
        verify(back.visible && back.enabled)
        verify(sort.visible && sort.enabled)
        compare(middle(field).y, middle(header).y)
        compare(middle(back).y, middle(header).y)
        compare(middle(sort).y, middle(header).y)
        verify(right(back) < left(field))
        verify(right(field) < left(sort))
        verify(Math.abs(middle(field).x - middle(header).x) < 1)
        // The drawer reaches up to the row search held above it.
        tryVerify(() => findChild(launcher, data.mode === "files" ? "files-pane" : "application-grid") !== null)
        const drawer = findChild(launcher, data.mode === "files" ? "files-pane" : "application-grid")
        verify(drawer.visible)
        compare(drawer.mapToItem(header, 0, 0).y, header.height + 16)
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
        // Back returns to search with what was typed, by mouse and by touch.
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
        // With nothing typed, search rests again above the first row, the two
        // centred together.
        const row = findChild(launcher, "first-row")
        tryCompare(field, "y", Math.round((field.parent.height - field.height - row.reach) / 2))
        tryCompare(field, "height", 58)
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
        const sort = findChild(launcher, "sort-button")
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
    // A pull down on the drawer's top edge still closes it, whether it starts
    // on search, beside it or on Back, by touch or with the mouse.
    function test_drawerTopEdgeCloses_data() {
        return [
            { tag: "apps, on search", mode: "apps", on: "search" },
            { tag: "files, on search", mode: "files", on: "search" },
            { tag: "apps, on Back", mode: "apps", on: "back" },
            { tag: "files, beside search", mode: "files", on: "beside" }]
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
            const back = findChild(launcher, "drawer-back")
            const start = data.on === "search" ? field.mapToItem(launcher, field.width / 2, field.height / 2)
                : data.on === "back" ? back.mapToItem(launcher, back.width / 2, back.height / 2)
                : back.mapToItem(launcher, back.width + 6, back.height / 2)
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
        catalog.descending = false
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
        compare(menu.width, 132)
        mouseClick(menu, 50, 66)
        tryCompare(catalog, "descending", true)
        compare(launcher.sortMenuOpen, false)
        compare(controller.closes, 0)
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
    // Notes opens in Search's own window with the drawer's motion: the field
    // becomes the note pad, the pills fade, Back and the note's controls come
    // in, and the window keeps its size. Nothing is handed to Gooseberry's
    // own card and Search stays open.
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
        compare(quickStub.starts, 1)
        compare(notesStub.opened, 0)
        compare(controller.closes, 0)
        compare(controller.drawerExpanded, false)
        const pad = findChild(launcher, "notes-pad")
        tryCompare(launcher, "notesProgress", 1)
        compare(sheet.width, rest.width)
        compare(sheet.height, rest.height)
        verify(field.opacity < 0.01)
        verify(findChild(launcher, "first-row").opacity < 0.01)
        const back = findChild(launcher, "notes-back")
        const grow = findChild(launcher, "notes-all")
        verify(back.opacity > 0.99 && grow.opacity > 0.99)
        verify(grow.mapToItem(sheet, grow.width, 0).x > sheet.width / 2)
        verify(back.mapToItem(sheet, 0, 0).x < sheet.width / 2)
        const padAt = pad.mapToItem(sheet, 0, 0)
        verify(padAt.y > back.mapToItem(sheet, 0, back.height).y - 4)
        verify(pad.width > field.width)
        verify(pad.activeFocus)
        // Back returns to Search, and the note stays open to resume.
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "notesProgress", 0)
        verify(!launcher.notesOpen)
        tryCompare(field, "opacity", 1)
        compare(quickStub.dones, 0)
        compare(controller.closes, 0)
        compare(field.mapToItem(sheet, 0, 0).y, fieldAt.y)
    }
    // Esc steps back from the note to Search, then closes Search.
    function test_notesModeEscape() {
        openNotesMode()
        keyClick(Qt.Key_Escape)
        tryCompare(launcher, "notesProgress", 0)
        compare(controller.closes, 0)
        keyClick(Qt.Key_Escape)
        compare(controller.closes, 1)
    }
    // Typing goes to the note, not to search; colours are the note's; Done finishes it and Search closes.
    function test_notesModeWrites() {
        openNotesMode()
        const pad = findChild(launcher, "notes-pad")
        verify(pad.activeFocus)
        keyClick(Qt.Key_H)
        keyClick(Qt.Key_I)
        compare(findChild(launcher, "search-query").text, "")
        compare(quickStub.texts[quickStub.texts.length - 1], "hi")
        const swatches = findChild(launcher, "notes-colours")
        const teal = swatches.children[2]
        mouseClick(teal, teal.width / 2, teal.height / 2)
        compare(quickStub.colour, "teal")
        const done = findChild(launcher, "notes-done")
        mouseClick(done, done.width / 2, done.height / 2)
        compare(quickStub.dones, 1)
        compare(controller.closes, 1)
    }
    // A chip's row of choices takes its place under the chip at the next
    // layout; a tap before then would be let go where the row no longer is.
    function tapChip(chip) {
        mouseClick(chip, chip.width / 2, chip.height / 2)
        waitForItemPolished(findChild(launcher, "notes-chips"))
        waitForRendering(launcher)
    }
    // Folder and Stuck to take Belongs to's place, as on Gooseberry's own
    // card, each chip saying what is chosen and opening its choices under it.
    function test_notesFolderChip() {
        openNotesMode()
        verify(!findChild(launcher, "notes-belongs").visible)
        const chip = findChild(launcher, "notes-folder")
        verify(chip.visible)
        compare(chip.label, "Folder · Kitchen ▾")
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
        compare(chip.label, "Folder · Inbox ▾")
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
        compare(chip.label, "Folder · Garden ▾")
        verify(!choices.visible)
        compare(controller.closes, 0)
    }
    function test_notesStuckChip() {
        openNotesMode()
        const chip = findChild(launcher, "notes-stuck")
        compare(chip.label, "Stuck to · Kate · plan.txt ▾")
        const choices = findChild(launcher, "notes-window-choices")
        tapChip(chip)
        verify(choices.visible)
        verify(!findChild(launcher, "notes-folder-choices").visible)
        compare(findChild(launcher, "notes-window-0").label, "Kate · plan.txt")
        const mail = findChild(launcher, "notes-window-1")
        compare(mail.label, "KMail · Inbox")
        mouseClick(mail, mail.width / 2, mail.height / 2)
        compare(quickStub.stucks, [["Inbox", "org.kde.kmail2"]])
        compare(chip.label, "Stuck to · KMail · Inbox ▾")
        verify(!choices.visible)
        tapChip(chip)
        const loose = findChild(launcher, "notes-dont-stick")
        verify(!loose.chosen)
        mouseClick(loose, loose.width / 2, loose.height / 2)
        compare(quickStub.stucks, [["Inbox", "org.kde.kmail2"], ["", ""]])
        compare(chip.label, "Not stuck to a window ▾")
        // Esc closes open choices first, and leaves the note open.
        tapChip(chip)
        verify(choices.visible)
        keyClick(Qt.Key_Escape)
        verify(!choices.visible)
        compare(launcher.notesProgress, 1)
        compare(controller.closes, 0)
    }
    // An older Gooseberry offers no folders: Belongs to stays as it was.
    function test_notesOlderGooseberryBelongsTo() {
        quickStub.offersFolders = false
        openNotesMode()
        verify(!findChild(launcher, "notes-chips").visible)
        verify(findChild(launcher, "notes-belongs").visible)
        const belongs = findChild(launcher, "notes-belongs-0")
        mouseClick(belongs, belongs.width / 2, belongs.height / 2)
        compare(quickStub.belongs, "window")
        compare(quickStub.folderSets, [])
    }
    // Over an Active card, All notes grows the window as Apps does, opens the
    // board, and fades once the board has drawn in the card's place.
    function test_notesGrowOverActive() {
        openNotesMode()
        const grow = findChild(launcher, "notes-all")
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
    // In Spread, All notes grows the guest, Kadunce awaits the board's window,
    // and Search leaves as it does for any launch.
    function test_notesGrowInSpread() {
        controller.guestMode = true
        controller.handoffs = 0
        openNotesMode()
        const grow = findChild(launcher, "notes-all")
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
        const grow = findChild(launcher, "notes-all")
        mouseClick(grow, grow.width / 2, grow.height / 2)
        verify(!launcher.notesGrowing)
        compare(controller.drawerExpanded, false)
        verify(launcher.notesOpen)
    }
    function openGenieMode() {
        launcher.fileBrowser = filesMock
        launcher.genie = genieStub
        controller.closes = 0
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const pill = findChild(launcher, "genie-pill")
        verify(pill.visible)
        mouseClick(pill, pill.width / 2, pill.height / 2)
        tryCompare(launcher, "genieProgress", 1)
    }
    // Genie follows Files, and is there only while Split Rock answers.
    function test_genieOffered() {
        launcher.fileBrowser = filesMock
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const row = findChild(launcher, "first-row")
        const genie = findChild(launcher, "genie-pill")
        verify(!genie.visible)
        launcher.genie = genieStub
        verify(genie.visible)
        compare(genie.label, "Ask")
        compare(row.pillsWidth, findChild(launcher, "apps-pill").width + findChild(launcher, "files-pill").width
            + genie.width + 2 * row.pillGap)
        genieStub.available = false
        verify(!genie.visible)
    }
    // Genie opens in Search's own window with the drawer's motion: the field
    // travels into the header for the question, the answer comes below, and
    // the window keeps its size.
    function test_genieModeOpensInSearch() {
        const sheet = findChild(launcher, "launcher-sheet")
        launcher.fileBrowser = filesMock
        launcher.genie = genieStub
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        controller.closes = 0
        const rest = Qt.size(sheet.width, sheet.height)
        const pill = findChild(launcher, "genie-pill")
        mouseClick(pill, pill.width / 2, pill.height / 2)
        verify(launcher.genieOpen)
        compare(genieStub.starts, 1)
        tryCompare(launcher, "genieProgress", 1)
        compare(sheet.width, rest.width)
        compare(sheet.height, rest.height)
        compare(controller.drawerExpanded, false)
        verify(findChild(launcher, "search-field").opacity < 0.01)
        const question = findChild(launcher, "genie-question")
        verify(question.activeFocus)
        const back = findChild(launcher, "genie-back")
        const expand = findChild(launcher, "genie-expand")
        const body = findChild(launcher, "genie-answer")
        const fieldTop = question.mapToItem(sheet, 0, 0).y
        verify(Math.abs(fieldTop - back.mapToItem(sheet, 0, back.height / 2).y) < question.height)
        verify(body.mapToItem(sheet, 0, 0).y > fieldTop)
        verify(expand.mapToItem(sheet, 0, 0).x > sheet.width / 2)
        // Typing asks Genie, not search.
        keyClick(Qt.Key_H)
        keyClick(Qt.Key_I)
        keyClick(Qt.Key_Return)
        compare(genieStub.asked, ["hi"])
        compare(findChild(launcher, "search-query").text, "")
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(launcher, "genieProgress", 0)
        verify(!launcher.genieOpen)
        compare(controller.closes, 0)
    }
    // A suggestion is asked as typed; an answer offers Do it, Show me how and
    // Keep this; Stop cancels an answer in progress.
    function test_genieModeAnswers() {
        openGenieMode()
        const suggestion = findChild(launcher, "genie-suggestion")
        mouseClick(suggestion, suggestion.width / 2, suggestion.height / 2)
        compare(genieStub.asked.length, 1)
        const stop = findChild(launcher, "genie-stop")
        tryVerify(function() { return stop.visible && stop.width > 0 })
        wait(50)
        mouseClick(stop, stop.width / 2, stop.height / 2)
        compare(genieStub.cancels, 1)
        genieStub.answer = "Your screen dims after 2 minutes on battery."
        genieStub.steps = ["Open System Settings.", "Find Dim screen."]
        genieStub.phase = "ready"
        genieStub.conversationChanged()
        const keep = findChild(launcher, "genie-keep")
        tryVerify(function() { return keep.visible && keep.width > 0 })
        wait(50)
        mouseClick(keep, keep.width / 2, keep.height / 2)
        compare(genieStub.acts, ["keep"])
        tryCompare(keep, "label", "Kept")
    }
    // Expand grows the window and Genie's own window takes its place, over
    // an Active card once it has drawn, and in Spread through Kadunce.
    function test_genieExpands() {
        openGenieMode()
        const expand = findChild(launcher, "genie-expand")
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.drawerExpanded, true)
        compare(controller.genieLaunches, 0)
        compare(genieStub.windows.length, 1)
        genieStub.windowShown(genieStub.windows[0])
        tryCompare(controller, "closes", 1)
        controller.guestMode = true
        controller.handoffs = 0
        controller.drawerExpanded = false
        openGenieMode()
        mouseClick(expand, expand.width / 2, expand.height / 2)
        compare(controller.genieLaunches, 1)
        controller.guestLaunchReady()
        tryCompare(controller, "handoffs", 1)
        controller.guestMode = false
    }
    // Before an assistant is ready, Genie says what it needs, and Open Genie
    // grows into its window to finish it.
    function test_genieNeedsSignIn() {
        genieStub.phase = "sign-in"
        openGenieMode()
        const open = findChild(launcher, "genie-open")
        tryVerify(function() { return open.visible })
        mouseClick(open, open.width / 2, open.height / 2)
        compare(genieStub.windows.length, 1)
    }
    // A longer answer shows its other paragraphs; That fixed it is offered
    // beside Keep this; Remember that? asks before anything is written.
    function test_genieRemembers() {
        openGenieMode()
        genieStub.answer = "Your screen dims on battery."
        genieStub.steps = ["Open Power Management."]
        genieStub.more = ["It saves power while you read."]
        genieStub.remember = "You read on battery most evenings."
        genieStub.phase = "ready"
        genieStub.conversationChanged()
        const more = findChild(launcher, "genie-more")
        tryVerify(function() { return more && more.visible })
        compare(more.text, "It saves power while you read.")
        const fixed = findChild(launcher, "genie-fixed")
        tryVerify(function() { return fixed.visible && fixed.width > 0 })
        wait(50)
        mouseClick(fixed, fixed.width / 2, fixed.height / 2)
        tryCompare(fixed, "label", "Fixed")
        const offer = findChild(launcher, "genie-remember-offer")
        verify(offer.visible)
        const notNow = findChild(launcher, "genie-not-now")
        mouseClick(notNow, notNow.width / 2, notNow.height / 2)
        compare(genieStub.acts, ["fixed", "dont-remember"])
        tryVerify(function() { return !offer.visible })
    }
}
