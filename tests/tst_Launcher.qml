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
    QtObject {
        id: controller
        property bool guestMode: false
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
        compare(sheet.width, 640)
        compare(sheet.height, Math.round(740 * 0.64))
        compare(sheet.x, 180)
        controller.guestMode = true
        compare(sheet.width, controller.guestWidth)
        compare(sheet.height, controller.guestHeight)
        compare(sheet.x, controller.guestX)
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
