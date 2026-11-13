/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <QList>
#include <QStringList>

// Which islands each Search on one panel leaves to another, so no island
// shows twice there whatever the widgets' settings say.
//
// Islands are of three sorts: "media", "note" for the quick note's, and
// "others" for the rest. Each widget names the sorts its settings show; given
// every widget on a panel in its order there, a widget leaves a sort to the
// first widget before it that shows the same.
inline QList<QStringList> islandsLeftToOthers(const QList<QStringList> &shownInOrder)
{
    QList<QStringList> left;
    QStringList taken;
    for (const QStringList &shown : shownInOrder) {
        QStringList yields;
        for (const QString &sort : shown) {
            if (taken.contains(sort)) {
                if (!yields.contains(sort)) yields.append(sort);
            } else {
                taken.append(sort);
            }
        }
        left.append(yields);
    }
    return left;
}
