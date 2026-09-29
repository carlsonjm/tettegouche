import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: pane
    required property var browser
    // Shuffle's paper corner, for all Files lays in its sheet; anything pressed
    // is a pill.
    readonly property int paperRadius: 8
    property bool creatingFolder: false
    property string renamePath: ""
    property bool draggingFiles: false
    property var dragPaths: []
    property string dropFolder: ""
    property point dragPosition
    // Files carried past this item's edge are handed to carryOut, to leave as
    // a drag another application can take.
    property Item carryArea: null
    signal carryOut(var paths)
    // Files another application is carrying over Files, and where they
    // would be copied: a folder under them, else the folder shown.
    property bool incoming: false
    property int incomingCount: 0
    property string incomingTarget: ""
    property bool showOperationSuccess: false
    // While the on-screen keys are up the folder, its path and its actions keep
    // the room above them: the actions join the path's row, and the tabs and
    // the Open row step aside.
    property bool compact: false
    // How far up from the window's bottom the keys reach, so menus open above.
    property real keysReach: 0
    readonly property string rawOperationStatus: browser ? browser.operationStatus : ""
    // While anything runs, its own row says so; the status line is for what
    // has just finished.
    readonly property string operationStatusText: {
        if (showOperationSuccess) return qsTr("Done");
        if (browser && browser.working) return "";
        // Results keep arriving while a search runs.
        if (browser && browser.searching && browser.entries.length > 0) return qsTr("Searching…");
        return rawOperationStatus === qsTr("Done") ? "" : rawOperationStatus;
    }
    // Tiles in four sizes, from a pinch, Ctrl with + or −, or Ctrl and the wheel.
    readonly property var tileLevels: [
        {cell: 104, height: 108, icon: 36},
        {cell: 140, height: 132, icon: 52},
        {cell: 184, height: 176, icon: 84},
        {cell: 240, height: 228, icon: 128}
    ]
    readonly property var tile: tileLevels[browser ? Math.max(0, Math.min(3, browser.tileSize)) : 1]
    function showOpenWith(path) {
        if (!browser || !path) return
        const choices = browser.openWithChoices(path)
        if (!choices.path) return
        openWithSheet.choices = choices
        openWithSheet.showingAll = !(choices.suggested && choices.suggested.length)
        openWithSheet.everything = openWithSheet.showingAll ? browser.allApplications() : []
        applicationFilter.text = ""
        alwaysUse.checked = false
        openWithSheet.open()
    }
    function showProperties(path) {
        if (!browser || !path) return
        browser.describe(path)
        propertiesSheet.open()
    }
    function resizeTiles(step) { if (browser) browser.tileSize = Math.max(0, Math.min(3, browser.tileSize + step)) }
    // Operations keep their rows while they run; only a start or an end
    // rebuilds the list, so a press on Pause is never lost to a progress tick.
    property var operationIds: []
    function syncOperations() {
        const ids = browser ? browser.operations.map(operation => operation.id) : [];
        if (JSON.stringify(ids) !== JSON.stringify(operationIds)) operationIds = ids;
    }
    function operationFor(id) {
        if (!browser) return null;
        const list = browser.operations;
        for (let i = 0; i < list.length; ++i) if (list[i].id === id) return list[i];
        return null;
    }
    onBrowserChanged: syncOperations()
    Component.onCompleted: syncOperations()
    // A tap that lands just after a folder opened belongs to the tap that
    // opened it, not to whatever now sits under the finger.
    property double navigatedAt: 0
    Timer {
        id: successHold
        interval: 800
        onTriggered: pane.showOperationSuccess = false
    }
    onRawOperationStatusChanged: {
        if (rawOperationStatus === qsTr("Done")) {
            showOperationSuccess = true;
            successHold.restart();
        } else {
            showOperationSuccess = false;
            successHold.stop();
        }
    }
    function beginFileDrag(path, position) {
        if(browser.busy || browser.opening)return
        if(selectedPaths.indexOf(path)<0)browser.selectedPath=path
        dragPaths=selectedPaths.slice(); draggingFiles=true
        actions.close(); files.forceActiveFocus(); updateFileDrag(position)
    }
    function overListing(position) {
        const local=files.mapFromItem(pane,position.x,position.y)
        return local.x>=0 && local.y>=0 && local.x<files.width && local.y<files.height
    }
    function folderAt(position) {
        const local=files.mapFromItem(pane,position.x,position.y)
        const index=overListing(position) ? files.indexAt(local.x+files.contentX,local.y+files.contentY) : -1
        const entry=index>=0 ? browser.entries[index] : null
        return entry && entry.directory ? entry.path : ""
    }
    function updateFileDrag(position) {
        if(!draggingFiles)return
        const area=carryArea || pane, edge=area.mapFromItem(pane,position.x,position.y)
        if(edge.x<0 || edge.y<0 || edge.x>area.width || edge.y>area.height) {
            const paths=dragPaths.slice()
            cancelFileDrag(); carryOut(paths); return
        }
        dragPosition=position
        const folder=folderAt(position)
        dropFolder=dragPaths.indexOf(folder)<0 ? folder : ""
    }
    function cancelFileDrag() { draggingFiles=false; dropFolder=""; dragPaths=[] }
    function trackIncoming(position) {
        dragPosition=position
        dropFolder=folderAt(position)
        incomingTarget=dropFolder.length ? dropFolder : overListing(position) && browser.inFolder ? browser.path : ""
    }
    function endIncoming() { incoming=false; incomingTarget=""; if(!draggingFiles)dropFolder="" }
    function finishFileDrag() {
        if(!draggingFiles)return
        const paths=dragPaths.slice(), destination=dropFolder
        cancelFileDrag()
        if(destination.length)browser.copyDropped(paths,destination)
    }
    onVisibleChanged: if(!visible) { cancelFileDrag(); endIncoming() }
    DropArea {
        objectName: "files-drop"
        anchors.fill: parent
        onEntered: drag => {
            if(!drag.hasUrls || !pane.browser || pane.browser.busy || pane.browser.opening) { drag.accepted=false; return }
            pane.incoming=true; pane.incomingCount=drag.urls.length
            pane.trackIncoming(Qt.point(drag.x,drag.y))
            drag.accept(Qt.CopyAction)
        }
        onPositionChanged: drag => pane.trackIncoming(Qt.point(drag.x,drag.y))
        onExited: pane.endIncoming()
        onDropped: drop => {
            pane.trackIncoming(Qt.point(drop.x,drop.y))
            const destination=pane.incomingTarget
            pane.endIncoming()
            if(!destination.length) { drop.accepted=false; return }
            pane.browser.copyIncoming(drop.urls,destination)
            drop.accept(Qt.CopyAction)
        }
    }
    readonly property string selectedPath: browser ? browser.selectedPath : ""
    readonly property var selectedPaths: browser ? browser.selectedPaths : []
    function clearSelection() { browser.selecting=false; browser.selectedPath="" }
    function newFolderForm() { renamePath=""; folderName.text=""; creatingFolder=true; folderName.forceActiveFocus() }
    function renameForm() {
        if(selectedPaths.length!==1)return
        renamePath=selectedPaths[0]
        const name=renamePath.split("/").pop()
        const entry=browser.entries.find(e=>e.path===renamePath)
        const dot=name.lastIndexOf(".")
        folderName.text=name
        creatingFolder=true; folderName.forceActiveFocus()
        // Select the name and leave its extension, as Dolphin does.
        folderName.select(0, entry && !entry.directory && dot>0 ? dot : name.length)
    }
    function submitName() {
        if(renamePath.length) { if(selectedPaths.length===1 && selectedPaths[0]===renamePath)browser.renameSelected(folderName.text) }
        else browser.newFolder(folderName.text)
        creatingFolder=false; renamePath=""
    }
    function showActions(path, directory, point) {
        if (path.length && selectedPaths.indexOf(path)<0) browser.selectedPath=path
        if (!path.length) clearSelection()
        actions.targetPath=path
        actions.targetDirectory=directory
        actions.x=point.x; actions.y=point.y; actions.open()
    }
    C.Menu {
        id: actions
        objectName: "file-context-menu"
        bottomMargin: pane.keysReach
        onAboutToShow: if (pane.browser && !targetPath.length) pane.browser.checkTrash()
        property string targetPath: ""
        property bool targetDirectory: false
        C.MenuItem { text: "Open"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length===1; onTriggered: pane.browser.openSelected() }
        C.MenuItem { text: "Copy"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length>0; onTriggered: pane.browser.copySelected() }
        C.MenuItem { text: "Cut"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length>0; onTriggered: pane.browser.cutSelected() }
        C.MenuItem { text: "Rename"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length===1; onTriggered: pane.renameForm() }
        C.MenuItem { objectName: "context-open-with"; text: "Open with…"; visible: actions.targetPath.length>0 && !actions.targetDirectory; enabled: pane.selectedPaths.length===1; onTriggered: pane.showOpenWith(pane.selectedPaths[0]) }
        C.MenuItem { text: "Move to trash"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length>0; onTriggered: trashConfirm.open() }
        C.MenuItem { objectName: "context-compress"; text: "Compress"; visible: actions.targetPath.length>0; enabled: pane.browser && pane.browser.canCompress; onTriggered: pane.browser.compressSelected() }
        C.MenuItem { objectName: "context-extract"; text: "Extract here"; visible: actions.targetPath.length>0 && pane.browser && pane.browser.canExtract; onTriggered: pane.browser.extractSelected() }
        C.MenuItem { text: "Restore last trashed item"; enabled: pane.browser && pane.browser.canRestoreTrash; onTriggered: pane.browser.restoreTrash() }
        C.MenuItem { objectName: "context-empty-trash"; text: "Empty Trash…"; visible: !actions.targetPath.length; enabled: pane.browser && pane.browser.trashItems>0; onTriggered: emptyTrashConfirm.open() }
        C.MenuItem {
            objectName: "context-paste"
            text: actions.targetDirectory ? "Paste into “"+actions.targetPath.split("/").pop()+"”" : "Paste here"
            visible: (!actions.targetPath.length && pane.browser && pane.browser.inFolder) || actions.targetDirectory
            enabled: pane.browser && pane.browser.canPaste && !pane.browser.busy
            onTriggered: { if(actions.targetDirectory) pane.browser.pasteInto(actions.targetPath); else pane.browser.paste() }
        }
        C.MenuItem { text: "Select all"; onTriggered: pane.browser.selectAll() }
        C.MenuItem { text: "New folder"; visible: !actions.targetPath.length && pane.browser && pane.browser.inFolder; onTriggered: pane.newFolderForm() }
        C.MenuItem { objectName: "context-properties"; text: "Properties"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length===1; onTriggered: pane.showProperties(pane.selectedPaths[0]) }
    }
    // The one permanent delete Files offers, said plainly before it happens.
    C.Dialog {
        id: emptyTrashConfirm
        objectName: "empty-trash-confirm"
        title: "Empty Trash?"
        modal: true; anchors.centerIn: parent
        width: Math.min(460, pane.width - 48)
        standardButtons: C.Dialog.Ok | C.Dialog.Cancel
        onOpened: standardButton(C.Dialog.Ok).text = "Empty Trash"
        Text {
            objectName: "empty-trash-summary"
            readonly property int items: pane.browser ? pane.browser.trashItems : 0
            readonly property string size: pane.browser ? pane.browser.trashSize : ""
            width: emptyTrashConfirm.availableWidth
            text: (items === 1 ? "1 item" : items + " items") + (size.length ? ", " + size + "," : "") + " will be deleted for good. This can't be undone."
            color: "#F8F8FF"; wrapMode: Text.Wrap
        }
        onAccepted: pane.browser.emptyTrash()
    }
    // A name already taken where files arrive: nothing is replaced unless the
    // person says so. A folder can be merged, never replaced.
    C.Popup {
        id: nameTakenSheet
        objectName: "name-taken-sheet"
        readonly property var question: pane.browser && pane.browser.question ? pane.browser.question : ({})
        property bool answered: false
        function reply(choice) {
            answered = true
            pane.browser.answer(choice, !!question.several && sameForRest.checked)
        }
        modal: true
        focus: true
        closePolicy: C.Popup.CloseOnEscape
        width: Math.min(520, pane.width - 48)
        x: Math.round((pane.width - width) / 2)
        y: Math.max(8, Math.round((pane.height - pane.keysReach - height) / 2))
        padding: 22
        onClosed: if (!answered && question.name) pane.browser.answer("stop", false)
        background: Rectangle { radius: pane.paperRadius; color: "#1B1B1B"; border.color: "#333333" }
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                objectName: "name-taken-title"
                Layout.fillWidth: true
                text: "“" + (nameTakenSheet.question.name || "") + "” is already in " + (nameTakenSheet.question.folder || "")
                color: "#F8F8FF"; font.pixelSize: 17; font.weight: Font.DemiBold; wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                visible: !!nameTakenSheet.question.isFolder
                text: "Merge puts what arrives into the folder that is there. A file already in it asks again."
                color: "#A8FFFFFF"; font.pixelSize: 13; wrapMode: Text.Wrap
            }
            GridLayout {
                visible: !nameTakenSheet.question.isFolder
                columns: 2; columnSpacing: 16; rowSpacing: 6
                Text { text: "Already there"; color: "#A8FFFFFF"; font.pixelSize: 13 }
                Text { objectName: "name-taken-existing"; Layout.fillWidth: true; text: nameTakenSheet.question.existing || ""; color: "#F8F8FF"; font.pixelSize: 13; wrapMode: Text.Wrap }
                Text { text: "Arriving"; color: "#A8FFFFFF"; font.pixelSize: 13 }
                Text { objectName: "name-taken-arriving"; Layout.fillWidth: true; text: nameTakenSheet.question.arriving || ""; color: "#F8F8FF"; font.pixelSize: 13; wrapMode: Text.Wrap }
            }
            RowLayout {
                visible: !!nameTakenSheet.question.several
                spacing: 10
                C.Switch { id: sameForRest; objectName: "name-taken-rest" }
                Text { text: "Do the same for the rest"; color: "#F8F8FF"; font.pixelSize: 13 }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                PillAction { objectName: "name-taken-stop"; text: "Stop"; onClicked: nameTakenSheet.reply("stop") }
                PillAction { objectName: "name-taken-skip"; text: "Skip"; visible: !!nameTakenSheet.question.canSkip; onClicked: nameTakenSheet.reply("skip") }
                PillAction { objectName: "name-taken-keep"; text: "Keep both"; visible: !!nameTakenSheet.question.canKeepBoth; onClicked: nameTakenSheet.reply("keep") }
                PillAction { objectName: "name-taken-replace"; text: nameTakenSheet.question.isFolder ? "Merge" : "Replace"; visible: !!nameTakenSheet.question.canReplace; onClicked: nameTakenSheet.reply("replace") }
            }
        }
    }
    // Open With: the applications for the file's kind, or all of them, and
    // the choice to make the pick KDE's default for that kind.
    C.Popup {
        id: openWithSheet
        objectName: "open-with-sheet"
        property var choices: ({})
        property bool showingAll: false
        property var everything: []
        modal: true
        focus: true
        width: Math.min(480, pane.width - 48)
        x: Math.round((pane.width - width) / 2)
        y: Math.max(8, Math.round((pane.height - pane.keysReach - height) / 2))
        padding: 22
        background: Rectangle { radius: pane.paperRadius; color: "#1B1B1B"; border.color: "#333333" }
        contentItem: ColumnLayout {
            spacing: 14
            Text {
                objectName: "open-with-title"
                Layout.fillWidth: true
                text: openWithSheet.choices.hasDefault === false ? "Choose an application for “" + (openWithSheet.choices.name || "") + "”"
                    : "Open “" + (openWithSheet.choices.name || "") + "” with"
                color: "#F8F8FF"; font.pixelSize: 17; font.weight: Font.DemiBold; wrapMode: Text.WrapAnywhere
            }
            C.TextField {
                id: applicationFilter
                objectName: "open-with-filter"
                Layout.fillWidth: true
                visible: openWithSheet.showingAll
                placeholderText: "Filter applications"
            }
            ListView {
                objectName: "open-with-list"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, Math.max(144, pane.height - pane.keysReach - 320))
                clip: true
                model: openWithSheet.showingAll
                    ? openWithSheet.everything.filter(a => a.name.toLowerCase().indexOf(applicationFilter.text.toLowerCase()) >= 0)
                    : (openWithSheet.choices.suggested || [])
                delegate: Rectangle {
                    required property var modelData
                    objectName: "open-with-" + modelData.id
                    width: ListView.view.width; height: 48; radius: pane.paperRadius
                    color: pick.pressed ? Qt.rgba(1, 1, 1, 0.16) : pickHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    Row {
                        x: 12; spacing: 12; anchors.verticalCenter: parent.verticalCenter
                        Kirigami.Icon { source: modelData.icon; width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.name; color: "#F8F8FF"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: modelData.isDefault; text: "Default"; color: "#A8FFFFFF"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }
                    HoverHandler { id: pickHover }
                    TapHandler {
                        id: pick
                        onTapped: {
                            pane.browser.openWith(openWithSheet.choices.path, modelData.id, alwaysUse.checked)
                            openWithSheet.close()
                        }
                    }
                }
            }
            PillAction {
                objectName: "open-with-all"
                visible: !openWithSheet.showingAll
                text: "Show all applications"
                onClicked: { openWithSheet.everything = pane.browser.allApplications(); openWithSheet.showingAll = true; applicationFilter.forceActiveFocus() }
            }
            RowLayout {
                spacing: 10
                C.Switch { id: alwaysUse; objectName: "open-with-always" }
                Text { Layout.fillWidth: true; text: "Always use it for " + (openWithSheet.choices.kind || "this kind of file"); color: "#F8F8FF"; font.pixelSize: 13; wrapMode: Text.Wrap }
            }
            PillAction { objectName: "open-with-cancel"; Layout.alignment: Qt.AlignRight; text: "Cancel"; onClicked: openWithSheet.close() }
        }
    }
    // A file's or folder's details: what is known at once, then a folder's
    // total size or a photo's, song's or video's own details as they arrive.
    C.Popup {
        id: propertiesSheet
        objectName: "properties-sheet"
        readonly property var details: pane.browser && pane.browser.details ? pane.browser.details : ({})
        modal: true
        focus: true
        width: Math.min(460, pane.width - 48)
        x: Math.round((pane.width - width) / 2)
        y: Math.max(8, Math.round((pane.height - pane.keysReach - height) / 2))
        padding: 22
        onClosed: if (pane.browser) pane.browser.stopDescribing()
        background: Rectangle { radius: pane.paperRadius; color: "#1B1B1B"; border.color: "#333333" }
        contentItem: ColumnLayout {
            spacing: 18
            RowLayout {
                spacing: 14
                Item {
                    Layout.preferredWidth: 56; Layout.preferredHeight: 56
                    Kirigami.Icon { anchors.fill: parent; source: propertiesSheet.details.icon || ""; visible: sheetThumbnail.status !== Image.Ready }
                    Image {
                        id: sheetThumbnail
                        objectName: "properties-thumbnail"
                        anchors.fill: parent
                        source: propertiesSheet.details.thumbnail || ""
                        sourceSize: Qt.size(56, 56)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                }
                Text {
                    objectName: "properties-name"
                    Layout.fillWidth: true
                    text: propertiesSheet.details.name || ""
                    color: "#F8F8FF"; font.pixelSize: 17; font.weight: Font.DemiBold
                    wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                }
            }
            ColumnLayout {
                spacing: 8
                Repeater {
                    objectName: "properties-rows"
                    model: propertiesSheet.details.rows || []
                    delegate: RowLayout {
                        required property var modelData
                        objectName: "properties-row-" + modelData.label
                        Layout.fillWidth: true
                        spacing: 16
                        Text { Layout.preferredWidth: 96; Layout.alignment: Qt.AlignTop; text: modelData.label; color: "#A8FFFFFF"; font.pixelSize: 13 }
                        Text { Layout.fillWidth: true; text: modelData.value; color: "#F8F8FF"; font.pixelSize: 13; wrapMode: Text.WrapAnywhere }
                    }
                }
            }
            PillAction { objectName: "properties-close"; Layout.alignment: Qt.AlignRight; text: "Close"; onClicked: propertiesSheet.close() }
        }
    }
    C.Dialog {
        id: trashConfirm
        objectName: "trash-confirm"
        title: "Move to trash?"
        modal: true; anchors.centerIn: parent
        standardButtons: C.Dialog.Ok | C.Dialog.Cancel
        Text { text: pane.selectedPaths.length+" item(s). Restore last trashed item brings them back, one at a time."; color: "#F8F8FF" }
        onAccepted: pane.browser.trashSelected()
    }
    component Action: C.Button {
        property string glyph: ""
        implicitHeight: 42
        hoverEnabled: true
        background: Rectangle {
            // Pressed, so a pill, or a circle for a glyph alone.
            radius: height / 2
            color: parent.down ? Qt.rgba(1, 1, 1, 0.16)
                : parent.hovered || parent.visualFocus ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Behavior on color {
                enabled: Kirigami.Units.shortDuration > 0
                ColorAnimation { duration: Kirigami.Units.shortDuration }
            }
        }
        contentItem: Item {
            // A pill as wide as its label, so no label is cut short.
            implicitWidth: parent && parent.glyph.length === 0 ? actionLabel.implicitWidth : 20
            implicitHeight: 20
            SuiteIcon {
                visible: parent.parent.glyph.length > 0
                glyph: parent.parent.glyph || "x"
                width: 20; height: 20
                anchors.centerIn: parent
                opacity: parent.parent.enabled ? 1 : 0.42
            }
            Text {
                id: actionLabel
                visible: parent.parent.glyph.length === 0
                anchors.fill: parent
                text: parent.parent.text
                color: parent.parent.enabled ? "#F8F8FF" : "#6BF8F8FF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
    component PillAction: Action {
        leftPadding: 16; rightPadding: 16
        background: Rectangle {
            y: 5; height: parent.height-10
            radius: height/2
            color: parent.down ? Qt.rgba(1, 1, 1, 0.16)
                : parent.hovered || parent.visualFocus ? Qt.rgba(1, 1, 1, 0.12) : "#242424"
            border.color: parent.activeFocus ? "#F8F8FF" : "#5A5A5A"
            Behavior on color {
                enabled: Kirigami.Units.shortDuration > 0
                ColorAnimation { duration: Kirigami.Units.shortDuration }
            }
        }
    }
    RowLayout {
        anchors.fill: parent
        spacing: 20
        ListView {
            objectName: "files-places"
            Layout.preferredWidth: 170
            Layout.fillHeight: true
            clip: true
            model: pane.browser ? pane.browser.places : []
            // The places, then the drives under a rule. A drive opens on a tap,
            // mounted first if it is not; one that is plugged in has an eject
            // button, and says on its row what it is doing.
            delegate: Item {
                id: place
                required property var modelData
                required property int index
                readonly property bool firstDrive: modelData.section === "drives"
                    && (index === 0 || ListView.view.model[index - 1].section !== "drives")
                readonly property bool busy: modelData.busy === true
                readonly property bool ejectable: modelData.canEject === true && !busy
                objectName: "files-place-" + modelData.label
                width: ListView.view.width; height: 54 + (firstDrive ? 13 : 0)
                Rectangle { visible: place.firstDrive; x: 12; y: 6; width: parent.width - 24; height: 1; color: "#333333" }
                Item {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 54
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3; radius: pane.paperRadius
                        color: place.modelData.path.length > 0 && pane.browser.path === place.modelData.path ? Qt.rgba(1, 1, 1, 0.24) : "transparent"
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; x: 12; spacing: 12
                        opacity: place.busy ? 0.6 : 1
                        Kirigami.Icon { source: place.modelData.icon; width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: place.modelData.label; color: "#F8F8FF"; width: place.ejectable ? 76 : 116; elide: Text.ElideRight }
                            Text {
                                objectName: "files-place-note-" + place.modelData.label
                                visible: text.length > 0
                                text: place.modelData.note || ""
                                color: "#A8FFFFFF"; font.pixelSize: 12; width: 116; elide: Text.ElideRight
                            }
                        }
                    }
                    Item {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: place.ejectable ? eject.left : parent.right }
                        TapHandler {
                            enabled: !place.busy
                            onTapped: place.modelData.drive ? pane.browser.openDrive(place.modelData.drive) : pane.browser.navigate(place.modelData.path)
                        }
                    }
                    Action {
                        id: eject
                        objectName: "files-eject-" + place.modelData.label
                        visible: place.ejectable
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        text: qsTr("Eject %1").arg(place.modelData.label)
                        glyph: "eject"
                        onClicked: pane.browser.ejectDrive(place.modelData.drive)
                    }
                }
            }
        }
        Rectangle { Layout.fillHeight: true; width: 1; color: "#333333" }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
            RowLayout {
                objectName: "files-tabs"
                Layout.fillWidth: true
                visible: !pane.compact
                ListView {
                    Layout.fillWidth: true; Layout.preferredHeight: 44
                    orientation: ListView.Horizontal; spacing: 6; clip: true
                    model: pane.browser ? pane.browser.tabs : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: 180; height: 42; radius: 12
                        color: "transparent"
                        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width-24; height: 2; radius: 1; color: pane.browser.currentTab===index ? "#888888" : "transparent" }
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 118; text: modelData.label; color: "#F8F8FF"; elide: Text.ElideRight }
                        TapHandler { onTapped: pane.browser.selectTab(index) }
                        Action { anchors.right: parent.right; width: 42; text: qsTr("Close tab"); glyph: "x"; enabled: pane.browser.tabs.length>1; onClicked: pane.browser.closeTab(index) }
                    }
                }
                Action { text: qsTr("New tab"); glyph: "plus"; Layout.preferredWidth: 42; onClicked: pane.browser.addTab() }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2; rowSpacing: 12; columnSpacing: 12
                RowLayout {
                    objectName: "files-navigation"
                    Layout.row: 0; Layout.column: 0; Layout.columnSpan: pane.compact ? 1 : 2
                    Layout.fillWidth: true
                    Action { text: qsTr("Back"); glyph: "arrow-left"; Layout.preferredWidth: 42; enabled: pane.browser && pane.browser.canBack; onClicked: pane.browser.back() }
                    Action { text: qsTr("Forward"); glyph: "arrow-right"; Layout.preferredWidth: 42; enabled: pane.browser && pane.browser.canForward; onClicked: pane.browser.forward() }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: "#333333" }
                    ListView {
                        Layout.fillWidth: true; Layout.preferredHeight: 42
                        orientation: ListView.Horizontal; spacing: 4; clip: true
                        model: pane.browser ? pane.browser.crumbs : []
                        onCountChanged: positionViewAtEnd()
                        delegate: Row {
                            required property var modelData
                            required property int index
                            height: 42; spacing: 4
                            Text { visible: index>0; text: "›"; color: "#777777"; height: 42; verticalAlignment: Text.AlignVCenter }
                            Action { id: crumbAction; text: modelData.label; width: Math.min(170,Math.max(42,crumbMetrics.advanceWidth+20)); onClicked: pane.browser.navigate(modelData.path)
                                TextMetrics { id: crumbMetrics; font: crumbAction.font; text: crumbAction.text }
                            }
                        }
                    }
                    Action { text: "Path"; onClicked: { pathEditor.visible=!pathEditor.visible; pathEditor.text=pane.browser.folder; if(pathEditor.visible)pathEditor.forceActiveFocus() } }
                    Action { text: qsTr("Refresh"); glyph: "refresh-cw"; Layout.preferredWidth: 42; onClicked: pane.browser.refresh() }
                }
                Rectangle {
                    objectName: "file-navigation-divider"
                    Layout.row: 1; Layout.column: 0; Layout.columnSpan: 2
                    Layout.fillWidth: true
                    visible: !pane.compact
                    implicitHeight: 1
                    color: "#333333"
                }
                C.TextField {
                    id: pathEditor
                    Keys.onEscapePressed: visible=false
                    Layout.row: 2; Layout.column: 0; Layout.columnSpan: 2
                    Layout.fillWidth: true; visible: false
                    placeholderText: "Absolute folder path"
                    onAccepted: { pane.browser.navigate(text); visible=false }
                }
                RowLayout {
                    objectName: "files-actions"
                    Layout.row: pane.compact ? 0 : 3; Layout.column: pane.compact ? 1 : 0
                    Layout.columnSpan: pane.compact ? 1 : 2
                    Layout.fillWidth: !pane.compact
                    // With text typed and nothing chosen, the folder and
                    // everything inside it can be searched for that text.
                    PillAction { objectName: "search-inside"; text: "Search inside folders"; visible: pane.browser && pane.browser.searchOffered && !(pane.selectedPaths && pane.selectedPaths.length>0); onClicked: pane.browser.searchInside(pane.browser.filter) }
                    // While files are chosen, what can be done with them.
                    PillAction { objectName: "done-selecting"; text: "Done selecting"; visible: pane.browser && pane.browser.selecting; onClicked: pane.clearSelection() }
                    PillAction { objectName: "selection-copy"; text: "Copy"; visible: pane.selectedPaths && pane.selectedPaths.length>0; onClicked: pane.browser.copySelected() }
                    PillAction { objectName: "selection-cut"; text: "Cut"; visible: pane.selectedPaths && pane.selectedPaths.length>0; onClicked: pane.browser.cutSelected() }
                    PillAction { objectName: "selection-rename"; text: "Rename"; visible: pane.selectedPaths && pane.selectedPaths.length===1; onClicked: pane.renameForm() }
                    PillAction { objectName: "selection-properties"; text: "Properties"; visible: pane.selectedPaths && pane.selectedPaths.length===1; onClicked: pane.showProperties(pane.selectedPaths[0]) }
                    PillAction { objectName: "selection-trash"; text: "Move to trash"; visible: pane.selectedPaths && pane.selectedPaths.length>0; onClicked: trashConfirm.open() }
                    Item {
                        objectName: "file-operation-status"
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        implicitHeight: 20
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            SuiteIcon {
                                visible: pane.showOperationSuccess
                                glyph: "check"
                                width: 18; height: 18
                                opacity: visible ? 1 : 0
                                Behavior on opacity {
                                    enabled: Kirigami.Units.shortDuration > 0
                                    NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                                }
                            }
                            Text {
                                text: pane.operationStatusText
                                color: "#A8FFFFFF"
                                width: Math.min(implicitWidth, 240)
                                elide: Text.ElideRight
                            }
                        }
                    }
                    PillAction { objectName: "paste-here"; text: "Paste"; visible: pane.browser && pane.browser.canPaste && pane.browser.inFolder; enabled: pane.browser && !pane.browser.busy; onClicked: pane.browser.paste() }
                    PillAction { objectName: "new-folder"; text: "New folder"; visible: !(pane.selectedPaths && pane.selectedPaths.length>0) && pane.browser && pane.browser.inFolder; enabled: pane.browser && !pane.browser.busy; onClicked: pane.newFolderForm() }
                    // With files chosen, their own menu; otherwise the folder's.
                    PillAction {
                        objectName: "more-actions"
                        text: pane.selectedPaths && pane.selectedPaths.length ? qsTr("More actions") : qsTr("Folder actions")
                        glyph: "ellipsis"; Accessible.name: text
                        onClicked: {
                            const first = pane.selectedPaths.length ? pane.selectedPaths[0] : ""
                            const entry = first ? pane.browser.entries.find(e => e.path === first) : null
                            pane.showActions(first, entry ? entry.directory : false, mapToItem(pane, 0, height))
                        }
                    }
                }
            }
            Repeater {
                model: pane.operationIds
                delegate: RowLayout {
                    id: operationRow
                    required property string modelData
                    readonly property var operation: pane.operationFor(modelData)
                    readonly property bool known: operation !== null && operation.progress !== undefined
                    objectName: "file-operation-"+modelData
                    Layout.fillWidth: true
                    visible: operation !== null
                    spacing: 10
                    Text {
                        Layout.preferredWidth: 220
                        text: !operationRow.operation ? "" : operationRow.operation.suspended ? "Paused · "+(operationRow.operation.title || operationRow.operation.label)
                            : operationRow.operation.title ? operationRow.operation.label+" "+operationRow.operation.title : operationRow.operation.label
                        color: operationRow.operation && operationRow.operation.suspended ? "#E3B866" : "#F8F8FF"
                        elide: Text.ElideMiddle
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2
                        color: "#333333"
                        Rectangle {
                            height: parent.height; radius: 2; color: "#F8F8FF"
                            visible: operationRow.known
                            width: operationRow.known ? parent.width*Math.max(0,Math.min(1,operationRow.operation.progress)) : 0
                        }
                    }
                    Text {
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                        text: operationRow.known ? Math.round(operationRow.operation.progress*100)+"%" : "—"
                        color: "#A8FFFFFF"
                        font.features: ({ "tnum": 1 })
                    }
                    Action {
                        objectName: "operation-pause-"+operationRow.modelData
                        Layout.preferredWidth: 42
                        visible: operationRow.operation !== null && operationRow.operation.canSuspend
                        text: operationRow.operation && operationRow.operation.suspended ? qsTr("Resume") : qsTr("Pause")
                        glyph: operationRow.operation && operationRow.operation.suspended ? "play" : "pause"
                        onClicked: operationRow.operation.suspended ? pane.browser.resumeOperation(operationRow.modelData)
                            : pane.browser.suspendOperation(operationRow.modelData)
                    }
                    Action {
                        objectName: "operation-cancel-"+operationRow.modelData
                        Layout.preferredWidth: 42
                        visible: operationRow.operation !== null && operationRow.operation.canCancel
                        text: qsTr("Cancel")
                        glyph: "x"
                        onClicked: pane.browser.cancelOperation(operationRow.modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; visible: pane.creatingFolder
                C.TextField { id: folderName; objectName: "folder-name"; Layout.fillWidth: true; placeholderText: pane.renamePath.length ? "New name" : "Folder name"; Keys.onEscapePressed: pane.creatingFolder=false; onAccepted: pane.submitName() }
                Action { text: pane.renamePath.length ? "Rename" : "Create"; onClicked: pane.submitName() }
                Action { objectName: "cancel-folder"; text: "Cancel"; onClicked: pane.creatingFolder=false }
            }
            Text { Layout.fillWidth: true; visible: text.length>0; text: pane.browser ? pane.browser.error : ""; color: "#ffb5a8"; wrapMode: Text.Wrap }
            GridView {
                id: files
                objectName: "files-grid"
                interactive: !pane.draggingFiles
                Timer {
                    interval: 16
                    running: pane.draggingFiles || pane.incoming || box.boxing
                    repeat: true
                    onTriggered: {
                        const p=pane.draggingFiles || pane.incoming ? files.mapFromItem(pane,pane.dragPosition.x,pane.dragPosition.y) : box.pointer
                        if(p.x<0 || p.x>files.width)return
                        const band=40
                        const speed=p.y<band ? -Math.min(1,(band-p.y)/band)*10 : p.y>files.height-band ? Math.min(1,(p.y-files.height+band)/band)*10 : 0
                        if(!speed)return
                        files.contentY=Math.max(0,Math.min(Math.max(0,files.contentHeight-files.height),files.contentY+speed))
                        if(pane.draggingFiles)pane.updateFileDrag(pane.dragPosition)
                        else if(pane.incoming)pane.trackIncoming(pane.dragPosition)
                        else { box.end=Qt.point(box.pointer.x+files.contentX,box.pointer.y+files.contentY); box.updateSelection() }
                    }
                }
                Keys.onReturnPressed: pane.browser.openSelected()
                Keys.onEnterPressed: pane.browser.openSelected()
                Keys.onPressed: event => {
                    event.accepted=false
                    if(pane.draggingFiles) {
                        if(event.key===Qt.Key_Escape)pane.cancelFileDrag()
                        event.accepted=true; return
                    }
                    if (event.key===Qt.Key_Escape && (pane.selectedPaths.length || pane.browser.selecting)) { pane.clearSelection(); event.accepted=true; return }
                    if(event.key===Qt.Key_F2) { pane.renameForm(); event.accepted=true; return }
                    if(event.key===Qt.Key_Delete) { if(pane.selectedPaths.length)trashConfirm.open(); event.accepted=true; return }
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key===Qt.Key_C) { pane.browser.copySelected(); event.accepted=true }
                        else if(event.key===Qt.Key_X) { pane.browser.cutSelected(); event.accepted=true }
                        else if (event.key===Qt.Key_V) { pane.browser.paste(); event.accepted=true }
                        else if (event.key===Qt.Key_A) { pane.browser.selectAll(); event.accepted=true }
                        if(event.accepted) return
                    }
                    const columns=Math.max(1,Math.floor(width/cellWidth))
                    let delta=0
                    if(event.key===Qt.Key_Left)delta=-1
                    if(event.key===Qt.Key_Right)delta=1
                    if(event.key===Qt.Key_Up)delta=-columns
                    if(event.key===Qt.Key_Down)delta=columns
                    if((delta || event.key===Qt.Key_Home || event.key===Qt.Key_End) && count) {
                        let index=pane.browser.entries.findIndex(e=>e.path===pane.browser.focusedPath)
                        index=event.key===Qt.Key_Home ? 0 : event.key===Qt.Key_End ? count-1 : index<0 ? 0 : Math.max(0,Math.min(count-1,index+delta))
                        const path=pane.browser.entries[index].path
                        if(event.modifiers & Qt.ShiftModifier)pane.browser.selectRange(path,!!(event.modifiers & Qt.ControlModifier))
                        else if(event.modifiers & Qt.ControlModifier)pane.browser.focusedPath=path
                        else pane.browser.selectedPath=path
                        positionViewAtIndex(index,GridView.Contain)
                        event.accepted=true
                    }
                }
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; boundsBehavior: Flickable.StopAtBounds
                cellWidth: width/Math.max(1,Math.floor(width/pane.tile.cell)); cellHeight: pane.tile.height
                PinchHandler {
                    id: tilePinch
                    objectName: "files-pinch"
                    target: null
                    property int startSize: 1
                    onActiveChanged: if (active) startSize = pane.browser.tileSize
                    // One size for each 30% the fingers spread or close.
                    onActiveScaleChanged: {
                        const steps = activeScale >= 1 ? Math.floor(Math.log(activeScale)/Math.log(1.3))
                            : -Math.floor(Math.log(1/activeScale)/Math.log(1.3))
                        pane.browser.tileSize = Math.max(0, Math.min(3, startSize + steps))
                    }
                }
                WheelHandler {
                    target: null
                    acceptedModifiers: Qt.ControlModifier
                    property real pending: 0
                    onWheel: event => {
                        pending += event.angleDelta.y
                        while (pending >= 120) { pane.resizeTiles(1); pending -= 120 }
                        while (pending <= -120) { pane.resizeTiles(-1); pending += 120 }
                    }
                }
                model: pane.browser ? pane.browser.entries : []
                MouseArea {
                    id: box
                    objectName: "file-selection-box"
                    anchors.fill: parent
                    z: 10
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    scrollGestureEnabled: false
                    property point origin
                    property point end
                    property point pointer
                    property bool boxing: false
                    property var original: []
                    property int modifiers: 0
                    function updateSelection() {
                        const left=Math.min(origin.x,end.x), right=Math.max(origin.x,end.x)
                        const top=Math.min(origin.y,end.y), bottom=Math.max(origin.y,end.y)
                        const columns=Math.max(1,Math.round(files.width/files.cellWidth))
                        let hits=[]
                        for(let i=0;i<files.count;i++) {
                            const x=(i%columns)*files.cellWidth+4, y=Math.floor(i/columns)*files.cellHeight+4
                            if(x<right && x+files.cellWidth-8>left && y<bottom && y+files.cellHeight-8>top)
                                hits.push(pane.browser.entries[i].path)
                        }
                        let result=hits
                        if(modifiers & Qt.ControlModifier)
                            result=original.filter(p=>hits.indexOf(p)<0).concat(hits.filter(p=>original.indexOf(p)<0))
                        else if(modifiers & Qt.ShiftModifier)
                            result=original.concat(hits.filter(p=>original.indexOf(p)<0))
                        pane.browser.selectPaths(result)
                    }
                    onPressed: mouse => {
                        const x=mouse.x+files.contentX, y=mouse.y+files.contentY
                        const insideTile=files.indexAt(x,y)>=0 && x%files.cellWidth>=4 && x%files.cellWidth<files.cellWidth-4 && y%files.cellHeight>=4 && y%files.cellHeight<files.cellHeight-4
                        if(mouse.source!==Qt.MouseEventNotSynthesized || pane.browser.busy || insideTile) {
                            mouse.accepted=false; return
                        }
                        original=pane.selectedPaths.slice(); modifiers=mouse.modifiers
                        origin=Qt.point(mouse.x+files.contentX,mouse.y+files.contentY); end=origin
                        pointer=Qt.point(mouse.x,mouse.y)
                        boxing=false; files.forceActiveFocus()
                    }
                    onPositionChanged: mouse => {
                        if(!pressed)return
                        pointer=Qt.point(mouse.x,mouse.y)
                        end=Qt.point(mouse.x+files.contentX,mouse.y+files.contentY)
                        if(Math.abs(end.x-origin.x)+Math.abs(end.y-origin.y)>Qt.styleHints.startDragDistance)boxing=true
                        if(boxing)updateSelection()
                    }
                    onReleased: {
                        if(boxing)updateSelection()
                        else if(!(modifiers & (Qt.ControlModifier|Qt.ShiftModifier)))pane.clearSelection()
                        boxing=false
                    }
                    onCanceled: { if(boxing)pane.browser.selectPaths(original); boxing=false }
                    Rectangle {
                        visible: box.boxing
                        x: Math.min(box.origin.x,box.end.x)-files.contentX
                        y: Math.min(box.origin.y,box.end.y)-files.contentY
                        width: Math.abs(box.end.x-box.origin.x); height: Math.abs(box.end.y-box.origin.y)
                        radius: 6; color: "#28777777"; border.color: "#aaaaaa"
                    }
                }
                onMovementEnded: pane.browser.scroll=contentY
                TapHandler {
                    longPressThreshold: 0.5
                    onTapped: point => {
                        if (files.indexAt(point.position.x+files.contentX,point.position.y+files.contentY)<0) {
                            pane.clearSelection(); pane.browser.focusedPath=""; files.forceActiveFocus()
                        }
                    }
                    onLongPressed: {
                        if (files.indexAt(point.position.x+files.contentX,point.position.y+files.contentY)<0)
                            pane.showActions("",false,files.mapToItem(pane,point.position.x,point.position.y))
                    }
                }
                TapHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.RightButton
                    onTapped: point => {
                        if (files.indexAt(point.position.x+files.contentX,point.position.y+files.contentY)<0)
                            pane.showActions("",false,files.mapToItem(pane,point.position.x,point.position.y))
                    }
                }
                delegate: Item {
                    id: tile
                    required property var modelData
                    objectName: "file-entry-"+modelData.name
                    readonly property bool selected: pane.selectedPaths ? pane.selectedPaths.indexOf(modelData.path)>=0 : false
                    width: files.cellWidth; height: files.cellHeight
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: pane.paperRadius; color: parent.selected ? Qt.rgba(1, 1, 1, 0.24) : "transparent"; border.color: parent.selected ? "#5A5A5A" : "transparent" }
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: pane.paperRadius; color: "#30444444"; border.color: "#F8F8FF"; border.width: 2; visible: (pane.draggingFiles || pane.incoming) && pane.dropFolder===modelData.path }
                    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: pane.paperRadius + 2; color: "transparent"; border.color: "#F8F8FF"; visible: files.activeFocus && pane.browser.focusedPath===modelData.path }
                    SuiteIcon {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                        glyph: parent.selected ? "check" : "circle"
                        width: 18; height: 18
                        visible: pane.browser && pane.browser.selecting
                    }
                    Column {
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: parent.width-16; anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                        Item {
                            width: pane.tile.icon; height: pane.tile.icon; anchors.horizontalCenter: parent.horizontalCenter
                            Kirigami.Icon { anchors.fill: parent; source: modelData.icon; visible: thumbnail.status !== Image.Ready }
                            // A photo, video, PDF or document shows itself once
                            // KDE has made its thumbnail.
                            Image {
                                id: thumbnail
                                objectName: "file-thumbnail-" + modelData.name
                                anchors.fill: parent
                                source: modelData.thumbnail || ""
                                sourceSize: Qt.size(pane.tile.icon, pane.tile.icon)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }
                        }
                        Text { text: modelData.name; color: "#F8F8FF"; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                        Text { text: modelData.detail; color: "#A8FFFFFF"; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; font.pixelSize: 11 }
                    }
                    TapHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.NoModifier
                        onTapped: {
                            if(pane.browser.selecting) pane.browser.toggleSelected(modelData.path)
                            else pane.browser.selectedPath=modelData.path
                            files.forceActiveFocus()
                        }
                        onDoubleTapped: { if(!pane.browser.selecting) { pane.browser.selectedPath=modelData.path; pane.browser.openSelected() } }
                    }
                    // Touch grammar: a tap opens, and a touch and hold starts
                    // choosing several; choosing, a tap adds or removes. A hold
                    // that then moves carries the files instead.
                    TapHandler {
                        id: touchTap
                        acceptedDevices: PointerDevice.TouchScreen
                        longPressThreshold: 0.5
                        property bool held: false
                        property bool dragged: false
                        onPressedChanged: if(pressed) { held=false; dragged=false }
                        onTapped: {
                            if(held)return
                            if(pane.browser.selecting) { pane.browser.toggleSelected(modelData.path); return }
                            if(Date.now()-pane.navigatedAt<Qt.styleHints.mouseDoubleClickInterval)return
                            pane.browser.selectedPath=modelData.path
                            if(modelData.directory)pane.navigatedAt=Date.now()
                            pane.browser.openSelected()
                        }
                        onLongPressed: {
                            held=true
                            if(pane.selectedPaths.indexOf(modelData.path)<0) {
                                if(pane.browser.selecting)pane.browser.toggleSelected(modelData.path)
                                else pane.browser.selectedPath=modelData.path
                            }
                            pane.browser.selecting=true
                        }
                    }
                    DragHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onActiveChanged: {
                            if(active)pane.beginFileDrag(modelData.path,tile.mapToItem(pane,centroid.position.x,centroid.position.y))
                            else Qt.callLater(pane.finishFileDrag)
                        }
                        onCentroidChanged: if(active)pane.updateFileDrag(tile.mapToItem(pane,centroid.position.x,centroid.position.y))
                        onCanceled: pane.cancelFileDrag()
                    }
                    DragHandler {
                        target: null
                        acceptedDevices: PointerDevice.TouchScreen
                        dragThreshold: touchTap.held ? Qt.styleHints.startDragDistance : 32767
                        onActiveChanged: {
                            if(active) { touchTap.dragged=true; pane.beginFileDrag(modelData.path,tile.mapToItem(pane,centroid.position.x,centroid.position.y)) }
                            else Qt.callLater(pane.finishFileDrag)
                        }
                        onCentroidChanged: if(active)pane.updateFileDrag(tile.mapToItem(pane,centroid.position.x,centroid.position.y))
                        onCanceled: { touchTap.dragged=true; pane.cancelFileDrag() }
                    }
                    TapHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.RightButton
                        onTapped: point => pane.showActions(modelData.path,modelData.directory,tile.mapToItem(pane,point.position.x,point.position.y))
                    }
                    TapHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.ControlModifier
                        onTapped: { pane.browser.toggleSelected(modelData.path); files.forceActiveFocus() }
                    }
                    TapHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.ShiftModifier
                        onTapped: { pane.browser.selectRange(modelData.path,false); files.forceActiveFocus() }
                    }
                    TapHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.ControlModifier | Qt.ShiftModifier
                        onTapped: { pane.browser.selectRange(modelData.path,true); files.forceActiveFocus() }
                    }
                }
                Text {
                    objectName: "files-empty"
                    anchors.centerIn: parent; visible: files.count===0; color: "#A8FFFFFF"
                    text: !pane.browser ? "" : pane.browser.searching ? "Searching…" : pane.browser.busy ? "Loading…" : pane.browser.error ? ""
                        : pane.browser.placeKind === "search" ? "Nothing found" : pane.browser.placeKind === "recent" ? "Nothing used recently" : "No files here"
                }
            }
            RowLayout {
                objectName: "files-open-row"
                Layout.fillWidth: true
                visible: !pane.compact
                Text { Layout.fillWidth: true; text: pane.selectedPaths && pane.selectedPaths.length>1 ? pane.selectedPaths.length+" selected" : pane.selectedPath.length ? pane.selectedPath.split("/").pop() : "Select a file to open"; elide: Text.ElideMiddle; color: "#A8FFFFFF"; font.pixelSize: 12 }
                Action {
                    objectName: "open-file"
                    text: pane.browser && pane.browser.opening ? "Opening…" : "Open"
                    enabled: pane.selectedPath.length>0 && !pane.browser.busy && !pane.browser.opening
                    onClicked: pane.browser.openSelected()
                }
            }
        }
    }
    Connections {
        target: pane.browser
        ignoreUnknownSignals: true
        function onChanged() {
            pane.cancelFileDrag()
            if(pane.browser.busy)return
            Qt.callLater(function() {
                const reveal=pane.browser.revealPath
                const index=reveal.length ? pane.browser.entries.findIndex(e=>e.path===reveal) : -1
                if(index>=0) {
                    files.positionViewAtIndex(index,GridView.Contain); pane.browser.revealPath=""
                    if(pane.browser.revealProperties) { pane.browser.revealProperties=false; pane.showProperties(reveal) }
                }
                else files.contentY=Math.min(pane.browser.scroll,Math.max(0,files.contentHeight-files.height))
            })
        }
        function onOperationChanged() { pane.syncOperations() }
        function onQuestionChanged() {
            if (pane.browser.question && pane.browser.question.name) {
                nameTakenSheet.answered = false
                sameForRest.checked = false
                if (!nameTakenSheet.opened) nameTakenSheet.open()
            } else if (nameTakenSheet.opened) {
                nameTakenSheet.answered = true
                nameTakenSheet.close()
            }
        }
        function onApplicationChoiceNeeded(path) { pane.showOpenWith(path) }
    }
    Rectangle {
        objectName: "files-drag-label"
        z: 100; visible: pane.draggingFiles || pane.incoming
        x: Math.max(0,Math.min(pane.width-width,pane.dragPosition.x+18))
        y: Math.max(0,Math.min(pane.height-height,pane.dragPosition.y-58))
        width: dragLabel.implicitWidth+28; height: 42; radius: pane.paperRadius
        color: "#242424"; border.color: "#5A5A5A"
        readonly property int count: pane.incoming ? pane.incomingCount : pane.dragPaths.length
        readonly property string target: pane.incoming ? pane.incomingTarget : pane.dropFolder
        Text { id: dragLabel; anchors.centerIn: parent; color: "#F8F8FF"; text: parent.target.length ? "Copy "+parent.count+" to “"+parent.target.split("/").pop()+"”" : "Copy "+parent.count+" · choose a folder" }
    }
    Shortcut { sequence: "Ctrl+T"; enabled: pane.visible; onActivated: pane.browser.addTab() }
    Shortcut { sequences: ["Alt+Return", "Alt+Enter"]; enabled: pane.visible && pane.selectedPaths.length===1; onActivated: pane.showProperties(pane.selectedPaths[0]) }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; enabled: pane.visible; onActivated: pane.resizeTiles(1) }
    Shortcut { sequence: "Ctrl+-"; enabled: pane.visible; onActivated: pane.resizeTiles(-1) }
    Shortcut { sequence: "Ctrl+0"; enabled: pane.visible; onActivated: pane.browser.tileSize=1 }
    Shortcut { sequence: "Ctrl+W"; enabled: pane.visible; onActivated: pane.browser.closeTab(pane.browser.currentTab) }
    Shortcut { sequence: "Ctrl+Tab"; enabled: pane.visible; onActivated: pane.browser.selectTab((pane.browser.currentTab+1)%pane.browser.tabs.length) }
    Shortcut { sequence: "Ctrl+L"; enabled: pane.visible; onActivated: { pathEditor.visible=true; pathEditor.text=pane.browser.folder; pathEditor.forceActiveFocus(); pathEditor.selectAll() } }
    Shortcut { sequence: "Alt+Left"; enabled: pane.visible; onActivated: pane.browser.back() }
    Shortcut { sequence: "Alt+Right"; enabled: pane.visible; onActivated: pane.browser.forward() }
    Shortcut { sequence: "Alt+Up"; enabled: pane.visible; onActivated: { const crumbs=pane.browser.crumbs; if(crumbs.length>1)pane.browser.navigate(crumbs[crumbs.length-2].path) } }
}
