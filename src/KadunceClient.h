/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QString>
#include <QVariantList>

// Kadunce's interface, which it serves on KWin's name. Every call Search makes
// to Kadunce is built here, so the service, path and interface are named once.
namespace Kadunce
{
inline QString service() { return QStringLiteral("org.kde.KWin"); }
inline QString path() { return QStringLiteral("/Kadunce"); }
inline QString interface() { return QStringLiteral("co.goodinput.Kadunce"); }

inline QDBusMessage method(const QString &name, const QVariantList &arguments = {})
{
    QDBusMessage request = QDBusMessage::createMethodCall(service(), path(), interface(), name);
    request.setArguments(arguments);
    return request;
}

// Waits for Kadunce's answer, at most `timeout` milliseconds.
inline QDBusMessage call(const QString &name, const QVariantList &arguments, int timeout)
{
    return QDBusConnection::sessionBus().call(method(name, arguments), QDBus::Block, timeout);
}

// Asks without waiting; the answer comes to whoever watches the call.
inline QDBusPendingCall ask(const QString &name, const QVariantList &arguments = {}, int timeout = -1)
{
    return QDBusConnection::sessionBus().asyncCall(method(name, arguments), timeout);
}

// Tells Kadunce something that needs no answer.
inline void tell(const QString &name, const QVariantList &arguments = {})
{
    QDBusConnection::sessionBus().asyncCall(method(name, arguments));
}

// Follows one of Kadunce's signals.
inline bool follow(const QString &signal, QObject *receiver, const char *slot)
{
    return QDBusConnection::sessionBus().connect(service(), path(), interface(), signal, receiver, slot);
}
}
