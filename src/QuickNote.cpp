/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "QuickNote.h"
#include "BusValue.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace {

using tettegouche::plainBusValue;

QDBusMessage method(const QString &name)
{
    return QDBusMessage::createMethodCall(QString::fromLatin1(QuickNote::Service),
        QString::fromLatin1(QuickNote::Path), QString::fromLatin1(QuickNote::Interface), name);
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
    bus.connect(QString::fromLatin1(Service), QString::fromLatin1(Path), QString::fromLatin1(Interface),
                QStringLiteral("Back"), this, SIGNAL(backRequested()));
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

void QuickNote::setFolder(const QString &name)
{
    flush();
    call(QStringLiteral("SetFolder"), {name});
}

void QuickNote::setStuck(const QString &window, const QString &app)
{
    flush();
    call(QStringLiteral("SetStuck"), {window, app});
}

void QuickNote::setReminder(const QString &when)
{
    flush();
    call(QStringLiteral("SetReminder"), {when});
}

void QuickNote::setChecklist(bool on)
{
    flush();
    call(QStringLiteral("SetChecklist"), {on});
}

void QuickNote::setLineChecked(int line, bool checked)
{
    if (line < 0) return;
    flush();
    call(QStringLiteral("SetLineChecked"), {uint(line), checked});
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

void QuickNote::setPinned(bool on)
{
    flush();
    call(QStringLiteral("SetPinned"), {on});
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

void QuickNote::findNotes(const QString &words)
{
    const quint64 serial = ++m_findSerial;
    QDBusMessage request = method(QStringLiteral("Find"));
    request.setArguments({words, uint(0)});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, serial, words] {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();
        if (serial != m_findSerial) return;
        m_notes = reply.type() == QDBusMessage::ReplyMessage ? plainBusValue(reply.arguments().value(0)).toList()
                                                             : QVariantList();
        m_notesWords = words;
        Q_EMIT notesChanged();
    });
}

void QuickNote::edit(const QString &noteId)
{
    flush();
    call(QStringLiteral("Edit"), {noteId});
}

void QuickNote::startWith(const QString &text)
{
    flush();
    call(QStringLiteral("Done"));
    call(QStringLiteral("Start"));
    if (!text.isEmpty()) call(QStringLiteral("SetText"), {text});
}

void QuickNote::openOnCard(const QString &noteId, const QString &back)
{
    askCard({{QStringLiteral("id"), noteId}, {QStringLiteral("back"), back}});
}

void QuickNote::startOnCard(const QString &text, const QString &back)
{
    askCard({{QStringLiteral("text"), text}, {QStringLiteral("back"), back}});
}

void QuickNote::askCard(const QVariantMap &request)
{
    flush();
    QDBusMessage message = method(QStringLiteral("OpenOnCard"));
    message.setArguments({request});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, request] {
        const QDBusPendingReply<bool> opened = *watcher;
        watcher->deleteLater();
        const QString noteId = request.value(QStringLiteral("id")).toString();
        if (opened.isError() && opened.error().type() == QDBusError::UnknownMethod && !noteId.isEmpty()) {
            // A Gooseberry of Milestone 4 opens a kept note on its card, with
            // no way back.
            QDBusMessage older = method(QStringLiteral("OpenNote"));
            older.setArguments({noteId});
            auto *again = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(older, 5000), this);
            connect(again, &QDBusPendingCallWatcher::finished, this, [this, again] {
                const QDBusPendingReply<bool> reply = *again;
                again->deleteLater();
                Q_EMIT cardAnswered(!reply.isError() && reply.value());
            });
            return;
        }
        Q_EMIT cardAnswered(!opened.isError() && opened.value());
    });
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
    for (auto it = m_state.begin(); it != m_state.end(); ++it) it.value() = plainBusValue(it.value());
    Q_EMIT noteChanged();
}
