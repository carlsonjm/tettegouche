/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// An application's name under its icon: two lines at most, broken only
// between words. A word too long for the tile makes the whole name a little
// smaller until it fits, rather than splitting it.
Text {
    id: name
    // The size a name has when every word fits.
    property real naturalSize: 12
    // The smallest it may become; below that the word is cut short.
    property real smallestSize: 9
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    lineHeight: 0.95
    elide: Text.ElideRight
    font.pixelSize: {
        const words = (text || "").split(/\s+/)
        let widest = 0
        for (const word of words) widest = Math.max(widest, measure.advanceWidth(word))
        if (widest <= width || widest <= 0 || width <= 0) return naturalSize
        return Math.max(smallestSize, Math.floor(naturalSize * width / widest * 4) / 4)
    }
    FontMetrics {
        id: measure
        font.family: name.font.family
        font.weight: name.font.weight
        font.pixelSize: name.naturalSize
    }
}
