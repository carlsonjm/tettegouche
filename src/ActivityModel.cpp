#include "ActivityModel.h"
#include "ActivityUtils.h"
#include <QStandardPaths>
#include <QTimer>
#include <QFileInfo>

namespace {
QString sourceKey(const QVariantMap &row) {
    return row.value(QStringLiteral("id")).toString() + QLatin1Char('/') + row.value(QStringLiteral("generation")).toString();
}
QString destinationKey(const QVariantMap &row) {
    const auto path = Ambient::localPath(row.value(QStringLiteral("destinationUrl")));
    const auto identity = Ambient::fileIdentity(path);
    if (identity.isEmpty() || (!row.value(QStringLiteral("fileIdentity")).toString().isEmpty()
            && row.value(QStringLiteral("fileIdentity")).toString() != identity)) return {};
    return path + QLatin1Char('\n') + identity;
}
}
std::shared_ptr<ActivityModel> ActivityModel::acquire() {
    static std::weak_ptr<ActivityModel> instance;
    auto model = instance.lock();
    if (!model) {
        model = std::make_shared<ActivityModel>(QDBusConnection::sessionBus(),
            QStandardPaths::writableLocation(QStandardPaths::DownloadLocation));
        instance = model;
    }
    return model;
}
ActivityModel::ActivityModel(const QDBusConnection &bus, const QString &downloads, QObject *parent)
    : QObject(parent), m_media(bus, this), m_jobs(this), m_files(downloads, this), m_tette(bus, this) {
    const auto update = [this] {
        if (m_refreshPending) return;
        m_refreshPending = true;
        QTimer::singleShot(0, this, [this] { m_refreshPending = false; refresh(); });
    };
    connect(&m_media, &MprisActivityProvider::changed, this, update);
    connect(&m_jobs, &DesktopJobProvider::changed, this, update);
    connect(&m_files, &IncomingFileProvider::changed, this, update);
    connect(&m_tette, &TetteTransferProvider::changed, this, update);
    update();
}
void ActivityModel::refresh() { reconcile(m_tette.activities() + m_jobs.activities(), m_media.activities(), m_files.activities()); }
void ActivityModel::reconcile(const QVariantList &transfers, const QVariantList &media, const QVariantList &files) {
    const auto now = Ambient::nowUs();
    m_consumedFiles.removeIf([now](const auto &e) { return e.value() <= now; });
    QSet<QString> liveSources;
    for (const auto &v : transfers) liveSources.insert(sourceKey(v.toMap()));
    for (auto it = m_destinations.begin(); it != m_destinations.end();) {
        if (liveSources.contains(it.key())) { ++it; continue; }
        // Consume only the just-ended write burst. Later writes can become new arrivals.
        for (const auto &id : m_claimedFiles.take(it.key())) {
            m_consumedFiles[id] = now + 2000000;
            m_files.consume(id);
        }
        it = m_destinations.erase(it);
    }
    QMap<QString, QVariantMap> fileByDestination;
    for (const auto &v : files) {
        const auto row = v.toMap(); const auto key = destinationKey(row);
        if (!key.isEmpty() && m_consumedFiles.contains(row.value(QStringLiteral("id")).toString())) {
            m_files.consume(row.value(QStringLiteral("id")).toString());
        } else if (!key.isEmpty()) fileByDestination.insert(key,row);
    }
    QMap<QString,int> destinationOwners;
    for (const auto &v : transfers) {
        const auto row = v.toMap(); const auto key = destinationKey(row);
        if (!key.isEmpty()) m_destinations[sourceKey(row)].insert(key);
        for (const auto &alias : m_destinations.value(sourceKey(row))) ++destinationOwners[alias];
    }
    QVariantList rows;
    QMap<QString,QVariantMap> routes;
    QSet<QString> retained;
    const auto append = [&](QVariantMap row, const QVariantMap &route, const QString &suggestedId = QString()) {
        const QString key = sourceKey(route);
        const auto oldId = m_presentations.value(key);
        const QString id = !oldId.isEmpty() ? oldId : !suggestedId.isEmpty() ? suggestedId : row.value(QStringLiteral("id")).toString();
        m_presentations[key] = id; retained.insert(key);
        int token = 0;
        if (m_routes.contains(id) && sourceKey(m_routes.value(id)) == key)
            token = m_routes.value(id).value(QStringLiteral("actionToken")).toInt();
        if (!token) token = ++m_token;
        auto target = route; target[QStringLiteral("actionToken")] = token;
        row[QStringLiteral("id")] = id; row[QStringLiteral("generation")] = token;
        routes[id] = target; rows.append(row);
    };
    for (const auto &v : transfers) {
        auto row = v.toMap(); const auto route = row; QString fileId;
        for (const auto &alias : m_destinations.value(sourceKey(row))) {
            if (destinationOwners.value(alias) != 1 || !fileByDestination.contains(alias)) continue;
            const auto fs = fileByDestination.take(alias);
            m_claimedFiles[sourceKey(row)].insert(fs.value(QStringLiteral("id")).toString());
            if (fileId.isEmpty()) {
                fileId = fs.value(QStringLiteral("id")).toString();
                row[QStringLiteral("observedSizeBytes")] = fs.value(QStringLiteral("observedSizeBytes"));
                row[QStringLiteral("evidence")] = QStringLiteral("job+filesystem");
            }
        }
        append(row, route, fileId);
    }
    for (const auto &v : media) append(v.toMap(), v.toMap());
    for (const auto &row : fileByDestination) append(row, row);
    m_presentations.removeIf([&retained](const auto &e) { return !retained.contains(e.key()); });
    m_routes = routes;
    if (rows != m_rows) { m_rows = rows; Q_EMIT changed(); }
}
void ActivityModel::invoke(const QString &id, int generation, const QString &action) {
    const auto route = m_routes.value(id);
    if (route.isEmpty() || route.value(QStringLiteral("actionToken")).toInt() != generation
            || !route.value(QStringLiteral("capabilities")).toMap().value(action).toBool()) return;
    const auto sourceId = route.value(QStringLiteral("id")).toString();
    const int sourceGeneration = route.value(QStringLiteral("generation")).toInt();
    if (sourceId.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) m_media.invoke(sourceId,sourceGeneration,action);
    else if (sourceId.startsWith(QLatin1String("tette:"))) m_tette.invoke(sourceId,sourceGeneration,action);
    else if (sourceId.startsWith(QLatin1String("job:"))) m_jobs.invoke(sourceId,sourceGeneration,action);
}
QUrl ActivityModel::destinationForReveal(const QString &id, int generation) const {
    const auto route = m_routes.value(id);
    if (route.value(QStringLiteral("actionToken")).toInt() != generation
            || !route.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("showInFiles")).toBool()
            || !m_files.matchesFile(route)) return {};
    return QUrl(route.value(QStringLiteral("destinationUrl")).toString());
}
