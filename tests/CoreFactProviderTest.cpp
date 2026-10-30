#include "CoreFactProvider.h"
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QSignalSpy>
#include <QTest>

// A stand-in for Split Rock's Core on the test's own bus: its facts, and what
// it was asked.
class FakeCore : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.SplitRock.Core")
public:
    uint version = 1;
    QList<QVariantMap> facts;
    QStringList acts;
public Q_SLOTS:
    uint ProtocolVersion() const { return version; }
    QList<QVariantMap> Facts() const { return facts; }
    bool Act(const QString &topic, const QString &action) { acts.append(topic + QLatin1Char(' ') + action); return true; }
    QList<QVariantMap> Actions() const {
        return {{{QStringLiteral("id"), QStringLiteral("install")}, {QStringLiteral("title"), QStringLiteral("Install an app")},
                 {QStringLiteral("keywords"), QStringList{QStringLiteral("install")}}}};
    }
    bool OpenAction(const QString &id, const QString &query) { acts.append(id + QStringLiteral(": ") + query); return true; }
Q_SIGNALS:
    void FactChanged(const QVariantMap &fact);
};

namespace {
QVariantMap storage(const QString &attention, int percent = 91) {
    return {{QStringLiteral("topic"), QStringLiteral("storage")}, {QStringLiteral("title"), QStringLiteral("Storage")},
            {QStringLiteral("line"), QStringLiteral("%1% full").arg(percent)}, {QStringLiteral("detail"), QStringLiteral("45 GB free")},
            {QStringLiteral("percent"), percent}, {QStringLiteral("level"), QStringLiteral("island")},
            {QStringLiteral("attention"), attention}, {QStringLiteral("icon"), QStringLiteral("drive-harddisk")},
            {QStringLiteral("actionText"), QStringLiteral("Free up space")},
            {QStringLiteral("keywords"), QStringList{QStringLiteral("storage"), QStringLiteral("disk")}}};
}

QVariantMap windows() {
    return {{QStringLiteral("topic"), QStringLiteral("windows")}, {QStringLiteral("title"), QStringLiteral("Windows program")},
            {QStringLiteral("line"), QStringLiteral("setup.exe is for Windows")}, {QStringLiteral("level"), QStringLiteral("island")},
            {QStringLiteral("attention"), QStringLiteral("island")}, {QStringLiteral("icon"), QStringLiteral("application-x-ms-dos-executable")},
            {QStringLiteral("actionText"), QStringLiteral("Find the Linux version")}};
}

// Bringing back the last sign-in's apps, with Always beside the tap when
// `always` is set, as Core lists it.
QVariantMap memory(bool always) {
    QVariantMap fact{{QStringLiteral("topic"), QStringLiteral("memory")}, {QStringLiteral("title"), QStringLiteral("Workspace Memory")},
                     {QStringLiteral("line"), QStringLiteral("Bring back 4 apps from yesterday?")},
                     {QStringLiteral("detail"), QStringLiteral("Each one goes back to its place")},
                     {QStringLiteral("level"), QStringLiteral("island")}, {QStringLiteral("attention"), QStringLiteral("island")},
                     {QStringLiteral("icon"), QStringLiteral("window-restore")}, {QStringLiteral("actionText"), QStringLiteral("Bring back")}};
    if (always)
        fact.insert(QStringLiteral("choices"), QVariant::fromValue(QList<QVariantMap>{
            {{QStringLiteral("action"), QStringLiteral("always")}, {QStringLiteral("text"), QStringLiteral("Always")}},
            // Without words it is not drawn, and Not now has its own place.
            {{QStringLiteral("action"), QStringLiteral("later")}},
            {{QStringLiteral("action"), QStringLiteral("not-now")}, {QStringLiteral("text"), QStringLiteral("Later")}}}));
    return fact;
}

QVariantMap automations() {
    return {{QStringLiteral("topic"), QStringLiteral("automations")}, {QStringLiteral("title"), QStringLiteral("Automations")},
            {QStringLiteral("line"), QStringLiteral("Open Firefox, Notes and Mail when you sign in?")},
            {QStringLiteral("level"), QStringLiteral("island")}, {QStringLiteral("attention"), QStringLiteral("island")},
            {QStringLiteral("actionText"), QStringLiteral("Yes, each time")}, {QStringLiteral("dismissText"), QStringLiteral("No thanks")}};
}

QVariantMap rowOf(const CoreFactProvider &provider, const QString &id) {
    for (const auto &value : provider.activities())
        if (value.toMap().value(QStringLiteral("id")).toString() == id) return value.toMap();
    return {};
}
}

class CoreFactProviderTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void initTestCase() { qDBusRegisterMetaType<QList<QVariantMap>>(); }

    // Without Core there are no rows and no facts, and nothing is asked.
    void noCoreNoRows() {
        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTest::qWait(200);
        QVERIFY(provider.facts().isEmpty());
        QVERIFY(provider.activities().isEmpty());
        provider.open(QStringLiteral("storage"));
    }

    // A fact that wants the island is a row; Open and setting it aside are
    // Core's to act on, and Core's answer takes the row away.
    void aFactOnTheIsland() {
        FakeCore core;
        core.facts = {storage(QStringLiteral("island"))};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.activities().size(), 1);
        const auto row = provider.activities().first().toMap();
        QCOMPARE(row.value(QStringLiteral("id")).toString(), QStringLiteral("core:storage"));
        QCOMPARE(row.value(QStringLiteral("kind")).toString(), QStringLiteral("core"));
        QCOMPARE(row.value(QStringLiteral("line")).toString(), QStringLiteral("91% full"));
        QCOMPARE(row.value(QStringLiteral("actionText")).toString(), QStringLiteral("Free up space"));
        QVERIFY(row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("open")).toBool());

        provider.invoke(QStringLiteral("core:storage"), row.value(QStringLiteral("generation")).toInt(), QStringLiteral("open"));
        QTRY_COMPARE(core.acts, QStringList{QStringLiteral("storage open")});
        // Only Open, and only with the row's own generation.
        provider.invoke(QStringLiteral("core:storage"), row.value(QStringLiteral("generation")).toInt() + 1, QStringLiteral("open"));
        provider.invoke(QStringLiteral("core:storage"), row.value(QStringLiteral("generation")).toInt(), QStringLiteral("delete"));
        provider.dismiss(QStringLiteral("core:storage"));
        QTRY_COMPARE(core.acts.size(), 2);
        QCOMPARE(core.acts.last(), QStringLiteral("storage dismiss"));

        // The upkeep cards, opened with what was typed.
        QTRY_COMPARE(provider.actions().size(), 1);
        provider.openAction(QStringLiteral("install"), QStringLiteral("install pdf editor"));
        QTRY_COMPARE(core.acts.size(), 3);
        QCOMPARE(core.acts.last(), QStringLiteral("install: install pdf editor"));

        QSignalSpy changed(&provider, &CoreFactProvider::changed);
        Q_EMIT core.FactChanged(storage(QStringLiteral("none")));
        QTRY_VERIFY(provider.activities().isEmpty());
        // Search still finds it.
        QCOMPARE(provider.facts().size(), 1);
        QVERIFY(changed.size() >= 1);

        // Core leaving takes its facts with it, and Search's Helpers hear
        // that its cards went.
        QSignalSpy actionsGone(&provider, &CoreFactProvider::actionsChanged);
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        QTRY_VERIFY(provider.facts().isEmpty());
        QVERIFY(provider.actions().isEmpty());
        QCOMPARE(actionsGone.size(), 1);
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core"));
    }

    // "Don't tell me again" is Core's to keep, and only for Windows programs.
    void neverOnlyForWindows() {
        FakeCore core;
        core.facts = {storage(QStringLiteral("island")), windows()};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-3"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.activities().size(), 2);
        int generation = 0;
        for (const auto &value : provider.activities()) {
            const auto row = value.toMap();
            const auto capabilities = row.value(QStringLiteral("capabilities")).toMap();
            generation = row.value(QStringLiteral("generation")).toInt();
            QCOMPARE(capabilities.value(QStringLiteral("never")).toBool(),
                     row.value(QStringLiteral("id")).toString() == QLatin1String("core:windows"));
        }

        provider.invoke(QStringLiteral("core:storage"), generation, QStringLiteral("never"));
        provider.invoke(QStringLiteral("core:windows"), generation + 1, QStringLiteral("never"));
        provider.invoke(QStringLiteral("core:windows"), generation, QStringLiteral("never"));
        QTRY_COMPARE(core.acts.size(), 1);
        QCOMPARE(core.acts.first(), QStringLiteral("windows never"));
        QTest::qWait(100);
        QCOMPARE(core.acts.size(), 1);

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-3"));
    }

    // A fact that asks carries Core's choices and its words for Not now, and
    // each answer goes to Core as Core names it; nothing it doesn't list does.
    void aQuestionAndItsChoices() {
        FakeCore core;
        core.facts = {storage(QStringLiteral("island")), memory(true), automations()};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-4"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.activities().size(), 3);
        const auto plain = rowOf(provider, QStringLiteral("core:storage"));
        QVERIFY(!plain.value(QStringLiteral("asks")).toBool());
        QVERIFY(plain.value(QStringLiteral("choices")).toList().isEmpty());
        QVERIFY(!plain.value(QStringLiteral("capabilities")).toMap().contains(QStringLiteral("not-now")));

        const auto question = rowOf(provider, QStringLiteral("core:memory"));
        QVERIFY(question.value(QStringLiteral("asks")).toBool());
        const auto choices = question.value(QStringLiteral("choices")).toList();
        QCOMPARE(choices.size(), 1);
        QCOMPARE(choices.first().toMap().value(QStringLiteral("action")).toString(), QStringLiteral("always"));
        QCOMPARE(choices.first().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("Always"));
        QVERIFY(question.value(QStringLiteral("dismissText")).toString().isEmpty());
        const auto capabilities = question.value(QStringLiteral("capabilities")).toMap();
        QVERIFY(capabilities.value(QStringLiteral("open")).toBool());
        QVERIFY(capabilities.value(QStringLiteral("always")).toBool());
        QVERIFY(capabilities.value(QStringLiteral("not-now")).toBool());
        QVERIFY(!capabilities.contains(QStringLiteral("later")));

        const auto offer = rowOf(provider, QStringLiteral("core:automations"));
        QVERIFY(offer.value(QStringLiteral("asks")).toBool());
        QCOMPARE(offer.value(QStringLiteral("dismissText")).toString(), QStringLiteral("No thanks"));
        QVERIFY(offer.value(QStringLiteral("choices")).toList().isEmpty());

        const int generation = question.value(QStringLiteral("generation")).toInt();
        provider.invoke(QStringLiteral("core:memory"), generation, QStringLiteral("always"));
        QTRY_COMPARE(core.acts, QStringList{QStringLiteral("memory always")});
        // Not listed, or listed for another fact: not passed.
        provider.invoke(QStringLiteral("core:memory"), generation, QStringLiteral("later"));
        provider.invoke(QStringLiteral("core:automations"), generation, QStringLiteral("always"));
        provider.invoke(QStringLiteral("core:storage"), generation, QStringLiteral("not-now"));
        provider.invoke(QStringLiteral("core:automations"), generation, QStringLiteral("not-now"));
        QTRY_COMPARE(core.acts.size(), 2);
        QCOMPARE(core.acts.last(), QStringLiteral("automations not-now"));
        QTest::qWait(100);
        QCOMPARE(core.acts.size(), 2);

        // A change on the bus carries its choices the same way.
        Q_EMIT core.FactChanged(memory(false));
        QTRY_VERIFY(rowOf(provider, QStringLiteral("core:memory")).value(QStringLiteral("choices")).toList().isEmpty());
        Q_EMIT core.FactChanged(memory(true));
        QTRY_COMPARE(rowOf(provider, QStringLiteral("core:memory")).value(QStringLiteral("choices")).toList().size(), 1);

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-4"));
    }

    // A Core that lists no choices still asks: bringing the apps back has
    // its tap and Not now, and Always is not passed for it.
    void aQuestionFromACoreWithoutChoices() {
        FakeCore core;
        core.facts = {memory(false)};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-5"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.activities().size(), 1);
        const auto row = provider.activities().first().toMap();
        QVERIFY(row.value(QStringLiteral("asks")).toBool());
        QVERIFY(row.value(QStringLiteral("choices")).toList().isEmpty());
        const int generation = row.value(QStringLiteral("generation")).toInt();
        provider.invoke(QStringLiteral("core:memory"), generation, QStringLiteral("always"));
        provider.invoke(QStringLiteral("core:memory"), generation, QStringLiteral("not-now"));
        QTRY_COMPARE(core.acts, QStringList{QStringLiteral("memory not-now")});
        provider.invoke(QStringLiteral("core:memory"), generation, QStringLiteral("open"));
        QTRY_COMPARE(core.acts.size(), 2);
        QCOMPARE(core.acts.last(), QStringLiteral("memory open"));

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-5"));
    }

    // A Core that speaks another version is left alone.
    void anotherVersionIsLeftAlone() {
        FakeCore core;
        core.version = 2;
        core.facts = {storage(QStringLiteral("island"))};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-2"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));
        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTest::qWait(300);
        QVERIFY(provider.facts().isEmpty());
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-2"));
    }
};

QTEST_GUILESS_MAIN(CoreFactProviderTest)
#include "CoreFactProviderTest.moc"
