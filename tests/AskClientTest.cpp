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
    bool needsEngine = false;
    bool codexOnly = false;
    // Questions are left unanswered, as while the model thinks.
    bool slow = false;
    uint pending = 0;
    QStringList toCodex;
    // A Do it card, as JSON, and what was read, for the plain answer.
    QString doIt;
    QStringList read;
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
            if (codexOnly) {
                Q_EMIT Answered(id,
                    { { QStringLiteral("codexOnly"), true },
                        { QStringLiteral("text"), QStringLiteral("Ask is set to Codex only.") } });
                return;
            }
            if (needsModel) {
                Q_EMIT Answered(id,
                    { { QStringLiteral("needsModel"), true }, { QStringLiteral("needsEngine"), needsEngine },
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
                    { QStringLiteral("query"), QStringLiteral("wifi") }, { QStringLiteral("doIt"), doIt },
                    { QStringLiteral("read"), read } });
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
        return { { QStringLiteral("installed"), true }, { QStringLiteral("signedIn"), codexSignedIn },
            { QStringLiteral("only"), codexOnly } };
    }
    QVariantMap Model() const
    {
        return { { QStringLiteral("state"), QStringLiteral("missing") }, { QStringLiteral("size"), QStringLiteral("about 2.5 GB") },
            { QStringLiteral("name"), QStringLiteral("Qwen3 4B") }, { QStringLiteral("credit"), QStringLiteral("Qwen3 4B by the Qwen team") },
            { QStringLiteral("engine"), !needsEngine } };
    }
    bool SetCodexOnly(bool only)
    {
        codexOnly = only;
        Q_EMIT CodexChanged(Codex());
        return true;
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

// A stand-in for Split Rock's broker: it makes a card's write once, for the
// token it handed out.
class FakeBroker : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.SplitRock.Broker")
public:
    QStringList ran;
    QString problem;
public Q_SLOTS:
    QVariantMap Run(const QString &token)
    {
        ran.append(token);
        if (!problem.isEmpty())
            return { { QStringLiteral("ok"), false }, { QStringLiteral("problem"), problem } };
        return { { QStringLiteral("ok"), true } };
    }
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

    // An answer that would keep something in Notes carries a Do it card and
    // names the notes it read; only the tap hands the card's token to the
    // broker's Run, once, and the card says how it went. A settings skill's
    // card, which has no token, is not shown here.
    void aDoItCardRunsOnlyOnTheTap()
    {
        FakeAsk ask;
        ask.read = QStringList { QStringLiteral("Testing notes"), QStringLiteral("Tablet round 30 Oct") };
        ask.doIt = QStringLiteral(R"({"title":"Where I left off with testing","what":"Save a note","tool":"notes.create",)"
                                  R"("app":"Notes","args":{"text":"x"},"token":"t-1"})");
        FakeBroker broker;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));
        QVERIFY(peer.registerObject(QStringLiteral("/Broker"), &broker, QDBusConnection::ExportAllSlots));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Broker")));

        AskClient client(QDBusConnection::sessionBus());
        client.setPause(50);
        QTRY_VERIFY(client.available());
        QVERIFY(!client.runDoIt());
        client.type(QStringLiteral("save this answer to my notes"));
        QTRY_COMPARE(client.state(), QStringLiteral("answered"));
        QCOMPARE(client.read(), ask.read);
        QCOMPARE(client.doIt().value(QStringLiteral("title")).toString(), QStringLiteral("Where I left off with testing"));
        QCOMPARE(client.doIt().value(QStringLiteral("app")).toString(), QStringLiteral("Notes"));
        QVERIFY(!client.doIt().contains(QStringLiteral("token")));
        QVERIFY(client.doItState().isEmpty());
        QTest::qWait(100);
        QVERIFY(broker.ran.isEmpty());

        QVERIFY(client.runDoIt());
        QCOMPARE(client.doItState(), QStringLiteral("running"));
        QVERIFY(!client.runDoIt());
        QTRY_COMPARE(client.doItState(), QStringLiteral("done"));
        QCOMPARE(broker.ran, QStringList { QStringLiteral("t-1") });

        // A write the broker refuses says so, with its words.
        broker.problem = QStringLiteral("The card has expired");
        ask.doIt.replace(QStringLiteral("t-1"), QStringLiteral("t-2"));
        client.type(QStringLiteral("save that answer to my notes"));
        QTRY_VERIFY(client.doItState().isEmpty() && !client.doIt().isEmpty() && client.state() == QLatin1String("answered"));
        QVERIFY(client.runDoIt());
        QTRY_COMPARE(client.doItState(), QStringLiteral("failed"));
        QCOMPARE(client.doItProblem(), QStringLiteral("The card has expired"));

        // A settings skill's card runs a command, not a token: not shown.
        ask.doIt = QStringLiteral(R"({"title":"Turn on Night Color","command":"kwriteconfig6 x"})");
        ask.read.clear();
        client.type(QStringLiteral("turn on night color please"));
        QTRY_VERIFY(client.state() == QLatin1String("answered") && client.doItState().isEmpty());
        QVERIFY(client.doIt().isEmpty());
        QVERIFY(client.read().isEmpty());
        QVERIFY(!client.runDoIt());
        client.type(QString());
        QVERIFY(client.doIt().isEmpty());

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Broker"));
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask"));
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
        // The card names the model and whose it is, and Codex only is offered
        // where Codex is installed.
        QTRY_COMPARE(client.modelName(), QStringLiteral("Qwen3 4B"));
        QCOMPARE(client.modelCredit(), QStringLiteral("Qwen3 4B by the Qwen team"));
        QTRY_VERIFY(client.codexInstalled());
        QVERIFY(!client.needsEngine());
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

    // Without llama.cpp the card says so; Codex only leaves the model out,
    // asks the question again, and sends it to Codex only on the tap, signed
    // in or not, since Codex's window signs in first.
    void codexOnlyInsteadOfTheModel()
    {
        FakeAsk ask;
        ask.needsModel = true;
        ask.needsEngine = true;
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-ask-4"));
        QVERIFY(peer.registerObject(
            QStringLiteral("/Ask"), &ask, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Ask")));

        AskClient client(QDBusConnection::sessionBus());
        client.setPause(50);
        QTRY_VERIFY(client.available());
        client.type(QStringLiteral("my wifi keeps dropping"));
        QTRY_COMPARE(client.state(), QStringLiteral("needsModel"));
        QVERIFY(client.needsEngine());
        QTRY_VERIFY(client.codexInstalled());
        QVERIFY(!client.codexOnly());
        client.chooseCodexOnly();
        QTRY_VERIFY(ask.codexOnly);
        QTRY_COMPARE(client.state(), QStringLiteral("codexOnly"));
        QVERIFY(client.codexOnly());
        QVERIFY(!client.needsEngine());
        QCOMPARE(ask.asked.size(), 2);
        QVERIFY(ask.toCodex.isEmpty());
        QVERIFY(client.askCodex());
        QTRY_COMPARE(ask.toCodex, QStringList { QStringLiteral("my wifi keeps dropping") });
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Ask"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-ask-4"));
    }
};

QTEST_GUILESS_MAIN(AskClientTest)
#include "AskClientTest.moc"
