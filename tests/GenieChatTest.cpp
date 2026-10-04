/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Search's Genie chat against a stand-in for Split Rock's conversation
// interface, version 1, on this test's private bus: what is offered, and that
// each call and signal crosses the bus as the interface states.

#include "GenieChat.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDir>
#include <QProcess>
#include <QTemporaryDir>
#include <QSignalSpy>
#include <QtTest>

class Conversation : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.SplitRock.Conversation")

public:
    QStringList calls;
    QVariantMap state{
        {QStringLiteral("phase"), QStringLiteral("ready")},
        {QStringLiteral("assistant"), QStringLiteral("Codex")},
        {QStringLiteral("question"), QString()},
        {QStringLiteral("answer"), QString()},
        {QStringLiteral("steps"), QStringList()},
        {QStringLiteral("suggestions"), QStringList{QStringLiteral("Make the writing bigger")}},
        {QStringLiteral("canDoIt"), false},
        {QStringLiteral("doItReason"), QStringLiteral("Not yet")},
        {QStringLiteral("kept"), false},
        {QStringLiteral("problem"), QString()},
    };

public Q_SLOTS:
    uint ProtocolVersion() { return 1; }
    QVariantMap Start() { calls << QStringLiteral("Start"); return state; }
    QVariantMap Ask(const QString &text)
    {
        calls << QStringLiteral("Ask:") + text;
        state[QStringLiteral("question")] = text;
        state[QStringLiteral("phase")] = QStringLiteral("answering");
        return state;
    }
    QVariantMap Cancel() { calls << QStringLiteral("Cancel"); return state; }
    QVariantMap Act(const QString &action) { calls << QStringLiteral("Act:") + action; return state; }
    bool OpenWindow(const QString &token) { calls << QStringLiteral("OpenWindow:") + token; return true; }

Q_SIGNALS:
    void Changed(const QVariantMap &state);
    void WindowShown(const QString &requestToken);
};

class GenieChatTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // Without the assistant on the bus, Genie is not offered, and nothing is
    // started for it.
    void absentIsNotOffered()
    {
        GenieChat genie;
        QTest::qWait(200);
        QVERIFY(!genie.available());
    }

    void speaksTheInterface()
    {
        auto bus = QDBusConnection::sessionBus();
        Conversation conversation;
        QVERIFY(bus.registerObject(QString::fromLatin1(GenieChat::Path), &conversation,
                                   QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(bus.registerService(QString::fromLatin1(GenieChat::Service)));

        GenieChat genie;
        QTRY_VERIFY_WITH_TIMEOUT(genie.available(), 5000);
        genie.start();
        QTRY_COMPARE(genie.assistant(), QStringLiteral("Codex"));
        QCOMPARE(genie.phase(), QStringLiteral("ready"));
        QCOMPARE(genie.suggestions(), QStringList{QStringLiteral("Make the writing bigger")});

        genie.ask(QStringLiteral("Why is my screen dim?"));
        QTRY_COMPARE(genie.phase(), QStringLiteral("answering"));
        QCOMPARE(genie.question(), QStringLiteral("Why is my screen dim?"));

        // The answer streams in through Changed.
        conversation.state[QStringLiteral("phase")] = QStringLiteral("ready");
        conversation.state[QStringLiteral("answer")] = QStringLiteral("It dims after two minutes.");
        conversation.state[QStringLiteral("steps")] = QStringList{QStringLiteral("Open Power Management.")};
        Q_EMIT conversation.Changed(conversation.state);
        QTRY_COMPARE(genie.answer(), QStringLiteral("It dims after two minutes."));
        QCOMPARE(genie.steps(), QStringList{QStringLiteral("Open Power Management.")});
        QVERIFY(!genie.canDoIt());
        QCOMPARE(genie.doItReason(), QStringLiteral("Not yet"));

        genie.act(QStringLiteral("keep"));
        genie.cancel();
        QSignalSpy shown(&genie, &GenieChat::windowShown);
        QVERIFY(genie.openWindow(QStringLiteral("token-1")));
        QTRY_VERIFY(conversation.calls.contains(QStringLiteral("OpenWindow:token-1")));
        Q_EMIT conversation.WindowShown(QStringLiteral("token-1"));
        QTRY_COMPARE(shown.count(), 1);
        QCOMPARE(shown.first().first().toString(), QStringLiteral("token-1"));
        QVERIFY(conversation.calls.contains(QStringLiteral("Act:keep")));
        QVERIFY(conversation.calls.contains(QStringLiteral("Cancel")));

        bus.unregisterService(QString::fromLatin1(GenieChat::Service));
        bus.unregisterObject(QString::fromLatin1(GenieChat::Path));
    }

    // Against Split Rock itself, with its pretend assistant, in a home of its
    // own and off screen. TETTEGOUCHE_TEST_GENIE names its program and
    // TETTEGOUCHE_TEST_GENIE_SCRIPT the pretend assistant's script; without
    // them this is skipped.
    void againstSplitRock()
    {
        const QString program = qEnvironmentVariable("TETTEGOUCHE_TEST_GENIE");
        const QString script = qEnvironmentVariable("TETTEGOUCHE_TEST_GENIE_SCRIPT");
        if (program.isEmpty() || script.isEmpty()) QSKIP("Split Rock is not named for this run.");
        QTemporaryDir home(QDir::tempPath() + QStringLiteral("/tettegouche-genie-XXXXXX"));
        QVERIFY(home.isValid());
        QDir().mkpath(home.filePath(QStringLiteral("config")));
        QFile rc(home.filePath(QStringLiteral("config/split-rockrc")));
        QVERIFY(rc.open(QIODevice::WriteOnly));
        rc.write("[Assistant]\nchosen=pretend\n");
        rc.close();
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("HOME"), home.path());
        for (const auto &[name, folder] : {std::pair{"XDG_DATA_HOME", "share"}, {"XDG_CONFIG_HOME", "config"},
                                           {"XDG_CACHE_HOME", "cache"}, {"XDG_STATE_HOME", "state-home"}})
            environment.insert(QString::fromLatin1(name), home.filePath(QString::fromLatin1(folder)));
        environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        environment.remove(QStringLiteral("WAYLAND_DISPLAY"));
        environment.remove(QStringLiteral("DISPLAY"));
        QProcess splitRock;
        splitRock.setProcessEnvironment(environment);
        splitRock.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        splitRock.start(program, {QStringLiteral("--background"), QStringLiteral("--assistants"),
            home.filePath(QStringLiteral("no-adapters")), QStringLiteral("--state"), home.filePath(QStringLiteral("state")),
            QStringLiteral("--pretend"), script});
        QVERIFY(splitRock.waitForStarted());
        auto cleanup = qScopeGuard([&splitRock] {
            splitRock.terminate();
            if (!splitRock.waitForFinished(5000)) splitRock.kill();
        });
        QTRY_VERIFY_WITH_TIMEOUT(QDBusConnection::sessionBus().interface()->isServiceRegistered(
            QString::fromLatin1(GenieChat::Service)).value(), 15000);

        GenieChat genie;
        QTRY_VERIFY_WITH_TIMEOUT(genie.available(), 10000);
        genie.start();
        QTRY_COMPARE_WITH_TIMEOUT(genie.phase(), QStringLiteral("ready"), 15000);
        QVERIFY(!genie.assistant().isEmpty());
        QVERIFY(!genie.suggestions().isEmpty());
        genie.ask(genie.suggestions().first());
        QTRY_VERIFY_WITH_TIMEOUT(genie.phase() == QLatin1String("answering") || !genie.answer().isEmpty(), 5000);
        QTRY_COMPARE_WITH_TIMEOUT(genie.phase(), QStringLiteral("ready"), 15000);
        QVERIFY(!genie.answer().isEmpty());
        // Keep this arrives with the notebook: refused, and said why.
        genie.act(QStringLiteral("keep"));
        QTRY_VERIFY_WITH_TIMEOUT(!genie.problem().isEmpty(), 5000);
        QSignalSpy shown(&genie, &GenieChat::windowShown);
        QVERIFY(genie.openWindow(QStringLiteral("token-real")));
        QTRY_COMPARE_WITH_TIMEOUT(shown.count(), 1, 10000);
        QCOMPARE(shown.first().first().toString(), QStringLiteral("token-real"));
    }
};

QTEST_GUILESS_MAIN(GenieChatTest)
#include "GenieChatTest.moc"
