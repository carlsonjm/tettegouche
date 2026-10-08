/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "ApplicationCatalog.h"
#include "UseRecord.h"

#include <AppStreamQt/component-box.h>
#include <AppStreamQt/launchable.h>
#include <AppStreamQt/pool.h>
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KApplicationTrader>

#include <QSettings>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

namespace
{
// The applications hidden from Apps, by desktop file id.
const QString HiddenKey = QStringLiteral("Browse/hiddenApplications");
const QString OrderKey = QStringLiteral("Browse/sortOrder");

QDateTime installedAt(const KService::Ptr &service)
{
    QString path = service->entryPath();
    if (QDir::isRelativePath(path))
        path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, path);
    const QFileInfo file(path);
    const QDateTime born = file.birthTime();
    return born.isValid() ? born : file.lastModified();
}
}

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
                          service->icon().trimmed(), id, installedAt(service)});
    }
    std::sort(m_entries.begin(), m_entries.end(),
              [](const Entry &left, const Entry &right) {
        return QString::localeAwareCompare(left.name, right.name) < 0;
    });
    const QStringList hidden = QSettings().value(HiddenKey).toStringList();
    m_hidden = QSet<QString>(hidden.cbegin(), hidden.cend());
    const int order = QSettings().value(OrderKey, int(NameAscending)).toInt();
    m_sortOrder = order >= NameAscending && order <= NewestInstalled ? order : NameAscending;
    rebuildVisibleRows();
}

ApplicationCatalog::~ApplicationCatalog() = default;

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
    case HiddenRole:
        return m_hidden.contains(entry.applicationId);
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
        {HiddenRole, QByteArrayLiteral("hidden")},
    };
}

bool ApplicationCatalog::launch(int row)
{
    if (row < 0 || row >= m_visibleRows.size()) {
        return false;
    }
    const Entry &entry = m_entries.at(m_visibleRows.at(row));
    auto *job = new KIO::ApplicationLauncherJob(entry.service, this);
    job->start();
    noteApplicationUsed(entry.applicationId);
    return true;
}

QString ApplicationCatalog::applicationId(int row) const
{
    return row >= 0 && row < m_visibleRows.size()
        ? m_entries.at(m_visibleRows.at(row)).applicationId : QString();
}

QUrl ApplicationCatalog::applicationUrl(int row) const
{
    const Entry *entry = entryAt(row);
    if (!entry) return {};
    QString path = entry->service->entryPath();
    if (QDir::isRelativePath(path))
        path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, path);
    return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(path);
}

QString ApplicationCatalog::applicationIcon(int row) const
{
    const Entry *entry = entryAt(row);
    return entry ? entry->icon : QString();
}

QString ApplicationCatalog::applicationName(int row) const
{
    return row >= 0 && row < m_visibleRows.size()
        ? m_entries.at(m_visibleRows.at(row)).name : QString();
}

const ApplicationCatalog::Entry *ApplicationCatalog::entryAt(int row) const
{
    return row >= 0 && row < m_visibleRows.size()
        ? &m_entries.at(m_visibleRows.at(row)) : nullptr;
}

QVariantList ApplicationCatalog::actions(int row) const
{
    QVariantList actions;
    const Entry *entry = entryAt(row);
    if (!entry) {
        return actions;
    }
    const QList<KServiceAction> own = entry->service->actions();
    for (int index = 0; index < own.size(); ++index) {
        const KServiceAction &action = own.at(index);
        if (action.isSeparator() || action.noDisplay()
            || action.text().trimmed().isEmpty()) {
            continue;
        }
        actions.append(QVariantMap{{QStringLiteral("index"), index},
                                   {QStringLiteral("name"), action.text().trimmed()},
                                   {QStringLiteral("icon"), action.icon()}});
    }
    return actions;
}

bool ApplicationCatalog::runAction(int row, int action)
{
    const Entry *entry = entryAt(row);
    if (!entry) {
        return false;
    }
    const QList<KServiceAction> own = entry->service->actions();
    if (action < 0 || action >= own.size() || own.at(action).isSeparator()) {
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(own.at(action), this);
    job->start();
    noteApplicationUsed(entry->applicationId);
    return true;
}

bool ApplicationCatalog::isHidden(int row) const
{
    const Entry *entry = entryAt(row);
    return entry && m_hidden.contains(entry->applicationId);
}

bool ApplicationCatalog::isHiddenApplication(const QString &applicationId) const
{
    return m_hidden.contains(applicationId);
}

void ApplicationCatalog::setHidden(int row, bool hidden)
{
    const Entry *entry = entryAt(row);
    if (!entry || m_hidden.contains(entry->applicationId) == hidden) {
        return;
    }
    if (hidden) {
        m_hidden.insert(entry->applicationId);
    } else {
        m_hidden.remove(entry->applicationId);
    }
    QStringList stored(m_hidden.cbegin(), m_hidden.cend());
    stored.sort();
    QSettings().setValue(HiddenKey, stored);
    rebuildVisibleRows();
    Q_EMIT hiddenCountChanged();
}

QString ApplicationCatalog::softwareId(const Entry &entry) const
{
    if (!m_softwareReady || !m_software) {
        return {};
    }
    const AppStream::ComponentBox found = m_software->componentsByLaunchable(
        AppStream::Launchable::KindDesktopId,
        entry.service->desktopEntryName() + QStringLiteral(".desktop"));
    const auto component = found.indexSafe(0);
    return component ? component->id() : QString();
}

void ApplicationCatalog::prepareSoftware()
{
    if (m_software) {
        return;
    }
    // Reading the system's software catalog takes no time from its cache and
    // seconds when the cache is stale, so it is never done on the way to a sheet.
    m_software = std::make_unique<AppStream::Pool>();
    connect(m_software.get(), &AppStream::Pool::loadFinished, this, [this](bool) {
        m_softwareReady = true;
        Q_EMIT softwareReadyChanged();
    });
    m_software->loadAsync();
}

bool ApplicationCatalog::canUninstall(int row) const
{
    const Entry *entry = entryAt(row);
    return entry && m_softwareReady
        && KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/appstream"))
        && !softwareId(*entry).isEmpty();
}

bool ApplicationCatalog::uninstall(int row)
{
    const Entry *entry = entryAt(row);
    const QString id = entry ? softwareId(*entry) : QString();
    if (id.isEmpty()) {
        return false;
    }
    auto *job = new KIO::OpenUrlJob(QUrl(QStringLiteral("appstream://") + id), this);
    job->start();
    return true;
}

bool ApplicationCatalog::showHidden() const
{
    return m_showHidden;
}

void ApplicationCatalog::setShowHidden(bool showHidden)
{
    if (m_showHidden == showHidden) {
        return;
    }
    m_showHidden = showHidden;
    rebuildVisibleRows();
    Q_EMIT showHiddenChanged();
}

int ApplicationCatalog::hiddenCount() const
{
    int count = 0;
    for (const Entry &entry : m_entries) {
        count += m_hidden.contains(entry.applicationId) ? 1 : 0;
    }
    return count;
}

bool ApplicationCatalog::softwareReady() const
{
    return m_softwareReady;
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

int ApplicationCatalog::sortOrder() const
{
    return m_sortOrder;
}

void ApplicationCatalog::setSortOrder(int sortOrder)
{
    if (sortOrder < NameAscending || sortOrder > NewestInstalled
        || m_sortOrder == sortOrder) {
        return;
    }
    m_sortOrder = sortOrder;
    QSettings().setValue(OrderKey, sortOrder);
    if (m_sortOrder == MostUsed && m_useReader) {
        m_use = m_useReader();
    }
    rebuildVisibleRows();
    Q_EMIT sortOrderChanged();
}

void ApplicationCatalog::setUseReader(UseReader reader)
{
    m_useReader = std::move(reader);
    refreshUse();
}

void ApplicationCatalog::refreshUse()
{
    // The record is read only while it decides the order.
    if (!m_useReader || m_sortOrder != MostUsed) {
        return;
    }
    m_use = m_useReader();
    rebuildVisibleRows();
}

void ApplicationCatalog::rebuildVisibleRows()
{
    beginResetModel();
    m_visibleRows.clear();
    m_visibleRows.reserve(m_entries.size());

    const auto matches = [this](const Entry &entry) {
        return (m_showHidden || !m_hidden.contains(entry.applicationId))
            && (m_filterText.isEmpty()
                || entry.name.contains(m_filterText, Qt::CaseInsensitive));
    };
    for (int row = 0; row < m_entries.size(); ++row) {
        if (matches(m_entries.at(row))) {
            m_visibleRows.append(row);
        }
    }
    // m_entries is already A to Z, so a stable sort keeps it among equals.
    switch (m_sortOrder) {
    case NameDescending:
        std::reverse(m_visibleRows.begin(), m_visibleRows.end());
        break;
    case MostUsed:
        std::stable_sort(m_visibleRows.begin(), m_visibleRows.end(), [this](int left, int right) {
            return m_use.value(m_entries.at(left).applicationId)
                > m_use.value(m_entries.at(right).applicationId);
        });
        break;
    case NewestInstalled:
        std::stable_sort(m_visibleRows.begin(), m_visibleRows.end(), [this](int left, int right) {
            return m_entries.at(left).installed > m_entries.at(right).installed;
        });
        break;
    default:
        break;
    }
    endResetModel();
}
