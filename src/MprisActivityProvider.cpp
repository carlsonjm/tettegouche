#include "MprisActivityProvider.h"
#include "ActivityUtils.h"
#include <QFile>
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusMessage>

namespace {
const QString path = QStringLiteral("/org/mpris/MediaPlayer2");
const QString playerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString rootInterface = QStringLiteral("org.mpris.MediaPlayer2");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");
}

class MprisSession : public QObject {
    Q_OBJECT
public:
    MprisSession(QDBusConnection bus, QString name, QString owner, int generation, QObject *parent)
        : QObject(parent), bus(bus), name(name), owner(owner), generation(generation) {
        bus.connect(owner, path, propertiesInterface, QStringLiteral("PropertiesChanged"), this,
                    SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
        bus.connect(owner, path, playerInterface, QStringLiteral("Seeked"), this, SLOT(seeked(qlonglong)));
        fetch(rootInterface); fetch(playerInterface);
    }
    QVariantMap activity() const {
        const QString status = player.value(QStringLiteral("PlaybackStatus")).toString();
        const bool control = player.value(QStringLiteral("CanControl")).toBool();
        if (status != QLatin1String("Playing") && !(status == QLatin1String("Paused")
                && control && player.value(QStringLiteral("CanPlay")).toBool())) return {};
        const auto meta = Ambient::map(player.value(QStringLiteral("Metadata")));
        QVariantMap row{{QStringLiteral("id"), name}, {QStringLiteral("generation"), generation}, {QStringLiteral("kind"), QStringLiteral("media")},
            {QStringLiteral("state"), status == QLatin1String("Playing") ? QStringLiteral("playing") : QStringLiteral("paused")},
            {QStringLiteral("source"), root.value(QStringLiteral("Identity"), QStringLiteral("Media"))},
            {QStringLiteral("icon"), root.value(QStringLiteral("DesktopEntry"), QStringLiteral("audio-x-generic-symbolic"))},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("play"), control && player.value(QStringLiteral("CanPlay")).toBool()},
                {QStringLiteral("pause"), control && player.value(QStringLiteral("CanPause")).toBool()},
                {QStringLiteral("previous"), control && player.value(QStringLiteral("CanGoPrevious")).toBool()},
                {QStringLiteral("next"), control && player.value(QStringLiteral("CanGoNext")).toBool()},
                {QStringLiteral("seek"), control && player.value(QStringLiteral("CanSeek")).toBool()}}}};
        if (!meta.value(QStringLiteral("xesam:title")).toString().isEmpty()) row[QStringLiteral("title")] = meta.value(QStringLiteral("xesam:title"));
        const auto artists = qdbus_cast<QStringList>(meta.value(QStringLiteral("xesam:artist")));
        if (!artists.isEmpty()) row[QStringLiteral("artist")] = artists.join(QStringLiteral(", "));
        if (meta.value(QStringLiteral("mpris:length")).toLongLong() > 0) row[QStringLiteral("durationUs")] = meta.value(QStringLiteral("mpris:length")).toLongLong();
        if (positionKnown) {
            row[QStringLiteral("positionUs")] = position; row[QStringLiteral("sampledAtMonotonicUs")] = sampleTime;
            row[QStringLiteral("rate")] = player.value(QStringLiteral("Rate"), 1.0);
        }
        return row;
    }
    void invoke(const QString &action) {
        if (!activity().value(QStringLiteral("capabilities")).toMap().value(action).toBool()) return;
        // Resolve the well-known name before dispatch; a stale owner must never receive a UI action.
        auto *check = new QDBusPendingCallWatcher(bus.interface()->asyncCall(
            QStringLiteral("GetNameOwner"), name), this);
        connect(check, &QDBusPendingCallWatcher::finished, this, [this, check, action] {
            const QDBusPendingReply<QString> reply = *check; check->deleteLater();
            if (reply.isError() || reply.value() != owner
                    || !activity().value(QStringLiteral("capabilities")).toMap().value(action).toBool()) return;
            static const QMap<QString, QString> methods{{QStringLiteral("play"),QStringLiteral("Play")},{QStringLiteral("pause"),QStringLiteral("Pause")},
                {QStringLiteral("previous"),QStringLiteral("Previous")},{QStringLiteral("next"),QStringLiteral("Next")},{QStringLiteral("seek"),QStringLiteral("Seek")}};
            auto call = QDBusMessage::createMethodCall(owner, path, playerInterface, methods.value(action));
            if (action == QLatin1String("seek")) call.setArguments({qlonglong(10000000)});
            bus.asyncCall(call);
        });
    }
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void propertiesChanged(const QString &iface, const QVariantMap &values, const QStringList &invalid) {
        if (iface != rootInterface && iface != playerInterface) return;
        auto &target = iface == playerInterface ? player : root;
        if (iface == playerInterface) advance();
        for (auto it = values.cbegin(); it != values.cend(); ++it) {
            revisions[iface + it.key()] = ++revision; target[it.key()] = it.value();
        }
        for (const auto &key : invalid) { revisions[iface + key] = ++revision; target.remove(key); }
        if (iface == playerInterface && (values.contains(QStringLiteral("Metadata")) || invalid.contains(QStringLiteral("Metadata")))) {
            positionKnown = false;
            revisions[playerInterface + QStringLiteral("Position")] = ++revision;
            fetch(playerInterface);
        }
        if (values.contains(QStringLiteral("Position"))) setPosition(values.value(QStringLiteral("Position")).toLongLong());
        if (invalid.contains(QStringLiteral("Position"))) positionKnown = false;
        if (!invalid.isEmpty()) fetch(iface);
        Q_EMIT changed();
    }
    void seeked(qlonglong value) {
        revisions[playerInterface + QStringLiteral("Position")] = ++revision;
        setPosition(value); Q_EMIT changed();
    }
private:
    void setPosition(qint64 value) { position = qMax(qint64(0),value); sampleTime = Ambient::nowUs(); positionKnown = true; }
    void advance() {
        const auto now = Ambient::nowUs();
        if (positionKnown && player.value(QStringLiteral("PlaybackStatus")) == QLatin1String("Playing"))
            position += qint64((now - sampleTime) * player.value(QStringLiteral("Rate"), 1.0).toDouble());
        sampleTime = now;
    }
    void fetch(const QString &iface) {
        const auto sentRevision = revision;
        auto call = QDBusMessage::createMethodCall(owner, path, propertiesInterface, QStringLiteral("GetAll"));
        call.setArguments({iface});
        auto *pending = new QDBusPendingCallWatcher(bus.asyncCall(call), this);
        connect(pending, &QDBusPendingCallWatcher::finished, this, [this, pending, iface, sentRevision] {
            const QDBusPendingReply<QVariantMap> reply = *pending; pending->deleteLater();
            if (reply.isError()) return;
            auto &target = iface == playerInterface ? player : root;
            advance();
            const auto values = reply.value();
            for (auto it = values.cbegin(); it != values.cend(); ++it) {
                if (revisions.value(iface + it.key()) > sentRevision) continue;
                target[it.key()] = it.value();
                if (iface == playerInterface && it.key() == QLatin1String("Position")) setPosition(it.value().toLongLong());
            }
            Q_EMIT changed();
        });
    }
    QDBusConnection bus;
    QString name, owner;
    int generation;
    QVariantMap root, player;
    QMap<QString, quint64> revisions;
    quint64 revision = 0;
    qint64 position = 0, sampleTime = 0;
    bool positionKnown = false;
};

MprisActivityProvider::MprisActivityProvider(const QDBusConnection &bus, QObject *parent)
    : QObject(parent), m_bus(bus) {
    connect(bus.interface(), &QDBusConnectionInterface::serviceOwnerChanged,
            this, &MprisActivityProvider::ownerChanged);
    auto *pending = new QDBusPendingCallWatcher(bus.interface()->asyncCall(QStringLiteral("ListNames")), this);
    connect(pending, &QDBusPendingCallWatcher::finished, this, [this, pending] {
        const QDBusPendingReply<QStringList> reply = *pending; pending->deleteLater();
        if (reply.isError()) return;
        for (const auto &name : reply.value()) {
            if (!name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) continue;
            auto *lookup = new QDBusPendingCallWatcher(m_bus.interface()->asyncCall(QStringLiteral("GetNameOwner"), name), this);
            const auto epoch = m_ownerEpochs.value(name);
            connect(lookup, &QDBusPendingCallWatcher::finished, this, [this, lookup, name, epoch] {
                const QDBusPendingReply<QString> owner = *lookup; lookup->deleteLater();
                if (!owner.isError() && m_ownerEpochs.value(name) == epoch && !m_sessions.contains(name)) ownerChanged(name, {}, owner.value());
            });
        }
    });
}
void MprisActivityProvider::ownerChanged(const QString &name, const QString &, const QString &owner) {
    if (!name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) return;
    ++m_ownerEpochs[name];
    delete m_sessions.take(name);
    if (!owner.isEmpty()) {
        auto *session = new MprisSession(m_bus, name, owner, ++m_generation, this);
        m_sessions.insert(name, session);
        connect(session, &MprisSession::changed, this, &MprisActivityProvider::changed);
    }
    Q_EMIT changed();
}
QVariantList MprisActivityProvider::activities() const {
    QVariantList rows;
    for (auto *session : m_sessions) { const auto row = session->activity(); if (!row.isEmpty()) rows.append(row); }
    return rows;
}
void MprisActivityProvider::invoke(const QString &id, int generation, const QString &action) {
    auto *session = m_sessions.value(id);
    if (session && session->activity().value(QStringLiteral("generation")).toInt() == generation) session->invoke(action);
}
#include "MprisActivityProvider.moc"
