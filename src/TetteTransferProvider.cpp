#include "TetteTransferProvider.h"
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
namespace {
const QString service = QStringLiteral("io.github.carlsonjm.Tettegouche");
const QString path = QStringLiteral("/Activities");
const QString iface = QStringLiteral("io.github.carlsonjm.Tettegouche.Activities1");
}
TetteTransferProvider::TetteTransferProvider(const QDBusConnection &bus, QObject *parent) : QObject(parent), m_bus(bus) {
    connect(bus.interface(), &QDBusConnectionInterface::serviceOwnerChanged, this, &TetteTransferProvider::ownerChanged);
    auto *lookup = new QDBusPendingCallWatcher(bus.interface()->asyncCall(QStringLiteral("GetNameOwner"), service), this);
    const auto generation = m_generation;
    connect(lookup, &QDBusPendingCallWatcher::finished, this, [this,lookup,generation] {
        const QDBusPendingReply<QString> reply = *lookup; lookup->deleteLater();
        if (!reply.isError() && m_generation == generation) ownerChanged(service, {}, reply.value());
    });
}
void TetteTransferProvider::ownerChanged(const QString &name, const QString &, const QString &owner) {
    if (name != service) return;
    if (!m_owner.isEmpty()) m_bus.disconnect(m_owner, path, iface, QStringLiteral("changed"), this, SLOT(snapshotChanged(QString,QDBusMessage)));
    ++m_generation; m_owner = owner; m_revision = -1; m_rows.clear(); Q_EMIT changed();
    if (owner.isEmpty()) return;
    m_bus.connect(owner, path, iface, QStringLiteral("changed"), this, SLOT(snapshotChanged(QString,QDBusMessage)));
    const int generation = m_generation;
    auto *pending = new QDBusPendingCallWatcher(m_bus.asyncCall(QDBusMessage::createMethodCall(owner,path,iface,QStringLiteral("snapshot"))), this);
    connect(pending, &QDBusPendingCallWatcher::finished, this, [this,pending,generation] {
        const QDBusPendingReply<QString> reply = *pending; pending->deleteLater();
        if (!reply.isError() && m_generation == generation) apply(reply.value());
    });
}
void TetteTransferProvider::snapshotChanged(const QString &json, const QDBusMessage &message) {
    if (message.service() == m_owner) apply(json);
}
void TetteTransferProvider::apply(const QString &json) {
    const auto doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) return;
    const auto object = doc.object(); const auto revision = object.value(QStringLiteral("revision")).toInteger(-1);
    if (revision <= m_revision || !object.value(QStringLiteral("activities")).isArray()) return;
    m_revision = revision; m_rows.clear();
    for (const auto &value : object.value(QStringLiteral("activities")).toArray()) {
        auto row = value.toObject().toVariantMap();
        if (row.value(QStringLiteral("id")).toString().isEmpty() || row.value(QStringLiteral("kind")) != QLatin1String("transfer")) continue;
        row[QStringLiteral("sourceId")] = row.value(QStringLiteral("id")); row[QStringLiteral("id")] = QString(QStringLiteral("tette:") + row.value(QStringLiteral("id")).toString());
        row[QStringLiteral("generation")] = m_generation; m_rows.append(row);
    }
    Q_EMIT changed();
}
void TetteTransferProvider::invoke(const QString &id, int generation, const QString &action) {
    if (generation != m_generation || m_owner.isEmpty() || action != QLatin1String("cancel")) return;
    for (const auto &value : m_rows) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("id")) != id || !row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("cancel")).toBool()) continue;
        auto *check = new QDBusPendingCallWatcher(m_bus.interface()->asyncCall(QStringLiteral("GetNameOwner"), service),this);
        connect(check,&QDBusPendingCallWatcher::finished,this,[this,check,generation,row] {
            const QDBusPendingReply<QString> reply = *check; check->deleteLater();
            if (reply.isError() || generation != m_generation || reply.value() != m_owner) return;
            auto call=QDBusMessage::createMethodCall(m_owner,path,iface,QStringLiteral("cancel"));
            call.setArguments({row.value(QStringLiteral("sourceId"))}); m_bus.asyncCall(call);
        });
        return;
    }
}
