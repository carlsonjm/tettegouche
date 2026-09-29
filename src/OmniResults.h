#pragma once
#include "SearchPolicy.h"
#include "RunnerIdentity.h"

#include <KRunner/AbstractRunner>
#include <KRunner/ResultsModel>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QConcatenateTablesProxyModel>
#include <QStandardItemModel>
#include <QProcess>
#include <QStandardPaths>
#include <QJsonObject>
#include <QSettings>
#include <QDir>
#include <QTimer>
#include <climits>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>

inline bool withinQuietFolder(const QString &path, const QStringList &folders) {
    const auto clean = QDir::cleanPath(path);
    for (QString folder : folders) {
        folder = folder.trimmed();
        if (folder.startsWith(QStringLiteral("~/"))) folder.replace(0, 1, QDir::homePath());
        if (!QDir::isAbsolutePath(folder)) continue;
        folder = QDir::cleanPath(folder);
        if (clean == folder || clean.startsWith(folder + QLatin1Char('/'))) return true;
    }
    return false;
}

inline bool bundledFile(const QString &path) {
    static const QRegularExpression bundles(QStringLiteral(
        "(?:\\.app/Contents/|/(?:node_modules|vendor|site-packages|dist-packages|wp-includes|wp-admin)/)"));
    return bundles.match(path).hasMatch();
}

inline QString intentText(QString text) {
    return text.toCaseFolded().remove(QRegularExpression(QStringLiteral("[\\s-]+")));
}

inline QStringList settingAliases(const QString &id) {
    static const QHash<QString, QStringList> aliases = {
        {QStringLiteral("kcm_bluetooth"), {QStringLiteral("bluetooth")}},
        {QStringLiteral("kcm_networkmanagement"), {QStringLiteral("wifi"), QStringLiteral("network"), QStringLiteral("internet"), QStringLiteral("vpn")}},
        {QStringLiteral("kcm_pulseaudio"), {QStringLiteral("sound"), QStringLiteral("audio"), QStringLiteral("volume"), QStringLiteral("microphone"), QStringLiteral("speaker")}},
        {QStringLiteral("kcm_kscreen"), {QStringLiteral("display"), QStringLiteral("monitor"), QStringLiteral("resolution"), QStringLiteral("scaling")}},
        {QStringLiteral("kcm_powerdevilprofilesconfig"), {QStringLiteral("power"), QStringLiteral("battery")}},
        {QStringLiteral("kcm_printer_manager"), {QStringLiteral("printer"), QStringLiteral("printing"), QStringLiteral("print")}},
        {QStringLiteral("kcm_solid_actions"), {QStringLiteral("storage"), QStringLiteral("disk"), QStringLiteral("drive"), QStringLiteral("removable devices")}},
        {QStringLiteral("kcm_componentchooser"), {QStringLiteral("default apps"), QStringLiteral("default applications")}},
        {QStringLiteral("kcm_nightlight"), {QStringLiteral("night light")}},
        {QStringLiteral("kcm_kdeconnect"), {QStringLiteral("kde connect")}}
    };
    for (auto it = aliases.cbegin(); it != aliases.cend(); ++it)
        if (id == it.key() || id.endsWith(QLatin1Char('_') + it.key())) return it.value();
    return {};
}

inline bool settingIntent(const QString &id, const QString &query) {
    const auto normalized = intentText(query);
    if (normalized.size() < 2) return false;
    for (const auto &alias : settingAliases(id))
        if (intentText(alias).startsWith(normalized)) return true;
    return false;
}

// Local aliases only expose modules actually installed on this machine.
// Launching remains an explicit user action and uses no shell.
class SettingsAliasRunner : public KRunner::AbstractRunner {
public:
    SettingsAliasRunner() : AbstractRunner(nullptr, KPluginMetaData(QJsonObject{
        {QStringLiteral("KPlugin"), QJsonObject{{QStringLiteral("Id"), QStringLiteral("systemsettings")}, {QStringLiteral("Name"), QStringLiteral("System Settings")}}}},
        QStringLiteral("systemsettings"))) {}
    void match(KRunner::RunnerContext &) override {}
};

inline int nameMatchQuality(QString name, QString query)
{
    name = name.toCaseFolded();
    query = query.simplified().toCaseFolded();
    if (query.isEmpty()) return 3;
    if (name == query || QFileInfo(name).completeBaseName() == query) return 0;
    if (name.startsWith(query)) return 1;
    const auto words = query.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    for (const auto &word : words) if (!name.contains(word)) return 3;
    return 2;
}

inline bool usefulFile(const QString &path, const QString &query)
{
    const QString normalized = QLatin1Char('/') + path + QLatin1Char('/');
    for (const auto &part : {"/.cache/", "/.git/", "/node_modules/", "/go/pkg/mod/",
                             "/.cargo/registry/", "/.venv/", "/__pycache__/",
                             "/CMakeFiles/", "/CMakeTmp/"})
        if (normalized.contains(QString::fromLatin1(part))) return false;
    static const QRegularExpression generatedDirectory(
        QStringLiteral("/(?:build(?:[-_][^/]*)?|cmake-build-[^/]+|[^/]+_autogen)/"));
    if (generatedDirectory.match(normalized).hasMatch()) return false;
    const QFileInfo file(path);
    const QString suffix = file.suffix().toLower();
    static const QSet<QString> artifacts = {
        QStringLiteral("d"), QStringLiteral("o"), QStringLiteral("obj"),
        QStringLiteral("pyc"), QStringLiteral("qmlc"), QStringLiteral("a"),
        QStringLiteral("so"), QStringLiteral("moc")};
    if (artifacts.contains(suffix)) return false;
    static const QSet<QString> technical = {
        QStringLiteral("h"), QStringLiteral("hpp"), QStringLiteral("hh"),
        QStringLiteral("hxx"), QStringLiteral("c"), QStringLiteral("cpp"),
        QStringLiteral("cc"), QStringLiteral("cxx"), QStringLiteral("go"),
        QStringLiteral("rs"), QStringLiteral("py"), QStringLiteral("js"),
        QStringLiteral("ts"), QStringLiteral("jsx"), QStringLiteral("tsx"),
        QStringLiteral("qml"), QStringLiteral("sh"), QStringLiteral("bash"),
        QStringLiteral("fish"), QStringLiteral("cmake"), QStringLiteral("json"),
        QStringLiteral("yaml"), QStringLiteral("yml"), QStringLiteral("toml"),
        QStringLiteral("ini"), QStringLiteral("conf"), QStringLiteral("desktop"),
        QStringLiteral("service"), QStringLiteral("socket"), QStringLiteral("lock")};
    // Explicit extension is an intentional technical-file search, not a setting
    // query that happens to match a source identifier. Never widen KDE's index.
    if (technical.contains(suffix)
        && !query.trimmed().endsWith(QLatin1Char('.') + suffix, Qt::CaseInsensitive)) return false;
    return !path.isEmpty() && nameMatchQuality(file.fileName(), query) < 3;
}

inline QString matchFilePath(const KRunner::QueryMatch &match)
{
    for (const auto &url : match.urls()) if (url.isLocalFile()) return url.toLocalFile();
    const auto url = match.data().toUrl();
    return url.isLocalFile() ? url.toLocalFile() : QString();
}

// Explicit provider allowlist: no shell execution, destructive session actions,
// browser history, or online requests while the user is typing.
inline int searchTier(const QString &id)
{
    if (id == QStringLiteral("services") || id == QStringLiteral("krunner_services")) return 0;
    if (id == QStringLiteral("baloosearch") || id == QStringLiteral("recentdocuments")
        || id == QStringLiteral("krunner_recentdocuments")) return 1;
    if (id == QStringLiteral("krunner_systemsettings") || id == QStringLiteral("systemsettings")
        || id == QStringLiteral("calculator") || id == QStringLiteral("unitconverter")) return 2;
    return 3;
}

inline int searchTier(const KRunner::QueryMatch &match)
{
    return match.runner() ? searchTier(match.runner()->id()) : 3;
}

inline int resultPriority(const KRunner::QueryMatch &match, const QString &query) {
    const int tier = searchTier(match);
    const bool setting = match.runner() && match.runner()->id().contains(QStringLiteral("systemsettings"));
    auto aliases = setting ? settingAliases(match.id()) : QStringList();
    if (tier == 1) aliases.append(QFileInfo(matchFilePath(match)).completeBaseName());
    auto evidence = SearchPolicy::evaluate(match.text(), aliases,
        tier == 1 ? QString() : match.subtext(), query);
    // A file stem is a name, not a semantic alias: preserve ordinary prefix
    // confidence rather than promoting filename prefixes to named intent.
    if (tier == 1 && evidence.confidence == SearchPolicy::NamedIntent)
        evidence.confidence = SearchPolicy::Prefix;
    if (match.runner() && (match.runner()->id() == QStringLiteral("calculator")
        || match.runner()->id() == QStringLiteral("unitconverter"))) evidence = {SearchPolicy::Exact, 0};
    return SearchPolicy::priority(evidence, tier);
}

inline QString destinationKey(const KRunner::QueryMatch &match) {
    if (!match.runner()) return {};
    const auto runner = match.runner()->id();
    if (runner.contains(QStringLiteral("systemsettings"))) {
        const auto position = match.id().indexOf(QStringLiteral("kcm_"));
        if (position >= 0) return QStringLiteral("setting:") + match.id().mid(position);
    }
    if (searchTier(match) == 0) {
        auto app = runnerApplicationId(match);
        if (!app.isEmpty()) {
            app = QFileInfo(app).fileName();
            if (app.startsWith(QStringLiteral("kcm_")) && app.endsWith(QStringLiteral(".desktop")))
                return QStringLiteral("setting:") + app.chopped(8);
            return QStringLiteral("app:") + app;
        }
    }
    if (searchTier(match) == 1) {
        const auto path = matchFilePath(match);
        if (!path.isEmpty()) return QStringLiteral("file:") + QDir::cleanPath(path);
    }
    // Never infer equivalence from display titles or resolve filesystem links:
    // different files with identical names and distinct tools remain distinct.
    return runner + QLatin1Char(':') + match.id();
}

class SearchSource : public KRunner::ResultsModel {
public:
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
        if (role == KRunner::ResultsModel::QueryMatchRole)
            return QVariant::fromValue(getQueryMatch(index));
        return KRunner::ResultsModel::data(index, role);
    }
};

// Both inputs deliberately share KRunner's numeric roles. Avoid the generic
// concatenator's name-based remapping of the standard-item source's roles.
class SearchSources : public QConcatenateTablesProxyModel {
public:
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
        return mapToSource(index).data(role);
    }
};

class OmniResults : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString queryString READ queryString WRITE setQueryString NOTIFY queryStringChanged)
    Q_PROPERTY(bool querying READ querying NOTIFY queryingChanged)
    Q_PROPERTY(bool allFiles READ allFiles WRITE setAllFiles NOTIFY scopeChanged)
    Q_PROPERTY(QString quietFolders READ quietFolders WRITE setQuietFolders NOTIFY scopeChanged)
public:
    explicit OmniResults(QObject *parent = nullptr) : QSortFilterProxyModel(parent) {
        QSettings settings(QStringLiteral("studio.warbler"), QStringLiteral("tettegouche-search"));
        const auto fallback = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
            + QStringLiteral("/Design Library");
        m_quietFolders = settings.value(QStringLiteral("quietFolders"),
            QFileInfo::exists(fallback) ? fallback : QString()).toString();
        m_aliases.setColumnCount(1);
        m_combined.addSourceModel(&m_results);
        m_combined.addSourceModel(&m_aliases);
        setSourceModel(&m_combined);
        m_modules = KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms/systemsettings"));
        m_modules.append(KPluginMetaData::findPlugins(QStringLiteral("plasma/kcms/systemsettings_qwidgets")));
        setDynamicSortFilter(true);
        sort(0);
        connect(&m_results, &KRunner::ResultsModel::queryStringChanged, this, &OmniResults::queryStringChanged);
        connect(&m_results, &KRunner::ResultsModel::queryingChanged, this, &OmniResults::queryingChanged);
        connect(this, &QAbstractItemModel::layoutChanged, this, &OmniResults::selectionChanged);
        connect(this, &QAbstractItemModel::rowsInserted, this, &OmniResults::selectionChanged);
        connect(this, &QAbstractItemModel::rowsRemoved, this, &OmniResults::selectionChanged);
        connect(this, &QAbstractItemModel::modelReset, this, &OmniResults::selectionChanged);
        const auto refresh = [this]() {
            if (m_refreshQueued) return;
            m_refreshQueued = true;
            QTimer::singleShot(0, this, [this]() { m_refreshQueued = false; invalidate(); });
        };
        connect(&m_combined, &QAbstractItemModel::rowsInserted, this, refresh);
        connect(&m_combined, &QAbstractItemModel::rowsRemoved, this, refresh);
        connect(&m_combined, &QAbstractItemModel::dataChanged, this, refresh);
        connect(&m_combined, &QAbstractItemModel::modelReset, this, refresh);
        connect(&m_combined, &QAbstractItemModel::layoutChanged, this, refresh);
    }
    Q_INVOKABLE void pinSelection(int row) {
        if (row < 0 || row >= rowCount()) return;
        if (m_frozenOrder.isEmpty()) {
            for (int i = 0; i < rowCount(); ++i)
                m_frozenOrder.insert(destinationKey(getQueryMatch(index(i, 0))), i);
        }
        m_selectedDestination = destinationKey(getQueryMatch(index(row, 0)));
        Q_EMIT selectionChanged();
    }
    Q_INVOKABLE bool selectionPinned() const { return !m_selectedDestination.isEmpty(); }
    Q_INVOKABLE int selectedRow() const {
        for (int i = 0; i < rowCount(); ++i)
            if (destinationKey(getQueryMatch(index(i, 0))) == m_selectedDestination) return i;
        return -1;
    }
    void releaseSelection() { m_selectedDestination.clear(); m_frozenOrder.clear(); }
    void setRunnerManager(KRunner::RunnerManager *manager) { m_results.setRunnerManager(manager); }
    void setLimit(int limit) { m_results.setLimit(limit); }
    virtual QString queryString() const { return m_results.queryString(); }
    bool allFiles() const { return m_allFiles; }
    void setAllFiles(bool value) { if (m_allFiles == value) return; releaseSelection(); m_allFiles = value; invalidate(); Q_EMIT scopeChanged(); }
    QString quietFolders() const { return m_quietFolders; }
    void setQuietFolders(const QString &value) {
        QSettings settings(QStringLiteral("studio.warbler"), QStringLiteral("tettegouche-search"));
        settings.setValue(QStringLiteral("quietFolders"), value);
        m_quietFolders = value;
        invalidate(); Q_EMIT scopeChanged();
    }
    void setQueryString(const QString &query) {
        releaseSelection();
        m_aliases.removeRows(0, m_aliases.rowCount());
        for (const auto &module : m_modules) {
            if (!settingIntent(module.pluginId(), query)) continue;
            KRunner::QueryMatch match(&m_aliasRunner);
            match.setId(module.pluginId());
            match.setText(module.name());
            match.setData(module.pluginId());
            auto *item = new QStandardItem(QIcon::fromTheme(module.iconName()), module.name());
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            item->setData(module.description(), KRunner::ResultsModel::SubtextRole);
            item->setData(true, KRunner::ResultsModel::EnabledRole);
            m_aliases.appendRow(item);
        }
        m_results.setQueryString(query);
        invalidate();
    }
    bool querying() const { return m_results.querying(); }
    QHash<int, QByteArray> roleNames() const override { return m_results.roleNames(); }
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
        return m_combined.data(mapToSource(index), role);
    }
    Q_INVOKABLE void clear() { releaseSelection(); m_aliases.removeRows(0, m_aliases.rowCount()); m_results.clear(); }
    Q_INVOKABLE bool run(const QModelIndex &index) {
        const auto source = m_combined.mapToSource(mapToSource(index));
        if (!source.isValid()) return false;
        if (source.model() == &m_aliases) {
            const auto module = getQueryMatch(index).data().toString();
            auto bus = QDBusConnection::sessionBus();
            if (bus.interface() && bus.interface()->isServiceRegistered(QStringLiteral("org.kde.systemsettings")).value()) {
                auto request = QDBusMessage::createMethodCall(QStringLiteral("org.kde.systemsettings"),
                    QStringLiteral("/org/kde/systemsettings"), QStringLiteral("org.kde.KDBusService"), QStringLiteral("CommandLine"));
                request.setArguments({QStringList{QStringLiteral("systemsettings"), module}, QDir::currentPath(), QVariantMap{}});
                const QDBusReply<int> reply = bus.call(request, QDBus::Block, 1000);
                return reply.isValid() && reply.value() == 0;
            }
            const auto executable = QStandardPaths::findExecutable(QStringLiteral("systemsettings"));
            return !executable.isEmpty() && QProcess::startDetached(executable,
                {module});
        }
        return m_results.run(source);
    }
    KRunner::QueryMatch getQueryMatch(const QModelIndex &index) const {
        return index.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
    }
Q_SIGNALS:
    void selectionChanged();
    void scopeChanged();
    void queryStringChanged(const QString &query);
    void queryingChanged();
protected:
    bool filterAcceptsRow(int row, const QModelIndex &parent) const override {
        if (!candidateEligible(row, parent)) return false;
        const auto match = sourceModel()->index(row, 0, parent)
            .data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
        const auto key = destinationKey(match);
        const auto priority = resultPriority(match, queryString());
        for (int other = 0; other < sourceModel()->rowCount(parent); ++other) {
            if (other == row) continue;
            const auto alternative = sourceModel()->index(other, 0, parent)
                .data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
            if (destinationKey(alternative) != key || !candidateEligible(other, parent)) continue;
            if (key.startsWith(QStringLiteral("setting:"))) {
                const bool canonical = match.runner()->id().contains(QStringLiteral("systemsettings"));
                const bool otherCanonical = alternative.runner()->id().contains(QStringLiteral("systemsettings"));
                if (canonical != otherCanonical) {
                    if (otherCanonical) return false;
                    continue;
                }
            }
            const auto otherPriority = resultPriority(alternative, queryString());
            if (otherPriority < priority || (otherPriority == priority && other < row)) return false;
        }
        return true;
    }
    bool candidateEligible(int row, const QModelIndex &parent) const {
        const auto match = sourceModel()->index(row, 0, parent)
            .data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
        if (searchTier(match) != 1 && resultPriority(match, queryString()) >= 5000) return false;
        if (match.runner() && match.runner() != &m_aliasRunner
            && match.runner()->id().contains(QStringLiteral("systemsettings"))) {
            for (int i = 0; i < m_aliases.rowCount(); ++i) {
                const auto id = m_aliases.index(i, 0).data(KRunner::ResultsModel::QueryMatchRole)
                    .value<KRunner::QueryMatch>().data().toString();
                if (match.id() == id || match.id().endsWith(QLatin1Char('_') + id)) return false;
            }
        }
        if (searchTier(match) != 1) return true;
        const auto path = matchFilePath(match);
        if (m_allFiles) return !path.isEmpty()
            && nameMatchQuality(QFileInfo(path).fileName(), queryString()) < 3;
        if (queryString().trimmed().size() < 3 || bundledFile(path)
            || withinQuietFolder(path, quietFolders().split(QLatin1Char('\n')))) return false;
        const auto directory = QFileInfo(path).absolutePath();
        if (!m_repoDirectories.contains(directory)) {
            QDir parent(directory);
            bool repository = false;
            do {
                if (QFileInfo::exists(parent.filePath(QStringLiteral(".git")))) { repository = true; break; }
            } while (parent.cdUp());
            m_repoDirectories.insert(directory, repository);
        }
        return !m_repoDirectories.value(directory) && usefulFile(path, queryString())
            && resultPriority(match, queryString()) < 5000;
    }
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override
    {
        if (!m_frozenOrder.isEmpty()) {
            const auto keyA = destinationKey(left.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
            const auto keyB = destinationKey(right.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
            const int a = m_frozenOrder.value(keyA, INT_MAX), b = m_frozenOrder.value(keyB, INT_MAX);
            if (a != b) return sortOrder() == Qt::AscendingOrder ? a < b : a > b;
        }
        const int qualityA = resultPriority(left.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>(), queryString());
        const int qualityB = resultPriority(right.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>(), queryString());
        if (qualityA != qualityB)
            return sortOrder() == Qt::AscendingOrder ? qualityA < qualityB : qualityA > qualityB;
        const int a = searchTier(left.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
        const int b = searchTier(right.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
        // QSortFilterProxyModel reverses the comparator for descending sorting.
        if (a != b) return sortOrder() == Qt::AscendingOrder ? a < b : a > b;
        // Preserve KDE's relevance order within each tier.
        return left.row() < right.row();
    }
private:
    bool m_refreshQueued = false;
    QString m_selectedDestination;
    QHash<QString, int> m_frozenOrder;
    bool m_allFiles = false;
    QString m_quietFolders;
    mutable QHash<QString, bool> m_repoDirectories;
    SettingsAliasRunner m_aliasRunner;
    SearchSource m_results;
    QStandardItemModel m_aliases;
    SearchSources m_combined;
    QList<KPluginMetaData> m_modules;
};
