/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QDBusMessage;

// The quick note's island: a door to a quick note, there while the notes
// application is installed with its Capture action, and the note pinned in
// the application beside it when there is one. The pinned note is read from
// the application's quick-note interface, version 1, while the application
// runs: asked when it appears, never started for it, and followed through
// PinnedChanged after that. An application without Pinned has no pinned note.
// The row is the one Ambient keeps without activity, and it is never set
// aside.
class NotesIslandProvider : public QObject
{
    Q_OBJECT

public:
    static constexpr char Service[] = "io.github.carlsonjm.gooseberry";
    static constexpr char Path[] = "/QuickNote";
    static constexpr char Interface[] = "io.github.carlsonjm.Gooseberry.QuickNote";
    static constexpr uint Version = 1;
    static constexpr char Id[] = "note";

    explicit NotesIslandProvider(const QDBusConnection &bus, QObject *parent = nullptr);

    // Whether the notes application is installed with its Capture action.
    bool installed() const { return m_installed; }
    // The pinned note: id, title, colour and colourHex; empty when none.
    QVariantMap pinned() const { return m_pinned; }
    // The island's one row while the application is installed.
    QVariantList activities() const;
    // Looks again for the application, as when KDE's application list changes.
    void refresh();

    // The island's taps, on the application's own card: an empty id is a new
    // quick note, through its Capture action, and an id that note, asked of
    // the application, or a new one where it is not there. False, doing
    // nothing, where the application is not installed with its Capture action.
    static bool openOnCard(const QString &noteId, QObject *parent);

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void pinnedChanged(const QVariantMap &pinned, const QDBusMessage &message);

private:
    void ask();
    void setPinned(const QVariantMap &pinned);

    QDBusConnection m_bus;
    QString m_owner;
    // The application answered with this interface's version.
    bool m_speaks = false;
    bool m_installed = false;
    QVariantMap m_pinned;
    int m_generation = 0;
};
