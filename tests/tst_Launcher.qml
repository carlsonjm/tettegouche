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
        function beginGuestApplicationLaunch(row, catalog) { return false }
        property int catalogActivated: -1
        function activateCatalogIfOpen(row) { catalogActivated = row; return 1 }
        function finishLaunch() { closes++ }
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
        function showInputMethod() {}
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
        function beginGuestWebLaunch() { return false }
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
        function applicationName(row) { return row >= 0 && row < count ? get(row).name : "" }
    }
    App.Launcher {
        id: launcher
        anchors.fill: parent
        launcherController: controller
        searchResults: results
        applicationCatalog: catalog
    }
    // The arrow keys choose an application in Browse everything, which Enter
    // opens: the chosen one rises and stays in view as the choice moves on.
    // The arrow keys choose an application in Browse everything, typed into
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
        wait(250)
        const closeDrawer = findChild(launcher, "close-drawer-button")
        verify(closeDrawer && closeDrawer.visible)
        const header = findChild(launcher, "drawer-header")
        const search = findChild(launcher, "search-field")
        const grid = findChild(launcher, "application-grid")
        compare(closeDrawer.parent.y + closeDrawer.height / 2, header.height / 2)
        compare(header.y,0)
        tryCompare(search,"y",64)
        compare(grid.y-search.y-search.height,16)
        const closesBefore = controller.closes
        mouseClick(closeDrawer, closeDrawer.width / 2, closeDrawer.height / 2)
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
    function test_compactDrawerHierarchy() {
        const tab = findChild(launcher, "drawer-grabber")
        const label = findChild(launcher, "browse-label")
        const header = findChild(launcher, "drawer-header")
        compare(launcher.drawerProgress, 0)
        verify(label.y + label.height < tab.y)
        verify(label.y + label.height <= header.height)
        launcher.drawerProgress = 0.5
        compare(tab.y, 13)
        compare(tab.width, 147)
        compare(tab.height, 32)
        launcher.drawerProgress = 0
        verify(label.y + label.height < tab.y)
        const search=findChild(launcher,"search-field")
        tryCompare(search,"y",Math.round((search.parent.height-search.height)/2))
        compare(search.x,(search.parent.width-search.width)/2)
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
        const entry=findChild(launcher,"files-entry")
        verify(entry.visible)
        mouseClick(entry,entry.width/2,20)
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
        const entry=findChild(launcher,"files-entry")
        mouseClick(entry,entry.width/2,20)
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
        const entry=findChild(launcher,"files-entry")
        mouseClick(entry,entry.width/2,20)
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
    function test_filesPull() {
        launcher.fileBrowser=filesMock
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        const entry=findChild(launcher,"files-entry")
        const touch=touchEvent(launcher)
        touch.press(0,entry,entry.width/2,28).commit()
        wait(20)
        touch.move(0,entry,entry.width/2,48).commit()
        wait(20)
        touch.move(0,entry,entry.width/2,88).commit()
        wait(20)
        touch.move(0,entry,entry.width/2,128).commit()
        wait(20)
        touch.release(0,entry,entry.width/2,128).commit()
        tryCompare(launcher,"drawerOpen",true)
        verify(launcher.filesMode)
        launcher.setDrawerOpen(false)
        tryCompare(launcher,"drawerProgress",0)
        wait(300)
        const header=findChild(launcher,"drawer-header")
        const start=header.mapToItem(launcher,header.width/2,12)
        touch.press(0,launcher,start.x,start.y).commit()
        wait(30)
        touch.move(0,launcher,start.x,start.y-30).commit()
        wait(30)
        touch.move(0,launcher,start.x,start.y-220).commit()
        wait(30)
        touch.release(0,launcher,start.x,start.y-220).commit()
        tryCompare(launcher,"drawerOpen",true)
        verify(!launcher.filesMode)
    }
    function test_drawerLabelHoverAndEdges() {
        launcher.fileBrowser=filesMock
        const sheet=findChild(launcher,"launcher-sheet")
        const top=findChild(launcher,"files-label")
        const entry=findChild(launcher,"files-entry")
        const bottom=findChild(launcher,"browse-label")
        const tab=findChild(launcher,"drawer-grabber")
        compare(Math.round(top.mapToItem(sheet,0,0).y),30)
        compare(Math.round(sheet.height-bottom.mapToItem(sheet,0,bottom.height).y),30)
        const line=findChild(launcher,"files-edge-line")
        compare(Math.round(line.mapToItem(sheet,0,line.height/2).y),12)
        compare(Math.round(sheet.height-tab.mapToItem(sheet,0,tab.height/2).y),12)
        mouseMove(entry,entry.width/2,12)
        wait(350)
        compare(top.color,launcher.edgeText)
        mouseMove(top,top.width/2,top.height/2)
        wait(350)
        compare(top.color,launcher.primaryText)
        mouseMove(tab,tab.width/2,12)
        wait(350)
        compare(bottom.color,launcher.edgeText)
        grabImage(launcher).save("/tmp/tette-compact-preview.png")
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

    // Files' order opens under its button and stays inside the sheet; a
    // line sets the order, and the hidden-files line shows what it holds.
    function test_filesSortMenu() {
        launcher.fileBrowser = filesMock
        filesMock.placeKind = "folder"
        filesMock.sortMode = 0
        filesMock.hidden = false
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
        const hidden = findChild(launcher, "files-show-hidden")
        verify(!hidden.checked)
        mouseClick(hidden, hidden.width / 2, hidden.height / 2)
        compare(filesMock.hidden, true)
        tryCompare(menu, "opened", false)
        mouseClick(sort, sort.width / 2, sort.height / 2)
        tryCompare(menu, "opened", true)
        verify(hidden.checked)
        menu.close()
        filesMock.hidden = false
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
        compare(findChild(launcher, "empty-trash-summary").text, "3 items, 12 MiB, will be deleted for good. This can't be undone.")
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
        // Meta+G opens Browse everything; again, it closes the launcher.
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
    function test_browseAndSort(data) {
        controller.guestMode = data.guest
        controller.closes = 0
        catalog.descending = false
        controller.opened()
        tryCompare(launcher, "openingControls", 1)
        const label = findChild(launcher, "browse-label")
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
}
