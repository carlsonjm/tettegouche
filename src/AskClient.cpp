/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "AskClient.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QRegularExpression>

namespace {
QString service()
{
    return QString::fromLatin1(AskClient::Service);
}
QString path()
{
    return QString::fromLatin1(AskClient::Path);
}
QString iface()
{
    return QString::fromLatin1(AskClient::Interface);
}
}

AskClient::AskClient(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
{
    m_pause.setSingleShot(true);
    m_pause.setInterval(700);
    connect(&m_pause, &QTimer::timeout, this, &AskClient::send);
    if (!m_bus.isConnected()) return;
    m_bus.connect(service(), path(), iface(), QStringLiteral("Said"), this, SLOT(said(uint, QString)));
    m_bus.connect(service(), path(), iface(), QStringLiteral("Answered"), this, SLOT(answered(uint, QVariantMap)));
    m_bus.connect(service(), path(), iface(), QStringLiteral("ModelChanged"), this, SLOT(modelChanged(QVariantMap)));
    auto *watcher = new QDBusServiceWatcher(service(), m_bus, QDBusServiceWatcher::WatchForRegistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
        if (!m_available) {
            m_available = true;
            Q_EMIT availableChanged();
        }
    });
    look();
}

// Ask is installed where the bus can start it; it need not be running.
void AskClient::look()
{
    auto *names = new QDBusPendingCallWatcher(
        m_bus.asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"),
                            QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
                            QStringLiteral("ListActivatableNames")),
            5000),
        this);
    connect(names, &QDBusPendingCallWatcher::finished, this, [this, names] {
        const QDBusPendingReply<QStringList> reply = *names;
        names->deleteLater();
        const bool here = !reply.isError()
            && (reply.value().contains(service()) || m_bus.interface()->isServiceRegistered(service()).value());
        if (here != m_available) {
            m_available = here;
            Q_EMIT availableChanged();
        }
    });
}

bool AskClient::readsAsQuestion(const QString &text)
{
    const QString words = text.simplified();
    if (words.endsWith(QLatin1Char('?')) && words.size() > 2) return true;
    return words.split(QLatin1Char(' '), Qt::SkipEmptyParts).size() >= 3;
}

void AskClient::type(const QString &text)
{
    m_typed = text.simplified();
    if (m_typed.isEmpty()) {
        m_declined = false;
        clear();
        return;
    }
    if (!m_available || !readsAsQuestion(m_typed)) {
        m_pause.stop();
        if (m_state != QLatin1String("downloading")) clear();
        return;
    }
    if (m_typed == m_question) return;
    m_pause.start();
}

void AskClient::askNow()
{
    m_pause.stop();
    if (m_available && !m_typed.isEmpty() && m_typed != m_question) send();
}

void AskClient::send()
{
    if (m_typed.isEmpty()) return;
    if (m_id != 0)
        m_bus.asyncCall(QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Cancel")) << m_id);
    m_question = m_typed;
    m_text.clear();
    m_who.clear();
    m_helpers.clear();
    m_query.clear();
    m_id = 0;
    m_sending = true;
    if (m_state != QLatin1String("downloading"))
        setState(QStringLiteral("asking"));
    else
        Q_EMIT changed();
    const QString asked = m_question;
    auto *call = new QDBusPendingCallWatcher(
        m_bus.asyncCall(
            QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Ask")) << asked, 10000),
        this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this, call, asked] {
        const QDBusPendingReply<uint> reply = *call;
        call->deleteLater();
        if (asked != m_question) return;
        m_sending = false;
        if (reply.isError()) {
            setState(QStringLiteral("problem"));
            return;
        }
        m_id = reply.value();
    });
}

void AskClient::clear()
{
    m_pause.stop();
    if (m_id != 0)
        m_bus.asyncCall(QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("Cancel")) << m_id);
    m_id = 0;
    m_sending = false;
    m_question.clear();
    m_text.clear();
    m_who.clear();
    m_helpers.clear();
    m_query.clear();
    setState(m_state == QLatin1String("downloading") ? m_state : QStringLiteral("idle"));
}

void AskClient::download()
{
    m_bus.asyncCall(QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("DownloadModel")));
    m_progress = 0;
    setState(QStringLiteral("downloading"));
}

void AskClient::notNow()
{
    m_declined = true;
    m_text.clear();
    setState(QStringLiteral("idle"));
}

void AskClient::said(uint id, const QString &text)
{
    // Words for a question this Search sent; the id may not have come back yet.
    if (id != m_id && !(m_sending && m_id == 0)) return;
    if (m_id == 0) m_id = id;
    m_text += text;
    if (m_state != QLatin1String("downloading")) m_state = QStringLiteral("asking");
    Q_EMIT changed();
}

void AskClient::answered(uint id, const QVariantMap &result)
{
    if (id != m_id && !(m_sending && m_id == 0)) return;
    m_id = 0;
    m_sending = false;
    if (result.value(QStringLiteral("cancelled")).toBool()) return;
    m_text = result.value(QStringLiteral("text")).toString();
    m_who = result.value(QStringLiteral("who")).toString();
    m_helpers = result.value(QStringLiteral("helpers")).toStringList();
    m_query = result.value(QStringLiteral("query")).toString();
    if (result.value(QStringLiteral("off")).toBool())
        setState(QStringLiteral("off"));
    else if (result.value(QStringLiteral("needsModel")).toBool())
        setState(m_declined ? QStringLiteral("idle") : QStringLiteral("needsModel"));
    else if (!result.value(QStringLiteral("problem")).toString().isEmpty())
        setState(QStringLiteral("problem"));
    else
        setState(QStringLiteral("answered"));
}

void AskClient::modelChanged(const QVariantMap &model)
{
    const QString state = model.value(QStringLiteral("state")).toString();
    m_progress = model.value(QStringLiteral("progress")).toDouble();
    m_size = model.value(QStringLiteral("size")).toString();
    if (state == QLatin1String("downloading") || state == QLatin1String("verifying")) {
        setState(QStringLiteral("downloading"));
        return;
    }
    if (m_state != QLatin1String("downloading")) {
        Q_EMIT changed();
        return;
    }
    // The download ended: the question asked meanwhile is answered now.
    if (state == QLatin1String("ready") && !m_question.isEmpty()) {
        m_state = QStringLiteral("asking");
        const QString again = m_question;
        m_question.clear();
        m_typed = again;
        send();
        return;
    }
    setState(state == QLatin1String("failed") ? QStringLiteral("problem") : QStringLiteral("idle"));
}

void AskClient::setState(const QString &state)
{
    m_state = state;
    Q_EMIT changed();
}
