/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The Notes door, over a stand-in for the notes application written into a
// temporary home: absent, present without its Capture action, and present
// with it. The stand-in only records how it was started, so nothing of the
// person's is read, written or opened.

#include "NotesDoor.h"

#include <KService>
#include <KSycoca>

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

namespace
{
void write(const QString &path, const QByteArray &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(text);
}

QString applications()
{
    return qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/");
}

QString record()
{
    return QDir::homePath() + QStringLiteral("/started");
}

// How the stand-in was last started, as it wrote it.
QByteArray started()
{
    QFile file(record());
    return file.open(QIODevice::ReadOnly) ? file.readAll().trimmed() : QByteArray();
}

// KDE's application list notices a change to its folders only once their time
// has moved on, so each change is waited for until the list shows it.
void settle(bool present)
{
    const QString id = QString::fromLatin1(NotesDoor::ApplicationId);
    QTRY_VERIFY_WITH_TIMEOUT((KSycoca::self()->ensureCacheValid(), bool(KService::serviceByStorageId(id)) == present), 5000);
}

// The stand-in: its entry and its Capture action each leave their arguments
// in the record.
void installNotes(bool withCapture)
{
    const QString program = QDir::homePath() + QStringLiteral("/bin/notes");
    write(program, "#!/bin/sh\necho \"$@\" > \"" + record().toUtf8() + "\"\n");
    QFile::setPermissions(program, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    QByteArray entry = "[Desktop Entry]\nType=Application\nName=Notes\nExec=" + program.toUtf8() + " --board\n";
    if (withCapture) {
        entry += "Actions=Capture;\n\n[Desktop Action Capture]\nName=New note\nExec=" + program.toUtf8() + " --capture\n";
    }
    write(applications() + QString::fromLatin1(NotesDoor::ApplicationId), entry);
    settle(true);
}

void removeNotes()
{
    QFile::remove(applications() + QString::fromLatin1(NotesDoor::ApplicationId));
    settle(false);
}
}

class NotesDoorTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // Another application, so the database is never empty.
        write(applications() + QStringLiteral("alpha.desktop"),
              "[Desktop Entry]\nType=Application\nName=Alpha\nExec=true\n");
        KSycoca::self()->ensureCacheValid();
    }

    // Without the notes application there is no door, and nothing opens.
    void absentOffersNothing()
    {
        removeNotes();
        NotesDoor door;
        QVERIFY(!door.available());
        QVERIFY(!door.open());
        QVERIFY(!QFile::exists(record()));
    }

    // An application by that name without its Capture action has no door
    // either: its entry opens a window, which is not what Notes promises.
    void withoutCaptureOffersNothing()
    {
        installNotes(false);
        NotesDoor door;
        QVERIFY(!door.available());
        QVERIFY(!door.open());
        removeNotes();
    }

    // Installed while Search is open, the door appears when Search looks again.
    void followsInstallation()
    {
        removeNotes();
        NotesDoor door;
        QVERIFY(!door.available());
        QSignalSpy changed(&door, &NotesDoor::availableChanged);
        installNotes(true);
        door.refresh();
        QVERIFY(door.available());
        QCOMPARE(changed.count(), 1);
        removeNotes();
        door.refresh();
        QVERIFY(!door.available());
        QCOMPARE(changed.count(), 2);
    }

    // Opening runs the Capture action, not the application's own entry.
    void opensCapture()
    {
        QFile::remove(record());
        installNotes(true);
        NotesDoor door;
        QVERIFY(door.available());
        QVERIFY(door.open());
        QTRY_COMPARE_WITH_TIMEOUT(started(), QByteArray("--capture"), 10000);
        removeNotes();
    }
};

int main(int argc, char **argv)
{
    QTemporaryDir home;
    if (!home.isValid()) return 1;
    qputenv("HOME", home.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (home.path() + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_DATA_HOME", (home.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_DATA_DIRS", (home.path() + QStringLiteral("/system")).toUtf8());
    qputenv("XDG_CACHE_HOME", (home.path() + QStringLiteral("/cache")).toUtf8());
    QCoreApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("tettegouche-test"));
    app.setApplicationName(QStringLiteral("notes-door-test"));
    NotesDoorTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "NotesDoorTest.moc"
