/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "NotesIslandProvider.h"
#include "BusValue.h"
#include "NotesDoor.h"

#include <KIO/ApplicationLauncherJob>
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
using tettegouche::plainBusValue;

QString service() { return QString::fromLatin1(NotesIslandProvider::Service); }
QString path() { return QString::fromLatin1(NotesIslandProvider::Path); }
QString iface() { return QString::fromLatin1(NotesIslandProvider::Interface); }
QString stuckPath() { return QString::fromLatin1(NotesIslandProvider::StuckPath); }
QString stuckIface() { return QString::fromLatin1(NotesIslandProvider::StuckInterface); }

// Asked only of an application already running: the island never starts it.
QDBusMessage method(const QString &name)
{
    auto message = QDBusMessage::createMethodCall(service(), path(), iface(), name);
    message.setAutoStartService(false);
    return message;
}

QDBusMessage stuckMethod(const QString &name, const QVariantList &arguments = {})
{
    auto message = QDBusMessage::createMethodCall(service(), stuckPath(), stuckIface(), name);
    message.setArguments(arguments);
    message.setAutoStartService(false);
    return message;
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
    m_bus.connect(service(), stuckPath(), stuckIface(), QStringLiteral("WindowsChanged"), this,
                  SLOT(stuckChanged(QDBusMessage)));
    ask();
    askStuck();
}

void NotesIslandProvider::refresh()
{
    bool installed = false;
    // A test of the other islands leaves out a notes application the
    // machine running it may have.
    const bool leftOut = qEnvironmentVariableIsSet("TETTE_AMBIENT_WITHOUT_NOTES");
    if (const auto notes = leftOut ? KService::Ptr() : KService::serviceByStorageId(QString::fromLatin1(NotesDoor::ApplicationId))) {
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
    m_stuckSpeaks = false;
    m_toldShown = -1;
    setPinned({});
    setStuck({});
    if (!owner.isEmpty()) {
        ask();
        askStuck();
    }
}

// The version first, then every window's notes, and the island told.
void NotesIslandProvider::askStuck()
{
    if (!m_bus.isConnected()) return;
    const int generation = m_generation;
    auto *version = new QDBusPendingCallWatcher(m_bus.asyncCall(stuckMethod(QStringLiteral("ProtocolVersion")), 5000), this);
    connect(version, &QDBusPendingCallWatcher::finished, this, [this, version, generation] {
        const QDBusPendingReply<uint> number = *version;
        version->deleteLater();
        if (number.isError() || number.value() != Version || generation != m_generation) return;
        m_stuckSpeaks = true;
        tellShown(true);
        auto *windows = new QDBusPendingCallWatcher(m_bus.asyncCall(stuckMethod(QStringLiteral("Windows")), 5000), this);
        connect(windows, &QDBusPendingCallWatcher::finished, this, [this, windows, generation] {
            const QDBusMessage reply = windows->reply();
            windows->deleteLater();
            if (generation != m_generation || reply.type() != QDBusMessage::ReplyMessage) return;
            setStuck(plainBusValue(reply.arguments().value(0)).toList());
        });
    });
}

void NotesIslandProvider::stuckChanged(const QDBusMessage &message)
{
    if (!m_stuckSpeaks || (!m_owner.isEmpty() && message.service() != m_owner)) return;
    setStuck(plainBusValue(message.arguments().value(0)).toList());
}

void NotesIslandProvider::setStuck(const QVariantList &windows)
{
    const QVariantMap before = activeEntry();
    m_stuck = windows;
    if (activeEntry() != before && m_installed) Q_EMIT changed();
}

void NotesIslandProvider::setActiveWindowIds(const QStringList &given)
{
    // Plasma's window list and the compositor may write a UUID's letters in
    // either case.
    QStringList ids;
    for (const QString &id : given) ids.append(id.toLower());
    if (ids == m_activeIds) return;
    const QVariantMap before = activeEntry();
    m_activeIds = ids;
    if (activeEntry() != before && m_installed) Q_EMIT changed();
}

QVariantMap NotesIslandProvider::activeEntry() const
{
    if (m_activeIds.isEmpty()) return {};
    for (const QVariant &value : m_stuck) {
        const QVariantMap entry = value.toMap();
        const QVariantList ids = entry.value(QStringLiteral("windowIds")).toList();
        for (const QVariant &id : ids) {
            if (m_activeIds.contains(id.toString().toLower()) && entry.value(QStringLiteral("count")).toInt() > 0)
                return entry;
        }
    }
    return {};
}

void NotesIslandProvider::setShownBy(const void *panel, bool shown)
{
    if (shown) m_shownBy.insert(panel);
    else m_shownBy.remove(panel);
    tellShown(false);
}

// Folded notes are left to the island while a panel shows it; the
// application forgets it once the panel leaves the bus.
void NotesIslandProvider::tellShown(bool always)
{
    const int shown = m_shownBy.isEmpty() ? 0 : 1;
    if (!m_stuckSpeaks || (!always && shown == m_toldShown)) return;
    m_toldShown = shown;
    m_bus.send(stuckMethod(QStringLiteral("DrawFolded"), {bool(shown)}));
}

void NotesIslandProvider::toggleWindowNotes()
{
    const QVariantMap entry = activeEntry();
    if (entry.isEmpty() || !m_stuckSpeaks) return;
    // The window is named by the id it is in use by, as the application
    // finds it; its title and application are left empty.
    QString id;
    for (const QVariant &value : entry.value(QStringLiteral("windowIds")).toList()) {
        if (m_activeIds.contains(value.toString().toLower())) {
            id = value.toString();
            break;
        }
    }
    const bool up = entry.value(QStringLiteral("shown")).toBool() && !entry.value(QStringLiteral("folded")).toBool();
    m_bus.send(stuckMethod(up ? QStringLiteral("Toggle") : QStringLiteral("Show"), {id, QString(), QString()}));
}

namespace
{
// The application's Capture action, where it is installed and not left out
// for a test of the other islands.
KServiceAction captureAction()
{
    if (qEnvironmentVariableIsSet("TETTE_AMBIENT_WITHOUT_NOTES")) return {};
    if (const auto notes = KService::serviceByStorageId(QString::fromLatin1(NotesDoor::ApplicationId))) {
        const auto actions = notes->actions();
        for (const KServiceAction &action : actions) {
            if (action.name() == QLatin1String(NotesDoor::ActionName)) return action;
        }
    }
    return {};
}

void runCapture(const KServiceAction &capture, QObject *parent)
{
    auto *job = new KIO::ApplicationLauncherJob(capture, parent);
    job->start();
}
} // namespace

bool NotesIslandProvider::openOnCard(const QString &noteId, QObject *parent)
{
    const KServiceAction capture = captureAction();
    if (capture.name().isEmpty()) return false;
    if (noteId.isEmpty()) {
        runCapture(capture, parent);
        return true;
    }
    // The pinned note shows only while the application runs, so it answers;
    // a note gone since, or an answer that never comes, starts a new one.
    auto request = QDBusMessage::createMethodCall(service(), path(), iface(), QStringLiteral("OpenNote"));
    request.setArguments({noteId});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, 5000), parent);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, parent, [watcher, capture, parent] {
        const QDBusPendingReply<bool> opened = *watcher;
        watcher->deleteLater();
        if (opened.isError() || !opened.value()) runCapture(capture, parent);
    });
    return true;
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
            setPinned(reply.type() == QDBusMessage::ReplyMessage ? plainBusValue(reply.arguments().value(0)).toMap()
                                                                 : QVariantMap());
        });
    });
}

void NotesIslandProvider::pinnedChanged(const QVariantMap &pinned, const QDBusMessage &message)
{
    if (!m_speaks || (!m_owner.isEmpty() && message.service() != m_owner)) return;
    QVariantMap note = pinned;
    for (auto it = note.begin(); it != note.end(); ++it) it.value() = plainBusValue(it.value());
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
    // The window in use's notes, while it has any that are not tucked away.
    const QVariantMap entry = activeEntry();
    if (!entry.isEmpty()) {
        row.insert(QStringLiteral("windowCount"), entry.value(QStringLiteral("count")).toInt());
        row.insert(QStringLiteral("windowColourHex"), entry.value(QStringLiteral("colourHex")).toString());
        row.insert(QStringLiteral("windowShown"), entry.value(QStringLiteral("shown")).toBool()
                                                      && !entry.value(QStringLiteral("folded")).toBool());
        row.insert(QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("windowNotes"), true}});
    }
    return {row};
}
