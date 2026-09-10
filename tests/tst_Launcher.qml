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
        signal opened()
        signal guestLaunchReady()
        signal guestNavigationReady(int slot)
        signal guestBridgeLost()
        function close() { closes++ }
        function showInputMethod() {}
        function updateGuestDrag(value) {}
    }
    ListModel {
        id: results
        property string queryString: ""
        property bool querying: false
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
    function test_bridgeLossRecoversSearch() {
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
