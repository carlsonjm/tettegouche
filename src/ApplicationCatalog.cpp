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
#include <KLocalizedString>

#include <QSettings>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

namespace
{
// The applications hidden from Apps, by desktop file id.
const QString HiddenKey = QStringLiteral("Browse/hiddenApplications");
const QString OrderKey = QStringLiteral("Browse/sortOrder");
// Apps' folders, as JSON: a list of {id, name, apps}, apps by desktop file id.
const QString FoldersKey = QStringLiteral("Browse/folders");

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
    const QJsonArray folders = QJsonDocument::fromJson(
        QSettings().value(FoldersKey).toString().toUtf8()).array();
    for (const QJsonValue &value : folders) {
        const QJsonObject folder = value.toObject();
        Folder kept{folder.value(QStringLiteral("id")).toString(),
                    folder.value(QStringLiteral("name")).toString().trimmed(), {}};
        for (const QJsonValue &application : folder.value(QStringLiteral("apps")).toArray()) {
            const QString id = application.toString();
            if (!id.isEmpty() && !kept.applications.contains(id)) {
                kept.applications.append(id);
            }
        }
        if (!kept.id.isEmpty() && kept.applications.size() >= 2) {
            m_folders.append(kept);
        }
    }
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
    if (const Folder *folder = folderAt(index.row())) {
        switch (role) {
        case NameRole:
            return folder->name.isEmpty()
                ? i18nc("@label an Apps folder with no name", "Folder") : folder->name;
        case IsFolderRole:
            return true;
        case FolderIdRole:
            return folder->id;
        case FolderIconsRole: {
            QVector<int> members;
            for (const QString &id : folder->applications) {
                const int at = entryIndex(id);
                if (at >= 0 && shown(m_entries.at(at))) members.append(at);
            }
            sortEntries(members);
            QStringList icons;
            for (int at : members) {
                if (icons.size() == 4) break;
                icons.append(m_entries.at(at).icon);
            }
            return icons;
        }
        case HiddenRole:
            return false;
        default:
            return {};
        }
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
    case IsFolderRole:
        return false;
    case FolderIdRole:
        return QString();
    case FolderIconsRole:
        return QStringList();
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
        {IsFolderRole, QByteArrayLiteral("isFolder")},
        {FolderIdRole, QByteArrayLiteral("folderId")},
        {FolderIconsRole, QByteArrayLiteral("folderIcons")},
    };
}

bool ApplicationCatalog::launch(int row)
{
    const Entry *entry = entryAt(row);
    if (!entry) {
        return false;
    }
    auto *job = new KIO::ApplicationLauncherJob(entry->service, this);
    job->start();
    noteApplicationUsed(entry->applicationId);
    return true;
}

QString ApplicationCatalog::applicationId(int row) const
{
    const Entry *entry = entryAt(row);
    return entry ? entry->applicationId : QString();
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
    const Entry *entry = entryAt(row);
    return entry ? entry->name : QString();
}

const ApplicationCatalog::Entry *ApplicationCatalog::entryAt(int row) const
{
    return row >= 0 && row < m_visibleRows.size() && m_visibleRows.at(row) >= 0
        ? &m_entries.at(m_visibleRows.at(row)) : nullptr;
}

const ApplicationCatalog::Folder *ApplicationCatalog::folderAt(int row) const
{
    if (row < 0 || row >= m_visibleRows.size() || m_visibleRows.at(row) >= 0) {
        return nullptr;
    }
    return &m_folders.at(-1 - m_visibleRows.at(row));
}

bool ApplicationCatalog::shown(const Entry &entry) const
{
    return m_showHidden || !m_hidden.contains(entry.applicationId);
}

int ApplicationCatalog::entryIndex(const QString &applicationId) const
{
    for (int at = 0; at < m_entries.size(); ++at) {
        if (m_entries.at(at).applicationId == applicationId) return at;
    }
    return -1;
}

int ApplicationCatalog::folderIndex(const QString &folderId) const
{
    for (int at = 0; at < m_folders.size(); ++at) {
        if (m_folders.at(at).id == folderId) return at;
    }
    return -1;
}

QHash<int, QVector<int>> ApplicationCatalog::drawnFolders() const
{
    QHash<int, QVector<int>> drawn;
    QSet<int> placed;
    for (int folder = 0; folder < m_folders.size(); ++folder) {
        QVector<int> members;
        for (const QString &id : m_folders.at(folder).applications) {
            const int at = entryIndex(id);
            // An application is in one folder: the first that names it.
            if (at >= 0 && shown(m_entries.at(at)) && !placed.contains(at)) {
                members.append(at);
            }
        }
        if (members.size() >= 2) {
            for (int at : members) placed.insert(at);
            drawn.insert(folder, members);
        }
    }
    return drawn;
}

bool ApplicationCatalog::isFolder(int row) const
{
    return folderAt(row) != nullptr;
}

QString ApplicationCatalog::folderId(int row) const
{
    const Folder *folder = folderAt(row);
    return folder ? folder->id : QString();
}

QString ApplicationCatalog::folderName(int row) const
{
    return isFolder(row) ? data(index(row), NameRole).toString() : QString();
}

QString ApplicationCatalog::folderOf(int row) const
{
    const Entry *entry = entryAt(row);
    if (!entry) return {};
    const int at = int(entry - m_entries.constData());
    const QHash<int, QVector<int>> drawn = drawnFolders();
    for (auto folder = drawn.cbegin(); folder != drawn.cend(); ++folder) {
        if (folder.value().contains(at)) return m_folders.at(folder.key()).id;
    }
    return {};
}

QVariantList ApplicationCatalog::folderList() const
{
    const QHash<int, QVector<int>> drawn = drawnFolders();
    QVector<int> order(drawn.keyBegin(), drawn.keyEnd());
    std::sort(order.begin(), order.end(), [this](int left, int right) {
        return QString::localeAwareCompare(m_folders.at(left).name, m_folders.at(right).name) < 0;
    });
    QVariantList list;
    for (int folder : order) {
        const Folder &kept = m_folders.at(folder);
        list.append(QVariantMap{{QStringLiteral("id"), kept.id},
                                {QStringLiteral("name"), kept.name.isEmpty()
                                     ? i18nc("@label an Apps folder with no name", "Folder") : kept.name}});
    }
    return list;
}

QString ApplicationCatalog::nameFor(const QStringList &applicationIds) const
{
    // The freedesktop main categories, in the order a shared one is chosen,
    // and the word a folder of them is called.
    const QList<QPair<QStringList, QString>> names = {
        {{QStringLiteral("Game")}, i18nc("@label an Apps folder of games", "Games")},
        {{QStringLiteral("AudioVideo"), QStringLiteral("Audio"), QStringLiteral("Video")},
         i18nc("@label an Apps folder of media players", "Media")},
        {{QStringLiteral("Development")}, i18nc("@label an Apps folder of programming tools", "Code")},
        {{QStringLiteral("Office")}, i18nc("@label an Apps folder of office applications", "Office")},
        {{QStringLiteral("Graphics")}, i18nc("@label an Apps folder of graphics applications", "Graphics")},
        {{QStringLiteral("Network")}, i18nc("@label an Apps folder of internet applications", "Internet")},
        {{QStringLiteral("System"), QStringLiteral("Settings")}, i18nc("@label an Apps folder of system tools", "System")},
        {{QStringLiteral("Utility")}, i18nc("@label an Apps folder of utilities", "Tools")},
    };
    QList<QStringList> categories;
    for (const QString &id : applicationIds) {
        const int at = entryIndex(id);
        categories.append(at >= 0 ? m_entries.at(at).service->categories() : QStringList());
    }
    for (const auto &[keys, name] : names) {
        const bool shared = std::all_of(categories.cbegin(), categories.cend(), [&keys](const QStringList &own) {
            return std::any_of(keys.cbegin(), keys.cend(), [&own](const QString &key) {
                return own.contains(key);
            });
        });
        if (shared) return name;
    }
    return i18nc("@label an Apps folder with no name", "Folder");
}

QString ApplicationCatalog::gather(int row, const QString &applicationId)
{
    if (applicationId.isEmpty() || entryIndex(applicationId) < 0) {
        return {};
    }
    QString target;
    if (const Folder *folder = folderAt(row)) {
        target = folder->id;
    } else {
        const Entry *entry = entryAt(row);
        if (!entry || entry->applicationId == applicationId) {
            return {};
        }
        target = folderOf(row);
        if (target.isEmpty()) {
            const QStringList pair{entry->applicationId, applicationId};
            target = QStringLiteral("f%1%2")
                .arg(QDateTime::currentMSecsSinceEpoch(), 0, 36)
                .arg(QRandomGenerator::global()->bounded(1296), 0, 36);
            // The pair leaves any folder it was in, then makes the new one.
            for (Folder &folder : m_folders) {
                folder.applications.removeAll(pair.at(0));
            }
            m_folders.append({target, nameFor(pair), {pair.at(0)}});
        }
    }
    for (Folder &folder : m_folders) {
        if (folder.id != target) folder.applications.removeAll(applicationId);
    }
    Folder &folder = m_folders[folderIndex(target)];
    if (!folder.applications.contains(applicationId)) {
        folder.applications.append(applicationId);
    }
    storeFolders();
    return target;
}

void ApplicationCatalog::putInFolder(int row, const QString &folderId)
{
    const Entry *entry = entryAt(row);
    const int at = folderIndex(folderId);
    if (!entry || at < 0 || m_folders.at(at).applications.contains(entry->applicationId)) {
        return;
    }
    const QString id = entry->applicationId;
    for (Folder &folder : m_folders) {
        folder.applications.removeAll(id);
    }
    m_folders[folderIndex(folderId)].applications.append(id);
    storeFolders();
}

void ApplicationCatalog::takeOut(int row)
{
    const Entry *entry = entryAt(row);
    if (!entry) return;
    const QString id = entry->applicationId;
    for (Folder &folder : m_folders) {
        folder.applications.removeAll(id);
    }
    storeFolders();
}

void ApplicationCatalog::renameFolder(const QString &folderId, const QString &name)
{
    const int at = folderIndex(folderId);
    if (at < 0 || m_folders.at(at).name == name.trimmed()) return;
    m_folders[at].name = name.trimmed();
    storeFolders();
}

void ApplicationCatalog::removeFolder(const QString &folderId)
{
    const int at = folderIndex(folderId);
    if (at < 0) return;
    m_folders.remove(at);
    storeFolders();
}

QList<QUrl> ApplicationCatalog::folderUrls(int row) const
{
    QList<QUrl> urls;
    const Folder *folder = folderAt(row);
    if (!folder) return urls;
    QVector<int> members = drawnFolders().value(-1 - m_visibleRows.at(row));
    sortEntries(members);
    for (int at : members) {
        QString path = m_entries.at(at).service->entryPath();
        if (QDir::isRelativePath(path))
            path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, path);
        if (!path.isEmpty()) urls.append(QUrl::fromLocalFile(path));
    }
    return urls;
}

void ApplicationCatalog::storeFolders()
{
    // A folder of one application is no longer one.
    m_folders.erase(std::remove_if(m_folders.begin(), m_folders.end(),
                                   [](const Folder &folder) { return folder.applications.size() < 2; }),
                    m_folders.end());
    QJsonArray stored;
    for (const Folder &folder : m_folders) {
        stored.append(QJsonObject{{QStringLiteral("id"), folder.id},
                                  {QStringLiteral("name"), folder.name},
                                  {QStringLiteral("apps"), QJsonArray::fromStringList(folder.applications)}});
    }
    QSettings().setValue(FoldersKey, QString::fromUtf8(QJsonDocument(stored).toJson(QJsonDocument::Compact)));
    rebuildVisibleRows();
}

QString ApplicationCatalog::openFolder() const
{
    return m_openFolder;
}

void ApplicationCatalog::setOpenFolder(const QString &folderId)
{
    const QString open = folderIndex(folderId) >= 0 ? folderId : QString();
    if (m_openFolder == open) return;
    m_openFolder = open;
    rebuildVisibleRows();
    Q_EMIT openFolderChanged();
}

QString ApplicationCatalog::openFolderName() const
{
    const int at = folderIndex(m_openFolder);
    if (at < 0) return {};
    return m_folders.at(at).name.isEmpty()
        ? i18nc("@label an Apps folder with no name", "Folder") : m_folders.at(at).name;
}

int ApplicationCatalog::folderCount() const
{
    return m_drawnFolders;
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

void ApplicationCatalog::sortEntries(QVector<int> &rows) const
{
    // Entry indices are already A to Z, so a stable sort keeps it among equals.
    std::sort(rows.begin(), rows.end());
    switch (m_sortOrder) {
    case NameDescending:
        std::reverse(rows.begin(), rows.end());
        break;
    case MostUsed:
        std::stable_sort(rows.begin(), rows.end(), [this](int left, int right) {
            return m_use.value(m_entries.at(left).applicationId)
                > m_use.value(m_entries.at(right).applicationId);
        });
        break;
    case NewestInstalled:
        std::stable_sort(rows.begin(), rows.end(), [this](int left, int right) {
            return m_entries.at(left).installed > m_entries.at(right).installed;
        });
        break;
    default:
        break;
    }
}

void ApplicationCatalog::rebuildVisibleRows()
{
    const QString wasOpen = m_openFolder;
    const int wasDrawn = m_drawnFolders;
    beginResetModel();
    m_visibleRows.clear();
    m_visibleRows.reserve(m_entries.size());

    const QHash<int, QVector<int>> drawn = drawnFolders();
    m_drawnFolders = drawn.size();
    // A folder that is no longer drawn closes.
    if (!m_openFolder.isEmpty() && !drawn.contains(folderIndex(m_openFolder))) {
        m_openFolder.clear();
    }

    QVector<int> entries;
    if (!m_filterText.isEmpty()) {
        for (int at = 0; at < m_entries.size(); ++at) {
            const Entry &entry = m_entries.at(at);
            if (shown(entry) && entry.name.contains(m_filterText, Qt::CaseInsensitive)) {
                entries.append(at);
            }
        }
    } else if (!m_openFolder.isEmpty()) {
        entries = drawn.value(folderIndex(m_openFolder));
    } else {
        QSet<int> inFolders;
        for (const QVector<int> &members : drawn) {
            for (int at : members) inFolders.insert(at);
        }
        QVector<int> folders(drawn.keyBegin(), drawn.keyEnd());
        std::sort(folders.begin(), folders.end(), [this](int left, int right) {
            const int byName = QString::localeAwareCompare(m_folders.at(left).name, m_folders.at(right).name);
            return byName != 0 ? byName < 0 : left < right;
        });
        for (int folder : folders) {
            m_visibleRows.append(-1 - folder);
        }
        for (int at = 0; at < m_entries.size(); ++at) {
            if (shown(m_entries.at(at)) && !inFolders.contains(at)) {
                entries.append(at);
            }
        }
    }
    sortEntries(entries);
    m_visibleRows.append(entries);
    endResetModel();
    if (wasDrawn != m_drawnFolders) Q_EMIT foldersChanged();
    if (wasOpen != m_openFolder) Q_EMIT openFolderChanged();
}
