/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "NotesIslandProvider.h"
#include "NotesDoor.h"

#include <KService>
#include <KSycoca>

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>

#include <algorithm>

namespace
{
QString service() { return QString::fromLatin1(NotesIslandProvider::Service); }
QString path() { return QString::fromLatin1(NotesIslandProvider::Path); }
QString iface() { return QString::fromLatin1(NotesIslandProvider::Interface); }

// Asked only of an application already running: the island never starts it.
QDBusMessage method(const QString &name)
{
    auto message = QDBusMessage::createMethodCall(service(), path(), iface(), name);
    message.setAutoStartService(false);
    return message;
}

// A dictionary inside a variant arrives as a bus argument; the row wants it
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

NotesIslandProvider::NotesIslandProvider(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
{
    // Installed or removed while the panel runs, the island follows.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &NotesIslandProvider::refresh);
    refresh();
    if (!m_bus.isConnected()) return;
    auto *watcher = new QDBusServiceWatcher(service(), m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &NotesIslandProvider::ownerChanged);
    m_bus.connect(service(), path(), iface(), QStringLiteral("PinnedChanged"), this,
                  SLOT(pinnedChanged(QVariantMap,QDBusMessage)));
    ask();
}

void NotesIslandProvider::refresh()
{
    bool installed = false;
    if (const auto notes = KService::serviceByStorageId(QString::fromLatin1(NotesDoor::ApplicationId))) {
        const auto actions = notes->actions();
        installed = std::any_of(actions.cbegin(), actions.cend(), [](const KServiceAction &action) {
            return action.name() == QLatin1String(NotesDoor::ActionName);
        });
    }
    if (installed == m_installed) return;
    m_installed = installed;
    Q_EMIT changed();
}

void NotesIslandProvider::ownerChanged(const QString &name, const QString &, const QString &owner)
{
    if (name != service()) return;
    ++m_generation;
    m_owner = owner;
    m_speaks = false;
    setPinned({});
    if (!owner.isEmpty()) ask();
}

// The version first: an application that speaks another one is left alone.
void NotesIslandProvider::ask()
{
    const int generation = m_generation;
    auto *version = new QDBusPendingCallWatcher(m_bus.asyncCall(method(QStringLiteral("ProtocolVersion")), 5000), this);
    connect(version, &QDBusPendingCallWatcher::finished, this, [this, version, generation] {
        const QDBusPendingReply<uint> number = *version;
        const QString owner = version->reply().service();
        version->deleteLater();
        if (number.isError() || number.value() != Version || generation != m_generation) return;
        if (m_owner.isEmpty()) m_owner = owner;
        m_speaks = true;
        auto *pinned = new QDBusPendingCallWatcher(m_bus.asyncCall(method(QStringLiteral("Pinned")), 5000), this);
        connect(pinned, &QDBusPendingCallWatcher::finished, this, [this, pinned, generation] {
            const QDBusMessage reply = pinned->reply();
            pinned->deleteLater();
            if (generation != m_generation) return;
            // An application without Pinned answers with an error: no pinned note.
            setPinned(reply.type() == QDBusMessage::ReplyMessage ? plain(reply.arguments().value(0)).toMap()
                                                                 : QVariantMap());
        });
    });
}

void NotesIslandProvider::pinnedChanged(const QVariantMap &pinned, const QDBusMessage &message)
{
    if (!m_speaks || (!m_owner.isEmpty() && message.service() != m_owner)) return;
    QVariantMap note = pinned;
    for (auto it = note.begin(); it != note.end(); ++it) it.value() = plain(it.value());
    setPinned(note);
}

void NotesIslandProvider::setPinned(const QVariantMap &pinned)
{
    // A note is pinned only by its id; an empty dictionary is none.
    QVariantMap note;
    if (!pinned.value(QStringLiteral("id")).toString().isEmpty()) {
        for (const auto &key : {QStringLiteral("id"), QStringLiteral("title"), QStringLiteral("colour"),
                               QStringLiteral("colourHex")})
            note.insert(key, pinned.value(key).toString());
    }
    if (note == m_pinned) return;
    m_pinned = note;
    if (m_installed) Q_EMIT changed();
}

QVariantList NotesIslandProvider::activities() const
{
    if (!m_installed) return {};
    QVariantMap row{{QStringLiteral("id"), QString::fromLatin1(Id)}, {QStringLiteral("generation"), m_generation},
                    {QStringLiteral("kind"), QStringLiteral("note")}, {QStringLiteral("state"), QStringLiteral("running")},
                    {QStringLiteral("capabilities"), QVariantMap{}}};
    if (!m_pinned.isEmpty()) {
        row.insert(QStringLiteral("noteId"), m_pinned.value(QStringLiteral("id")));
        row.insert(QStringLiteral("title"), m_pinned.value(QStringLiteral("title")));
        row.insert(QStringLiteral("colourHex"), m_pinned.value(QStringLiteral("colourHex")));
    }
    return {row};
}
