/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// What Search's first screen offers as used lately, over applications and
// files of its own in a temporary home. Run plainly, a stand-in record is
// handed to the model. Run with --record, inside tests/verify-recent-use.sh,
// it reads KDE's own activity service, started there on a private bus.

#include "RecentUse.h"
#include "UseRecord.h"

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
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(text);
}

QString home(const QString &name)
{
    return QDir::homePath() + QLatin1Char('/') + name;
}

QStringList names(const RecentUse &recent)
{
    QStringList shown;
    for (int row = 0; row < recent.rowCount(); ++row) {
        shown.append(recent.data(recent.index(row), RecentUse::NameRole).toString());
    }
    return shown;
}

QString role(const RecentUse &recent, int row, RecentUse::Role which)
{
    return recent.data(recent.index(row), which).toString();
}

void writeApplications()
{
    const QString applications = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/");
    write(applications + QStringLiteral("alpha.desktop"),
          "[Desktop Entry]\nType=Application\nName=Alpha\nIcon=alpha-icon\nExec=true\n");
    write(applications + QStringLiteral("beta.desktop"),
          "[Desktop Entry]\nType=Application\nName=Beta\nExec=true\n");
    write(applications + QStringLiteral("quiet.desktop"),
          "[Desktop Entry]\nType=Application\nName=Quiet\nExec=true\nNoDisplay=true\n");
    write(applications + QStringLiteral("io.github.carlsonjm.Tettegouche.desktop"),
          "[Desktop Entry]\nType=Application\nName=Tettegouche\nExec=true\n");
    write(applications + QStringLiteral("reader.desktop"),
          "[Desktop Entry]\nType=Application\nName=Reader\nExec=true %f\nMimeType=text/plain;\n");
    KSycoca::self()->ensureCacheValid();
}
}

class RecentUseTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        writeApplications();
        write(home(QStringLiteral("Documents/notes.txt")), "notes");
        write(home(QStringLiteral("Pictures/photo.png")), QByteArray("\x89PNG\r\n\x1a\n", 8));
        write(home(QStringLiteral("Documents/.secret.txt")), "secret");
        QDir().mkpath(home(QStringLiteral("Projects")));
    }

    // Newest first, applications and files together. Left out: a folder, a
    // file that is gone or hidden, anything not on this machine, an
    // application that is hidden from menus, unknown or Tettegouche itself,
    // and a second use of the same thing.
    void offersWhatWasUsedLately()
    {
        RecentUse recent;
        recent.setReader([] {
            return QList<RecentUse::Used>{
                {QUrl::fromLocalFile(home(QStringLiteral("Documents/notes.txt"))).toString(), 100},
                {QStringLiteral("applications:alpha.desktop"), 200},
                {home(QStringLiteral("Projects")), 150},
                {home(QStringLiteral("Documents/gone.txt")), 190},
                {QStringLiteral("applications:quiet.desktop"), 180},
                {QStringLiteral("applications:missing.desktop"), 170},
                {QStringLiteral("applications:io.github.carlsonjm.Tettegouche.desktop"), 160},
                {home(QStringLiteral("Pictures/photo.png")), 140},
                {QStringLiteral("applications:beta.desktop"), 130},
                {QStringLiteral("https://example.org/page"), 120},
                {home(QStringLiteral("Documents/.secret.txt")), 110},
                {home(QStringLiteral("Documents/notes.txt")), 90},
                {QStringLiteral("applications:alpha.desktop"), 50},
            };
        });
        recent.setThumbnails([](const QString &path, const QString &mimeType, qint64) {
            return mimeType.startsWith(QStringLiteral("image/")) ? QStringLiteral("thumb:") + path : QString();
        });
        QSignalSpy counted(&recent, &RecentUse::countChanged);
        recent.refresh();
        QCOMPARE(names(recent), (QStringList{QStringLiteral("Alpha"), QStringLiteral("photo.png"),
                                             QStringLiteral("Beta"), QStringLiteral("notes.txt")}));
        QCOMPARE(counted.count(), 1);
        QCOMPARE(role(recent, 0, RecentUse::KindRole), QStringLiteral("application"));
        QCOMPARE(role(recent, 0, RecentUse::IconRole), QStringLiteral("alpha-icon"));
        QCOMPARE(role(recent, 1, RecentUse::KindRole), QStringLiteral("file"));
        QCOMPARE(role(recent, 1, RecentUse::ThumbnailRole),
                 QStringLiteral("thumb:") + home(QStringLiteral("Pictures/photo.png")));
        QCOMPARE(role(recent, 3, RecentUse::IconRole), QStringLiteral("text-plain"));
        QVERIFY(role(recent, 3, RecentUse::ThumbnailRole).isEmpty());
        // What a row opens: an application its own, a file its usual one.
        QCOMPARE(recent.applicationFor(0), QStringLiteral("alpha.desktop"));
        QCOMPARE(recent.applicationFor(3), QStringLiteral("reader.desktop"));
        QVERIFY(recent.applicationFor(9).isEmpty());
    }

    // What is pinned, open or hidden from Apps is left out once known, from
    // the record already read; while the screen is shared nothing is offered.
    void leavesOutWhatIsAtHand()
    {
        RecentUse recent;
        recent.setReader([] {
            return QList<RecentUse::Used>{
                {QStringLiteral("applications:alpha.desktop"), 30},
                {QStringLiteral("applications:beta.desktop"), 20},
                {home(QStringLiteral("Documents/notes.txt")), 10},
            };
        });
        QStringList atHand;
        recent.setExcluded([&atHand](const QString &applicationId, const QString &name) {
            return atHand.contains(applicationId) || atHand.contains(name);
        });
        recent.refresh();
        QCOMPARE(recent.count(), 3);
        atHand = {QStringLiteral("beta.desktop")};
        recent.refilter();
        QCOMPARE(names(recent), (QStringList{QStringLiteral("Alpha"), QStringLiteral("notes.txt")}));
        atHand = {QStringLiteral("Alpha")};
        recent.refilter();
        QCOMPARE(names(recent), (QStringList{QStringLiteral("Beta"), QStringLiteral("notes.txt")}));
        recent.setWithheld(true);
        QCOMPARE(recent.count(), 0);
        recent.setWithheld(false);
        QCOMPARE(recent.count(), 2);
    }

    // More than a row ever shows is never kept.
    void keepsAFew()
    {
        for (int i = 0; i < 12; ++i) {
            write(home(QStringLiteral("Documents/file-%1.txt").arg(i)), "x");
        }
        RecentUse recent;
        recent.setReader([] {
            QList<RecentUse::Used> record;
            for (int i = 0; i < 12; ++i) {
                record.append({home(QStringLiteral("Documents/file-%1.txt").arg(i)), uint(100 + i)});
            }
            return record;
        });
        recent.refresh();
        QCOMPARE(recent.count(), RecentUse::Kept);
        QCOMPARE(names(recent).first(), QStringLiteral("file-11.txt"));
    }

    // A file gone since Search opened opens nothing.
    void opensNothingGone()
    {
        const QString path = home(QStringLiteral("Documents/brief.txt"));
        write(path, "brief");
        RecentUse recent;
        recent.setReader([path] { return QList<RecentUse::Used>{{path, 10}}; });
        recent.refresh();
        QCOMPARE(recent.count(), 1);
        QVERIFY(QFile::remove(path));
        QVERIFY(!recent.open(0));
        QVERIFY(!recent.open(-1));
        QVERIFY(!recent.open(1));
    }
};

// Against KDE's own activity service: what Files and other launchers told it
// is read back newest first, applications among the files, and an
// application started from here is told to it and comes first.
int readRecord()
{
    writeApplications();
    RecentUse recent;
    recent.refresh();
    const QStringList expected{QStringLiteral("last.txt"), QStringLiteral("Alpha"), QStringLiteral("first.txt")};
    if (names(recent) != expected) {
        fprintf(stderr, "read %s, expected %s\n", qPrintable(names(recent).join(u", ")), qPrintable(expected.join(u", ")));
        return 1;
    }
    // The service stamps a use by the second.
    QTest::qWait(1100);
    noteApplicationUsed(QStringLiteral("beta.desktop"));
    // It reaches the record in the service's next batch.
    for (int i = 0; i < 75 && names(recent).value(0) != QStringLiteral("Beta"); ++i) {
        QTest::qWait(200);
        recent.refresh();
    }
    if (names(recent).value(0) != QStringLiteral("Beta")) {
        fprintf(stderr, "after starting Beta, read %s\n", qPrintable(names(recent).join(u", ")));
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1 && qstrcmp(argv[1], "--record") == 0) {
        QCoreApplication application(argc, argv);
        return readRecord();
    }
    QTemporaryDir root;
    qputenv("HOME", root.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (root.path() + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_DATA_HOME", (root.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_DATA_DIRS", (root.path() + QStringLiteral("/system")).toUtf8());
    qputenv("XDG_CACHE_HOME", (root.path() + QStringLiteral("/cache")).toUtf8());
    // The system's kinds of file, without its applications.
    QDir().mkpath(root.path() + QStringLiteral("/system"));
    QFile::link(QStringLiteral("/usr/share/mime"), root.path() + QStringLiteral("/system/mime"));
    QCoreApplication application(argc, argv);
    RecentUseTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "RecentUseTest.moc"
