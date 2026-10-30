#include "CoreFactProvider.h"
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMetaType>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTest>

// A stand-in for Split Rock's Core on the test's own bus: its facts, and what
// it was asked.
class FakeCore : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.SplitRock.Core")
public:
    uint version = 1;
    QList<QVariantMap> facts;
    QStringList acts;
    // A Core from before layouts answers that it has no such method.
    bool keepsLayouts = false;
    QList<QVariantMap> layouts;
    QVariantMap current;
public Q_SLOTS:
    QList<QVariantMap> Layouts() {
        if (!keepsLayouts) sendErrorReply(QDBusError::UnknownMethod, QStringLiteral("No such method"));
        return layouts;
    }
    QVariantMap CurrentLayout() const { return current; }
    QString SaveLayout(const QString &name, const QString &groups, bool atSignIn) {
        acts.append(QStringLiteral("save %1 %2 %3").arg(name, groups, atSignIn ? QStringLiteral("at-sign-in") : QStringLiteral("-")));
        return QStringLiteral("3");
    }
    bool OpenLayout(const QString &id) { acts.append(QStringLiteral("open-layout ") + id); return true; }
    bool RemoveLayout(const QString &id) { acts.append(QStringLiteral("remove-layout ") + id); return true; }
    bool SetLayoutAtSignIn(const QString &id, bool on) {
        acts.append(QStringLiteral("at-sign-in %1 %2").arg(id, on ? QStringLiteral("on") : QStringLiteral("off")));
        return true;
    }
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
    void LayoutsChanged();
    void LayoutOpened(const QString &id, int placed, int missed, const QStringList &missedNames);
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

QVariantMap group(const QStringList &apps, const QStringList &names) {
    return {{QStringLiteral("apps"), apps}, {QStringLiteral("names"), names}, {QStringLiteral("stack"), apps.size() > 1}};
}

// Coding: Ghostty stacked with Claude, then Zen on its own.
QVariantMap coding(bool atSignIn) {
    return {{QStringLiteral("id"), QStringLiteral("1")}, {QStringLiteral("name"), QStringLiteral("Coding")},
            {QStringLiteral("groups"), QVariant::fromValue(QList<QVariantMap>{
                group({QStringLiteral("com.mitchellh.ghostty"), QStringLiteral("claude")}, {QStringLiteral("Ghostty"), QStringLiteral("Claude")}),
                group({QStringLiteral("app.zen_browser.zen")}, {QStringLiteral("Zen")})})},
            {QStringLiteral("atSignIn"), atSignIn}};
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

    // A Core that keeps layouts lists them, plain, and each call goes to it
    // as the contract names it; a change on the bus reads them again.
    void layoutsFromCore() {
        FakeCore core;
        core.keepsLayouts = true;
        core.layouts = {coding(true)};
        core.current = {{QStringLiteral("available"), true}, {QStringLiteral("workspace"), QStringLiteral("desktop-1")},
                        {QStringLiteral("groups"), QVariant::fromValue(QList<QVariantMap>{
                            group({QStringLiteral("org.kde.dolphin")}, {QString()})})}};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-6"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_VERIFY(provider.keepsLayouts());
        QCOMPARE(provider.layouts().size(), 1);
        const auto layout = provider.layouts().first();
        QCOMPARE(layout.value(QStringLiteral("id")).toString(), QStringLiteral("1"));
        QCOMPARE(layout.value(QStringLiteral("name")).toString(), QStringLiteral("Coding"));
        QVERIFY(layout.value(QStringLiteral("atSignIn")).toBool());
        const auto groups = layout.value(QStringLiteral("groups")).toList();
        QCOMPARE(groups.size(), 2);
        QCOMPARE(groups.at(0).toMap().value(QStringLiteral("names")).toStringList(), (QStringList{QStringLiteral("Ghostty"), QStringLiteral("Claude")}));
        QVERIFY(groups.at(0).toMap().value(QStringLiteral("stack")).toBool());
        QCOMPARE(groups.at(1).toMap().value(QStringLiteral("apps")).toStringList(), QStringList{QStringLiteral("app.zen_browser.zen")});
        QVERIFY(!groups.at(1).toMap().value(QStringLiteral("stack")).toBool());

        // What is open now, an app the menu doesn't name named by its id.
        QSignalSpy read(&provider, &CoreFactProvider::currentLayoutRead);
        provider.readCurrentLayout();
        QTRY_COMPARE(read.size(), 1);
        const auto current = read.first().first().toMap();
        QVERIFY(current.value(QStringLiteral("available")).toBool());
        QCOMPARE(current.value(QStringLiteral("workspace")).toString(), QStringLiteral("desktop-1"));
        const auto open = current.value(QStringLiteral("groups")).toList();
        QCOMPARE(open.size(), 1);
        QCOMPARE(open.first().toMap().value(QStringLiteral("names")).toStringList(), QStringList{QStringLiteral("org.kde.dolphin")});

        provider.saveLayout(QStringLiteral(" Writing "), {QVariantMap{{QStringLiteral("apps"), QStringList{QStringLiteral("notes"), QStringLiteral("zen")}},
                                                                     {QStringLiteral("names"), QStringList{QStringLiteral("Notes"), QStringLiteral("Zen")}},
                                                                     {QStringLiteral("stack"), true}},
                                                         QVariantMap{{QStringLiteral("apps"), QStringList()}}}, false);
        QTRY_COMPARE(core.acts.size(), 1);
        QCOMPARE(core.acts.last(), QStringLiteral(R"(save Writing [{"apps":["notes","zen"],"stack":true}] -)"));
        // No name, or nothing to keep: nothing is asked.
        provider.saveLayout(QStringLiteral("  "), groups, true);
        provider.saveLayout(QStringLiteral("Empty"), {}, true);
        provider.openLayout(QStringLiteral("1"));
        QTRY_COMPARE(core.acts.size(), 2);
        QCOMPARE(core.acts.last(), QStringLiteral("open-layout 1"));
        provider.setLayoutAtSignIn(QStringLiteral("1"), false);
        provider.removeLayout(QStringLiteral("1"));
        QTRY_COMPARE(core.acts.size(), 4);
        QCOMPARE(core.acts.at(2), QStringLiteral("at-sign-in 1 off"));
        QCOMPARE(core.acts.at(3), QStringLiteral("remove-layout 1"));

        QSignalSpy changed(&provider, &CoreFactProvider::layoutsChanged);
        core.layouts.clear();
        Q_EMIT core.LayoutsChanged();
        QTRY_VERIFY(provider.layouts().isEmpty());
        QVERIFY(provider.keepsLayouts());
        QCOMPARE(changed.size(), 1);

        // Core leaving takes its layouts with it.
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        QTRY_VERIFY(!provider.keepsLayouts());
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-6"));
    }

    // A run that leaves apps out names them on the island once: a tap or
    // setting it aside takes the row away, and Core hears nothing of it.
    void aLayoutThatMissesNamesWhatDidntOpen() {
        FakeCore core;
        core.keepsLayouts = true;
        core.layouts = {coding(false)};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-7"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.layouts().size(), 1);
        // Everything in its place: nothing to say.
        Q_EMIT core.LayoutOpened(QStringLiteral("1"), 3, 0, {});
        QTest::qWait(100);
        QVERIFY(provider.activities().isEmpty());

        Q_EMIT core.LayoutOpened(QStringLiteral("1"), 2, 1, {QStringLiteral("Mail")});
        QTRY_COMPARE(provider.activities().size(), 1);
        auto row = rowOf(provider, QStringLiteral("core:layout-missed"));
        QCOMPARE(row.value(QStringLiteral("kind")).toString(), QStringLiteral("core"));
        QCOMPARE(row.value(QStringLiteral("missed")).toStringList(), QStringList{QStringLiteral("Mail")});
        QCOMPARE(row.value(QStringLiteral("layout")).toString(), QStringLiteral("Coding"));
        QVERIFY(!row.value(QStringLiteral("asks")).toBool());
        provider.invoke(QStringLiteral("core:layout-missed"), row.value(QStringLiteral("generation")).toInt(), QStringLiteral("open"));
        QVERIFY(provider.activities().isEmpty());

        Q_EMIT core.LayoutOpened(QStringLiteral("9"), 0, 2, {QStringLiteral("Mail"), QStringLiteral("Notes")});
        QTRY_COMPARE(provider.activities().size(), 1);
        row = rowOf(provider, QStringLiteral("core:layout-missed"));
        QVERIFY(row.value(QStringLiteral("layout")).toString().isEmpty());
        provider.dismiss(QStringLiteral("core:layout-missed"));
        QVERIFY(provider.activities().isEmpty());
        QTest::qWait(100);
        QVERIFY(core.acts.isEmpty());

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-7"));
    }

    // A Core from before layouts keeps none, and nothing about them is asked
    // of it; the rest of Core goes on as before.
    void anOlderCoreKeepsNoLayouts() {
        FakeCore core;
        core.facts = {storage(QStringLiteral("island"))};
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-core-8"));
        QVERIFY(peer.registerObject(QStringLiteral("/Core"), &core, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.splitrock.Core")));

        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTRY_COMPARE(provider.activities().size(), 1);
        QTRY_COMPARE(provider.actions().size(), 1);
        QTest::qWait(100);
        QVERIFY(!provider.keepsLayouts());
        QVERIFY(provider.layouts().isEmpty());
        QSignalSpy read(&provider, &CoreFactProvider::currentLayoutRead);
        provider.readCurrentLayout();
        QCOMPARE(read.size(), 1);
        QVERIFY(!read.first().first().toMap().value(QStringLiteral("available")).toBool());
        provider.openLayout(QStringLiteral("1"));
        provider.saveLayout(QStringLiteral("Coding"), {QVariantMap{{QStringLiteral("apps"), QStringList{QStringLiteral("zen")}}}}, false);
        QTest::qWait(100);
        QVERIFY(core.acts.isEmpty());

        peer.unregisterService(QStringLiteral("io.github.carlsonjm.splitrock.Core"));
        peer.unregisterObject(QStringLiteral("/Core"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-core-8"));
    }

    // Without Core there are no layouts.
    void noCoreNoLayouts() {
        CoreFactProvider provider(QDBusConnection::sessionBus());
        QTest::qWait(200);
        QVERIFY(!provider.keepsLayouts());
        QVERIFY(provider.layouts().isEmpty());
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
