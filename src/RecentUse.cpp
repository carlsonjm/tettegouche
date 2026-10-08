/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "RecentUse.h"
#include "UseRecord.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KService>
#include <PlasmaActivities/Stats/Query>
#include <PlasmaActivities/Stats/ResultSet>
#include <PlasmaActivities/Stats/Terms>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QSet>
#include <QUrl>

#include <algorithm>

namespace
{
const QString ApplicationScheme = QStringLiteral("applications:");
const QString OwnApplication = QStringLiteral("io.github.carlsonjm.Tettegouche.desktop");
const QString Application = QStringLiteral("application");
const QString File = QStringLiteral("file");
}

RecentUse::RecentUse(QObject *parent)
    : QAbstractListModel(parent)
    , m_reader(&RecentUse::readRecord)
{
}

int RecentUse::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant RecentUse::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    const Item &item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item.name;
    case IconRole:
        return item.icon;
    case ThumbnailRole:
        return item.thumbnail;
    case KindRole:
        return item.kind;
    default:
        return {};
    }
}

QHash<int, QByteArray> RecentUse::roleNames() const
{
    return {
        {NameRole, QByteArrayLiteral("name")},
        {IconRole, QByteArrayLiteral("icon")},
        {ThumbnailRole, QByteArrayLiteral("thumbnail")},
        {KindRole, QByteArrayLiteral("kind")},
    };
}

void RecentUse::setWithheld(bool withheld)
{
    if (m_withheld == withheld) {
        return;
    }
    m_withheld = withheld;
    rebuild();
}

void RecentUse::refresh()
{
    m_record = m_reader ? m_reader() : QList<Used>{};
    rebuild();
}

void RecentUse::refilter()
{
    rebuild();
}

void RecentUse::rebuild()
{
    QVector<Item> items;
    if (!m_withheld) {
        QList<Used> record = m_record;
        std::stable_sort(record.begin(), record.end(), [](const Used &left, const Used &right) {
            return left.lastUsed > right.lastUsed;
        });
        QSet<QString> seen;
        const QMimeDatabase mimes;
        for (const Used &used : std::as_const(record)) {
            if (items.size() >= Kept) {
                break;
            }
            if (used.resource.startsWith(ApplicationScheme)) {
                const auto service = KService::serviceByStorageId(used.resource.mid(ApplicationScheme.size()));
                if (!service || !service->isApplication() || service->noDisplay()
                    || service->name().trimmed().isEmpty()) {
                    continue;
                }
                const QString id = service->storageId();
                if (id.compare(OwnApplication, Qt::CaseInsensitive) == 0 || seen.contains(id)) {
                    continue;
                }
                seen.insert(id);
                if (m_excluded && m_excluded(id, service->name().trimmed())) {
                    continue;
                }
                items.append({Application, service->name().trimmed(), service->icon(), {}, id, {}, {}});
                continue;
            }
            const QUrl url = QUrl::fromUserInput(used.resource, QString(), QUrl::AssumeLocalFile);
            if (!url.isLocalFile()) {
                continue;
            }
            // A folder belongs to Files, and a file that is gone or hidden is
            // not offered.
            const QFileInfo info(url.toLocalFile());
            if (!info.isFile() || info.isHidden()) {
                continue;
            }
            const QString path = info.absoluteFilePath();
            if (seen.contains(path)) {
                continue;
            }
            seen.insert(path);
            const QString mimeType = mimes.mimeTypeForFile(info).name();
            const QString thumbnail = m_thumbnails
                ? m_thumbnails(path, mimeType, info.lastModified().toMSecsSinceEpoch()) : QString();
            items.append({File, info.fileName(), mimes.mimeTypeForName(mimeType).iconName(), thumbnail, {},
                          path, mimeType});
        }
    }
    const bool countChanges = items.size() != m_items.size();
    beginResetModel();
    m_items = items;
    endResetModel();
    if (countChanges) {
        Q_EMIT countChanged();
    }
}

QString RecentUse::applicationFor(int row) const
{
    if (row < 0 || row >= m_items.size()) {
        return {};
    }
    const Item &item = m_items.at(row);
    if (item.kind == Application) {
        return item.applicationId;
    }
    const auto service = KApplicationTrader::preferredService(item.mimeType);
    return service ? service->storageId() : QString();
}

bool RecentUse::open(int row)
{
    if (row < 0 || row >= m_items.size()) {
        return false;
    }
    const Item item = m_items.at(row);
    if (item.kind == Application) {
        const auto service = KService::serviceByStorageId(item.applicationId);
        if (!service) {
            return false;
        }
        auto *job = new KIO::ApplicationLauncherJob(service, this);
        job->start();
        noteApplicationUsed(item.applicationId);
        return true;
    }
    // Gone since the record was read: nothing opens.
    if (!QFileInfo(item.path).isFile()) {
        return false;
    }
    const QUrl url = QUrl::fromLocalFile(item.path);
    auto *job = new KIO::OpenUrlJob(url, item.mimeType, this);
    job->setRunExecutables(false);
    job->setShowOpenOrExecuteDialog(false);
    job->start();
    noteUsed(url.toString());
    return true;
}

QList<RecentUse::Used> RecentUse::readRecord()
{
    using namespace KActivities::Stats;
    using namespace KActivities::Stats::Terms;
    // The current activity is asked of KDE's activity service directly. The
    // library's own answer arrives on the event loop after the service is
    // first seen, so read the moment Search opens it named none, and nothing
    // was read.
    const QDBusReply<QString> current = QDBusConnection::sessionBus().call(
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.ActivityManager"),
            QStringLiteral("/ActivityManager/Activities"), QStringLiteral("org.kde.ActivityManager.Activities"),
            QStringLiteral("CurrentActivity")),
        QDBus::Block, 500);
    if (!current.isValid() || current.value().isEmpty()) {
        return {};
    }
    // Enough to fill a row once what is pinned, open or gone is left out.
    const Query query = UsedResources | RecentlyUsedFirst | Agent::any() | Type::any()
        | Activity(current.value()) | Limit(60);
    QList<Used> record;
    for (const ResultSet::Result &result : ResultSet(query)) {
        record.append({result.resource(), result.lastUpdate()});
    }
    return record;
}

QHash<QString, double> RecentUse::readApplicationUse()
{
    using namespace KActivities::Stats;
    using namespace KActivities::Stats::Terms;
    const Query query = UsedResources | HighScoredFirst | Agent::any() | Type::any()
        | Activity::any() | Url::startsWith(ApplicationScheme) | Limit(500);
    QHash<QString, double> use;
    for (const ResultSet::Result &result : ResultSet(query)) {
        const QString id = result.resource().mid(ApplicationScheme.size());
        if (!id.isEmpty()) {
            use[id] += result.score();
        }
    }
    return use;
}
