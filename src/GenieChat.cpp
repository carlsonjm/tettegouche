/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "GenieChat.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace {

QDBusMessage method(const QString &name)
{
    return QDBusMessage::createMethodCall(QString::fromLatin1(GenieChat::Service),
        QString::fromLatin1(GenieChat::Path), QString::fromLatin1(GenieChat::Interface), name);
}

QVariant plain(const QVariant &value)
{
    if (value.canConvert<QDBusArgument>()) {
        const auto argument = value.value<QDBusArgument>();
        if (argument.currentType() == QDBusArgument::MapType) {
            QVariantMap map;
            argument >> map;
            for (auto it = map.begin(); it != map.end(); ++it) it.value() = plain(it.value());
            return map;
        }
        if (argument.currentType() == QDBusArgument::ArrayType) {
            QVariantList list;
            argument >> list;
            for (QVariant &item : list) item = plain(item);
            return list;
        }
    }
    if (value.canConvert<QDBusVariant>()) return plain(value.value<QDBusVariant>().variant());
    return value;
}

} // namespace

GenieChat::GenieChat(QObject *parent)
    : QObject(parent)
{
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                QStringLiteral("Changed"), this, SLOT(changedElsewhere(QVariantMap)));
    bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                QStringLiteral("WindowShown"), this, SLOT(shown(QString)));
    refresh();
}

void GenieChat::refresh()
{
    // Offered only where the assistant runs or the bus can start it, so a
    // computer without it never starts anything for Search's first screen.
    auto *bus = QDBusConnection::sessionBus().interface();
    const QString service = QString::fromLatin1(Service);
    const bool present = bus && (bus->isServiceRegistered(service).value()
        || bus->activatableServiceNames().value().contains(service));
    if (!present) {
        setAvailable(false);
        return;
    }
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("ProtocolVersion")), 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<uint> reply = *watcher;
        watcher->deleteLater();
        setAvailable(!reply.isError() && reply.value() == Version);
    });
}

void GenieChat::start()
{
    call(QStringLiteral("Start"));
}

void GenieChat::ask(const QString &question)
{
    if (question.trimmed().isEmpty()) return;
    call(QStringLiteral("Ask"), {question});
}

void GenieChat::cancel()
{
    call(QStringLiteral("Cancel"));
}

void GenieChat::act(const QString &action)
{
    call(QStringLiteral("Act"), {action});
}

bool GenieChat::openWindow(const QString &requestToken)
{
    if (!m_available) return false;
    QDBusMessage request = method(QStringLiteral("OpenWindow"));
    request.setArguments({requestToken});
    QDBusConnection::sessionBus().asyncCall(request, 5000);
    return true;
}

void GenieChat::call(const QString &name, const QVariantList &arguments)
{
    QDBusMessage request = method(name);
    request.setArguments(arguments);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, 10000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<QVariantMap> reply = *watcher;
        watcher->deleteLater();
        if (reply.isError()) {
            QVariantMap failed = m_state;
            failed.insert(QStringLiteral("problem"), reply.error().message());
            setState(failed);
            return;
        }
        setState(reply.value());
    });
}

void GenieChat::changedElsewhere(const QVariantMap &state)
{
    setState(state);
}

void GenieChat::shown(const QString &requestToken)
{
    Q_EMIT windowShown(requestToken);
}

void GenieChat::setAvailable(bool available)
{
    if (available == m_available) return;
    m_available = available;
    Q_EMIT availableChanged();
}

void GenieChat::setState(const QVariantMap &state)
{
    m_state = state;
    for (auto it = m_state.begin(); it != m_state.end(); ++it) it.value() = plain(it.value());
    Q_EMIT conversationChanged();
}
