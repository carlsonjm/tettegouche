/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Search's colours, read from the theme of the item they paint. On a dark
// ground they are the suite's fixed values, so a dark colour scheme looks as
// it always has; on a light ground the ink and the ground come from the theme
// and every wash, control and line is that ink laid over the ground.
QtObject {
    id: tone
    objectName: "searchColors"

    // The Kirigami.Theme of the item being coloured: `item.Kirigami.Theme`.
    required property QtObject theme

    readonly property color ground: theme ? theme.backgroundColor : "#141414"
    readonly property color themeInk: theme ? theme.textColor : "#F8F8FF"
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(ground) === Kirigami.ColorUtils.Dark

    // White on dark, the theme's text colour on light: the base of every wash.
    readonly property color ink: dark ? "#FFFFFF" : themeInk

    // Words, from the strongest to the faintest.
    readonly property color text: dark ? "#F8F8FF" : themeInk
    readonly property color primaryText: dark ? "#f2ffffff" : themeInk
    readonly property color secondaryText: dark ? "#A8FFFFFF" : wash(0.66)
    readonly property color bodyText: dark ? "#A8F8F8FF" : wash(0.66)
    readonly property color edgeText: dark ? "#88ffffff" : wash(0.53)
    readonly property color placeholderText: dark ? "#86ffffff" : wash(0.53)
    readonly property color disabledText: dark ? "#6BF8F8FF" : wash(0.42)
    // The light that sweeps across the field's first words.
    readonly property color shine: dark ? "#ffffff" : themeInk
    // Words on a pill filled with the text colour.
    readonly property color textOnInk: dark ? "#141414" : ground

    // Genie's answer, a panel of its own inside the sheet.
    readonly property color answerSurface: dark ? "#1C1C1C" : over(0.04)
    readonly property color answerText: dark ? "#E4E4EA" : wash(0.88)
    readonly property color answerNote: dark ? "#A8A8B0" : wash(0.62)
    readonly property color answerPlaceholder: dark ? "#8E929A" : wash(0.5)
    // Small capitals and hints over the note's own controls.
    readonly property color hintText: dark ? "#8A8A90" : wash(0.55)

    // Report colours: something went wrong, went well, or waits.
    readonly property color errorText: dark ? "#ffb5a8" : themeColor("negativeTextColor", "#DA4453")
    readonly property color troubleText: dark ? "#E08A80" : themeColor("negativeTextColor", "#DA4453")
    readonly property color goodText: dark ? "#7FD1BE" : themeColor("positiveTextColor", "#27AE60")
    readonly property color openTag: dark ? "#ff71e6be" : themeColor("positiveTextColor", "#27AE60")
    readonly property color waitingText: dark ? "#E3B866" : themeColor("neutralTextColor", "#F67400")

    // The sheet, the boxes laid on it and the lines between them.
    readonly property color surface: dark ? "#141414" : ground
    readonly property color sheet: dark ? "#1B1B1B" : over(0.03)
    readonly property color outline: dark ? "#5a5a5a" : over(0.32)
    readonly property color line: dark ? "#333333" : over(0.16)
    readonly property color mark: dark ? "#888888" : over(0.5)
    readonly property color crumb: dark ? "#777777" : over(0.45)

    // The suite's grey pill, under the pointer and pressed.
    readonly property color control: dark ? "#242424" : over(0.07)
    readonly property color controlHover: dark ? "#333333" : over(0.12)
    readonly property color controlPressed: dark ? "#4A4A4A" : over(0.22)
    readonly property color lightPressed: dark ? "#d8d8de" : wash(0.8)
    readonly property color doorHover: dark ? "#2a2a2a" : over(0.09)
    readonly property color doorPressed: dark ? "#303030" : over(0.11)
    readonly property color tilePressed: dark ? "#262626" : over(0.08)
    readonly property color chosen: dark ? "#333333" : over(0.12)
    readonly property color placeChosen: dark ? "#2C2C2C" : over(0.10)

    // See-through washes for rows and tiles.
    readonly property color hover: dark ? "#22ffffff" : wash(0.08)
    readonly property color tileHover: dark ? "#20ffffff" : wash(0.08)
    readonly property color current: dark ? "#3dffffff" : wash(0.16)
    readonly property color focusRing: dark ? "#b0ffffff" : wash(0.69)
    readonly property color track: dark ? "#24ffffff" : wash(0.14)
    readonly property color progress: dark ? "#d9ffffff" : wash(0.85)

    // The scroll handle at rest, under the pointer and held.
    readonly property color handle: dark ? "#4A4A4A" : over(0.28)
    readonly property color handleHover: dark ? "#6A6A6A" : over(0.38)
    readonly property color handlePressed: dark ? "#8A8A8A" : over(0.5)

    // Selected words in the search field.
    readonly property color selection: dark ? "#6da9ddff" : themeColor("highlightColor", "#3DAEE9")
    readonly property color selectedText: dark ? "#ffffffff" : themeColor("highlightedTextColor", "#FFFFFF")

    // The ink at a given strength, for see-through washes and fills.
    function wash(alpha) {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    // Ghost White at a given strength on dark; the ink's wash on light.
    function ghost(alpha) {
        return dark ? Qt.rgba(248 / 255, 248 / 255, 1, alpha) : wash(alpha);
    }

    // The ink at a given strength laid solid over the ground.
    function over(alpha) {
        return Qt.tint(ground, wash(alpha));
    }

    // One of the theme's own colours, when the theme names it.
    function themeColor(name, fallback) {
        return theme && theme[name] !== undefined ? theme[name] : fallback;
    }
}
