import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: pane
    required property var browser
    property bool creatingFolder: false
    property string renamePath: ""
    property bool draggingFiles: false
    property var dragPaths: []
    property string dropFolder: ""
    property point dragPosition
    property bool showOperationSuccess: false
    readonly property string rawOperationStatus: browser ? browser.operationStatus : ""
    readonly property string operationStatusText: {
        if (showOperationSuccess) return qsTr("Done");
        return rawOperationStatus === qsTr("Done") ? "" : rawOperationStatus;
    }
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
        if(browser.busy || browser.working || browser.opening)return
        if(selectedPaths.indexOf(path)<0)browser.selectedPath=path
        dragPaths=selectedPaths.slice(); draggingFiles=true
        actions.close(); files.forceActiveFocus(); updateFileDrag(position)
    }
    function updateFileDrag(position) {
        if(!draggingFiles)return
        dragPosition=position
        const local=files.mapFromItem(pane,position.x,position.y)
        const index=local.x>=0 && local.y>=0 && local.x<files.width && local.y<files.height
            ? files.indexAt(local.x+files.contentX,local.y+files.contentY) : -1
        const entry=index>=0 ? browser.entries[index] : null
        dropFolder=entry && entry.directory && dragPaths.indexOf(entry.path)<0 ? entry.path : ""
    }
    function cancelFileDrag() { draggingFiles=false; dropFolder=""; dragPaths=[] }
    function finishFileDrag() {
        if(!draggingFiles)return
        const paths=dragPaths.slice(), destination=dropFolder
        cancelFileDrag()
        if(destination.length)browser.copyDropped(paths,destination)
    }
    onVisibleChanged: if(!visible)cancelFileDrag()
    readonly property string selectedPath: browser ? browser.selectedPath : ""
    readonly property var selectedPaths: browser ? browser.selectedPaths : []
    function clearSelection() { browser.selecting=false; browser.selectedPath="" }
    function newFolderForm() { renamePath=""; folderName.text=""; creatingFolder=true; folderName.forceActiveFocus() }
    function renameForm() {
        if(selectedPaths.length!==1)return
        renamePath=selectedPaths[0]; folderName.text=renamePath.split("/").pop()
        creatingFolder=true; folderName.forceActiveFocus(); folderName.selectAll()
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
        property string targetPath: ""
        property bool targetDirectory: false
        C.MenuItem { text: "Open"; visible: actions.targetPath.length>0; enabled: pane.selectedPaths.length===1; onTriggered: pane.browser.openSelected() }
        C.MenuItem { text: "Copy"; enabled: pane.selectedPaths.length>0; onTriggered: pane.browser.copySelected() }
        C.MenuItem { text: "Cut"; enabled: pane.selectedPaths.length>0 && !pane.browser.working; onTriggered: pane.browser.cutSelected() }
        C.MenuItem { text: "Rename"; enabled: pane.selectedPaths.length===1 && !pane.browser.working; onTriggered: pane.renameForm() }
        C.MenuItem { text: "Move to trash"; enabled: pane.selectedPaths.length>0 && !pane.browser.working; onTriggered: trashConfirm.open() }
        C.MenuItem { text: "Restore last trashed item"; enabled: pane.browser.canRestoreTrash && !pane.browser.working; onTriggered: pane.browser.restoreTrash() }
        C.MenuItem {
            objectName: "context-paste"
            text: actions.targetDirectory ? "Paste into “"+actions.targetPath.split("/").pop()+"”" : "Paste here"
            visible: !actions.targetPath.length || actions.targetDirectory
            enabled: pane.browser && pane.browser.canPaste && !pane.browser.working && !pane.browser.busy
            onTriggered: { if(actions.targetDirectory) pane.browser.pasteInto(actions.targetPath); else pane.browser.paste() }
        }
        C.MenuItem { text: "Select all"; onTriggered: pane.browser.selectAll() }
        C.MenuItem { text: "New folder"; visible: !actions.targetPath.length; onTriggered: pane.newFolderForm() }
    }
    C.Dialog {
        id: trashConfirm
        objectName: "trash-confirm"
        title: "Move to trash?"
        modal: true; anchors.centerIn: parent
        standardButtons: C.Dialog.Ok | C.Dialog.Cancel
        Text { text: pane.selectedPaths.length+" item(s). You can restore them afterward."; color: "#F8F8FF" }
        onAccepted: pane.browser.trashSelected()
    }
    component Action: C.Button {
        property string glyph: ""
        implicitHeight: 42
        hoverEnabled: true
        background: Rectangle {
            radius: 12
            color: parent.down ? Qt.rgba(1, 1, 1, 0.16)
                : parent.hovered || parent.visualFocus ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Behavior on color {
                enabled: Kirigami.Units.shortDuration > 0
                ColorAnimation { duration: Kirigami.Units.shortDuration }
            }
        }
        contentItem: Item {
            SuiteIcon {
                visible: parent.parent.glyph.length > 0
                glyph: parent.parent.glyph || "x"
                width: 20; height: 20
                anchors.centerIn: parent
                opacity: parent.parent.enabled ? 1 : 0.42
            }
            Text {
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
            Layout.preferredWidth: 170
            Layout.fillHeight: true
            clip: true
            model: pane.browser ? pane.browser.places : []
            delegate: Item {
                required property var modelData
                width: ListView.view.width; height: 54
                Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 16; color: pane.browser.path === modelData.path ? Qt.rgba(1, 1, 1, 0.24) : "transparent" }
                Row { anchors.verticalCenter: parent.verticalCenter; x: 12; spacing: 12
                    Kirigami.Icon { source: modelData.icon; width: 22; height: 22 }
                    Text { text: modelData.label; color: "#F8F8FF"; width: 116; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                }
                TapHandler { onTapped: pane.browser.navigate(modelData.path) }
            }
        }
        Rectangle { Layout.fillHeight: true; width: 1; color: "#333333" }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
            RowLayout {
                Layout.fillWidth: true
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
            RowLayout {
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
                Action { text: "Path"; onClicked: { pathEditor.visible=!pathEditor.visible; pathEditor.text=pane.browser.path; if(pathEditor.visible)pathEditor.forceActiveFocus() } }
                Action { text: qsTr("Refresh"); glyph: "refresh-cw"; Layout.preferredWidth: 42; onClicked: pane.browser.refresh() }
            }
            Rectangle {
                objectName: "file-navigation-divider"
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#333333"
            }
            C.TextField {
                id: pathEditor
                Keys.onEscapePressed: visible=false
                Layout.fillWidth: true; visible: false
                placeholderText: "Absolute folder path"
                onAccepted: { pane.browser.navigate(text); visible=false }
            }
            RowLayout {
                Layout.fillWidth: true
                PillAction { text: "Done selecting"; visible: pane.browser && pane.browser.selecting; onClicked: pane.clearSelection() }
                PillAction { text: "Copy"; visible: pane.selectedPaths && pane.selectedPaths.length>0; onClicked: pane.browser.copySelected() }
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
                PillAction { objectName: "new-folder"; text: "New folder"; enabled: pane.browser && !pane.browser.working && !pane.browser.busy; onClicked: pane.newFolderForm() }
                PillAction { text: qsTr("Folder actions"); glyph: "ellipsis"; Accessible.name: text; onClicked: pane.showActions("",false,mapToItem(pane,0,height)) }
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
                    running: pane.draggingFiles || box.boxing
                    repeat: true
                    onTriggered: {
                        const p=pane.draggingFiles ? files.mapFromItem(pane,pane.dragPosition.x,pane.dragPosition.y) : box.pointer
                        if(p.x<0 || p.x>files.width)return
                        const band=40
                        const speed=p.y<band ? -Math.min(1,(band-p.y)/band)*10 : p.y>files.height-band ? Math.min(1,(p.y-files.height+band)/band)*10 : 0
                        if(!speed)return
                        files.contentY=Math.max(0,Math.min(Math.max(0,files.contentHeight-files.height),files.contentY+speed))
                        if(pane.draggingFiles)pane.updateFileDrag(pane.dragPosition)
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
                    if(event.key===Qt.Key_Delete) { if(pane.selectedPaths.length && !pane.browser.working)trashConfirm.open(); event.accepted=true; return }
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
                cellWidth: width/Math.max(1,Math.floor(width/140)); cellHeight: 132
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
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 14; color: parent.selected ? Qt.rgba(1, 1, 1, 0.24) : "transparent"; border.color: parent.selected ? "#5A5A5A" : "transparent" }
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 14; color: "#30444444"; border.color: "#F8F8FF"; border.width: 2; visible: pane.draggingFiles && pane.dropFolder===modelData.path }
                    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 15; color: "transparent"; border.color: "#F8F8FF"; visible: files.activeFocus && pane.browser.focusedPath===modelData.path }
                    SuiteIcon {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                        glyph: parent.selected ? "check" : "circle"
                        width: 18; height: 18
                        visible: pane.browser && pane.browser.selecting
                    }
                    Column {
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: parent.width-16; anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                        Kirigami.Icon { source: modelData.icon; width: 52; height: 52; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: modelData.name; color: "#F8F8FF"; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                        Text { text: modelData.detail; color: "#A8FFFFFF"; width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11 }
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
                    TapHandler {
                        id: touchTap
                        acceptedDevices: PointerDevice.TouchScreen
                        longPressThreshold: 0.18
                        property bool held: false
                        property bool dragged: false
                        onPressedChanged: {
                            if(pressed) { held=false; dragged=false }
                            else if(held) Qt.callLater(function() {
                                if(!touchTap.dragged && !pane.draggingFiles && pane.visible) {
                                    pane.browser.selecting=true
                                    pane.showActions(modelData.path,modelData.directory,tile.mapToItem(pane,tile.width/2,40))
                                }
                            })
                        }
                        onTapped: {
                            if(held)return
                            if(pane.browser.selecting)pane.browser.toggleSelected(modelData.path)
                            else pane.browser.selectedPath=modelData.path
                            files.forceActiveFocus()
                        }
                        onDoubleTapped: { if(!held && !pane.browser.selecting) { pane.browser.selectedPath=modelData.path; pane.browser.openSelected() } }
                        onLongPressed: {
                            held=true
                            if(pane.selectedPaths.indexOf(modelData.path)<0)pane.browser.selectedPath=modelData.path
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
                Text { anchors.centerIn: parent; visible: files.count===0; text: !pane.browser ? "" : pane.browser.busy ? "Loading…" : pane.browser.error ? "" : "No files here"; color: "#A8FFFFFF" }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: pane.selectedPaths && pane.selectedPaths.length>1 ? pane.selectedPaths.length+" selected" : pane.selectedPath.length ? pane.selectedPath.split("/").pop() : "Select a file to open"; elide: Text.ElideMiddle; color: "#A8FFFFFF"; font.pixelSize: 12 }
                Action {
                    objectName: "open-file"
                    text: pane.browser && pane.browser.opening ? "Opening…" : "Open"
                    enabled: pane.selectedPath.length>0 && !pane.browser.busy && !pane.browser.opening && !pane.browser.working
                    onClicked: pane.browser.openSelected()
                }
            }
        }
    }
    Connections {
        target: pane.browser
        function onChanged() { pane.cancelFileDrag(); if(!pane.browser.busy) Qt.callLater(function(){ files.contentY=Math.min(pane.browser.scroll,Math.max(0,files.contentHeight-files.height)) }) }
    }
    Rectangle {
        z: 100; visible: pane.draggingFiles
        x: Math.max(0,Math.min(pane.width-width,pane.dragPosition.x+18))
        y: Math.max(0,Math.min(pane.height-height,pane.dragPosition.y-58))
        width: dragLabel.implicitWidth+28; height: 42; radius: 14
        color: "#242424"; border.color: "#5A5A5A"
        Text { id: dragLabel; anchors.centerIn: parent; color: "#F8F8FF"; text: pane.dropFolder.length ? "Copy "+pane.dragPaths.length+" to “"+pane.dropFolder.split("/").pop()+"”" : "Copy "+pane.dragPaths.length+" · choose a folder" }
    }
    Shortcut { sequence: "Ctrl+T"; enabled: pane.visible; onActivated: pane.browser.addTab() }
    Shortcut { sequence: "Ctrl+W"; enabled: pane.visible; onActivated: pane.browser.closeTab(pane.browser.currentTab) }
    Shortcut { sequence: "Ctrl+Tab"; enabled: pane.visible; onActivated: pane.browser.selectTab((pane.browser.currentTab+1)%pane.browser.tabs.length) }
    Shortcut { sequence: "Ctrl+L"; enabled: pane.visible; onActivated: { pathEditor.visible=true; pathEditor.text=pane.browser.path; pathEditor.forceActiveFocus(); pathEditor.selectAll() } }
    Shortcut { sequence: "Alt+Left"; enabled: pane.visible; onActivated: pane.browser.back() }
    Shortcut { sequence: "Alt+Right"; enabled: pane.visible; onActivated: pane.browser.forward() }
    Shortcut { sequence: "Alt+Up"; enabled: pane.visible; onActivated: { const crumbs=pane.browser.crumbs; if(crumbs.length>1)pane.browser.navigate(crumbs[crumbs.length-2].path) } }
}
