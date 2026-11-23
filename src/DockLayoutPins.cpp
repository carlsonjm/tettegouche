/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "DockLayoutPins.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>

namespace {
QString service() { return QString::fromLatin1(DockLayoutPins::Service); }
QString path() { return QString::fromLatin1(DockLayoutPins::Path); }
QString iface() { return QString::fromLatin1(DockLayoutPins::Interface); }
}

DockLayoutPins::DockLayoutPins(const QDBusConnection &bus, QObject *parent) : QObject(parent), m_bus(bus) {
    auto *watcher = new QDBusServiceWatcher(service(), m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this](const QString &, const QString &, const QString &owner) { ownerChanged(owner); });
    m_bus.connect(service(), path(), iface(), QStringLiteral("pinnedLayoutsChanged"), this,
                  SLOT(pinnedMoved(QDBusMessage)));
    m_bus.connect(service(), path(), iface(), QStringLiteral("layoutsRequested"), this,
                  SLOT(layoutsAsked(QString,QDBusMessage)));
    ask();
}

void DockLayoutPins::ownerChanged(const QString &owner) {
    m_owner = owner;
    ++m_generation;
    if (owner.isEmpty()) {
        if (!m_present && m_pinned.isEmpty()) return;
        m_present = false;
        m_pinned.clear();
        Q_EMIT changed();
        return;
    }
    ask();
}

void DockLayoutPins::ask() {
    const quint64 generation = ++m_generation;
    auto *watcher = new QDBusPendingCallWatcher(
        m_bus.asyncCall(QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("pinnedLayouts")), 2000),
        this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation] {
        watcher->deleteLater();
        if (generation != m_generation) return;
        const QDBusPendingReply<QStringList> reply = *watcher;
        // A dock from before layouts could be pinned answers with an error:
        // nothing to pin to.
        const bool present = !reply.isError();
        const QStringList pinned = present ? reply.value() : QStringList();
        if (present == m_present && pinned == m_pinned) return;
        m_present = present;
        m_pinned = pinned;
        Q_EMIT changed();
    });
}

void DockLayoutPins::pinnedMoved(const QDBusMessage &message) {
    if (!m_owner.isEmpty() && message.service() != m_owner) return;
    ask();
}

void DockLayoutPins::layoutsAsked(const QString &output, const QDBusMessage &message) {
    if (!m_owner.isEmpty() && message.service() != m_owner) return;
    Q_EMIT layoutsRequested(output);
}

void DockLayoutPins::pin(const QString &id, bool pin) {
    if (!m_present || id.isEmpty() || m_pinned.contains(id) == pin) return;
    auto request = QDBusMessage::createMethodCall(service(), path(), iface(),
                                                  pin ? QStringLiteral("pinLayout") : QStringLiteral("unpinLayout"));
    request << id;
    // Said in the journal, so a pin that does not reach the dock is found; a
    // dock that refuses is asked again what it holds.
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(request, 2000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, id, pin] {
        const QDBusPendingReply<bool> reply = *watcher; watcher->deleteLater();
        if (reply.isError()) qInfo() << "Tettegouche: the dock did not take" << (pin ? "pin" : "unpin") << "of layout" << id << reply.error().message();
        else qInfo() << "Tettegouche: the dock" << (reply.value() ? "took" : "refused") << (pin ? "pin" : "unpin") << "of layout" << id;
        if (reply.isError() || !reply.value()) ask();
    });
    if (pin) m_pinned.append(id);
    else m_pinned.removeAll(id);
    Q_EMIT changed();
}
