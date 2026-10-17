/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The quick note's island, over a stand-in for the notes application: its
// entry written into a temporary home, and its quick-note interface on the
// test's own bus. Nothing of the person's is read, written or opened.

#include "NotesDoor.h"
#include "NotesIslandProvider.h"

#include <KService>
#include <KSycoca>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include <algorithm>

// The application's quick-note interface with a pinned note.
class FakeNotes : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Gooseberry.QuickNote")
public:
    uint version = 1;
    QVariantMap pinned;
public Q_SLOTS:
    uint ProtocolVersion() const { return version; }
    QVariantMap Pinned() const { return pinned; }
Q_SIGNALS:
    void PinnedChanged(const QVariantMap &pinned);
};

// An older application, which pins nothing.
class OlderNotes : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Gooseberry.QuickNote")
public Q_SLOTS:
    uint ProtocolVersion() const { return 1; }
};

namespace
{
void write(const QString &path, const QByteArray &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(text);
}

QString entry()
{
    return qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/")
        + QString::fromLatin1(NotesDoor::ApplicationId);
}

// What KDE's application list holds for the notes application: -1 none,
// 0 the application alone, 1 with its Capture action.
int listed()
{
    KSycoca::self()->ensureCacheValid();
    const auto notes = KService::serviceByStorageId(QString::fromLatin1(NotesDoor::ApplicationId));
    if (!notes) return -1;
    const auto actions = notes->actions();
    return std::any_of(actions.cbegin(), actions.cend(), [](const KServiceAction &action) {
        return action.name() == QLatin1String(NotesDoor::ActionName);
    }) ? 1 : 0;
}

// KDE's application list notices a change only once its folders' time has
// moved on, so each change is waited for until the list shows it: the
// entry rewritten with its action as well as the entry coming and going.
void settle(int expected)
{
    QTRY_COMPARE_WITH_TIMEOUT(listed(), expected, 5000);
}

void installNotes(bool withCapture)
{
    QByteArray text = "[Desktop Entry]\nType=Application\nName=Notes\nExec=true\n";
    if (withCapture) text += "Actions=Capture;\n\n[Desktop Action Capture]\nName=New note\nExec=true --capture\n";
    // A file rewritten in place leaves its folder's time as it was, so the
    // list would not look again: it goes, then comes back.
    QFile::remove(entry());
    write(entry(), text);
    settle(withCapture ? 1 : 0);
}

void removeNotes()
{
    QFile::remove(entry());
    settle(-1);
}

QVariantMap note(const QString &id, const QString &title, const QString &hex)
{
    return {{QStringLiteral("id"), id}, {QStringLiteral("title"), title},
            {QStringLiteral("colour"), QStringLiteral("yellow")}, {QStringLiteral("colourHex"), hex}};
}

QVariantMap row(const NotesIslandProvider &provider)
{
    const auto rows = provider.activities();
    return rows.size() == 1 ? rows.first().toMap() : QVariantMap();
}
}

class NotesIslandProviderTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // Another application, so the database is never empty.
        write(qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/alpha.desktop"),
              "[Desktop Entry]\nType=Application\nName=Alpha\nExec=true\n");
        KSycoca::self()->ensureCacheValid();
    }

    // Without the application, or without its Capture action, there is no
    // island; installed, the door is there whether or not it runs.
    void followsInstallation()
    {
        removeNotes();
        NotesIslandProvider provider(QDBusConnection::sessionBus());
        QVERIFY(provider.activities().isEmpty());
        installNotes(false);
        provider.refresh();
        QVERIFY(provider.activities().isEmpty());
        installNotes(true);
        provider.refresh();
        const auto door = row(provider);
        QCOMPARE(door.value(QStringLiteral("id")).toString(), QStringLiteral("note"));
        QCOMPARE(door.value(QStringLiteral("kind")).toString(), QStringLiteral("note"));
        QVERIFY(!door.contains(QStringLiteral("noteId")));
        removeNotes();
        provider.refresh();
        QVERIFY(provider.activities().isEmpty());
    }

    // The pinned note sits beside the door, and follows PinnedChanged until
    // the application goes.
    void pinnedNoteBesideTheDoor()
    {
        installNotes(true);
        FakeNotes notes;
        notes.pinned = note(QStringLiteral("n1"), QStringLiteral("Milk, eggs"), QStringLiteral("#F5C542"));
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-notes"));
        QVERIFY(peer.registerObject(QStringLiteral("/QuickNote"), &notes,
                                    QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.gooseberry")));

        NotesIslandProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(row(provider).value(QStringLiteral("noteId")).toString(), QStringLiteral("n1"));
        QCOMPARE(row(provider).value(QStringLiteral("title")).toString(), QStringLiteral("Milk, eggs"));
        QCOMPARE(row(provider).value(QStringLiteral("colourHex")).toString(), QStringLiteral("#F5C542"));

        Q_EMIT notes.PinnedChanged(note(QStringLiteral("n2"), QStringLiteral("Call the vet"), QStringLiteral("#7FB8F0")));
        QTRY_COMPARE(row(provider).value(QStringLiteral("noteId")).toString(), QStringLiteral("n2"));
        QCOMPARE(row(provider).value(QStringLiteral("title")).toString(), QStringLiteral("Call the vet"));

        // Unpinned, the door stays alone.
        Q_EMIT notes.PinnedChanged(QVariantMap());
        QTRY_VERIFY(!row(provider).contains(QStringLiteral("noteId")));
        QVERIFY(!row(provider).isEmpty());

        // The application leaving takes its pinned note with it.
        Q_EMIT notes.PinnedChanged(note(QStringLiteral("n3"), QStringLiteral("Soon"), QStringLiteral("#F5C542")));
        QTRY_COMPARE(row(provider).value(QStringLiteral("noteId")).toString(), QStringLiteral("n3"));
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.gooseberry"));
        QTRY_VERIFY(!row(provider).contains(QStringLiteral("noteId")));
        peer.unregisterObject(QStringLiteral("/QuickNote"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-notes"));
        removeNotes();
    }

    // An older application pins nothing, and one that speaks another
    // version is left alone.
    void olderOrOtherPinsNothing()
    {
        installNotes(true);
        {
            OlderNotes older;
            auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("older-notes"));
            QVERIFY(peer.registerObject(QStringLiteral("/QuickNote"), &older, QDBusConnection::ExportAllSlots));
            QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.gooseberry")));
            NotesIslandProvider provider(QDBusConnection::sessionBus());
            QTest::qWait(300);
            QCOMPARE(provider.activities().size(), 1);
            QVERIFY(provider.pinned().isEmpty());
            peer.unregisterService(QStringLiteral("io.github.carlsonjm.gooseberry"));
            peer.unregisterObject(QStringLiteral("/QuickNote"));
            QDBusConnection::disconnectFromBus(QStringLiteral("older-notes"));
        }
        {
            FakeNotes notes;
            notes.version = 2;
            notes.pinned = note(QStringLiteral("n1"), QStringLiteral("Milk"), QStringLiteral("#F5C542"));
            auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("other-notes"));
            QVERIFY(peer.registerObject(QStringLiteral("/QuickNote"), &notes,
                                        QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
            QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.gooseberry")));
            NotesIslandProvider provider(QDBusConnection::sessionBus());
            QTest::qWait(300);
            Q_EMIT notes.PinnedChanged(notes.pinned);
            QTest::qWait(200);
            QVERIFY(provider.pinned().isEmpty());
            peer.unregisterService(QStringLiteral("io.github.carlsonjm.gooseberry"));
            peer.unregisterObject(QStringLiteral("/QuickNote"));
            QDBusConnection::disconnectFromBus(QStringLiteral("other-notes"));
        }
        removeNotes();
    }
};

int main(int argc, char **argv)
{
    QTemporaryDir home;
    if (!home.isValid()) return 1;
    // Nothing of a running desktop reaches the test, so it counts the same
    // when run on one: its session, its menus and settings, and the switch
    // that leaves the island out for tests of the other islands.
    for (const char *name : {"DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "XAUTHORITY", "SESSION_MANAGER",
                             "XDG_SESSION_TYPE", "XDG_SESSION_ID", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
                             "XDG_MENU_PREFIX", "DESKTOP_SESSION", "KDE_FULL_SESSION", "KDE_SESSION_VERSION",
                             "KDE_SESSION_UID", "TETTE_AMBIENT_WITHOUT_NOTES"})
        qunsetenv(name);
    qputenv("XDG_CONFIG_DIRS", (home.path() + QStringLiteral("/system-config")).toUtf8());
    qputenv("XDG_STATE_HOME", (home.path() + QStringLiteral("/state")).toUtf8());
    qputenv("HOME", home.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (home.path() + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_DATA_HOME", (home.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_DATA_DIRS", (home.path() + QStringLiteral("/system")).toUtf8());
    qputenv("XDG_CACHE_HOME", (home.path() + QStringLiteral("/cache")).toUtf8());
    QCoreApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("tettegouche-test"));
    app.setApplicationName(QStringLiteral("notes-island-provider-test"));
    NotesIslandProviderTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "NotesIslandProviderTest.moc"
