/* SPDX-License-Identifier: GPL-2.0-or-later */
import QtQuick
import org.kde.kirigami as Kirigami

// Ambient's colours, read from the theme of the item they paint, which in the
// panel is the Plasma style's. On a dark ground they are the suite's fixed
// values, so a dark style looks as it always has; on a light ground the ink
// and the ground come from the theme and every wash is that ink.
QtObject {
    id: tone
    objectName: "ambientColors"

    // The Kirigami.Theme of the item being coloured: `item.Kirigami.Theme`.
    required property QtObject theme

    readonly property color ground: theme ? theme.backgroundColor : "#141414"
    readonly property color themeInk: theme ? theme.textColor : "#F8F8FF"
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(ground) === Kirigami.ColorUtils.Dark

    // Ghost White on dark, the theme's text colour on light.
    readonly property color text: dark ? "#F8F8FF" : themeInk
    // An island on an opaque band, and the open island's card.
    readonly property color surface: dark ? "#141414" : ground
    readonly property color card: dark ? "#000000" : ground
    // Words on a fill of the text colour.
    readonly property color textOnInk: dark ? "#000000" : ground
    // The square behind album art, or behind the player's icon without it.
    readonly property color art: dark ? "#2A2A2F" : over(0.12)
    // A paused transfer.
    readonly property color waitingText: dark ? "#E3B866" : themeColor("neutralTextColor", "#F67400")

    // The text colour at a given strength, for see-through washes and fills.
    function wash(alpha) {
        return Qt.rgba(text.r, text.g, text.b, alpha);
    }

    // The text colour at a given strength laid solid over the ground.
    function over(alpha) {
        return Qt.tint(ground, wash(alpha));
    }

    // One of the theme's own colours, when the theme names it.
    function themeColor(name, fallback) {
        return theme && theme[name] !== undefined ? theme[name] : fallback;
    }
}
