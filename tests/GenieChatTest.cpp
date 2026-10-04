/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Search's Genie chat against a stand-in for Split Rock's conversation
// interface, version 1, on this test's private bus: what is offered, and that
// each call and signal crosses the bus as the interface states.

#include "GenieChat.h"

#include <QDBusConnection>
#include <QDBusContext>
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
};

QTEST_GUILESS_MAIN(GenieChatTest)
#include "GenieChatTest.moc"
