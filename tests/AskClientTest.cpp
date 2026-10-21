/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "AskClient.h"
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QSignalSpy>
#include <QTest>
#include <QTimer>

// A stand-in for Split Rock's Ask on the test's own bus: it answers each
// question with set words, the Helpers named for it, or says what it needs.
class FakeAsk : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.SplitRock.Ask")
public:
    QStringList asked;
    QStringList cancelled;
    bool needsModel = false;
    bool codexSignedIn = false;
    bool handsToCodex = false;
    // Questions are left unanswered, as while the model thinks.
    bool slow = false;
    uint pending = 0;
    QStringList toCodex;
    int downloads = 0;
    uint next = 0;
public Q_SLOTS:
    uint ProtocolVersion() const { return 1; }
    uint Ask(const QString &question)
    {
        asked.append(question);
        const uint id = ++next;
        // As Ask does: a new question stops the one before it.
        if (pending != 0)
            Q_EMIT Answered(std::exchange(pending, 0), { { QStringLiteral("cancelled"), true } });
        if (slow) {
            pending = id;
            return id;
        }
        QTimer::singleShot(10, this, [this, id, question] {
            if (needsModel) {
                Q_EMIT Answered(id,
                    { { QStringLiteral("needsModel"), true },
                        { QStringLiteral("text"), QStringLiteral("Ask needs a one-time download.") } });
                return;
            }
            if (handsToCodex) {
                Q_EMIT Answered(id,
                    { { QStringLiteral("who"), QStringLiteral("computer") }, { QStringLiteral("handOff"), true },
                        { QStringLiteral("handedToCodex"), true },
                        { QStringLiteral("text"), QStringLiteral("Codex is taking it.") } });
                return;
            }
            Q_EMIT Said(id, QStringLiteral("Wi-Fi that drops "));
            Q_EMIT Said(id, QStringLiteral("often comes from power saving."));
            Q_EMIT Answered(id,
                { { QStringLiteral("who"), QStringLiteral("computer") },
                    { QStringLiteral("text"), QStringLiteral("Wi-Fi that drops often comes from power saving.") },
                    { QStringLiteral("helpers"),
                        QStringList { QStringLiteral("health"), QStringLiteral("changes") } },
                    { QStringLiteral("query"), QStringLiteral("wifi") } });
        });
        return id;
    }
    void Cancel(uint id) { cancelled.append(QString::number(id)); }
    // Another surface's question stops this one.
    void stopElsewhere()
    {
        if (pending != 0)
            Q_EMIT Answered(std::exchange(pending, 0), { { QStringLiteral("cancelled"), true } });
    }
    QVariantMap Codex() const
    {
        return { { QStringLiteral("installed"), true }, { QStringLiteral("signedIn"), codexSignedIn } };
    }
    bool OpenCodex(const QString &question)
    {
        toCodex.append(question);
        return true;
    }
    void signIn(bool in)
    {
        codexSignedIn = in;
        Q_EMIT CodexChanged(Codex());
    }
    void DownloadModel()
    {
        ++downloads;
        Q_EMIT ModelChanged({ { QStringLiteral("state"), QStringLiteral("downloading") },
            { QStringLiteral("progress"), 0.4 }, { QStringLiteral("size"), QStringLiteral("about 2.5 GB") } });
    }
Q_SIGNALS:
    void Said(uint id, const QString &text);
    void Answered(uint id, const QVariantMap &result);
    void ModelChanged(const QVariantMap &model);
    void CodexChanged(const QVariantMap &codex);
};

class AskClientTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    // Without Ask the chip stays Helpers, and nothing is asked.
    void noAskNoQuestions()
    {
        AskClient client(QDBusConnection::sessionBus());
        QTest::qWait(300);
        QVERIFY(!client.available());
        client.type(QStringLiteral("my wifi keeps dropping"));
        QTest::qWait(100);
        QCOMPARE(client.state(), QStringLiteral("idle"));
    }

    void whatReadsAsAQuestion()
    {
        QVERIFY(AskClient::readsAsQuestion(QStringLiteral("my wifi keeps dropping")));
        QVERIFY(AskClient::readsAsQuestion(QStringLiteral("wifi?")));
        QVERIFY(!AskClient::readsAsQuestion(QStringLiteral("update")));
        QVERIFY(!AskClient::readsAsQuestion(QStringLiteral("free up")));
    }

    // A question is sent once the typing pauses; its words come as written,
    // and the Helpers it names are listed.
    void aQuestionOnceTheTypingPauses()
    {
        FakeAsk ask;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));

        AskClient client(QDBusConnection::sessionBus());
        client.setPause(100);
        QTRY_VERIFY(client.available());
        client.type(QStringLiteral("my wifi"));
        client.type(QStringLiteral("my wifi keeps"));
        client.type(QStringLiteral("my wifi keeps dropping"));
        // A Helper's name alone is never sent.
        QTRY_COMPARE(client.state(), QStringLiteral("answered"));
        QCOMPARE(ask.asked, QStringList { QStringLiteral("my wifi keeps dropping") });
        QCOMPARE(client.text(), QStringLiteral("Wi-Fi that drops often comes from power saving."));
        QCOMPARE(client.who(), QStringLiteral("computer"));
        QCOMPARE(client.helpers(), (QStringList { QStringLiteral("health"), QStringLiteral("changes") }));
        QCOMPARE(client.query(), QStringLiteral("wifi"));

        // The same words again ask nothing; clearing the field clears it.
        client.type(QStringLiteral("my wifi keeps dropping"));
        QTest::qWait(250);
        QCOMPARE(ask.asked.size(), 1);
        client.type(QString());
        QCOMPARE(client.state(), QStringLiteral("idle"));
        QVERIFY(client.text().isEmpty());
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask"));
    }

    // A question stopped by another one to Ask, not by this Search, says
    // Ask couldn't answer rather than leaving the box empty; the one this
    // Search typed over is not mistaken for it.
    void stoppedElsewhereSaysSo()
    {
        FakeAsk ask;
        ask.slow = true;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));
        AskClient client(QDBusConnection::sessionBus());
        client.setPause(50);
        QTRY_VERIFY(client.available());
        client.type(QStringLiteral("my wifi keeps dropping"));
        client.askNow();
        QTRY_COMPARE(ask.asked.size(), 1);
        client.type(QStringLiteral("my sound keeps dropping"));
        client.askNow();
        QTRY_COMPARE(ask.asked.size(), 2);
        QTest::qWait(100);
        QCOMPARE(client.state(), QStringLiteral("asking"));
        ask.stopElsewhere();
        QTRY_COMPARE(client.state(), QStringLiteral("problem"));
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask"));
    }

    // Without the model Ask says once what it needs; Download asks for it,
    // and Not now leaves the Helpers to answer.
    void theModelFirst()
    {
        FakeAsk ask;
        ask.needsModel = true;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask-2"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));

        AskClient client(QDBusConnection::sessionBus());
        client.setPause(50);
        QTRY_VERIFY(client.available());
        client.type(QStringLiteral("how do I print"));
        client.askNow();
        QTRY_COMPARE(client.state(), QStringLiteral("needsModel"));
        client.notNow();
        QCOMPARE(client.state(), QStringLiteral("idle"));
        client.type(QStringLiteral("how do I print a letter"));
        QTRY_COMPARE(ask.asked.size(), 2);
        QTest::qWait(100);
        // Not now holds until the field is cleared.
        QCOMPARE(client.state(), QStringLiteral("idle"));

        client.type(QString());
        client.type(QStringLiteral("how do I print"));
        QTRY_COMPARE(client.state(), QStringLiteral("needsModel"));
        client.download();
        QTRY_COMPARE(ask.downloads, 1);
        QTRY_COMPARE(client.state(), QStringLiteral("downloading"));
        QTRY_COMPARE(client.progress(), 0.4);
        QCOMPARE(client.size(), QStringLiteral("about 2.5 GB"));
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask-2"));
    }

    // Codex is offered once it is signed in, and takes the question only on
    // the person's tap; handed on by the switch, the answer says so.
    void codexOnATap()
    {
        FakeAsk ask;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask-3"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));

        AskClient client(QDBusConnection::sessionBus());
        client.setPause(50);
        QTRY_VERIFY(client.available());
        QVERIFY(!client.askCodex());
        client.type(QStringLiteral("my wifi keeps dropping"));
        QTRY_COMPARE(client.state(), QStringLiteral("answered"));
        QTest::qWait(100);
        QVERIFY(!client.codexReady());
        QVERIFY(!client.askCodex());
        ask.signIn(true);
        QTRY_VERIFY(client.codexReady());
        QVERIFY(ask.toCodex.isEmpty());
        QVERIFY(client.askCodex());
        QTRY_COMPARE(ask.toCodex, QStringList { QStringLiteral("my wifi keeps dropping") });
        QVERIFY(!client.handedToCodex());

        ask.handsToCodex = true;
        client.type(QStringLiteral("set up my printer please"));
        QTRY_VERIFY(client.handedToCodex());
        QCOMPARE(client.text(), QStringLiteral("Codex is taking it."));
        client.type(QString());
        QVERIFY(!client.handedToCodex());
        ask.signIn(false);
        QTRY_VERIFY(!client.codexReady());
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask-3"));
    }
};

QTEST_GUILESS_MAIN(AskClientTest)
#include "AskClientTest.moc"
