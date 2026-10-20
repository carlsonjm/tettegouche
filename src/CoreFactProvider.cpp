#include "CoreFactProvider.h"
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>

#include <algorithm>

namespace {
const QString Prefix = QStringLiteral("core:");
QString service() { return QString::fromLatin1(CoreFactProvider::Service); }
QString path() { return QString::fromLatin1(CoreFactProvider::Path); }
QString iface() { return QString::fromLatin1(CoreFactProvider::Interface); }
}

CoreFactProvider::CoreFactProvider(const QDBusConnection &bus, QObject *parent) : QObject(parent), m_bus(bus) {
    qDBusRegisterMetaType<QList<QVariantMap>>();
    if (!m_bus.isConnected()) return;
    auto *watcher = new QDBusServiceWatcher(service(), m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &CoreFactProvider::ownerChanged);
    m_bus.connect(service(), path(), iface(), QStringLiteral("FactChanged"), this,
                  SLOT(factChanged(QVariantMap,QDBusMessage)));
    // The first question starts Core where it is installed and not yet running.
    ask();
}

void CoreFactProvider::ownerChanged(const QString &name, const QString &, const QString &owner) {
    if (name != service()) return;
    ++m_generation;
    m_owner = owner;
    if (!m_actions.isEmpty()) { m_actions.clear(); Q_EMIT actionsChanged(); }
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
            if (reply.value() != m_facts) { m_facts = reply.value(); Q_EMIT changed(); }
        });
        auto *actions = new QDBusPendingCallWatcher(m_bus.asyncCall(
            QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Actions")), 5000), this);
        connect(actions, &QDBusPendingCallWatcher::finished, this, [this, actions, generation] {
            const QDBusPendingReply<QList<QVariantMap>> reply = *actions; actions->deleteLater();
            if (reply.isError() || generation != m_generation || reply.value() == m_actions) return;
            m_actions = reply.value();
            Q_EMIT actionsChanged();
        });
    });
}

void CoreFactProvider::factChanged(const QVariantMap &fact, const QDBusMessage &message) {
    if (!m_owner.isEmpty() && message.service() != m_owner) return;
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
        rows.append(QVariantMap{
            {QStringLiteral("id"), QString(Prefix + topic)}, {QStringLiteral("generation"), m_generation},
            {QStringLiteral("kind"), QStringLiteral("core")}, {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("title"), fact.value(QStringLiteral("title")).toString()},
            {QStringLiteral("line"), fact.value(QStringLiteral("line")).toString()},
            {QStringLiteral("detail"), fact.value(QStringLiteral("detail")).toString()},
            {QStringLiteral("actionText"), fact.value(QStringLiteral("actionText")).toString()},
            {QStringLiteral("icon"), fact.value(QStringLiteral("icon")).toString()},
            {QStringLiteral("capabilities"), capabilities}});
    }
    return rows;
}

void CoreFactProvider::invoke(const QString &id, int generation, const QString &action) {
    if (!id.startsWith(Prefix) || generation != m_generation) return;
    const auto topic = id.mid(Prefix.size());
    if (action == QLatin1String("open")) act(topic, action);
    else if (action == QLatin1String("never") && topic == QLatin1String("windows")) act(topic, action);
}

void CoreFactProvider::dismiss(const QString &id) {
    if (id.startsWith(Prefix)) act(id.mid(Prefix.size()), QStringLiteral("dismiss"));
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
