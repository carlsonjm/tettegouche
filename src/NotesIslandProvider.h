/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QDBusMessage;

// The quick note's island: a door to a quick note, there while the notes
// application is installed with its Capture action, and the note pinned in
// the application beside it when there is one. The pinned note is read from
// the application's quick-note interface, version 1, while the application
// runs: asked when it appears, never started for it, and followed through
// PinnedChanged after that. An application without Pinned has no pinned note.
// The notes stuck to the window in use join it, as the application tells
// them over its stuck-notes interface, version 1: while a panel shows the
// island, the application is told to leave no dot over a window whose notes
// are folded, since the island brings them back. The row is the one Ambient
// keeps without activity, and it is never set aside.
class NotesIslandProvider : public QObject
{
    Q_OBJECT

public:
    static constexpr char Service[] = "io.github.carlsonjm.gooseberry";
    static constexpr char Path[] = "/QuickNote";
    static constexpr char Interface[] = "io.github.carlsonjm.Gooseberry.QuickNote";
    static constexpr uint Version = 1;
    static constexpr char Id[] = "note";
    static constexpr char StuckPath[] = "/StuckNotes";
    static constexpr char StuckInterface[] = "io.github.carlsonjm.Gooseberry.StuckNotes";

    explicit NotesIslandProvider(const QDBusConnection &bus, QObject *parent = nullptr);

    // Whether the notes application is installed with its Capture action.
    bool installed() const { return m_installed; }
    // The pinned note: id, title, colour and colourHex; empty when none.
    QVariantMap pinned() const { return m_pinned; }
    // The island's one row while the application is installed.
    QVariantList activities() const;
    // Looks again for the application, as when KDE's application list changes.
    void refresh();
    // The ids Plasma's window list gives the window in use.
    void setActiveWindowIds(const QStringList &ids);
    // Whether this panel shows the island; while any does, folded notes are
    // left to it.
    void setShownBy(const void *panel, bool shown);
    // The island's tap on the window's notes: they come up over it, open,
    // when they are away or folded, and go away when they are up.
    void toggleWindowNotes();

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
    void stuckChanged(const QDBusMessage &message);

private:
    void ask();
    void setPinned(const QVariantMap &pinned);
    void askStuck();
    void setStuck(const QVariantList &windows);
    void tellShown(bool always);
    // The stuck-notes entry of the window in use, empty when it has none.
    QVariantMap activeEntry() const;

    QDBusConnection m_bus;
    QString m_owner;
    // The application answered with this interface's version.
    bool m_speaks = false;
    bool m_installed = false;
    QVariantMap m_pinned;
    int m_generation = 0;
    QStringList m_activeIds;
    QVariantList m_stuck;
    bool m_stuckSpeaks = false;
    QSet<const void *> m_shownBy;
    // What the application was last told, or -1 for nothing yet.
    int m_toldShown = -1;
};
