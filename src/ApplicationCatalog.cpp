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
#include <KIO/CommandLauncherJob>
#include <KIO/OpenUrlJob>
#include <KApplicationTrader>
#include <KDirWatch>
#include <KLocalizedString>
#include <KShell>
#include <KSycoca>

#include <QSettings>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <limits>

namespace
{
// The applications hidden from Apps, by desktop file id.
const QString HiddenKey = QStringLiteral("Browse/hiddenApplications");
const QString OrderKey = QStringLiteral("Browse/sortOrder");
const QString TileSizeKey = QStringLiteral("Browse/tileSize");
// Apps' folders, as JSON: a list of {id, name, apps}, apps by desktop file id.
const QString FoldersKey = QStringLiteral("Browse/folders");
// The folders left open, by id.
const QString OpenFoldersKey = QStringLiteral("Browse/openFolders");

// How long ago, in whole days, against the current date: never, for no
// date, and none for one still to come.
qint64 daysSince(const QDateTime &when)
{
    if (!when.isValid()) return std::numeric_limits<qint64>::max();
    return std::max<qint64>(0, when.date().daysTo(QDate::currentDate()));
}

// Which of four spans a number of days falls in, the nearest first.
int spanOf(qint64 days, qint64 first, qint64 second, qint64 third)
{
    return days < first ? 0 : days < second ? 1 : days < third ? 2 : 3;
}

// When Apps first found each application, as JSON: {id: milliseconds since
// the epoch}, 0 for one already here when Apps began keeping count.
const QString ArrivalsKey = QStringLiteral("Browse/arrivals");
}

ApplicationCatalog::ApplicationCatalog(QObject *parent)
    : QAbstractListModel(parent)
    , m_entries(readEntries())
{
    // Installed, removed or edited while Search runs, Apps follows.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &ApplicationCatalog::reload);
    // KDE's list only changes when something rebuilds it, and nothing does
    // when an application arrives from pacman or Flatpak (whose exports are a
    // folder of links). So Search watches every folder applications are
    // installed to, the missing ones included, and once the installer has
    // settled asks for the list to be checked, which rebuilds it.
    auto *settle = new QTimer(this);
    settle->setSingleShot(true);
    settle->setInterval(2000);
    connect(settle, &QTimer::timeout, this, &ApplicationCatalog::checkInstalled);
    auto *installs = new KDirWatch(this);
    const QStringList data = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    for (const QString &dir : data) installs->addDir(dir + QStringLiteral("/applications"));
    connect(installs, &KDirWatch::dirty, settle, qOverload<>(&QTimer::start));
    connect(installs, &KDirWatch::created, settle, qOverload<>(&QTimer::start));
    connect(installs, &KDirWatch::deleted, settle, qOverload<>(&QTimer::start));
    noteArrivals(m_entries);
    const QStringList hidden = QSettings().value(HiddenKey).toStringList();
    m_hidden = QSet<QString>(hidden.cbegin(), hidden.cend());
    const int order = QSettings().value(OrderKey, int(NameAscending)).toInt();
    m_sortOrder = order == MostUsed || order == NewestInstalled ? order : NameAscending;
    m_tileSize = std::clamp(QSettings().value(TileSizeKey, 1).toInt(), 0, 3);
    const QStringList open = QSettings().value(OpenFoldersKey).toStringList();
    m_openFolders = QSet<QString>(open.cbegin(), open.cend());
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

QVector<ApplicationCatalog::Entry> ApplicationCatalog::readEntries()
{
    QVector<Entry> entries;
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
        entries.append({service, service->name().trimmed(),
                        service->icon().trimmed(), id, {}});
    }
    std::sort(entries.begin(), entries.end(),
              [](const Entry &left, const Entry &right) {
        return QString::localeAwareCompare(left.name, right.name) < 0;
    });
    return entries;
}

void ApplicationCatalog::noteArrivals(QVector<Entry> &entries)
{
    // A package manager replaces an application's desktop file at each
    // update, and Flatpak's is a link into each update's own folder, so the
    // file's dates say when it was last updated. Arrival is when Apps first
    // found it instead, kept by its id.
    QSettings settings;
    const bool counting = settings.contains(ArrivalsKey);
    QJsonObject arrivals = QJsonDocument::fromJson(settings.value(ArrivalsKey).toString().toUtf8()).object();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool added = false;
    for (Entry &entry : entries) {
        if (!arrivals.contains(entry.applicationId)) {
            // Those here as Apps begins keeping count arrived before it.
            arrivals.insert(entry.applicationId, counting ? now : qint64(0));
            added = true;
        }
        const qint64 at = arrivals.value(entry.applicationId).toInteger();
        entry.installed = at > 0 ? QDateTime::fromMSecsSinceEpoch(at) : QDateTime();
    }
    if (added || !counting) {
        settings.setValue(ArrivalsKey, QString::fromUtf8(QJsonDocument(arrivals).toJson(QJsonDocument::Compact)));
    }
}

void ApplicationCatalog::checkInstalled()
{
    // KDE checks only the folders its list was built from. One made since,
    // as Flatpak's first install makes its exports, is never looked at, so
    // the list is rebuilt outright; the rebuilt list arrives as a change.
    QSet<QString> known;
    const QStringList built = KSycoca::self()->allResourceDirs();
    for (const QString &dir : built) known.insert(QDir::cleanPath(dir));
    const QStringList folders = QStandardPaths::locateAll(
        QStandardPaths::GenericDataLocation, QStringLiteral("applications"), QStandardPaths::LocateDirectory);
    for (const QString &dir : folders) {
        if (!known.contains(QDir::cleanPath(dir))) {
            QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
            return;
        }
    }
    KSycoca::self()->ensureCacheValid();
}

void ApplicationCatalog::reload()
{
    // Folders, hidden applications, the order and the words typed are kept
    // by id, so they hold over the new list; a folder whose applications have
    // gone stops being drawn, as it would at the next start.
    const int wasHidden = hiddenCount();
    QVector<Entry> entries = readEntries();
    noteArrivals(entries);
    rebuildVisibleRows(&entries);
    if (hiddenCount() != wasHidden) Q_EMIT hiddenCountChanged();
}

int ApplicationCatalog::applicationRow(const QString &applicationId) const
{
    if (applicationId.isEmpty()) return -1;
    for (int row = 0; row < m_visibleRows.size(); ++row) {
        const Row &drawn = m_visibleRows.at(row);
        if ((drawn.kind == ApplicationRow || drawn.kind == MemberRow)
            && m_entries.at(drawn.at).applicationId == applicationId) return row;
    }
    return -1;
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
    const Row &row = m_visibleRows.at(index.row());
    if (row.kind == SectionRow) {
        switch (role) {
        case NameRole:
            return row.label;
        case KindRole:
            return QStringLiteral("section");
        case IsFolderRole:
        case HiddenRole:
        case OpenRole:
            return false;
        default:
            return {};
        }
    }
    if (const Folder *folder = folderAt(index.row())) {
        switch (role) {
        case KindRole:
            return QStringLiteral("folder");
        case OpenRole:
            return m_openFolders.contains(folder->id);
        case SizeRole:
            return drawnFolders().value(row.at).size();
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
    const Entry &entry = m_entries.at(row.at);
    switch (role) {
    case KindRole:
        return row.kind == MemberRow ? QStringLiteral("member") : QStringLiteral("application");
    case OpenRole:
        return false;
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
        {KindRole, QByteArrayLiteral("kind")},
        {OpenRole, QByteArrayLiteral("open")},
        {SizeRole, QByteArrayLiteral("size")},
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
    if (row < 0 || row >= m_visibleRows.size()) return nullptr;
    const Row &drawn = m_visibleRows.at(row);
    return drawn.kind == ApplicationRow || drawn.kind == MemberRow ? &m_entries.at(drawn.at) : nullptr;
}

const ApplicationCatalog::Folder *ApplicationCatalog::folderAt(int row) const
{
    if (row < 0 || row >= m_visibleRows.size() || m_visibleRows.at(row).kind != FolderRow) {
        return nullptr;
    }
    return &m_folders.at(m_visibleRows.at(row).at);
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

QVariantMap ApplicationCatalog::item(int row) const
{
    QVariantMap item;
    if (row < 0 || row >= m_visibleRows.size()) return item;
    const QHash<int, QByteArray> roles = roleNames();
    for (auto role = roles.cbegin(); role != roles.cend(); ++role) {
        item.insert(QString::fromLatin1(role.value()), data(index(row), role.key()));
    }
    return item;
}

QString ApplicationCatalog::kind(int row) const
{
    return row >= 0 && row < m_visibleRows.size() ? data(index(row), KindRole).toString() : QString();
}

bool ApplicationCatalog::isOpen(int row) const
{
    const Folder *folder = folderAt(row);
    return folder && m_openFolders.contains(folder->id);
}

void ApplicationCatalog::setFolderOpen(const QString &folderId, bool open)
{
    if (folderIndex(folderId) < 0 || m_openFolders.contains(folderId) == open) return;
    if (open) m_openFolders.insert(folderId);
    else m_openFolders.remove(folderId);
    storeOpenFolders();
    rebuildVisibleRows();
}

int ApplicationCatalog::folderRow(const QString &folderId) const
{
    for (int row = 0; row < m_visibleRows.size(); ++row) {
        const Row &drawn = m_visibleRows.at(row);
        if (drawn.kind == FolderRow && m_folders.at(drawn.at).id == folderId) return row;
    }
    return -1;
}

void ApplicationCatalog::storeOpenFolders()
{
    QStringList stored;
    for (const Folder &folder : m_folders) {
        if (m_openFolders.contains(folder.id)) stored.append(folder.id);
    }
    m_openFolders = QSet<QString>(stored.cbegin(), stored.cend());
    QSettings().setValue(OpenFoldersKey, stored);
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
            m_openFolders.insert(target);
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

QString ApplicationCatalog::makeFolder(const QStringList &applicationIds)
{
    QStringList chosen;
    for (const QString &id : applicationIds) {
        if (!id.isEmpty() && !chosen.contains(id) && entryIndex(id) >= 0) chosen.append(id);
    }
    if (chosen.size() < 2) {
        return {};
    }
    const QString target = QStringLiteral("f%1%2")
        .arg(QDateTime::currentMSecsSinceEpoch(), 0, 36)
        .arg(QRandomGenerator::global()->bounded(1296), 0, 36);
    for (Folder &folder : m_folders) {
        for (const QString &id : chosen) folder.applications.removeAll(id);
    }
    m_folders.append({target, nameFor(chosen), chosen});
    m_openFolders.insert(target);
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
    QVector<int> members = drawnFolders().value(m_visibleRows.at(row).at);
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
    storeOpenFolders();
    rebuildVisibleRows();
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
    return entry && canUninstallApplication(entry->applicationId);
}

bool ApplicationCatalog::uninstall(int row)
{
    const Entry *entry = entryAt(row);
    return entry && uninstallApplication(entry->applicationId);
}

bool ApplicationCatalog::canUninstallApplication(const QString &applicationId) const
{
    const int at = entryIndex(applicationId);
    if (at < 0) return false;
    if (m_canRemove && m_canRemove()) return true;
    return m_softwareReady
        && KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/appstream"))
        && !softwareId(m_entries.at(at)).isEmpty();
}

bool ApplicationCatalog::uninstallApplication(const QString &applicationId)
{
    const int at = entryIndex(applicationId);
    if (at < 0) return false;
    const Entry &entry = m_entries.at(at);
    if (m_canRemove && m_canRemove() && m_remove) {
        m_remove(entry.applicationId, entry.name);
        return true;
    }
    const QString id = softwareId(entry);
    if (id.isEmpty()) {
        return false;
    }
    auto *job = new KIO::OpenUrlJob(QUrl(QStringLiteral("appstream://") + id), this);
    job->start();
    return true;
}

bool ApplicationCatalog::canEdit(int row) const
{
    const Entry *entry = entryAt(row);
    return entry && entry->service->isApplication()
        && KService::serviceByDesktopName(QStringLiteral("org.kde.kmenuedit"));
}

bool ApplicationCatalog::edit(int row)
{
    const KService::Ptr editor = KService::serviceByDesktopName(QStringLiteral("org.kde.kmenuedit"));
    if (!editor || !canEdit(row)) {
        return false;
    }
    // The editor finds the entry by its desktop file id, which is its menu id,
    // in whichever menu holds it, and a running editor turns to it.
    // The editor's own command line may carry options and field codes after
    // its program, which is all that is run here.
    const QString program = KShell::splitArgs(editor->exec()).value(0);
    if (program.isEmpty()) {
        return false;
    }
    auto *job = new KIO::CommandLauncherJob(program, {entryAt(row)->applicationId}, this);
    job->setDesktopName(editor->desktopEntryName());
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

int ApplicationCatalog::tileSize() const
{
    return m_tileSize;
}

void ApplicationCatalog::setTileSize(int tileSize)
{
    tileSize = std::clamp(tileSize, 0, 3);
    if (m_tileSize == tileSize) {
        return;
    }
    m_tileSize = tileSize;
    QSettings().setValue(TileSizeKey, tileSize);
    Q_EMIT tileSizeChanged();
}

int ApplicationCatalog::sortOrder() const
{
    return m_sortOrder;
}

void ApplicationCatalog::setSortOrder(int sortOrder)
{
    if ((sortOrder != NameAscending && sortOrder != MostUsed && sortOrder != NewestInstalled)
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
    case MostUsed:
        // Section by section, the most used first inside each.
        std::stable_sort(rows.begin(), rows.end(), [this](int left, int right) {
            const int leftSpan = useSpan(left);
            const int rightSpan = useSpan(right);
            if (leftSpan != rightSpan) return leftSpan < rightSpan;
            return m_use.value(m_entries.at(left).applicationId).score
                > m_use.value(m_entries.at(right).applicationId).score;
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

int ApplicationCatalog::useSpan(int entry) const
{
    // The same day, the week, the month, or earlier or never.
    return spanOf(daysSince(m_use.value(m_entries.at(entry).applicationId).last), 1, 7, 31);
}

QPair<QString, QString> ApplicationCatalog::sectionOf(int entry) const
{
    const Entry &own = m_entries.at(entry);
    switch (m_sortOrder) {
    case MostUsed: {
        const int span = useSpan(entry);
        const QString key = QString::number(span);
        if (span == 0) return {key, i18nc("@title a section of Apps", "Used today")};
        if (span == 1) return {key, i18nc("@title a section of Apps", "This week")};
        if (span == 2) return {key, i18nc("@title a section of Apps", "This month")};
        return {key, i18nc("@title a section of Apps", "Earlier")};
    }
    case NewestInstalled: {
        const int span = spanOf(daysSince(own.installed), 7, 31, 365);
        const QString key = QString::number(span);
        if (span == 0) return {key, i18nc("@title a section of Apps", "This week")};
        if (span == 1) return {key, i18nc("@title a section of Apps", "This month")};
        if (span == 2) return {key, i18nc("@title a section of Apps", "This year")};
        return {key, i18nc("@title a section of Apps", "Older")};
    }
    default:
        // A to Z runs as one, with no sections.
        return {};
    }
}

QString ApplicationCatalog::folderLabel(int folder) const
{
    return m_folders.at(folder).name.isEmpty()
        ? i18nc("@label an Apps folder with no name", "Folder") : m_folders.at(folder).name;
}

QPair<QString, QString> ApplicationCatalog::folderSection(const QVector<int> &members) const
{
    // Its first application in the order, which its open folder shows first.
    QVector<int> ordered = members;
    sortEntries(ordered);
    return sectionOf(ordered.constFirst());
}

void ApplicationCatalog::rebuildVisibleRows(QVector<Entry> *entries)
{
    const int wasDrawn = m_drawnFolders;
    beginResetModel();
    if (entries) m_entries.swap(*entries);
    m_visibleRows.clear();
    m_visibleRows.reserve(m_entries.size());

    const QHash<int, QVector<int>> drawn = drawnFolders();
    m_drawnFolders = drawn.size();

    if (!m_filterText.isEmpty()) {
        QVector<int> entries;
        for (int at = 0; at < m_entries.size(); ++at) {
            const Entry &entry = m_entries.at(at);
            if (shown(entry) && entry.name.contains(m_filterText, Qt::CaseInsensitive)) {
                entries.append(at);
            }
        }
        sortEntries(entries);
        for (int at : entries) m_visibleRows.append({ApplicationRow, at, {}});
    } else {
        QSet<int> inFolders;
        for (const QVector<int> &members : drawn) {
            for (int at : members) inFolders.insert(at);
        }
        // An open folder's row, then its applications in the order.
        const auto appendFolder = [this, &drawn](int folder) {
            m_visibleRows.append({FolderRow, folder, {}});
            if (!m_openFolders.contains(m_folders.at(folder).id)) return;
            QVector<int> members = drawn.value(folder);
            sortEntries(members);
            for (int at : members) m_visibleRows.append({MemberRow, at, {}});
        };
        if (m_sortOrder == NameAscending) {
            // One run A to Z, each folder among the applications at its
            // name's place; a folder goes before an application of its name.
            QVector<Row> run;
            for (auto folder = drawn.cbegin(); folder != drawn.cend(); ++folder) {
                run.append({FolderRow, folder.key(), folderLabel(folder.key())});
            }
            for (int at = 0; at < m_entries.size(); ++at) {
                if (shown(m_entries.at(at)) && !inFolders.contains(at)) {
                    run.append({ApplicationRow, at, m_entries.at(at).name});
                }
            }
            std::stable_sort(run.begin(), run.end(), [](const Row &left, const Row &right) {
                const int byName = QString::localeAwareCompare(left.label, right.label);
                if (byName != 0) return byName < 0;
                if (left.kind != right.kind) return left.kind == FolderRow;
                return left.at < right.at;
            });
            for (const Row &row : run) {
                if (row.kind == FolderRow) appendFolder(row.at);
                else m_visibleRows.append({ApplicationRow, row.at, {}});
            }
        } else {
            struct Section {
                QString label;
                QVector<int> folders;
                QVector<int> entries;
            };
            // The keys are already in the order's own.
            QMap<QString, Section> sections;
            for (auto folder = drawn.cbegin(); folder != drawn.cend(); ++folder) {
                const auto [key, label] = folderSection(folder.value());
                sections[key].label = label;
                sections[key].folders.append(folder.key());
            }
            for (int at = 0; at < m_entries.size(); ++at) {
                if (!shown(m_entries.at(at)) || inFolders.contains(at)) continue;
                const auto [key, label] = sectionOf(at);
                sections[key].label = label;
                sections[key].entries.append(at);
            }
            for (auto section = sections.begin(); section != sections.end(); ++section) {
                m_visibleRows.append({SectionRow, -1, section->label});
                std::sort(section->folders.begin(), section->folders.end(), [this](int left, int right) {
                    const int byName = QString::localeAwareCompare(folderLabel(left), folderLabel(right));
                    return byName != 0 ? byName < 0 : left < right;
                });
                for (int folder : section->folders) appendFolder(folder);
                sortEntries(section->entries);
                for (int at : section->entries) m_visibleRows.append({ApplicationRow, at, {}});
            }
        }
    }
    endResetModel();
    if (wasDrawn != m_drawnFolders) Q_EMIT foldersChanged();
}
