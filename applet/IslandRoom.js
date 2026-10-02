/* SPDX-License-Identifier: GPL-2.0-or-later */
.pragma library

// How neighbour islands share the band. Each kind of activity is its own
// island. The newest has the room until urgency settles it; every island keeps
// its first piece, and the islands then take turns, one piece each per step in
// each island's own order, the island with the room first. An island stops at
// its first piece that does not fit. Names wait until every island has the
// rest, so they are the first to go; a song's title and artist are not names.
// What cannot keep even its first piece folds into a counted bubble.
//
// Where a piece sits is the island's business, not its order here: what the
// island is, then its words, then its buttons last; music alone keeps its
// controls in the middle.

// Most urgent first.
var URGENCY = { waiting: 6, screen: 5, drive: 4, arrived: 3, transfer: 2, media: 1 };

// Each island's pieces in the order they drop, the last to go first. A piece
// with `needs` rides with that piece and takes no room of its own.
var PIECES = {
    media: [
        { id: "toggle" }, { id: "title" }, { id: "art" }, { id: "skip" },
        { id: "artist", needs: "title" }, { id: "time" }, { id: "duration" },
        { id: "player", name: true },
    ],
    transfer: [
        { id: "ring" }, { id: "percent", needs: "ring" }, { id: "name", name: true },
        { id: "bytes" }, { id: "source", name: true }, { id: "cancel" },
    ],
    arrived: [
        { id: "mark" }, { id: "show" }, { id: "name", name: true }, { id: "words" },
    ],
    screen: [
        { id: "stop" }, { id: "dot" }, { id: "who", name: true },
    ],
    waiting: [
        { id: "icon" }, { id: "name" }, { id: "question" },
    ],
    drive: [
        { id: "icon" }, { id: "size" }, { id: "open" }, { id: "name", name: true },
    ],
};

function turnOrder(kinds, room) {
    return kinds.slice().sort(function (a, b) {
        if (a === room) return -1;
        if (b === room) return 1;
        return (URGENCY[b] || 0) - (URGENCY[a] || 0);
    });
}

// The pieces of `kind` that stand on their own and can show now.
function own(kind, available) {
    return (PIECES[kind] || []).filter(function (p) {
        return !p.needs && available(kind, p.id);
    });
}

function withRiders(kind, items, available) {
    var all = items.slice();
    (PIECES[kind] || []).forEach(function (p) {
        if (p.needs && all.indexOf(p.needs) >= 0 && available(kind, p.id)) all.push(p.id);
    });
    return all;
}

// Lays the islands out in `width`. `measure(kind, pieces)` is an island's
// whole width showing those pieces, and `available(kind, piece)` says what
// can show; `gap` separates islands and `bubble` is the fold's size. Returns
// { shown: {kind: [piece ids]}, folded: [kinds], used }.
function layout(kinds, room, width, measure, available, gap, bubble) {
    var order = turnOrder(kinds, room);
    var shown = []; var folded = []; var used = 0; var i, s;
    for (i = 0; i < order.length; ++i) {
        var k = order[i];
        var pieces = own(k, available);
        if (!pieces.length) continue;
        var cost = measure(k, [pieces[0].id]) + (shown.length ? gap : 0);
        if (used + cost <= width) { shown.push({ kind: k, items: [pieces[0].id] }); used += cost; }
        else folded.push(k);
    }
    if (folded.length) {
        while (shown.length && used + (shown.length ? gap : 0) + bubble > width) {
            var last = shown.pop();
            used -= measure(last.kind, last.items) + (shown.length ? gap : 0);
            folded.unshift(last.kind);
        }
        used += (shown.length ? gap : 0) + bubble;
    }
    // An island that stops keeps stopping: it takes no names after a piece of
    // its own did not fit.
    for (i = 0; i < shown.length; ++i) shown[i].stopped = false;
    function turns(names) {
        for (i = 0; i < shown.length; ++i) {
            s = shown[i];
            s.queue = own(s.kind, available).slice(1).filter(function (p) { return !!p.name === names; });
        }
        for (;;) {
            var any = false;
            for (i = 0; i < shown.length; ++i) {
                s = shown[i];
                if (s.stopped || !s.queue.length) continue;
                var p = s.queue.shift();
                any = true;
                var more = measure(s.kind, s.items.concat([p.id])) - measure(s.kind, s.items);
                if (used + more <= width) { s.items.push(p.id); used += more; }
                else s.stopped = true;
            }
            if (!any) break;
        }
    }
    turns(false);
    turns(true);
    var result = { shown: {}, folded: folded, used: used };
    for (i = 0; i < shown.length; ++i)
        result.shown[shown[i].kind] = withRiders(shown[i].kind, shown[i].items, available);
    return result;
}

// Drops `kind`'s pieces, names first and then the last in its order, until
// what is left measures no more than `allowance`; its first piece always
// stays, and riders go with what they ride on.
function trim(kind, items, allowance, measure) {
    var pieces = PIECES[kind] || [];
    var find = function (id) { return pieces.filter(function (p) { return p.id === id; })[0] || { id: id }; };
    var kept = items.slice();
    var standing = function () { return kept.filter(function (id) { return !find(id).needs; }); };
    while (standing().length > 1 && measure(kind, kept) > allowance) {
        var drop = standing().slice(1).sort(function (a, b) {
            var pa = find(a), pb = find(b);
            if (!!pa.name !== !!pb.name) return pa.name ? -1 : 1;
            return pieces.indexOf(pb) - pieces.indexOf(pa);
        })[0];
        kept = kept.filter(function (id) { return id !== drop && find(id).needs !== drop; });
    }
    return kept;
}

// The least the band needs: each island's first piece and its shell.
function minimumWidth(kinds, measure, available, gap) {
    var total = 0; var count = 0;
    for (var i = 0; i < kinds.length; ++i) {
        var pieces = own(kinds[i], available);
        if (!pieces.length) continue;
        total += measure(kinds[i], [pieces[0].id]) + (count ? gap : 0);
        ++count;
    }
    return Math.ceil(total);
}
