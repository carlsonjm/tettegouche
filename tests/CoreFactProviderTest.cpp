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
