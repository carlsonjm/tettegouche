#include "ScreenShareProvider.h"
#include "ActivityUtils.h"
#include <QDBusArgument>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>

namespace {
const QString Watcher = QStringLiteral("org.kde.StatusNotifierWatcher");
const QString WatcherPath = QStringLiteral("/StatusNotifierWatcher");
const QString ItemInterface = QStringLiteral("org.kde.StatusNotifierItem");
const QString Properties = QStringLiteral("org.freedesktop.DBus.Properties");
const QString Menu = QStringLiteral("com.canonical.dbusmenu");
const QString PortalId = QStringLiteral("xdg-desktop-portal-kde");
const QString Prefix = QStringLiteral("screen:");

// A tooltip is (icon name, pixmaps, title, subtitle); the subtitle names who.
QString subtitle(const QVariant &value) {
    if (value.metaType() != QMetaType::fromType<QDBusArgument>()) return {};
    const auto argument = value.value<QDBusArgument>();
    QString icon, title, sub;
    argument.beginStructure();
    argument >> icon;
    argument.beginArray();
    while (!argument.atEnd()) {
        int width = 0, height = 0;
        QByteArray data;
        argument.beginStructure();
        argument >> width >> height >> data;
        argument.endStructure();
    }
    argument.endArray();
    argument >> title >> sub;
    argument.endStructure();
    return sub;
}

// The first action a menu layout holds: (id, properties, children).
int firstAction(const QDBusArgument &layout) {
    int id = 0;
    QVariantMap properties;
    layout.beginStructure();
    layout >> id;
    layout >> properties;
    int found = -1;
    layout.beginArray();
    while (!layout.atEnd()) {
        QDBusVariant child;
        layout >> child;
        if (found < 0) found = firstAction(child.variant().value<QDBusArgument>());
    }
    layout.endArray();
    layout.endStructure();
    if (found >= 0) return found;
    const bool separator = properties.value(QStringLiteral("type")).toString() == QLatin1String("separator");
    return id != 0 && !separator && properties.value(QStringLiteral("enabled"), true).toBool() ? id : -1;
}
}

ScreenShareProvider::ScreenShareProvider(const QDBusConnection &bus, QObject *parent) : QObject(parent), m_bus(bus) {
    m_bus.connect(Watcher, WatcherPath, Watcher, QStringLiteral("StatusNotifierItemRegistered"), this, SLOT(registered(QString)));
    m_bus.connect(Watcher, WatcherPath, Watcher, QStringLiteral("StatusNotifierItemUnregistered"), this, SLOT(unregistered(QString)));
    // Any item's change: the portal's own are picked out by sender.
    for (const auto *signal : {"NewTitle", "NewToolTip", "NewStatus", "NewIcon"})
        m_bus.connect(QString(), QString(), ItemInterface, QString::fromLatin1(signal), this, SLOT(itemChanged(QDBusMessage)));
    load();
}

QPair<QString, QString> ScreenShareProvider::address(const QString &item) {
    const auto slash = item.indexOf(QLatin1Char('/'));
    if (slash < 0) return {item, QStringLiteral("/StatusNotifierItem")};
    return {item.left(slash), item.mid(slash)};
}

void ScreenShareProvider::load() {
    auto call = QDBusMessage::createMethodCall(Watcher, WatcherPath, Properties, QStringLiteral("Get"));
    call.setArguments({Watcher, QStringLiteral("RegisteredStatusNotifierItems")});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) return;
        for (const auto &item : reply.arguments().value(0).value<QDBusVariant>().variant().toStringList()) read(item);
    });
}

void ScreenShareProvider::registered(const QString &item) { read(item); }

void ScreenShareProvider::unregistered(const QString &item) {
    if (m_shares.remove(item)) Q_EMIT changed();
}

void ScreenShareProvider::itemChanged(const QDBusMessage &message) {
    for (auto it = m_shares.cbegin(); it != m_shares.cend(); ++it)
        if (it->service == message.service()) { read(it.key()); return; }
}

// Reads one item; the portal's while it is active is a share.
void ScreenShareProvider::read(const QString &item) {
    const auto [service, path] = address(item);
    auto call = QDBusMessage::createMethodCall(service, path, Properties, QStringLiteral("GetAll"));
    call.setArguments({ItemInterface});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, item, service, path] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        const auto properties = reply.type() == QDBusMessage::ReplyMessage ? Ambient::map(reply.arguments().value(0)) : QVariantMap();
        const bool share = properties.value(QStringLiteral("Id")).toString() == PortalId
            && properties.value(QStringLiteral("Status")).toString() != QLatin1String("Passive");
        if (!share) {
            if (m_shares.remove(item)) Q_EMIT changed();
            return;
        }
        auto &found = m_shares[item];
        if (!found.generation) found.generation = ++m_generation;
        found.item = item;
        found.service = reply.service().isEmpty() ? service : reply.service();
        found.path = path;
        found.menu = properties.value(QStringLiteral("Menu")).value<QDBusObjectPath>().path();
        found.icon = properties.value(QStringLiteral("IconName")).toString();
        found.who = subtitle(properties.value(QStringLiteral("ToolTip")));
        if (found.who.isEmpty()) found.who = properties.value(QStringLiteral("Title")).toString();
        Q_EMIT changed();
    });
}

QVariantList ScreenShareProvider::activities() const {
    QList<Share> shares = m_shares.values();
    std::sort(shares.begin(), shares.end(), [](const Share &a, const Share &b) { return a.generation < b.generation; });
    QVariantList rows;
    for (const auto &share : shares) {
        rows.append(QVariantMap{{QStringLiteral("id"), QString(Prefix + share.item)}, {QStringLiteral("generation"), share.generation},
            {QStringLiteral("kind"), QStringLiteral("screen")}, {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("title"), share.who}, {QStringLiteral("icon"), share.icon},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("stop"), !share.menu.isEmpty()}}}});
    }
    return rows;
}

// Stop: the menu's one action, End, as a click on it.
void ScreenShareProvider::invoke(const QString &id, int generation, const QString &action) {
    const auto found = m_shares.constFind(id.mid(Prefix.size()));
    if (!id.startsWith(Prefix) || found == m_shares.cend() || found->generation != generation
            || action != QLatin1String("stop") || found->menu.isEmpty()) return;
    const auto service = found->service, menu = found->menu;
    auto call = QDBusMessage::createMethodCall(service, menu, Menu, QStringLiteral("GetLayout"));
    call.setArguments({0, -1, QStringList{QStringLiteral("type"), QStringLiteral("enabled")}});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, service, menu] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) return;
        const int action = firstAction(reply.arguments().value(1).value<QDBusArgument>());
        if (action < 0) return;
        auto event = QDBusMessage::createMethodCall(service, menu, Menu, QStringLiteral("Event"));
        event.setArguments({action, QStringLiteral("clicked"), QVariant::fromValue(QDBusVariant(0)), 0u});
        m_bus.asyncCall(event);
    });
}
