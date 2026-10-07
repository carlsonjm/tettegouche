/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Search's quick note against the real notes application, started on this
// test's private bus in a home of its own and off screen, so nothing reaches a
// person's notes or desktop. Skipped where the application is not installed.

#include "QuickNote.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

class QuickNoteTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        const QString binary = qEnvironmentVariable("TETTEGOUCHE_TEST_NOTES",
            QStandardPaths::findExecutable(QStringLiteral("gooseberry")));
        if (binary.isEmpty()) QSKIP("The notes application is not installed.");
        QVERIFY(m_home.isValid());
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("HOME"), m_home.path());
        for (const auto &[name, folder] : {std::pair{"XDG_DATA_HOME", "share"}, {"XDG_CONFIG_HOME", "config"},
                                           {"XDG_CACHE_HOME", "cache"}, {"XDG_STATE_HOME", "state"}})
            environment.insert(QString::fromLatin1(name), m_home.filePath(QString::fromLatin1(folder)));
        environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        m_notes.setProcessEnvironment(environment);
        m_notes.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        m_notes.start(binary, {QStringLiteral("--background")});
        QVERIFY(m_notes.waitForStarted());
        QTRY_VERIFY_WITH_TIMEOUT(QDBusConnection::sessionBus().interface()->isServiceRegistered(
            QString::fromLatin1(QuickNote::Service)), 15000);
    }

    void cleanupTestCase()
    {
        if (m_notes.state() == QProcess::NotRunning) return;
        m_notes.terminate();
        if (!m_notes.waitForFinished(5000)) m_notes.kill();
    }

    // The version is asked for, and the note is started, written at a pause,
    // coloured and finished, each change kept in the folder.
    void writesThroughTheApplication()
    {
        QuickNote note;
        QTRY_VERIFY_WITH_TIMEOUT(note.available(), 10000);
        note.start();
        QTRY_VERIFY_WITH_TIMEOUT(note.isOpen(), 5000);
        QCOMPARE(note.colours().size(), 5);
        QVERIFY(!note.choices().isEmpty());
        QVERIFY(note.choices().first().toMap().contains(QStringLiteral("label")));

        note.setText(QStringLiteral("Call the framer"));
        // Written only after the pause.
        QTest::qWait(100);
        QVERIFY(note.text().isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(note.text(), QStringLiteral("Call the framer"), 3000);
        QVERIFY(note.kept());
        const QString id = note.noteId();
        QVERIFY(!id.isEmpty());
        QVERIFY(QFile::exists(m_home.filePath(QStringLiteral("Documents/Gooseberry"))));

        const QString other = note.colours().at(2);
        note.setColour(other);
        QTRY_COMPARE_WITH_TIMEOUT(note.colour(), other, 3000);
        QCOMPARE(note.colourHex(), note.colourHexes().at(2));

        // Folder and Stuck to, where the application offers them.
        if (note.offersFolders()) {
            QVERIFY(!note.folders().isEmpty());
            QVERIFY(note.folders().first().toMap().contains(QStringLiteral("chosen")));
            note.setFolder(QStringLiteral("Framing"));
            QTRY_COMPARE_WITH_TIMEOUT(note.folder(), QStringLiteral("Framing"), 3000);
            QVERIFY(!note.folderLabel().isEmpty());
            note.setFolder(QString());
            QTRY_VERIFY_WITH_TIMEOUT(note.folder().isEmpty(), 3000);
            note.setStuck(QString(), QString());
            QTRY_VERIFY_WITH_TIMEOUT(!note.stuck(), 3000);
        }

        // Typing past the longest wait is written without a pause.
        for (int i = 0; i < 40; ++i) {
            note.setText(QStringLiteral("Call the framer") + QString(i, QLatin1Char('.')));
            QTest::qWait(90);
        }
        QVERIFY(note.text().startsWith(QStringLiteral("Call the framer.")));

        note.done();
        QTRY_VERIFY_WITH_TIMEOUT(!note.isOpen(), 3000);
    }

    // All notes: the board's window draws and says so with the token.
    void opensTheBoard()
    {
        QuickNote note;
        QTRY_VERIFY_WITH_TIMEOUT(note.available(), 10000);
        note.start();
        QTRY_VERIFY_WITH_TIMEOUT(note.isOpen(), 5000);
        QSignalSpy shown(&note, &QuickNote::boardShown);
        QVERIFY(note.openBoard(QStringLiteral("token-1")));
        QTRY_COMPARE_WITH_TIMEOUT(shown.count(), 1, 10000);
        QCOMPARE(shown.first().first().toString(), QStringLiteral("token-1"));
        note.done();
    }

private:
    QTemporaryDir m_home{QDir::tempPath() + QStringLiteral("/tettegouche-notes-XXXXXX")};
    QProcess m_notes;
};

QTEST_GUILESS_MAIN(QuickNoteTest)
#include "QuickNoteTest.moc"
