/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "ApplicationCatalog.h"

#include <KIO/ApplicationLauncherJob>
#include <KService/KApplicationTrader>

#include <QSet>

#include <algorithm>

ApplicationCatalog::ApplicationCatalog(QObject *parent)
    : QAbstractListModel(parent)
{
    QSet<QString> seen;
    const KService::List applications = KApplicationTrader::query(
        [](const KService::Ptr &service) {
            return service && service->isApplication()
                && !service->noDisplay() && !service->name().trimmed().isEmpty()
                && !service->exec().trimmed().isEmpty();
        });
    for (const KService::Ptr &service : applications) {
        const QString id = service->storageId().trimmed();
        if (id.isEmpty() || seen.contains(id)
            || id.compare(QStringLiteral(
                    "io.github.carlsonjm.Tettegouche.desktop"),
                    Qt::CaseInsensitive) == 0) {
            continue;
        }
        seen.insert(id);
        m_entries.append({service, service->name().trimmed(),
                          service->icon().trimmed(), id});
    }
    std::sort(m_entries.begin(), m_entries.end(),
              [](const Entry &left, const Entry &right) {
        return QString::localeAwareCompare(left.name, right.name) < 0;
    });
}

int ApplicationCatalog::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant ApplicationCatalog::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0
        || index.row() >= m_entries.size()) {
        return {};
    }
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case NameRole:
        return entry.name;
    case IconRole:
        return entry.icon;
    case ApplicationIdRole:
        return entry.applicationId;
    default:
        return {};
    }
}

QHash<int, QByteArray> ApplicationCatalog::roleNames() const
{
    return {
        {NameRole, QByteArrayLiteral("name")},
        {IconRole, QByteArrayLiteral("icon")},
        {ApplicationIdRole, QByteArrayLiteral("applicationId")},
    };
}

bool ApplicationCatalog::launch(int row)
{
    if (row < 0 || row >= m_entries.size()) {
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(
        m_entries.at(row).service, this);
    job->start();
    return true;
}

QString ApplicationCatalog::applicationId(int row) const
{
    return row >= 0 && row < m_entries.size()
        ? m_entries.at(row).applicationId : QString();
}

QString ApplicationCatalog::applicationName(int row) const
{
    return row >= 0 && row < m_entries.size()
        ? m_entries.at(row).name : QString();
}
