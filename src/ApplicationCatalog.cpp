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
    rebuildVisibleRows();
}

int ApplicationCatalog::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visibleRows.size();
}

QVariant ApplicationCatalog::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0
        || index.row() >= m_visibleRows.size()) {
        return {};
    }
    const Entry &entry = m_entries.at(m_visibleRows.at(index.row()));
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
    if (row < 0 || row >= m_visibleRows.size()) {
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(
        m_entries.at(m_visibleRows.at(row)).service, this);
    job->start();
    return true;
}

QString ApplicationCatalog::applicationId(int row) const
{
    return row >= 0 && row < m_visibleRows.size()
        ? m_entries.at(m_visibleRows.at(row)).applicationId : QString();
}

QString ApplicationCatalog::applicationName(int row) const
{
    return row >= 0 && row < m_visibleRows.size()
        ? m_entries.at(m_visibleRows.at(row)).name : QString();
}

QString ApplicationCatalog::filterText() const
{
    return m_filterText;
}

void ApplicationCatalog::setFilterText(const QString &filterText)
{
    const QString normalized = filterText.trimmed();
    if (m_filterText == normalized) {
        return;
    }
    m_filterText = normalized;
    rebuildVisibleRows();
    Q_EMIT filterTextChanged();
}

bool ApplicationCatalog::descending() const
{
    return m_descending;
}

void ApplicationCatalog::setDescending(bool descending)
{
    if (m_descending == descending) {
        return;
    }
    m_descending = descending;
    rebuildVisibleRows();
    Q_EMIT descendingChanged();
}

void ApplicationCatalog::rebuildVisibleRows()
{
    beginResetModel();
    m_visibleRows.clear();
    m_visibleRows.reserve(m_entries.size());

    const auto matches = [this](const Entry &entry) {
        return m_filterText.isEmpty()
            || entry.name.contains(m_filterText, Qt::CaseInsensitive);
    };
    if (m_descending) {
        for (int row = m_entries.size() - 1; row >= 0; --row) {
            if (matches(m_entries.at(row))) {
                m_visibleRows.append(row);
            }
        }
    } else {
        for (int row = 0; row < m_entries.size(); ++row) {
            if (matches(m_entries.at(row))) {
                m_visibleRows.append(row);
            }
        }
    }
    endResetModel();
}
