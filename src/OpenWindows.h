/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

#include <functional>

class QAbstractItemModel;
class QQmlEngine;

// The windows open now, from Plasma's own window list, for Search without
// Kadunce: which applications are open, for OPEN and for Recent, and bringing
// one forward rather than starting it again.
//
// The list is Plasma's task manager list as its QML module serves it, which
// Plasma installs with itself, so Search links none of Plasma's private
// libraries for it. The list is made the first time it is asked for, and so
// is never made where Kadunce answers. Its rows are read by their role names;
// a window is brought forward with the list's own requestActivate.
class OpenWindows : public QObject
{
    Q_OBJECT
public:
    // Makes the window list, owned by the given object; none where it cannot.
    using Source = std::function<QAbstractItemModel *(QObject *owner)>;
    explicit OpenWindows(Source source, QObject *parent = nullptr);

    // Plasma's task manager list, one row a window, from every desktop,
    // activity and screen; none where the module is missing.
    static Source plasmaWindowList(QQmlEngine *engine);

    // Whether there is a list to read.
    bool available();
    // The open windows in Kadunce's workspace-context form, version 1, so one
    // reader matches results against either.
    QString context();
    // Brings forward the window context() named; false when it is gone.
    bool activate(const QString &windowId);

Q_SIGNALS:
    // A window opened, closed or changed what it is.
    void changed();

private:
    QAbstractItemModel *windows();
    int role(const char *name) const;
    QString windowId(int row) const;

    Source m_source;
    QPointer<QAbstractItemModel> m_windows;
    bool m_made = false;
};
