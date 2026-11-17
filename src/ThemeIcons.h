/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSet>

namespace tettegouche
{
// Kirigami's Icon looks its icon up when its name, its size or its colours
// change, and keeps that picture after. Another icon theme chosen, or an icon
// file a package replaces, changes none of the three, so the item goes on
// drawing the picture it has. Polishing the item is what makes it look the
// icon up again; this asks that of every Icon under an item, and says how
// many were asked. An Icon made later looks its icon up as it is made.
inline int lookUpIconsAgain(QObject *object, QSet<QObject *> &seen)
{
    if (!object || seen.contains(object)) return 0;
    seen.insert(object);
    int asked = 0;
    auto *item = qobject_cast<QQuickItem *>(object);
    if (item) {
        if (item->inherits("Icon") && item->property("source").isValid()) {
            item->polish();
            ++asked;
        }
        // What an item draws inside it, such as a list's rows, is its child
        // on screen without being its child as an object.
        const QList<QQuickItem *> drawn = item->childItems();
        for (QQuickItem *child : drawn) asked += lookUpIconsAgain(child, seen);
    }
    const QObjectList owned = object->children();
    for (QObject *child : owned) asked += lookUpIconsAgain(child, seen);
    return asked;
}

// The same for every window this program has, shown or not: a hidden
// window's icons are looked up as it next shows.
inline int lookUpIconsAgain()
{
    QSet<QObject *> seen;
    int asked = 0;
    const QWindowList windows = QGuiApplication::allWindows();
    for (QWindow *window : windows) {
        if (auto *quick = qobject_cast<QQuickWindow *>(window)) {
            asked += lookUpIconsAgain(quick->contentItem(), seen);
            asked += lookUpIconsAgain(quick, seen);
        }
    }
    return asked;
}
}
