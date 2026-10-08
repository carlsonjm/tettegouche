/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Controls as C

// A menu drawn as part of the sheet it opens in: it never passes the sheet's
// edges, so nothing of it lands where a card's neighbour is or where a tap
// cannot reach it, and it wears the sheet's colours and the suite's floating
// corner, with lines a finger can hit. Its lines are SheetMenuItems.
C.Popup {
    id: menu
    // A duration at Plasma's animation speed: 1 ms when it is instant.
    function ms(base) { return Math.max(1, Math.round(base * Math.max(0, Kirigami.Units.longDuration) / 200)) }
    // The item whose edges the menu stays inside.
    property Item bounds: parent
    // How far up from the window's bottom the on-screen keys reach; the
    // menu keeps above them.
    property real keysReach: 0
    // The lines, in order.
    default property alias entries: lines.data
    readonly property int edge: 8

    parent: bounds
    padding: 6
    modal: false
    dim: false
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    // As wide as its widest line that shows, so no line is cut short.
    implicitWidth: {
        let widest = 0
        for (const line of lines.children)
            if (line.isSheetMenuItem && line.visible) widest = Math.max(widest, line.implicitWidth)
        return Math.min(Math.max(180, widest + leftPadding + rightPadding), 340)
    }

    // Where it opens, in bounds: a rectangle it opens from and how. Its
    // place follows its own size, which is known only once its lines show.
    property rect from: Qt.rect(0, 0, 0, 0)
    property string side: "corner"   // corner, beside or under
    property real floor: bounds ? bounds.height - edge : 0
    x: {
        if (!bounds) return 0
        let want = from.x
        if (side === "beside")
            want = from.x + from.width + width <= bounds.width - edge ? from.x + from.width : from.x - width
        else if (side === "under")
            want = from.x + from.width - width
        return Math.max(edge, Math.min(want, bounds.width - width - edge))
    }
    y: {
        const top = side === "under" ? from.y + from.height + 4 : from.y
        const flipped = side === "under" ? from.y - 4 : from.y + from.height
        return top + height <= floor ? top : Math.max(edge, Math.min(flipped, floor) - height)
    }
    function openFrom(rect, how) {
        const window = bounds.Window.window
        const bottom = bounds.mapToItem(null, 0, bounds.height).y
        const keys = window ? Math.max(0, keysReach - (window.height - bottom)) : 0
        floor = bounds.height - keys - edge
        from = rect
        side = how
        current = -1
        open()
    }
    // Opens with its corner at a point in bounds, below and to the right of
    // it where there is room, else above or to the left.
    function openAt(x, y) { openFrom(Qt.rect(x, y, 0, 0), "corner") }
    // Opens beside a point, a finger's say: to its right, else its left, so
    // no line starts under it.
    function openNear(x, y) { openFrom(Qt.rect(x - 24, y, 48, 0), "beside") }
    // Opens beside an item: to its right, else its left, top edges level.
    function openBeside(item) { openFrom(item.mapToItem(bounds, 0, 0, item.width, item.height), "beside") }
    // Opens under an item, its right edge level with the item's.
    function openUnder(item) { openFrom(item.mapToItem(bounds, 0, 0, item.width, item.height), "under") }

    // The keys move along the lines that can be chosen.
    property int current: -1
    function chosenLines() {
        const out = []
        for (const line of lines.children)
            if (line.visible && line.enabled && line.isSheetMenuItem) out.push(line)
        return out
    }
    function step(by) {
        const choices = chosenLines()
        if (!choices.length) return
        const at = choices.indexOf(lines.children[current])
        const next = at < 0 ? (by > 0 ? 0 : choices.length - 1)
            : (at + by + choices.length) % choices.length
        current = Array.prototype.indexOf.call(lines.children, choices[next])
    }
    contentItem: Column {
        id: lines
        spacing: 2
        focus: true
        Keys.onUpPressed: menu.step(-1)
        Keys.onDownPressed: menu.step(1)
        Keys.onReturnPressed: if (menu.current >= 0) lines.children[menu.current].choose()
        Keys.onEnterPressed: if (menu.current >= 0) lines.children[menu.current].choose()
    }
    onOpened: lines.forceActiveFocus()
    Component.onCompleted: {
        for (const line of lines.children)
            if (line.isSheetMenuItem) {
                line.menu = menu
                line.width = Qt.binding(() => lines.width)
            }
    }

    background: Rectangle {
        id: face
        // The sheet's colours, from the theme of the window it opens in.
        SearchColors {
            id: tone
            theme: face.Kirigami.Theme
        }
        radius: 12
        color: tone.surface
        border.width: 1
        border.color: tone.outline
        // A press between lines stops at the menu.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: menu.ms(120); easing.type: Easing.OutCubic }
    }
    // It goes at once: a fading menu still takes presses, and the tap that
    // follows a choice should reach what it lands on.
}
