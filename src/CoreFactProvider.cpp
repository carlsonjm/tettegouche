#include "CoreFactProvider.h"
#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>

namespace {
const QString Prefix = QStringLiteral("core:");
QString service() { return QString::fromLatin1(CoreFactProvider::Service); }
QString path() { return QString::fromLatin1(CoreFactProvider::Path); }
QString iface() { return QString::fromLatin1(CoreFactProvider::Interface); }

const QString Choices = QStringLiteral("choices");
// The row that names what a layout left out. Not one of Core's topics, so
// nothing about it goes to Core.
const QString Missed = QStringLiteral("layout-missed");
constexpr int MissedMs = 60000;
const QString DismissText = QStringLiteral("dismissText");

QVariantList choicesOf(const QVariantMap &fact) { return fact.value(Choices).toList(); }

// A fact asks when Core gives it more to answer than its tap: choices, or its
// own words for Not now. Bringing back the last sign-in's apps and an
// automation's offer ask whatever their Core gives them, since a single tap
// on either would be a yes to words nobody read.
bool asks(const QVariantMap &fact) {
    const auto topic = fact.value(QStringLiteral("topic")).toString();
    return !choicesOf(fact).isEmpty() || !fact.value(DismissText).toString().isEmpty()
        || topic == QLatin1String("memory") || topic == QLatin1String("automations");
}

bool listed(const QVariantMap &fact, const QString &action) {
    const auto choices = choicesOf(fact);
    return std::any_of(choices.cbegin(), choices.cend(), [&action](const QVariant &choice) {
        return choice.toMap().value(QStringLiteral("action")).toString() == action;
    });
}
}

QVariantMap CoreFactProvider::readFact(const QVariantMap &fact) {
    if (!fact.contains(Choices)) return fact;
    auto read = fact;
    const auto value = fact.value(Choices);
    QVariantList raw;
    if (value.canConvert<QDBusArgument>()) {
        for (const auto &choice : qdbus_cast<QList<QVariantMap>>(value.value<QDBusArgument>())) raw.append(choice);
    } else {
        raw = value.toList();
    }
    // Only a choice with both an action and its words is drawn; an action
    // Search already offers in its own place is not offered twice.
    QVariantList choices;
    for (const auto &entry : std::as_const(raw)) {
        const auto choice = entry.toMap();
        const auto action = choice.value(QStringLiteral("action")).toString();
        const auto text = choice.value(QStringLiteral("text")).toString();
        if (action.isEmpty() || text.isEmpty() || action == QLatin1String("open") || action == QLatin1String("not-now")
                || action == QLatin1String("dismiss"))
            continue;
        choices.append(QVariantMap{{QStringLiteral("action"), action}, {QStringLiteral("text"), text}});
    }
    if (choices.isEmpty()) read.remove(Choices);
    else read.insert(Choices, choices);
    return read;
}

namespace {
QList<QVariantMap> mapsOf(const QVariant &value) {
    if (value.canConvert<QDBusArgument>()) return qdbus_cast<QList<QVariantMap>>(value.value<QDBusArgument>());
    QList<QVariantMap> maps;
    for (const auto &entry : value.toList()) maps.append(entry.toMap());
    return maps;
}

// A layout's groups as they come from the bus, made plain. A group without
// apps is left out; names stand in for apps the menu doesn't name.
QVariantList groupsOf(const QVariant &value) {
    QVariantList groups;
    for (const auto &group : mapsOf(value)) {
        const auto apps = group.value(QStringLiteral("apps")).toStringList();
        if (apps.isEmpty()) continue;
        auto names = group.value(QStringLiteral("names")).toStringList();
        for (qsizetype i = 0; i < apps.size(); ++i) {
            if (i >= names.size()) names.append(apps.at(i));
            else if (names.at(i).isEmpty()) names[i] = apps.at(i);
        }
        names = names.mid(0, apps.size());
        groups.append(QVariantMap{{QStringLiteral("apps"), apps}, {QStringLiteral("names"), names},
                                  {QStringLiteral("stack"), apps.size() > 1 && group.value(QStringLiteral("stack")).toBool()}});
    }
    return groups;
}
}

CoreFactProvider::CoreFactProvider(const QDBusConnection &bus, QObject *parent) : QObject(parent), m_bus(bus) {
    qDBusRegisterMetaType<QList<QVariantMap>>();
    m_missedFor.setSingleShot(true);
    m_missedFor.setInterval(MissedMs);
    connect(&m_missedFor, &QTimer::timeout, this, &CoreFactProvider::forgetMissed);
    if (!m_bus.isConnected()) return;
    auto *watcher = new QDBusServiceWatcher(service(), m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &CoreFactProvider::ownerChanged);
    m_bus.connect(service(), path(), iface(), QStringLiteral("FactChanged"), this,
                  SLOT(factChanged(QVariantMap,QDBusMessage)));
    m_bus.connect(service(), path(), iface(), QStringLiteral("LayoutsChanged"), this, SLOT(layoutsMoved(QDBusMessage)));
    m_bus.connect(service(), path(), iface(), QStringLiteral("LayoutOpened"), this,
                  SLOT(layoutOpened(QString,int,int,QStringList,QDBusMessage)));

    // The first question starts Core where it is installed and not yet running.
    ask();
}

void CoreFactProvider::ownerChanged(const QString &name, const QString &, const QString &owner) {
    if (name != service()) return;
    ++m_generation;
    m_owner = owner;
    if (!m_actions.isEmpty()) { m_actions.clear(); Q_EMIT actionsChanged(); }
    if (m_keepsLayouts || !m_layouts.isEmpty()) { m_keepsLayouts = false; m_layouts.clear(); Q_EMIT layoutsChanged(); }
    m_missedFor.stop();
    m_missed.clear();
    m_missedLayout.clear();
    if (!m_facts.isEmpty()) { m_facts.clear(); Q_EMIT changed(); }
    if (!owner.isEmpty()) ask();
}

// The version first: a Core that speaks another one is left alone.
void CoreFactProvider::ask() {
    const int generation = m_generation;
    auto *version = new QDBusPendingCallWatcher(m_bus.asyncCall(
        QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("ProtocolVersion")), 5000), this);
    connect(version, &QDBusPendingCallWatcher::finished, this, [this, version, generation] {
        const QDBusPendingReply<uint> number = *version; version->deleteLater();
        if (number.isError() || number.value() != Version || generation != m_generation) return;
        auto *facts = new QDBusPendingCallWatcher(m_bus.asyncCall(
            QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Facts")), 5000), this);
        connect(facts, &QDBusPendingCallWatcher::finished, this, [this, facts, generation] {
            const QDBusPendingReply<QList<QVariantMap>> reply = *facts; facts->deleteLater();
            if (reply.isError() || generation != m_generation) return;
            QList<QVariantMap> read;
            for (const auto &fact : reply.value()) read.append(readFact(fact));
            if (read != m_facts) { m_facts = read; Q_EMIT changed(); }
        });
        auto *actions = new QDBusPendingCallWatcher(m_bus.asyncCall(
            QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Actions")), 5000), this);
        connect(actions, &QDBusPendingCallWatcher::finished, this, [this, actions, generation] {
            const QDBusPendingReply<QList<QVariantMap>> reply = *actions; actions->deleteLater();
            if (reply.isError() || generation != m_generation || reply.value() == m_actions) return;
            m_actions = reply.value();
            Q_EMIT actionsChanged();
        });
        askLayouts();
    });
}

// A Core older than layouts answers that it has no such method: it keeps none.
void CoreFactProvider::askLayouts() {
    const int generation = m_generation;
    auto *layouts = new QDBusPendingCallWatcher(m_bus.asyncCall(
        QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Layouts")), 5000), this);
    connect(layouts, &QDBusPendingCallWatcher::finished, this, [this, layouts, generation] {
        const QDBusPendingReply<QList<QVariantMap>> reply = *layouts; layouts->deleteLater();
        if (generation != m_generation) return;
        QList<QVariantMap> read;
        if (!reply.isError()) {
            for (const auto &layout : reply.value()) {
                const auto id = layout.value(QStringLiteral("id")).toString();
                const auto name = layout.value(QStringLiteral("name")).toString();
                if (id.isEmpty() || name.isEmpty()) continue;
                read.append({{QStringLiteral("id"), id}, {QStringLiteral("name"), name},
                             {QStringLiteral("groups"), groupsOf(layout.value(QStringLiteral("groups")))},
                             {QStringLiteral("atSignIn"), layout.value(QStringLiteral("atSignIn")).toBool()}});
            }
        }
        const bool keeps = !reply.isError();
        if (keeps == m_keepsLayouts && read == m_layouts) return;
        m_keepsLayouts = keeps;
        m_layouts = read;
        Q_EMIT layoutsChanged();
    });
}

void CoreFactProvider::layoutsMoved(const QDBusMessage &message) {
    if (!m_keepsLayouts || (!m_owner.isEmpty() && message.service() != m_owner)) return;
    askLayouts();
}

void CoreFactProvider::layoutOpened(const QString &id, int, int missed, const QStringList &missedNames,
                                    const QDBusMessage &message) {
    if (!m_owner.isEmpty() && message.service() != m_owner) return;
    if (missed <= 0 || missedNames.isEmpty()) return;
    m_missed = missedNames;
    m_missedLayout.clear();
    for (const auto &layout : std::as_const(m_layouts)) {
        if (layout.value(QStringLiteral("id")).toString() == id) m_missedLayout = layout.value(QStringLiteral("name")).toString();
    }
    m_missedFor.start();
    Q_EMIT changed();
}

void CoreFactProvider::forgetMissed() {
    m_missedFor.stop();
    if (m_missed.isEmpty()) return;
    m_missed.clear();
    m_missedLayout.clear();
    Q_EMIT changed();
}

void CoreFactProvider::readCurrentLayout() {
    if (!m_keepsLayouts) {
        Q_EMIT currentLayoutRead({{QStringLiteral("available"), false}});
        return;
    }
    const int generation = m_generation;
    auto *current = new QDBusPendingCallWatcher(m_bus.asyncCall(
        QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("CurrentLayout")), 5000), this);
    connect(current, &QDBusPendingCallWatcher::finished, this, [this, current, generation] {
        const QDBusPendingReply<QVariantMap> reply = *current; current->deleteLater();
        if (generation != m_generation || reply.isError()) {
            Q_EMIT currentLayoutRead({{QStringLiteral("available"), false}});
            return;
        }
        const auto layout = reply.value();
        Q_EMIT currentLayoutRead({{QStringLiteral("available"), layout.value(QStringLiteral("available"), true).toBool()},
                                  {QStringLiteral("workspace"), layout.value(QStringLiteral("workspace")).toString()},
                                  {QStringLiteral("groups"), groupsOf(layout.value(QStringLiteral("groups")))}});
    });
}

void CoreFactProvider::saveLayout(const QString &name, const QVariantList &groups, bool atSignIn) {
    QJsonArray kept;
    for (const auto &entry : groups) {
        const auto group = entry.toMap();
        const auto apps = group.value(QStringLiteral("apps")).toStringList();
        if (apps.isEmpty()) continue;
        kept.append(QJsonObject{{QStringLiteral("apps"), QJsonArray::fromStringList(apps)},
                                {QStringLiteral("stack"), apps.size() > 1 && group.value(QStringLiteral("stack")).toBool()}});
    }
    if (name.trimmed().isEmpty() || kept.isEmpty()) return;
    call(QStringLiteral("SaveLayout"),
         {name.trimmed(), QString::fromUtf8(QJsonDocument(kept).toJson(QJsonDocument::Compact)), atSignIn});
}

void CoreFactProvider::openLayout(const QString &id) {
    call(QStringLiteral("OpenLayout"), {id});
}

void CoreFactProvider::removeLayout(const QString &id) {
    call(QStringLiteral("RemoveLayout"), {id});
}

void CoreFactProvider::setLayoutAtSignIn(const QString &id, bool on) {
    call(QStringLiteral("SetLayoutAtSignIn"), {id, on});
}

// Core answers with LayoutsChanged, which reads the layouts again.
void CoreFactProvider::call(const QString &method, const QVariantList &arguments) {
    if (!m_keepsLayouts || arguments.value(0).toString().isEmpty()) return;
    auto message = QDBusMessage::createMethodCall(service(), path(), iface(), method);
    message.setArguments(arguments);
    m_bus.asyncCall(message, 5000);
}

void CoreFactProvider::factChanged(const QVariantMap &arrived, const QDBusMessage &message) {
    if (!m_owner.isEmpty() && message.service() != m_owner) return;
    const auto fact = readFact(arrived);
    const auto topic = fact.value(QStringLiteral("topic")).toString();
    if (topic.isEmpty()) return;
    for (auto &known : m_facts) {
        if (known.value(QStringLiteral("topic")).toString() != topic) continue;
        if (known == fact) return;
        known = fact;
        Q_EMIT changed();
        return;
    }
    m_facts.append(fact);
    Q_EMIT changed();
}

QVariantList CoreFactProvider::activities() const {
    QVariantList rows;
    for (const auto &fact : m_facts) {
        if (fact.value(QStringLiteral("attention")).toString() != QLatin1String("island")) continue;
        const auto topic = fact.value(QStringLiteral("topic")).toString();
        QVariantMap capabilities{{QStringLiteral("open"), true}};
        // Core takes "never" only for Windows programs.
        if (topic == QLatin1String("windows")) capabilities.insert(QStringLiteral("never"), true);
        const bool asking = asks(fact);
        if (asking) capabilities.insert(QStringLiteral("not-now"), true);
        for (const auto &choice : choicesOf(fact))
            capabilities.insert(choice.toMap().value(QStringLiteral("action")).toString(), true);
        rows.append(QVariantMap{
            {QStringLiteral("id"), QString(Prefix + topic)}, {QStringLiteral("generation"), m_generation},
            {QStringLiteral("kind"), QStringLiteral("core")}, {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("title"), fact.value(QStringLiteral("title")).toString()},
            {QStringLiteral("line"), fact.value(QStringLiteral("line")).toString()},
            {QStringLiteral("detail"), fact.value(QStringLiteral("detail")).toString()},
            {QStringLiteral("actionText"), fact.value(QStringLiteral("actionText")).toString()},
            {QStringLiteral("icon"), fact.value(QStringLiteral("icon")).toString()},
            {QStringLiteral("asks"), asking},
            {Choices, choicesOf(fact)},
            {DismissText, fact.value(DismissText).toString()},
            {QStringLiteral("capabilities"), capabilities}});
    }
    if (!m_missed.isEmpty()) {
        rows.append(QVariantMap{
            {QStringLiteral("id"), QString(Prefix + Missed)}, {QStringLiteral("generation"), m_generation},
            {QStringLiteral("kind"), QStringLiteral("core")}, {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("icon"), QStringLiteral("view-grid")}, {QStringLiteral("missed"), m_missed},
            {QStringLiteral("layout"), m_missedLayout},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("open"), true}}}});
    }
    return rows;
}

void CoreFactProvider::invoke(const QString &id, int generation, const QString &action) {
    if (!id.startsWith(Prefix) || generation != m_generation) return;
    const auto topic = id.mid(Prefix.size());
    // Told once: a tap takes it away.
    if (topic == Missed) { if (action == QLatin1String("open")) forgetMissed(); return; }
    if (action == QLatin1String("open")) { act(topic, action); return; }
    if (action == QLatin1String("never") && topic == QLatin1String("windows")) { act(topic, action); return; }
    const auto found = std::find_if(m_facts.cbegin(), m_facts.cend(), [&topic](const QVariantMap &fact) {
        return fact.value(QStringLiteral("topic")).toString() == topic;
    });
    if (found == m_facts.cend()) return;
    if ((action == QLatin1String("not-now") && asks(*found)) || listed(*found, action)) act(topic, action);
}

void CoreFactProvider::dismiss(const QString &id) {
    if (id == Prefix + Missed) forgetMissed();
    else if (id.startsWith(Prefix)) act(id.mid(Prefix.size()), QStringLiteral("dismiss"));
}

void CoreFactProvider::open(const QString &topic) {
    act(topic, QStringLiteral("open"));
}

void CoreFactProvider::openAction(const QString &id, const QString &query) {
    if (m_actions.isEmpty()) return;
    auto call = QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("OpenAction"));
    call.setArguments({id, query});
    m_bus.asyncCall(call, 5000);
}

bool CoreFactProvider::removesApps() const {
    return std::any_of(m_actions.cbegin(), m_actions.cend(), [](const QVariantMap &action) {
        return action.value(QStringLiteral("id")).toString() == QLatin1String("install");
    });
}

void CoreFactProvider::removeApp(const QString &applicationId, const QString &name) {
    if (!removesApps()) return;
    auto call = QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("RemoveApp"));
    call.setArguments({applicationId});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, name] {
        const QDBusPendingReply<bool> reply = *watcher; watcher->deleteLater();
        if (reply.isError() && reply.error().type() == QDBusError::UnknownMethod)
            openAction(QStringLiteral("install"), QStringLiteral("uninstall ") + name);
    });
}

// Core answers with FactChanged, which takes the row away.
void CoreFactProvider::act(const QString &topic, const QString &action) {
    if (m_owner.isEmpty() && m_facts.isEmpty()) return;
    auto call = QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Act"));
    call.setArguments({topic, action});
    m_bus.asyncCall(call, 5000);
}
