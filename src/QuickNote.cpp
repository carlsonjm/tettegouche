/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "QuickNote.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace {

QDBusMessage method(const QString &name)
{
    return QDBusMessage::createMethodCall(QString::fromLatin1(QuickNote::Service),
        QString::fromLatin1(QuickNote::Path), QString::fromLatin1(QuickNote::Interface), name);
}

// A dictionary inside a variant list arrives as a bus argument; QML wants it
// as a plain map.
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

QuickNote::QuickNote(QObject *parent)
    : QObject(parent)
{
    m_pause.setSingleShot(true);
    m_pause.setInterval(PauseMs);
    connect(&m_pause, &QTimer::timeout, this, &QuickNote::flush);
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                QStringLiteral("Changed"), this, SLOT(changedElsewhere(QVariantMap)));
    bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                QStringLiteral("BoardShown"), this, SLOT(shown(QString)));
    refresh();
}

QuickNote::~QuickNote()
{
    // Search may close within a pause of the last letter; that typing is
    // written before it goes.
    if (!m_hasPending) return;
    QDBusMessage request = method(QStringLiteral("SetText"));
    request.setArguments({m_pending});
    QDBusConnection::sessionBus().call(request, QDBus::Block, 1000);
}

QString QuickNote::colourHex() const
{
    const int at = colours().indexOf(colour());
    const QStringList hexes = colourHexes();
    return at >= 0 && at < hexes.size() ? hexes.at(at) : QString();
}

QVariantList QuickNote::choices() const
{
    return m_state.value(QStringLiteral("choices")).toList();
}

void QuickNote::refresh()
{
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(method(QStringLiteral("ProtocolVersion")), 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<uint> reply = *watcher;
        watcher->deleteLater();
        const bool available = !reply.isError() && reply.value() == Version;
        if (available != m_available) {
            m_available = available;
            Q_EMIT availableChanged();
        }
    });
}

void QuickNote::start()
{
    call(QStringLiteral("Start"));
}

void QuickNote::setText(const QString &text)
{
    if (!m_hasPending) m_waiting.start();
    m_pending = text;
    m_hasPending = true;
    if (m_waiting.elapsed() >= LongestWaitMs) {
        flush();
        return;
    }
    m_pause.start();
}

void QuickNote::flush()
{
    m_pause.stop();
    if (!m_hasPending) return;
    m_hasPending = false;
    call(QStringLiteral("SetText"), {m_pending});
}

void QuickNote::setColour(const QString &name)
{
    flush();
    call(QStringLiteral("SetColour"), {name});
}

void QuickNote::setBelongs(const QString &kind, const QString &project)
{
    flush();
    call(QStringLiteral("SetBelongs"), {kind, project});
}

void QuickNote::done()
{
    flush();
    call(QStringLiteral("Done"));
}

void QuickNote::tuckAway()
{
    flush();
    call(QStringLiteral("TuckAway"));
}

void QuickNote::remove()
{
    flush();
    call(QStringLiteral("Remove"));
}

bool QuickNote::openBoard(const QString &requestToken)
{
    if (!m_available) return false;
    flush();
    QDBusMessage request = method(QStringLiteral("OpenBoard"));
    request.setArguments({noteId(), requestToken});
    QDBusConnection::sessionBus().asyncCall(request, 5000);
    return true;
}

void QuickNote::call(const QString &name, const QVariantList &arguments)
{
    QDBusMessage request = method(name);
    request.setArguments(arguments);
    take(QDBusConnection::sessionBus().asyncCall(request, 5000));
}

void QuickNote::take(const QDBusPendingCall &call)
{
    auto *watcher = new QDBusPendingCallWatcher(call, this);
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

void QuickNote::changedElsewhere(const QVariantMap &state)
{
    // Typing waiting here is newer than what the application last kept.
    if (m_hasPending) return;
    setState(state);
}

void QuickNote::shown(const QString &requestToken)
{
    Q_EMIT boardShown(requestToken);
}

void QuickNote::setState(const QVariantMap &state)
{
    m_state = state;
    for (auto it = m_state.begin(); it != m_state.end(); ++it) it.value() = plain(it.value());
    Q_EMIT noteChanged();
}
