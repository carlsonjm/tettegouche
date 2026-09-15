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
        function finishLaunch() { closes++ }
        property int webSearches: 0
        property bool bluetoothResult: false
        property int relatedRevision: 0
        property QtObject bluetoothContext: QtObject {
            property var connectedDevices: []
        }
        signal opened()
        signal revealFileRequested()
        signal guestLaunchReady()
        signal guestNavigationReady(int slot)
        signal guestBridgeLost()
        function close() { closes++ }
        function showInputMethod() {}
        function relatedOptionLabel(row) { return "Open Bluetooth settings" }
        function updateGuestDrag(value) {}
        function relatedItems(row) {
            return bluetoothResult ? bluetoothContext.connectedDevices.map(function(name) {
                return { label: name, status: "Connected" }
            }) : []
        }
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
    }
    App.Launcher {
        id: launcher
        anchors.fill: parent
        launcherController: controller
        searchResults: results
        applicationCatalog: catalog
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
        touch.press(0,folder,folder.width/2,40).commit()
        wait(30)
        touch.release(0,folder,folder.width/2,40).commit()
        compare(filesMock.selectedPath,"/home/test/Projects")
        compare(filesMock.openCalls,before)
        verify(!menu.visible)
        wait(50)
        touch.press(0,folder,folder.width/2,40).commit()
        wait(30)
        touch.release(0,folder,folder.width/2,40).commit()
        compare(filesMock.openCalls,before+1)
        verify(!menu.visible)
        wait(600)
        touch.press(0,file,file.width/2,40).commit()
        wait(30)
        touch.release(0,file,file.width/2,40).commit()
        compare(filesMock.selectedPath,"/home/test/Notes.txt")
        verify(!menu.visible)
        wait(600)
        touch.press(0,file,file.width/2,40).commit()
        wait(230)
        verify(!menu.visible)
        touch.release(0,file,file.width/2,40).commit()
        tryCompare(menu,"opened",true)
        compare(menu.targetPath,"/home/test/Notes.txt")
        compare(filesMock.openCalls,before+1)
        menu.close()
        tryCompare(menu,"visible",false)
        touch.press(0,grid,grid.width-10,grid.height-10).commit()
        wait(30)
        touch.release(0,grid,grid.width-10,grid.height-10).commit()
        compare(filesMock.selectedPath,"")
        verify(!menu.visible)
        const pane=findChild(launcher,"files-pane")
        filesMock.droppedPaths=[]; filesMock.pastedInto=""
        wait(600)
        touch.press(0,file,file.width/2,40).commit()
        wait(230)
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
