import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: pane
    required property var browser
    readonly property string selectedPath: browser ? browser.selectedPath : ""
    component Action: C.Button {
        implicitHeight: 42
        hoverEnabled: true
        background: Rectangle { radius: 12; color: parent.down ? "#404040" : parent.hovered || parent.visualFocus ? "#303030" : "transparent"; Behavior on color { ColorAnimation { duration: 100 } } }
        contentItem: Text { text: parent.text; color: parent.enabled ? "#eeeeee" : "#777777"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
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
                Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 16; color: pane.browser.path === modelData.path ? "#303030" : "transparent" }
                Row { anchors.verticalCenter: parent.verticalCenter; x: 12; spacing: 12
                    Kirigami.Icon { source: modelData.icon; width: 22; height: 22 }
                    Text { text: modelData.label; color: "#eeeeee"; width: 116; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                }
                TapHandler { onTapped: pane.browser.navigate(modelData.path) }
            }
        }
        Rectangle { Layout.fillHeight: true; width: 1; color: "#303030" }
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
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 118; text: modelData.label; color: "#eeeeee"; elide: Text.ElideRight }
                        TapHandler { onTapped: pane.browser.selectTab(index) }
                        Action { anchors.right: parent.right; width: 42; text: "×"; enabled: pane.browser.tabs.length>1; onClicked: pane.browser.closeTab(index) }
                    }
                }
                Action { text: "+"; Layout.preferredWidth: 42; onClicked: pane.browser.addTab() }
            }
            RowLayout {
                Layout.fillWidth: true
                Action { text: "←"; Accessible.name: "Back"; Layout.preferredWidth: 42; enabled: pane.browser && pane.browser.canBack; onClicked: pane.browser.back() }
                Action { text: "→"; Accessible.name: "Forward"; Layout.preferredWidth: 42; enabled: pane.browser && pane.browser.canForward; onClicked: pane.browser.forward() }
                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: "#303030" }
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
                Action { text: "↻"; Layout.preferredWidth: 42; onClicked: pane.browser.refresh() }
            }
            C.TextField {
                id: pathEditor
                Layout.fillWidth: true; visible: false
                placeholderText: "Absolute folder path"
                onAccepted: { pane.browser.navigate(text); visible=false }
            }
            Text { Layout.fillWidth: true; visible: text.length>0; text: pane.browser ? pane.browser.error : ""; color: "#ffb5a8"; wrapMode: Text.Wrap }
            GridView {
                id: files
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; boundsBehavior: Flickable.StopAtBounds
                cellWidth: width/Math.max(1,Math.floor(width/140)); cellHeight: 132
                model: pane.browser ? pane.browser.entries : []
                onMovementEnded: pane.browser.scroll=contentY
                delegate: Item {
                    required property var modelData
                    width: files.cellWidth; height: files.cellHeight
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 14; color: pane.selectedPath===modelData.path ? "#303030" : "transparent"; border.color: pane.selectedPath===modelData.path ? "#777777" : "transparent" }
                    Column {
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: parent.width-16; anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                        Kirigami.Icon { source: modelData.icon; width: 52; height: 52; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: modelData.name; color: "#eeeeee"; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                        Text { text: modelData.detail; color: "#aaaaaa"; width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11 }
                    }
                    TapHandler { onTapped: { if(modelData.directory)pane.browser.navigate(modelData.path); else pane.browser.selectedPath=modelData.path } }
                }
                Text { anchors.centerIn: parent; visible: files.count===0; text: !pane.browser ? "" : pane.browser.busy ? "Loading…" : pane.browser.error ? "" : "No files here"; color: "#aaaaaa" }
            }
            Text { text: "Browsing preview · file actions follow in the next slice"; color: "#888888"; font.pixelSize: 11 }
        }
    }
    Connections {
        target: pane.browser
        function onChanged() { if(!pane.browser.busy) Qt.callLater(function(){ files.contentY=Math.min(pane.browser.scroll,Math.max(0,files.contentHeight-files.height)) }) }
    }
    Shortcut { sequence: "Ctrl+T"; enabled: pane.visible; onActivated: pane.browser.addTab() }
    Shortcut { sequence: "Ctrl+W"; enabled: pane.visible; onActivated: pane.browser.closeTab(pane.browser.currentTab) }
    Shortcut { sequence: "Ctrl+Tab"; enabled: pane.visible; onActivated: pane.browser.selectTab((pane.browser.currentTab+1)%pane.browser.tabs.length) }
}
