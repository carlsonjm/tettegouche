pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

// Three island looks, stacked over a wallpaper at the band's true size. A, the
// clear island, is the one built; the other two are kept to be seen again. All three share the same
// stand-in activities: nothing here plays, copies or talks to any application.
// An ordinary window: Esc closes any open island, then the window; Close ends
// it too.
//
//     qml6 tools/IslandBakeoff.qml [-- --image FILE] [--scene N] [--open KIND] [--card] [--grab FILE]
Window {
    id: win
    title: "Shuffle bake-off: the Ambient island"
    width: 1463
    height: 915
    visible: true
    color: "black"
    screen: Qt.application.screens.find(candidate => candidate.name === "eDP-1") ?? Qt.application.screens[0]
    visibility: grabPath.length > 0 ? Window.Windowed : Window.FullScreen

    function argument(name) {
        const at = Qt.application.arguments.indexOf(name);
        return at >= 0 && at + 1 < Qt.application.arguments.length ? Qt.application.arguments[at + 1] : "";
    }
    function flag(name) {
        return Qt.application.arguments.indexOf(name) >= 0;
    }
    readonly property string grabPath: argument("--grab")
    readonly property url wallpaper: argument("--image").length > 0 ? "file://" + argument("--image") : ""
    readonly property string glyphRoot: Qt.resolvedUrl("../assets/icons/lucide/")
    property int backdrop: argument("--image").length > 0 ? 0 : 1
    readonly property var backdropNames: ["Your wallpaper", "A bright wallpaper", "A white page"]
    property bool cardUp: flag("--card")
    property bool smallClear: false

    readonly property color ink: "#F8F8FF"
    readonly property color ink2: "#A8F8F8FF"
    readonly property color amber: "#E3B866"
    readonly property string family: Kirigami.Theme.defaultFont.family

    // The band as Shuffle draws it: 64 px, the launcher's 44 px square on the
    // cards' 10 px gutter, the dock centred.
    readonly property real barHeight: 56
    readonly property real stripHeight: Math.floor((height - barHeight) / 3)
    readonly property real bandHeight: 64
    readonly property real gutter: 10
    readonly property var dockApps: ["com.mitchellh.ghostty", "code-oss", "steam", "discord", "spotify",
        "zen-browser", "org.kde.dolphin", "applets-screenshooter", "chatgpt", "org.kde.spectacle"]
    readonly property var running: [1, 1, 0, 0, 1, 1, 0, 1, 1, 0]
    readonly property int activeApp: 9
    readonly property real dockWidth: dockApps.length * 44 + (dockApps.length - 1) * 8
    readonly property real dockLeft: Math.round((width - dockWidth) / 2)
    // Ambient's side: the band's left flank, as Shuffle allocates it, after
    // the launcher's square.
    readonly property real flankWidth: Math.max(0, Math.floor((width - dockWidth) / 2) - 2 * 8 - gutter)
    readonly property real areaLeft: gutter + 44
    readonly property real areaRight: gutter + flankWidth
    readonly property real areaCentre: (areaLeft + areaRight) / 2

    // Each strip's island. Sizes in logical pixels.
    readonly property var styles: [
        { key: "shown", title: "As shown: a solid island",
          detail: "Black, 44 px tall, the height of the dock's icons.",
          height: 44, clear: false, glyph: 20, play: 22, art: 30, step: 44, reach: 44, side: 124, twoLines: true,
          small: 84 },
        { key: "clear", title: "A. A clear island, the same size",
          detail: "Your wallpaper shows through it. It turns black when a card is up, as the band does, and when it opens.",
          height: 44, clear: true, glyph: 20, play: 22, art: 30, step: 44, reach: 44, side: 124, twoLines: true,
          small: 84 },
        { key: "small", title: "B. Today's size",
          detail: "Drawn as small as today's Ambient, 32 px tall. Its buttons still answer a finger across the band's full height, as Temperance's do.",
          height: 32, clear: false, glyph: 18, play: 20, art: 22, step: 34, reach: 60, side: 104, twoLines: false,
          small: 76 }
    ]

    // What is going on, in arrival order: "media", "copy", "dialog".
    readonly property var sceneNames: ["Nothing", "Music", "A copy", "Music + a copy",
        "Music + a copy + a dialog", "Music + two copies"]
    property int scene: 1
    property var present: []
    property bool playing: true
    property real position: 94
    property int track: 0
    property int player: 0
    readonly property var players: [
        { app: "Spotify", icon: "spotify", tracks: [
            { title: "Holocene", artist: "Bon Iver", length: 336, a: "#C9795B", b: "#4E3A86" },
            { title: "Re: Stacks", artist: "Bon Iver", length: 401, a: "#7FA7C9", b: "#27334A" },
            { title: "Skinny Love", artist: "Bon Iver", length: 238, a: "#D9C27A", b: "#6B4B2A" } ] },
        { app: "Zen Browser", icon: "zen-browser", tracks: [
            { title: "Lake Superior in winter", artist: "YouTube", length: 612, a: "#9DC7D8", b: "#1F4F66" } ] }
    ]
    readonly property var playerNow: players[player]
    readonly property var nowPlaying: playerNow.tracks[track % playerNow.tracks.length]
    readonly property string mainKind: present.length > 0 ? present[0] : ""
    readonly property bool shared: present.length > 1
    readonly property string bubbleKind: shared ? present[present.length - 1] : ""
    readonly property int bubbleCount: present.slice(1).reduce(
        (n, kind) => n + (kind === "copy" ? copyModel.count : 1), 0)

    ListModel { id: copyModel }
    property int copyTick: 0
    function first(role) {
        copyTick;
        return copyModel.count > 0 ? copyModel.get(0)[role] : undefined;
    }

    function setScene(n) {
        scene = n;
        closeAll();
        present = [[], ["media"], ["copy"], ["media", "copy"], ["media", "copy", "dialog"], ["media", "copy"]][n];
        copyModel.clear();
        if (present.indexOf("copy") >= 0)
            copyModel.append({ name: "Photos", target: "Backup", files: 214, gigabytes: 2.9, progress: 0.42, paused: false });
        if (n === 5)
            copyModel.append({ name: "Shuffle-1.0.iso", target: "Downloads", files: 1, gigabytes: 4.2, progress: 0.18, paused: false });
        copyTick++;
        playing = true;
        player = 0;
        track = 0;
        position = 94;
    }
    function leave(kind) {
        present = present.filter(k => k !== kind);
    }
    function cancelCopy(index) {
        copyModel.remove(index);
        copyTick++;
        if (copyModel.count === 0) leave("copy");
    }
    function step(delta) {
        const count = playerNow.tracks.length;
        track = ((track + delta) % count + count) % count;
        position = 0;
    }
    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function strip(i) {
        return strips.itemAt(i);
    }
    function closeAll() {
        let any = false;
        for (let i = 0; i < strips.count; ++i) {
            if (strips.itemAt(i) && strips.itemAt(i).open) {
                strips.itemAt(i).open = false;
                any = true;
            }
        }
        return any;
    }

    Component.onCompleted: {
        setScene(Number(argument("--scene") || 1));
    }
    Timer {
        running: win.argument("--open").length > 0
        interval: 100
        onTriggered: {
            for (let i = 0; i < strips.count; ++i) strips.itemAt(i).openIsland(win.argument("--open"));
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: win.playing && win.present.indexOf("media") >= 0
        onTriggered: {
            if (win.position + 1 >= win.nowPlaying.length) win.step(1);
            else win.position += 1;
        }
    }
    Timer {
        interval: 400
        repeat: true
        running: copyModel.count > 0
        onTriggered: {
            for (let i = 0; i < copyModel.count; ++i) {
                if (!copyModel.get(i).paused)
                    copyModel.setProperty(i, "progress", Math.min(0.96, copyModel.get(i).progress + 0.002));
            }
            win.copyTick++;
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: if (!win.closeAll()) Qt.quit()
    }

    // ---------------------------------------------------------------- pieces

    component Glyph: Image {
        property string name
        property real size: 20
        width: size
        height: size
        source: win.glyphRoot + name + ".svg"
        sourceSize: Qt.size(size * 2, size * 2)
        smooth: true
    }

    // A control: the glyph rises under the finger. Its reach can be taller
    // than the island it sits in.
    component GlyphButton: Item {
        id: button
        property string glyph
        property real size: 20
        signal activated()
        width: 44
        height: 44
        Glyph {
            anchors.centerIn: parent
            name: button.glyph
            size: button.size
            scale: buttonArea.pressed ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            onClicked: button.activated()
        }
    }

    // Back or forward 10 s: a turning arrow round the number.
    component SkipTen: Item {
        id: skip
        property bool forward: true
        signal activated()
        width: 44
        height: 44
        Item {
            anchors.centerIn: parent
            width: 26
            height: 26
            scale: skipArea.pressed ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    if (!skip.forward) { c.translate(width, 0); c.scale(-1, 1); }
                    const cx = 13, cy = 13, r = 10;
                    const a0 = -Math.PI / 2 + 0.45, a1 = -Math.PI / 2 - 0.45 + 2 * Math.PI;
                    c.strokeStyle = "#F8F8FF";
                    c.lineWidth = 2;
                    c.lineCap = "round";
                    c.lineJoin = "round";
                    c.beginPath();
                    c.arc(cx, cy, r, a0, a1, false);
                    c.stroke();
                    const px = cx + r * Math.cos(a1), py = cy + r * Math.sin(a1);
                    const back = [Math.sin(a1), -Math.cos(a1)];
                    const wing = (angle) => [back[0] * Math.cos(angle) - back[1] * Math.sin(angle),
                                             back[0] * Math.sin(angle) + back[1] * Math.cos(angle)];
                    const w1 = wing(0.6), w2 = wing(-0.6);
                    c.beginPath();
                    c.moveTo(px + w1[0] * 5, py + w1[1] * 5);
                    c.lineTo(px, py);
                    c.lineTo(px + w2[0] * 5, py + w2[1] * 5);
                    c.stroke();
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: "10"
                color: win.ink
                font.family: win.family
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: skipArea
            anchors.fill: parent
            onClicked: skip.activated()
        }
    }

    component PillButton: Rectangle {
        id: pill
        property string label
        property bool filled: false
        property real fontSize: 14
        signal activated()
        height: 40
        width: Math.max(40, pillText.implicitWidth + 28)
        radius: height / 2
        color: filled ? win.ink : Qt.rgba(1, 1, 1, pillArea.pressed ? 0.22 : 0.12)
        scale: pillArea.pressed ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.filled ? "#000000" : win.ink
            font.family: win.family
            font.pixelSize: pill.fontSize
            font.weight: Font.Medium
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            onClicked: pill.activated()
        }
    }

    // Stand-in album art.
    component Art: Rectangle {
        id: artBox
        property var art: win.nowPlaying
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0; color: artBox.art.a }
            GradientStop { position: 1; color: artBox.art.b }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.34
            height: width
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.22)
        }
    }

    // A transfer's reported progress, as a ring.
    component Ring: Canvas {
        id: ring
        property real progress: 0
        property real thickness: 3
        onProgressChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const r = Math.min(width, height) / 2 - thickness / 2 - 0.5;
            c.lineWidth = thickness;
            c.lineCap = "round";
            c.strokeStyle = "rgba(255,255,255,0.2)";
            c.beginPath();
            c.arc(width / 2, height / 2, r, 0, 2 * Math.PI, false);
            c.stroke();
            c.strokeStyle = "#F8F8FF";
            c.beginPath();
            c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ring.progress, false);
            c.stroke();
        }
    }

    component Label: Text {
        color: win.ink
        font.family: win.family
        font.pixelSize: 13
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // An activity's small mark: in the bubble and in the open island's row.
    component Mark: Item {
        id: mark
        property string kind
        property real size: 30
        width: size
        height: size
        Art {
            visible: mark.kind === "media"
            anchors.fill: parent
            radius: width / 2
        }
        Ring {
            visible: mark.kind === "copy"
            anchors.fill: parent
            thickness: mark.size < 26 ? 2.5 : 3
            progress: win.first("progress") || 0
        }
        Kirigami.Icon {
            visible: mark.kind === "dialog"
            anchors.centerIn: parent
            width: mark.size * 0.8
            height: width
            source: "org.kde.kate"
            fallback: "kate"
        }
        Rectangle {
            visible: mark.kind === "dialog"
            x: parent.width - width + 1
            y: parent.height - height + 1
            width: mark.size < 26 ? 8 : 10
            height: width
            radius: width / 2
            color: win.amber
            border.width: 1.5
            border.color: "#000000"
        }
    }

    // One closed layout inside the island; fades as the island opens.
    component Compact: Row {
        required property bool active
        property bool opened: false
        anchors.centerIn: parent
        opacity: active && !opened ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: opened ? 90 : 200 } }
    }

    // ---------------------------------------------------------------- a strip

    component Strip: Item {
        id: strip
        required property var style
        required property int index
        property bool open: false
        property string openKind: ""
        readonly property real bandTop: height - win.bandHeight
        readonly property real pillHeight: style.height
        readonly property real pillY: bandTop + (win.bandHeight - pillHeight) / 2
        readonly property bool clear: style.key === "small" ? win.smallClear : style.clear
        // A clear island is black wherever the band is: under a card, and open.
        readonly property color fill: clear && !win.cardUp && !open ? Qt.rgba(1, 1, 1, 0.07) : "#000000"
        readonly property color edge: clear && !win.cardUp && !open ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.12)
        width: win.width
        height: win.stripHeight
        clip: true

        function openIsland(kind) {
            if (win.present.indexOf(kind) < 0) return;
            openKind = kind;
            open = true;
        }
        Connections {
            target: win
            function onPresentChanged() {
                if (win.present.length === 0) strip.open = false;
                else if (win.present.indexOf(strip.openKind) < 0) strip.openKind = win.present[0];
            }
        }

        Item {
            y: strip.height - win.height
            width: win.width
            height: win.height
            Image {
                anchors.fill: parent
                visible: win.backdrop === 0
                source: win.wallpaper
                fillMode: Image.PreserveAspectCrop
            }
            Rectangle {
                anchors.fill: parent
                visible: win.backdrop === 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#f3d9b1" }
                    GradientStop { position: 0.5; color: "#bfe3f2" }
                    GradientStop { position: 1; color: "#f6f1e7" }
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: win.backdrop === 2
                color: "white"
            }
        }

        // A card up: the Active card's lower part, its edges on the gutter.
        Rectangle {
            visible: win.cardUp
            x: win.gutter
            width: parent.width - 2 * win.gutter
            y: -12
            height: strip.bandTop - win.gutter - y
            radius: 12
            color: "#1b1d1c"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }

        Rectangle {
            x: 12
            y: 10
            width: stripLabel.width + 24
            height: stripLabel.height + 16
            radius: 12
            color: Qt.rgba(0, 0, 0, 0.55)
        }
        Column {
            id: stripLabel
            x: 24
            y: 18
            width: 700
            spacing: 3
            Text {
                text: strip.style.title
                color: win.ink
                font.family: win.family
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: strip.style.detail
                color: win.ink
                opacity: 0.85
                wrapMode: Text.WordWrap
                font.family: win.family
                font.pixelSize: 13
            }
        }

        Item {
            y: strip.bandTop
            width: parent.width
            height: win.bandHeight

            Rectangle {
                anchors.fill: parent
                visible: !win.cardUp
                gradient: Gradient {
                    GradientStop { position: 0 / 24; color: Qt.rgba(0, 0, 0, 0.0000) }
                    GradientStop { position: 2 / 24; color: Qt.rgba(0, 0, 0, 0.0285) }
                    GradientStop { position: 4 / 24; color: Qt.rgba(0, 0, 0, 0.0994) }
                    GradientStop { position: 6 / 24; color: Qt.rgba(0, 0, 0, 0.1960) }
                    GradientStop { position: 8 / 24; color: Qt.rgba(0, 0, 0, 0.3061) }
                    GradientStop { position: 10 / 24; color: Qt.rgba(0, 0, 0, 0.4205) }
                    GradientStop { position: 12 / 24; color: Qt.rgba(0, 0, 0, 0.5324) }
                    GradientStop { position: 14 / 24; color: Qt.rgba(0, 0, 0, 0.6365) }
                    GradientStop { position: 16 / 24; color: Qt.rgba(0, 0, 0, 0.7286) }
                    GradientStop { position: 18 / 24; color: Qt.rgba(0, 0, 0, 0.8053) }
                    GradientStop { position: 20 / 24; color: Qt.rgba(0, 0, 0, 0.8642) }
                    GradientStop { position: 22 / 24; color: Qt.rgba(0, 0, 0, 0.9030) }
                    GradientStop { position: 24 / 24; color: Qt.rgba(0, 0, 0, 0.9200) }
                }
            }
            Rectangle {
                anchors.fill: parent
                visible: win.cardUp
                color: "#141414"
            }

            // The launcher dot, centred in its touch square on the gutter.
            Rectangle {
                x: win.gutter + (44 - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: 12
                color: win.ink
            }

            Row {
                x: win.dockLeft
                height: parent.height
                spacing: 8
                Repeater {
                    model: win.dockApps
                    delegate: Item {
                        id: slot
                        required property string modelData
                        required property int index
                        width: 44
                        height: 64
                        Kirigami.Icon {
                            y: 10
                            width: 44
                            height: 44
                            source: slot.modelData
                        }
                        Rectangle {
                            visible: win.running[slot.index] === 1 && slot.index !== win.activeApp
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 57
                            width: 4
                            height: 4
                            radius: 2
                            color: "white"
                            opacity: 0.7
                        }
                        Rectangle {
                            visible: slot.index === win.activeApp
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 57
                            width: 22
                            height: 4
                            radius: 2
                            color: "white"
                        }
                    }
                }
            }

            // Temperance, roughly: its status icons and clock.
            Row {
                anchors.right: parent.right
                anchors.rightMargin: win.gutter + 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Repeater {
                    model: ["notifications-symbolic", "weather-few-clouds-symbolic",
                        "network-wireless-signal-excellent-symbolic", "battery-080-symbolic"]
                    delegate: Kirigami.Icon {
                        required property string modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        isMask: true
                        color: win.ink
                        source: modelData
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "1:24"
                    color: win.ink
                    font.family: win.family
                    font.pixelSize: 15
                }
            }
        }

        // Tapping outside the open island closes it.
        MouseArea {
            anchors.fill: parent
            enabled: strip.open
            onClicked: strip.open = false
        }

        readonly property Item compactContent: win.mainKind === "media" ? (win.shared ? mediaSmall : mediaFull)
            : win.mainKind === "copy" ? (win.shared ? copySmall : copyFull)
            : win.mainKind === "dialog" ? dialogSmall : null
        readonly property real compactWidth: compactContent ? compactContent.implicitWidth + 12 : pillHeight
        readonly property real groupWidth: compactWidth + (win.shared ? 8 + pillHeight : 0)
        readonly property real compactX: Math.max(win.areaLeft, win.areaCentre - groupWidth / 2)
        readonly property real openWidth: Math.min(384, win.areaRight - win.areaLeft)
        readonly property real openHeight: openContent.implicitHeight + 36
        readonly property real openX: Math.max(win.areaLeft, Math.min(win.areaRight - openWidth,
            compactX + compactWidth / 2 - openWidth / 2))
        readonly property real openY: pillY + pillHeight - openHeight

        Rectangle {
            id: island
            objectName: "island-" + strip.index
            x: strip.open ? strip.openX : strip.compactX
            y: strip.open ? strip.openY : strip.pillY
            width: strip.open ? strip.openWidth : strip.compactWidth
            height: strip.open ? strip.openHeight : strip.pillHeight
            radius: Math.min(height / 2, 30)
            color: strip.fill
            border.width: 1
            border.color: strip.edge
            // Clipped only while it changes shape or is open, so a control's
            // reach can run past a small island's edge.
            clip: strip.open || reshaping.running
            opacity: win.present.length > 0 ? 1 : 0
            scale: win.present.length === 0 ? 0.6 : islandArea.pressed && !strip.open ? 1.03 : 1
            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }

            Timer {
                id: reshaping
                interval: 360
            }
            Connections {
                target: strip
                function onOpenChanged() { reshaping.restart(); }
            }

            // A tap away from the controls opens the island.
            MouseArea {
                id: islandArea
                anchors.fill: parent
                onClicked: if (!strip.open) strip.openIsland(win.mainKind)
            }

            // Music alone: art and title, the controls in the middle, the time
            // and the player on the far side.
            Compact {
                id: mediaFull
                active: strip.compactContent === mediaFull
                opened: strip.open
                height: strip.pillHeight
                Item {
                    width: strip.style.side
                    height: strip.pillHeight
                    Art {
                        x: (strip.pillHeight - strip.style.art) / 2 - 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: strip.style.art
                        height: strip.style.art
                        radius: strip.style.art > 26 ? 8 : 6
                    }
                    Column {
                        x: strip.style.art + 10
                        width: parent.width - x - 4
                        anchors.verticalCenter: parent.verticalCenter
                        Label { width: parent.width; text: win.nowPlaying.title; font.weight: Font.DemiBold }
                        Label { visible: strip.style.twoLines; width: parent.width; text: win.nowPlaying.artist
                            color: win.ink2; font.pixelSize: 11 }
                    }
                }
                Row {
                    objectName: "media-controls-" + strip.index
                    anchors.verticalCenter: parent.verticalCenter
                    GlyphButton { width: strip.style.step; height: strip.style.reach; glyph: "skip-back"
                        size: strip.style.glyph; onActivated: win.step(-1) }
                    GlyphButton { width: strip.style.step; height: strip.style.reach; glyph: win.playing ? "pause" : "play"
                        size: strip.style.play; onActivated: win.playing = !win.playing }
                    GlyphButton { width: strip.style.step; height: strip.style.reach; glyph: "skip-forward"
                        size: strip.style.glyph; onActivated: win.step(1) }
                }
                Item {
                    width: strip.style.side
                    height: strip.pillHeight
                    Column {
                        anchors.right: playerIcon.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Label { anchors.right: parent.right; text: win.clock(win.position); font.features: ({ "tnum": 1 }) }
                        Label { visible: strip.style.twoLines; anchors.right: parent.right; text: win.clock(win.nowPlaying.length)
                            color: win.ink2; font.pixelSize: 11; font.features: ({ "tnum": 1 }) }
                    }
                    Kirigami.Icon {
                        id: playerIcon
                        anchors.right: parent.right
                        anchors.rightMargin: (strip.pillHeight - width) / 2 - 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: strip.style.art > 26 ? 24 : 18
                        height: width
                        source: win.playerNow.icon
                    }
                }
            }

            // Music sharing the band: art, play or pause, and the title.
            Compact {
                id: mediaSmall
                active: strip.compactContent === mediaSmall
                opened: strip.open
                height: strip.pillHeight
                spacing: 2
                Item { width: (strip.pillHeight - strip.style.art) / 2 - 6; height: 1 }
                Art { anchors.verticalCenter: parent.verticalCenter; width: strip.style.art; height: strip.style.art
                    radius: strip.style.art > 26 ? 8 : 6 }
                GlyphButton { anchors.verticalCenter: parent.verticalCenter; width: strip.style.step; height: strip.style.reach
                    glyph: win.playing ? "pause" : "play"; size: strip.style.play; onActivated: win.playing = !win.playing }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, strip.style.small)
                    text: win.nowPlaying.title
                    font.weight: Font.DemiBold
                }
                Item { width: 6; height: 1 }
            }

            // A copy alone: its ring, what and where, the percentage and Cancel.
            Compact {
                id: copyFull
                active: strip.compactContent === copyFull
                opened: strip.open
                height: strip.pillHeight
                spacing: 8
                Item { width: (strip.pillHeight - strip.style.art) / 2 - 8; height: 1 }
                Ring {
                    anchors.verticalCenter: parent.verticalCenter
                    width: strip.style.art
                    height: strip.style.art
                    thickness: strip.style.art < 26 ? 2.5 : 3
                    progress: win.first("progress") || 0
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: copyModel.count > 0 ? win.first("name") + " → " + win.first("target") : ""
                        font.weight: Font.DemiBold; width: Math.min(implicitWidth, 150) }
                    Label { visible: strip.style.twoLines
                        text: copyModel.count > 0 ? Math.round(win.first("files") * win.first("progress"))
                            + " of " + win.first("files") + " files" : ""; color: win.ink2; font.pixelSize: 11 }
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: copyModel.count > 0 ? Math.round(win.first("progress") * 100) + "%" : ""
                    font.features: ({ "tnum": 1 })
                }
                GlyphButton { anchors.verticalCenter: parent.verticalCenter; width: strip.style.step; height: strip.style.reach
                    glyph: "x"; size: strip.style.glyph; onActivated: win.cancelCopy(0) }
            }

            // A copy sharing the band.
            Compact {
                id: copySmall
                active: strip.compactContent === copySmall
                opened: strip.open
                height: strip.pillHeight
                spacing: 6
                Item { width: (strip.pillHeight - strip.style.art) / 2 - 8; height: 1 }
                Ring {
                    anchors.verticalCenter: parent.verticalCenter
                    width: strip.style.art
                    height: strip.style.art
                    thickness: strip.style.art < 26 ? 2.5 : 3
                    progress: win.first("progress") || 0
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: copyModel.count > 0 ? Math.round(win.first("progress") * 100) + "%" : ""
                    font.features: ({ "tnum": 1 })
                }
                GlyphButton { anchors.verticalCenter: parent.verticalCenter; width: strip.style.step; height: strip.style.reach
                    glyph: "x"; size: strip.style.glyph; onActivated: win.cancelCopy(0) }
            }

            // A waiting dialog.
            Compact {
                id: dialogSmall
                active: strip.compactContent === dialogSmall
                opened: strip.open
                height: strip.pillHeight
                spacing: 8
                Item { width: 2; height: 1 }
                Mark { anchors.verticalCenter: parent.verticalCenter; kind: "dialog"; size: strip.style.art }
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Kate is waiting"; font.weight: Font.DemiBold }
                Item { width: 8; height: 1 }
            }

            // ---- open: one activity in full, with a row to pick among several

            Column {
                id: openContent
                x: 18
                y: 18
                width: strip.openWidth - 36
                spacing: 14
                opacity: strip.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: strip.open ? 280 : 90; easing.type: strip.open ? Easing.InQuad : Easing.Linear } }

                Row {
                    visible: win.shared
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: win.present
                        delegate: Item {
                            id: choice
                            required property string modelData
                            width: 44
                            height: 40
                            Mark {
                                anchors.centerIn: parent
                                kind: choice.modelData
                                size: 30
                                opacity: strip.openKind === choice.modelData ? 1 : 0.45
                                scale: strip.openKind === choice.modelData ? 1.12 : 1
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: strip.openKind = choice.modelData }
                        }
                    }
                }

                // Music.
                Column {
                    visible: strip.openKind === "media"
                    width: parent.width
                    spacing: 10
                    Row {
                        spacing: 14
                        Art { width: 64; height: 64; radius: 14 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: openContent.width - 78
                            spacing: 2
                            Label { width: parent.width; text: win.nowPlaying.title; font.pixelSize: 17; font.weight: Font.DemiBold }
                            Label { width: parent.width; text: win.nowPlaying.artist; font.pixelSize: 14; color: win.ink2 }
                            Row {
                                spacing: 6
                                Kirigami.Icon { width: 14; height: 14; source: win.playerNow.icon }
                                Label { text: win.playerNow.app; font.pixelSize: 12; color: win.ink2 }
                            }
                        }
                    }
                    Item {
                        id: seek
                        width: parent.width
                        height: 40
                        readonly property real fraction: win.position / win.nowPlaying.length
                        Rectangle {
                            y: 12
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.2)
                            Rectangle {
                                width: parent.width * seek.fraction
                                height: parent.height
                                radius: 2
                                color: win.ink
                            }
                            Rectangle {
                                x: parent.width * seek.fraction - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: win.ink
                                scale: seekArea.pressed ? 1.5 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }
                        }
                        Label { y: 22; text: win.clock(win.position); color: win.ink2; font.pixelSize: 11; font.features: ({ "tnum": 1 }) }
                        Label { y: 22; anchors.right: parent.right; color: win.ink2; font.pixelSize: 11; font.features: ({ "tnum": 1 })
                            text: "−" + win.clock(win.nowPlaying.length - win.position) }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            function seekTo(x) { win.position = Math.max(0, Math.min(1, x / width)) * (win.nowPlaying.length - 1); }
                            onPressed: mouse => seekTo(mouse.x)
                            onPositionChanged: mouse => seekTo(mouse.x)
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        SkipTen { forward: false; onActivated: win.position = Math.max(0, win.position - 10) }
                        GlyphButton { glyph: "skip-back"; size: 22; onActivated: win.step(-1) }
                        Rectangle {
                            width: 56
                            height: 56
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 28
                            color: Qt.rgba(1, 1, 1, 0.14)
                            scale: bigPlay.pressed ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: 90 } }
                            Glyph { anchors.centerIn: parent; name: win.playing ? "pause" : "play"; size: 26 }
                            MouseArea { id: bigPlay; anchors.fill: parent; onClicked: win.playing = !win.playing }
                        }
                        GlyphButton { glyph: "skip-forward"; size: 22; onActivated: win.step(1) }
                        SkipTen { forward: true; onActivated: win.position = Math.min(win.nowPlaying.length - 1, win.position + 10) }
                    }
                    Item {
                        width: parent.width
                        height: 40
                        Item {
                            width: otherPlayer.implicitWidth
                            height: parent.height
                            Label {
                                id: otherPlayer
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Also here: " + win.players[1 - win.player].app + ", paused"
                                color: win.ink2
                                font.pixelSize: 12
                            }
                            MouseArea { anchors.fill: parent; onClicked: { win.player = 1 - win.player; win.track = 0; win.position = 40; } }
                        }
                        PillButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Open " + win.playerNow.app
                            fontSize: 13
                            onActivated: strip.open = false
                        }
                    }
                }

                // Copies: each with its own progress, Pause and Cancel.
                Column {
                    visible: strip.openKind === "copy"
                    width: parent.width
                    spacing: 6
                    Label { text: copyModel.count > 1 ? copyModel.count + " copies" : "Copying"; color: win.ink2; font.pixelSize: 12 }
                    Repeater {
                        model: copyModel
                        delegate: Row {
                            id: copyRow
                            required property int index
                            required property string name
                            required property string target
                            required property int files
                            required property real gigabytes
                            required property real progress
                            required property bool paused
                            width: openContent.width
                            height: 56
                            spacing: 10
                            Item {
                                width: 40
                                height: 40
                                anchors.verticalCenter: parent.verticalCenter
                                Ring { anchors.fill: parent; progress: copyRow.progress; thickness: 3.5 }
                                Label { anchors.centerIn: parent; text: Math.round(copyRow.progress * 100); font.pixelSize: 11
                                    font.features: ({ "tnum": 1 }) }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: copyRow.width - 40 - 2 * 44 - 30
                                Label { width: parent.width; text: copyRow.name + " → " + copyRow.target; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Label {
                                    width: parent.width
                                    color: copyRow.paused ? win.amber : win.ink2
                                    font.pixelSize: 12
                                    text: copyRow.paused ? "Paused" : (copyRow.files > 1
                                        ? Math.round(copyRow.files * copyRow.progress) + " of " + copyRow.files + " files · "
                                        : "") + (copyRow.gigabytes * copyRow.progress).toFixed(1) + " of " + copyRow.gigabytes + " GB"
                                }
                            }
                            GlyphButton {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: copyRow.paused ? "play" : "pause"
                                onActivated: { copyModel.setProperty(copyRow.index, "paused", !copyRow.paused); win.copyTick++; }
                            }
                            GlyphButton {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "x"
                                onActivated: win.cancelCopy(copyRow.index)
                            }
                        }
                    }
                }

                // A waiting dialog.
                Column {
                    visible: strip.openKind === "dialog"
                    width: parent.width
                    spacing: 14
                    Row {
                        spacing: 14
                        Kirigami.Icon { width: 44; height: 44; source: "org.kde.kate"; fallback: "kate" }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: openContent.width - 58
                            spacing: 2
                            Label { width: parent.width; text: "Kate"; font.pixelSize: 17; font.weight: Font.DemiBold }
                            Label { width: parent.width; text: "Save changes to notes.txt?"; font.pixelSize: 14; color: win.ink2 }
                            Label { width: parent.width; text: "Waiting for you"; font.pixelSize: 12; color: win.amber }
                        }
                    }
                    PillButton {
                        objectName: "show-app-" + strip.index
                        width: parent.width
                        height: 44
                        filled: true
                        label: "Show Kate"
                        onActivated: { strip.open = false; win.leave("dialog"); }
                    }
                }
            }
        }

        // The bubble: whatever arrived after the island's own activity.
        Rectangle {
            id: bubble
            objectName: "bubble-" + strip.index
            readonly property bool shown: win.shared && !strip.open
            x: island.x + island.width + 8
            y: strip.pillY
            width: strip.pillHeight
            height: strip.pillHeight
            radius: width / 2
            color: strip.fill
            border.width: 1
            border.color: strip.edge
            opacity: shown ? 1 : 0
            scale: shown ? (bubbleArea.pressed ? 1.1 : 1) : 0.4
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
            Mark {
                anchors.centerIn: parent
                kind: win.bubbleKind
                size: strip.style.art
            }
            Rectangle {
                visible: win.bubbleCount > 1
                x: parent.width - width * 0.8
                y: -4
                width: strip.pillHeight > 40 ? 18 : 15
                height: width
                radius: width / 2
                color: win.ink
                Text {
                    anchors.centerIn: parent
                    text: win.bubbleCount
                    color: "#000000"
                    font.family: win.family
                    font.pixelSize: parent.width > 16 ? 11 : 10
                    font.weight: Font.Bold
                }
            }
            MouseArea {
                id: bubbleArea
                // A small bubble still takes a finger across the band.
                anchors.centerIn: parent
                width: Math.max(parent.width, 44)
                height: Math.max(parent.height, strip.style.reach)
                enabled: bubble.shown
                onClicked: strip.openIsland(win.bubbleKind)
            }
        }
    }

    // ---------------------------------------------------------------- layout

    Rectangle {
        width: parent.width
        height: win.barHeight
        color: "#0B0B0C"
        Flow {
            x: 12
            y: 8
            width: parent.width - 24
            spacing: 6
            Repeater {
                model: win.sceneNames
                delegate: PillButton {
                    required property string modelData
                    required property int index
                    label: modelData
                    fontSize: 13
                    filled: win.scene === index
                    onActivated: win.setScene(index)
                }
            }
            Item { width: 18; height: 40 }
            PillButton { label: win.cardUp ? "A card is up" : "No card up"; fontSize: 13; onActivated: win.cardUp = !win.cardUp }
            PillButton { label: win.backdropNames[win.backdrop]; fontSize: 13; onActivated: win.backdrop = (win.backdrop + 1) % 3 }
            PillButton { label: win.smallClear ? "B: clear" : "B: solid"; fontSize: 13; onActivated: win.smallClear = !win.smallClear }
            PillButton { label: "Close"; fontSize: 13; onActivated: Qt.quit() }
        }
    }

    Column {
        y: win.barHeight
        width: parent.width
        Repeater {
            id: strips
            model: win.styles
            delegate: Strip {
                required property var modelData
                style: modelData
                objectName: "strip-" + index
            }
        }
    }

    // ---------------------------------------------------------------- checks

    function report() {
        for (let i = 0; i < strips.count; ++i) {
            const s = strips.itemAt(i);
            const island = findIn(s, "island-" + i);
            const bubble = findIn(s, "bubble-" + i);
            console.log("GEOMETRY " + JSON.stringify({
                strip: i, scene: scene, open: s.open,
                island: [island.x, island.y - s.bandTop, island.width, island.height],
                islandCentre: island.x + island.width / 2, areaCentre: areaCentre,
                bubble: bubble.opacity > 0.5 ? [bubble.x, bubble.width] : null,
                groupCentre: bubble.opacity > 0.5 ? (island.x + bubble.x + bubble.width) / 2 : island.x + island.width / 2
            }));
        }
    }
    function findIn(item, name) {
        if (item.objectName === name) return item;
        for (let i = 0; i < item.children.length; ++i) {
            const found = findIn(item.children[i], name);
            if (found) return found;
        }
        return null;
    }
    Timer {
        running: win.grabPath.length > 0
        interval: 1500
        onTriggered: {
            win.report();
            win.contentItem.grabToImage(result => {
                result.saveToFile(win.grabPath);
                Qt.quit();
            });
        }
    }
}
