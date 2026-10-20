#pragma once
#include <functional>
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
#include <QDBusArgument>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QPainter>
#include <QPixmap>
#include <KLocalizedString>

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

// The names Windows gives its own tools, kept for the apps that do those jobs
// here, so someone moving from Windows finds them by the words they know.
// A name of two words counts once the second word is begun: "file" alone
// still means files, "file e" means the file manager.
inline const QHash<QString, QStringList> &windowsNames() {
    static const QHash<QString, QStringList> names = {
        {QStringLiteral("systemsettings"), {QStringLiteral("control panel")}},
        {QStringLiteral("org.kde.plasma-systemmonitor"), {QStringLiteral("task manager")}},
        {QStringLiteral("org.kde.dolphin"), {QStringLiteral("file explorer"), QStringLiteral("windows explorer"),
            QStringLiteral("this pc"), QStringLiteral("my computer")}},
        {QStringLiteral("org.kde.kinfocenter"), {QStringLiteral("device manager")}}
    };
    return names;
}

inline QStringList windowsWordsReached(const QString &application, const QString &query) {
    const auto typed = intentText(query);
    QStringList reached;
    auto name = QFileInfo(application).fileName();
    if (name.endsWith(QStringLiteral(".desktop"))) name.chop(8);
    for (const auto &words : windowsNames().value(name)) {
        const auto first = intentText(words.section(QLatin1Char(' '), 0, 0));
        if (typed.size() > first.size() && intentText(words).startsWith(typed)) reached.append(words);
    }
    return reached;
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

// Notes found by the notes application, Gooseberry, which keeps them; Search
// only lists what it answers. Never registered with KRunner.
class NotesRunner : public KRunner::AbstractRunner {
public:
    static constexpr const char *Id = "gooseberry-notes";
    NotesRunner() : AbstractRunner(nullptr, KPluginMetaData(QJsonObject{
        {QStringLiteral("KPlugin"), QJsonObject{{QStringLiteral("Id"), QString::fromLatin1(Id)}, {QStringLiteral("Name"), QStringLiteral("Notes")}}}},
        QString::fromLatin1(Id))) {}
    void match(KRunner::RunnerContext &) override {}
};

// Facts from Split Rock's Core, such as how full the drive is, and the upkeep
// cards Core opens on their own, such as Check for updates, found by the
// words Core gives each; Core opens the card. Never registered with KRunner.
class CoreRunner : public KRunner::AbstractRunner {
public:
    static constexpr const char *Id = "split-rock-core";
    CoreRunner() : AbstractRunner(nullptr, KPluginMetaData(QJsonObject{
        {QStringLiteral("KPlugin"), QJsonObject{{QStringLiteral("Id"), QString::fromLatin1(Id)}, {QStringLiteral("Name"), QStringLiteral("Core")}}}},
        QString::fromLatin1(Id))) {}
    void match(KRunner::RunnerContext &) override {}
};

// An app found by a Windows name for it; Search starts the app itself.
// Never registered with KRunner.
class WindowsWordsRunner : public KRunner::AbstractRunner {
public:
    static constexpr const char *Id = "windows-words";
    WindowsWordsRunner() : AbstractRunner(nullptr, KPluginMetaData(QJsonObject{
        {QStringLiteral("KPlugin"), QJsonObject{{QStringLiteral("Id"), QString::fromLatin1(Id)}, {QStringLiteral("Name"), QStringLiteral("Applications")}}}},
        QString::fromLatin1(Id))) {}
    void match(KRunner::RunnerContext &) override {}
};

inline bool coreMatch(const KRunner::QueryMatch &match) {
    return match.runner() && match.runner()->id() == QLatin1String(CoreRunner::Id);
}

// Whether a query asks for a Core fact: the start of one of its words, or a
// query that holds one ("disk space"). Two letters say too little.
inline bool coreFactFits(const QVariantMap &fact, const QString &query) {
    const auto asked = query.trimmed().toLower();
    if (asked.size() < 3) return false;
    auto words = fact.value(QStringLiteral("keywords")).toStringList();
    words.append(fact.value(QStringLiteral("title")).toString());
    for (const auto &word : std::as_const(words)) {
        const auto known = word.toLower();
        if (known.isEmpty()) continue;
        if (known.startsWith(asked) || asked.contains(known)) return true;
    }
    return false;
}

inline bool noteMatch(const KRunner::QueryMatch &match) {
    return match.runner() && match.runner()->id() == QLatin1String(NotesRunner::Id);
}

// A note's dictionary as the bus delivered it, made plain.
inline QVariantMap busMap(const QVariant &value) {
    if (value.canConvert<QDBusVariant>()) return busMap(value.value<QDBusVariant>().variant());
    if (value.canConvert<QDBusArgument>()) return qdbus_cast<QVariantMap>(value.value<QDBusArgument>());
    return value.toMap();
}

inline QVariantList busList(const QVariant &value) {
    if (value.canConvert<QDBusArgument>()) return qdbus_cast<QVariantList>(value.value<QDBusArgument>());
    return value.toList();
}

// A note's own colour, as the square beside it in the results.
inline QIcon noteIcon(const QString &hex) {
    QPixmap square(64, 64);
    square.fill(Qt::transparent);
    QPainter painter(&square);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(Qt::NoPen);
    painter.setBrush(QColor::isValidColorName(hex) ? QColor::fromString(hex) : QColor(0xF5, 0xD7, 0x6E));
    painter.drawRoundedRect(QRectF(6, 6, 52, 52), 10, 10);
    return QIcon(square);
}

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
    if (id == QStringLiteral("services") || id == QStringLiteral("krunner_services")
        || id == QLatin1String(WindowsWordsRunner::Id)) return 0;
    if (id == QStringLiteral("baloosearch") || id == QStringLiteral("recentdocuments")
        || id == QStringLiteral("krunner_recentdocuments")) return 1;
    if (id == QStringLiteral("krunner_systemsettings") || id == QStringLiteral("systemsettings")
        || id == QStringLiteral("calculator") || id == QStringLiteral("unitconverter")
        || id == QLatin1String(NotesRunner::Id) || id == QLatin1String(CoreRunner::Id)) return 2;
    return 3;
}

inline int searchTier(const KRunner::QueryMatch &match)
{
    return match.runner() ? searchTier(match.runner()->id()) : 3;
}

// Above every confidence an app, setting, Helper or note can hold.
constexpr int FilesAfterAids = 6000;

inline int resultPriority(const KRunner::QueryMatch &match, const QString &query) {
    const int tier = searchTier(match);
    // Core's rows are listed only when the query asks for one by its words
    // (coreFactFits), so they come before any file or folder of the same
    // name: typing "update" means the Helper, not a folder called update.
    // Only an app named exactly what was typed stays ahead.
    if (coreMatch(match)) return SearchPolicy::priority({SearchPolicy::Exact, 0}, 0) + 50;
    if (noteMatch(match)) {
        // Gooseberry found the words in the note, its folder or its window;
        // a title that matches ranks as any name does.
        auto evidence = SearchPolicy::name(match.text(), query);
        if (evidence.confidence == SearchPolicy::Unrelated) evidence = {SearchPolicy::Context, 0};
        return SearchPolicy::priority(evidence, tier);
    }
    const bool setting = match.runner() && match.runner()->id().contains(QStringLiteral("systemsettings"));
    auto aliases = setting ? settingAliases(match.id()) : QStringList();
    if (tier == 0) aliases.append(windowsWordsReached(runnerApplicationId(match), query));
    if (tier == 1) aliases.append(QFileInfo(matchFilePath(match)).completeBaseName());
    auto evidence = SearchPolicy::evaluate(match.text(), aliases,
        tier == 1 ? QString() : match.subtext(), query);
    // A file stem is a name, not a semantic alias: preserve ordinary prefix
    // confidence rather than promoting filename prefixes to named intent.
    if (tier == 1 && evidence.confidence == SearchPolicy::NamedIntent)
        evidence.confidence = SearchPolicy::Prefix;
    if (match.runner() && (match.runner()->id() == QStringLiteral("calculator")
        || match.runner()->id() == QStringLiteral("unitconverter"))) evidence = {SearchPolicy::Exact, 0};
    const int ranked = SearchPolicy::priority(evidence, tier);
    // Files and folders follow every app, setting, Helper, note and sum the
    // words found, whatever their own confidence: a folder called settings
    // never pushes Settings down. A file whose whole name was typed with its
    // extension ("sound.png") is asked for by name and keeps its place.
    const bool namedFile = evidence.confidence == SearchPolicy::Exact
        && !QFileInfo(query.trimmed()).suffix().isEmpty();
    if (tier == 1 && !namedFile && evidence.confidence != SearchPolicy::Unrelated)
        return ranked + FilesAfterAids;
    return ranked;
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
    // Search's Helpers chip: every upkeep card Core lists, as its tiles, and
    // while it is shown, what is typed finds only those.
    Q_PROPERTY(QVariantList helpers READ helpers NOTIFY helpersChanged)
    Q_PROPERTY(bool helpersOnly READ helpersOnly WRITE setHelpersOnly NOTIFY helpersOnlyChanged)
    // The Helpers an answer from Ask names, by Core's ids: listed first, in
    // Ask's order, whatever words were typed.
    Q_PROPERTY(QStringList askedHelpers READ askedHelpers WRITE setAskedHelpers NOTIFY askedHelpersChanged)
    // What an asked Helper is opened with, such as the app Ask found the
    // question names; empty, it is opened with what is typed.
    Q_PROPERTY(QString askedQuery MEMBER m_askedQuery NOTIFY askedHelpersChanged)
public:
    explicit OmniResults(QObject *parent = nullptr) : QSortFilterProxyModel(parent) {
        QSettings settings(QStringLiteral("co.goodinput"), QStringLiteral("tettegouche-search"));
        const auto fallback = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
            + QStringLiteral("/Design Library");
        m_quietFolders = settings.value(QStringLiteral("quietFolders"),
            QFileInfo::exists(fallback) ? fallback : QString()).toString();
        m_aliases.setColumnCount(1);
        m_combined.addSourceModel(&m_results);
        m_combined.addSourceModel(&m_aliases);
        m_notes.setColumnCount(1);
        m_combined.addSourceModel(&m_notes);
        m_core.setColumnCount(1);
        m_combined.addSourceModel(&m_core);
        m_windowsWords.setColumnCount(1);
        m_combined.addSourceModel(&m_windowsWords);
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
    // Watched before the proxy's own handlers, so which row stands for a
    // destination is never judged from the rows that were there before.
    void setSourceModel(QAbstractItemModel *source) override {
        for (const auto &watch : std::as_const(m_rowWatch)) disconnect(watch);
        m_rowWatch.clear();
        m_shownStale = true;
        if (source) {
            // Each row also remembers which verdict is its own, moved along
            // as rows arrive and leave, so sorting reads it straight back.
            const auto stale = [this]() { m_shownStale = true; m_rowVerdict.clear(); };
            m_rowWatch = {
                connect(source, &QAbstractItemModel::rowsInserted, this, [this](const QModelIndex &parent, int first, int last) {
                    m_shownStale = true;
                    if (!parent.isValid() && first <= m_rowVerdict.size()) m_rowVerdict.insert(first, last - first + 1, -1);
                }),
                connect(source, &QAbstractItemModel::rowsRemoved, this, [this](const QModelIndex &parent, int first, int last) {
                    m_shownStale = true;
                    if (!parent.isValid() && first < m_rowVerdict.size())
                        m_rowVerdict.remove(first, qMin<qsizetype>(last, m_rowVerdict.size() - 1) - first + 1);
                }),
                connect(source, &QAbstractItemModel::dataChanged, this, [this](const QModelIndex &from, const QModelIndex &to) {
                    m_shownStale = true;
                    if (from.parent().isValid()) return;
                    for (int row = from.row(); row <= to.row() && row < m_rowVerdict.size(); ++row) m_rowVerdict[row] = -1;
                }),
                connect(source, &QAbstractItemModel::rowsMoved, this, stale),
                connect(source, &QAbstractItemModel::modelReset, this, stale),
                connect(source, &QAbstractItemModel::layoutChanged, this, stale)};
        }
        m_rowVerdict.clear();
        QSortFilterProxyModel::setSourceModel(source);
    }
    void setLimit(int limit) { m_results.setLimit(limit); }
    virtual QString queryString() const { return m_results.queryString(); }
    bool allFiles() const { return m_allFiles; }
    void setAllFiles(bool value) { if (m_allFiles == value) return; releaseSelection(); m_allFiles = value; invalidate(); Q_EMIT scopeChanged(); }
    QString quietFolders() const { return m_quietFolders; }
    void setQuietFolders(const QString &value) {
        QSettings settings(QStringLiteral("co.goodinput"), QStringLiteral("tettegouche-search"));
        settings.setValue(QStringLiteral("quietFolders"), value);
        m_quietFolders = value;
        invalidate(); Q_EMIT scopeChanged();
    }
    // Notes are asked of Gooseberry only while Search offers Notes.
    void setNotesOffered(bool offered) { m_notesOffered = offered; }
    // Lists the notes Gooseberry found for the query, replacing those shown.
    void showNotes(const QVariantList &found) {
        m_notes.removeRows(0, m_notes.rowCount());
        for (const auto &value : found) {
            const auto note = busMap(value);
            const auto id = note.value(QStringLiteral("id")).toString();
            if (id.isEmpty()) continue;
            auto title = note.value(QStringLiteral("title")).toString();
            if (title.isEmpty()) title = i18n("Empty note");
            const bool stuck = note.value(QStringLiteral("stuck")).toBool();
            const auto where = stuck
                ? i18n("Note stuck to %1", note.value(QStringLiteral("window")).toString())
                : i18n("Note in %1", note.value(QStringLiteral("folderLabel")).toString());
            const auto excerpt = note.value(QStringLiteral("excerpt")).toString();
            KRunner::QueryMatch match(&m_notesRunner);
            match.setId(id);
            match.setText(title);
            match.setSubtext(where);
            match.setData(id);
            auto *item = new QStandardItem(noteIcon(note.value(QStringLiteral("colourHex")).toString()), title);
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            item->setData(excerpt.isEmpty() ? where : i18nc("@info a line of a note, then where it is", "%1 · %2", excerpt, where),
                KRunner::ResultsModel::SubtextRole);
            item->setData(true, KRunner::ResultsModel::EnabledRole);
            m_notes.appendRow(item);
        }
        invalidate();
    }
    // Core's facts, as its provider holds them, and how to ask Core to open
    // one's card. Asked of nothing while typing: the facts are already here.
    void setCoreFacts(std::function<QList<QVariantMap>()> facts, std::function<void(const QString &)> open) {
        m_coreFacts = std::move(facts);
        m_openCore = std::move(open);
    }
    // The upkeep cards Core opens on their own, found by their words; opening
    // one passes what was typed, which Install an app searches for.
    void setCoreActions(std::function<QList<QVariantMap>()> actions,
                        std::function<void(const QString &, const QString &)> open) {
        m_coreActions = std::move(actions);
        m_openCoreAction = std::move(open);
        Q_EMIT helpersChanged();
    }
    // Every upkeep card Core lists, in Core's own order: its id, title, the
    // line under it and its icon. None without Core.
    QVariantList helpers() const {
        QVariantList listed;
        for (const auto &action : m_coreActions ? m_coreActions() : QList<QVariantMap>{}) {
            const auto id = action.value(QStringLiteral("id")).toString();
            const auto title = action.value(QStringLiteral("title")).toString();
            if (id.isEmpty() || title.isEmpty()) continue;
            listed.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("title"), title},
                                      {QStringLiteral("sub"), action.value(QStringLiteral("sub")).toString()},
                                      {QStringLiteral("icon"), action.value(QStringLiteral("icon")).toString()}});
        }
        return listed;
    }
    // Asks Core to open one on its own, as Enter on its row does.
    Q_INVOKABLE bool openHelper(const QString &id) {
        if (!m_openCoreAction || id.isEmpty()) return false;
        m_openCoreAction(id, QString());
        return true;
    }
    QStringList askedHelpers() const { return m_askedHelpers; }
    void setAskedHelpers(const QStringList &ids) {
        if (ids == m_askedHelpers) return;
        releaseSelection();
        m_askedHelpers = ids;
        // The rows move under the same query, so each is judged again.
        m_verdictQuery = QStringLiteral("\x1f");
        showCore(queryString());
        Q_EMIT askedHelpersChanged();
    }
    bool helpersOnly() const { return m_helpersOnly; }
    void setHelpersOnly(bool only) {
        if (m_helpersOnly == only) return;
        releaseSelection();
        m_helpersOnly = only;
        invalidate();
        Q_EMIT helpersOnlyChanged();
    }
    // How to find an installed app by its desktop name (its name, icon,
    // description and storage id, or nothing where it is not installed), and
    // how to start it, for the apps found by their Windows names.
    void setApplications(std::function<QVariantMap(const QString &)> find,
                         std::function<bool(const QString &)> open) {
        m_findApplication = std::move(find);
        m_openApplication = std::move(open);
    }
    void showWindowsWords(const QString &query) {
        m_windowsWords.removeRows(0, m_windowsWords.rowCount());
        if (!m_findApplication) return;
        for (auto it = windowsNames().cbegin(); it != windowsNames().cend(); ++it) {
            const auto &name = it.key();
            if (windowsWordsReached(name, query).isEmpty()) continue;
            const auto app = m_findApplication(name);
            const auto id = app.value(QStringLiteral("id")).toString();
            const auto title = app.value(QStringLiteral("name")).toString();
            if (id.isEmpty() || title.isEmpty()) continue;
            KRunner::QueryMatch match(&m_windowsWordsRunner);
            match.setId(id);
            match.setText(title);
            match.setSubtext(app.value(QStringLiteral("description")).toString());
            match.setData(QUrl(QStringLiteral("applications:") + id));
            auto *item = new QStandardItem(QIcon::fromTheme(app.value(QStringLiteral("icon")).toString()), title);
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            item->setData(match.subtext(), KRunner::ResultsModel::SubtextRole);
            item->setData(true, KRunner::ResultsModel::EnabledRole);
            m_windowsWords.appendRow(item);
        }
        invalidate();
    }
    void showCore(const QString &query) {
        m_core.removeRows(0, m_core.rowCount());
        for (const auto &fact : m_coreFacts ? m_coreFacts() : QList<QVariantMap>{}) {
            if (!coreFactFits(fact, query)) continue;
            const auto topic = fact.value(QStringLiteral("topic")).toString();
            const auto title = fact.value(QStringLiteral("title")).toString();
            const auto line = fact.value(QStringLiteral("line")).toString();
            const auto text = line.isEmpty() ? title : i18nc("@info what Core watches, then how it stands", "%1 · %2", title, line);
            QStringList under;
            for (const auto &key : {QStringLiteral("detail"), QStringLiteral("actionText")}) {
                const auto part = fact.value(key).toString();
                if (!part.isEmpty()) under.append(part);
            }
            KRunner::QueryMatch match(&m_coreRunner);
            match.setId(topic);
            match.setText(text);
            match.setSubtext(under.join(QStringLiteral(" · ")));
            match.setData(topic);
            auto *item = new QStandardItem(QIcon::fromTheme(fact.value(QStringLiteral("icon")).toString()), text);
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            item->setData(match.subtext(), KRunner::ResultsModel::SubtextRole);
            item->setData(true, KRunner::ResultsModel::EnabledRole);
            m_core.appendRow(item);
        }
        // The Helpers Ask named come first, in its order; then those the
        // words find.
        const auto actions = m_coreActions ? m_coreActions() : QList<QVariantMap>{};
        QList<QVariantMap> listed;
        for (const auto &asked : m_askedHelpers) {
            for (const auto &action : actions) {
                if (action.value(QStringLiteral("id")).toString() == asked) listed.append(action);
            }
        }
        for (const auto &action : actions) {
            if (!m_askedHelpers.contains(action.value(QStringLiteral("id")).toString()) && coreFactFits(action, query))
                listed.append(action);
        }
        for (const auto &action : listed) {
            const auto id = action.value(QStringLiteral("id")).toString();
            const auto title = action.value(QStringLiteral("title")).toString();
            if (id.isEmpty() || title.isEmpty()) continue;
            KRunner::QueryMatch match(&m_coreRunner);
            match.setId(QStringLiteral("action:") + id);
            match.setText(title);
            match.setSubtext(action.value(QStringLiteral("sub")).toString());
            match.setData(QString(QStringLiteral("action:") + id));
            auto *item = new QStandardItem(QIcon::fromTheme(action.value(QStringLiteral("icon")).toString()), title);
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            item->setData(match.subtext(), KRunner::ResultsModel::SubtextRole);
            item->setData(true, KRunner::ResultsModel::EnabledRole);
            m_core.appendRow(item);
        }
        invalidate();
    }
    void setQueryString(const QString &query) {
        releaseSelection();
        m_aliases.removeRows(0, m_aliases.rowCount());
        askNotes(query);
        showCore(query);
        showWindowsWords(query);
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
    Q_INVOKABLE void clear() {
        releaseSelection();
        ++m_notesAsk;
        m_aliases.removeRows(0, m_aliases.rowCount());
        m_notes.removeRows(0, m_notes.rowCount());
        m_core.removeRows(0, m_core.rowCount());
        m_windowsWords.removeRows(0, m_windowsWords.rowCount());
        m_results.clear();
    }
    Q_INVOKABLE bool run(const QModelIndex &index) {
        const auto source = m_combined.mapToSource(mapToSource(index));
        if (!source.isValid()) return false;
        if (source.model() == &m_notes) {
            // Gooseberry opens the note on its own card; Search waits for nothing.
            auto request = QDBusMessage::createMethodCall(QString::fromLatin1(NotesService),
                QString::fromLatin1(NotesPath), QString::fromLatin1(NotesInterface), QStringLiteral("OpenNote"));
            request.setArguments({getQueryMatch(index).data().toString()});
            return QDBusConnection::sessionBus().send(request);
        }
        if (source.model() == &m_core) {
            // Core opens the card; Search waits for nothing.
            const auto target = getQueryMatch(index).data().toString();
            if (target.startsWith(QLatin1String("action:"))) {
                if (!m_openCoreAction) return false;
                const auto id = target.mid(7);
                m_openCoreAction(id, m_askedHelpers.contains(id) && !m_askedQuery.isEmpty()
                        ? m_askedQuery : queryString().trimmed());
                return true;
            }
            if (!m_openCore) return false;
            m_openCore(target);
            return true;
        }
        if (source.model() == &m_windowsWords)
            return m_openApplication && m_openApplication(runnerApplicationId(getQueryMatch(index)));
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
    void helpersChanged();
    void helpersOnlyChanged();
    void askedHelpersChanged();
protected:
    bool filterAcceptsRow(int row, const QModelIndex &parent) const override {
        // Under the Helpers chip only the upkeep cards are listed.
        if (m_helpersOnly && !helperRow(sourceModel()->index(row, 0, parent))) return false;
        // A copy: judging other rows below may move the one kept.
        const Verdict found = verdict(sourceModel()->index(row, 0, parent));
        if (!found.eligible) return false;
        if (m_shownStale || m_shownRows != sourceModel()->rowCount(parent)) {
            // One row stands for each destination: for a setting, KDE's own
            // module before a shortcut to it; then the stronger match, then
            // the earlier row.
            m_shownFor.clear();
            m_shownRows = sourceModel()->rowCount(parent);
            QHash<QString, Verdict> standing;
            for (int other = 0; other < m_shownRows; ++other) {
                const auto &candidate = verdict(sourceModel()->index(other, 0, parent));
                if (!candidate.eligible) continue;
                const auto current = standing.constFind(candidate.key);
                bool wins = current == standing.cend();
                if (!wins && candidate.key.startsWith(QStringLiteral("setting:")) && candidate.setting != current->setting)
                    wins = candidate.setting;
                else if (!wins)
                    wins = candidate.priority < current->priority;
                if (!wins) continue;
                standing.insert(candidate.key, candidate);
                m_shownFor.insert(candidate.key, other);
            }
            m_shownStale = false;
        }
        return m_shownFor.value(found.key, -1) == row;
    }

    static bool helperRow(const QModelIndex &index) {
        const auto match = index.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
        return coreMatch(match) && match.data().toString().startsWith(QLatin1String("action:"));
    }

    // What a match is worth for the query: whether it may be listed, where
    // it leads and how strongly it answers. Worked out once for each match
    // and kept until the query or the scope changes, so rows arriving later
    // never send Search back over the ones it has already judged.
    struct Verdict {
        bool eligible = false;
        bool setting = false;
        int priority = 0;
        int tier = 3;
        QString key;
    };
    const Verdict &verdict(const QModelIndex &index) const {
        const auto query = queryString();
        if (query != m_verdictQuery || m_allFiles != m_verdictAllFiles || m_quietFolders != m_verdictQuiet) {
            m_verdicts.clear();
            m_verdictList.clear();
            m_rowVerdict.clear();
            m_verdictQuery = query;
            m_verdictAllFiles = m_allFiles;
            m_verdictQuiet = m_quietFolders;
            m_shownStale = true;
        }
        const bool flat = !index.parent().isValid();
        const int row = index.row();
        if (flat && row < m_rowVerdict.size() && m_rowVerdict.at(row) >= 0) return m_verdictList.at(m_rowVerdict.at(row));
        const auto match = index.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
        const auto runner = match.runner() ? match.runner()->id() : QString();
        const auto identity = runner + QLatin1Char('\x1f') + match.id() + QLatin1Char('\x1f') + match.text()
            + QLatin1Char('\x1f') + match.subtext() + QLatin1Char('\x1f') + match.data().toString();
        int slot = m_verdicts.value(identity, -1);
        if (slot < 0) {
            ++m_verdictChecks;
            Verdict found;
            found.priority = resultPriority(match, query);
            found.tier = searchTier(match);
            found.key = destinationKey(match);
            found.setting = runner.contains(QStringLiteral("systemsettings"));
            found.eligible = candidateEligible(match, found.priority);
            slot = m_verdictList.size();
            m_verdictList.append(found);
            m_verdicts.insert(identity, slot);
        }
        if (flat) {
            if (row >= m_rowVerdict.size()) m_rowVerdict.resize(row + 1, -1);
            m_rowVerdict[row] = slot;
        }
        return m_verdictList.at(slot);
    }
    // Every match judged afresh, counted so a test can hold the work to one
    // judgement for each.
    mutable int m_verdictChecks = 0;
    bool candidateEligible(const KRunner::QueryMatch &match, int priority) const {
        if (searchTier(match) != 1 && priority >= 5000) return false;
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
        // A file the words found sits past FilesAfterAids; one they did not
        // find stays below it, unrelated.
        return !m_repoDirectories.value(directory) && usefulFile(path, queryString())
            && (priority < 5000 || priority >= FilesAfterAids);
    }
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override
    {
        if (!m_frozenOrder.isEmpty()) {
            const auto keyA = destinationKey(left.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
            const auto keyB = destinationKey(right.data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>());
            const int a = m_frozenOrder.value(keyA, INT_MAX), b = m_frozenOrder.value(keyB, INT_MAX);
            if (a != b) return sortOrder() == Qt::AscendingOrder ? a < b : a > b;
        }
        const auto &judgedA = verdict(left);
        const int qualityA = judgedA.priority, a = judgedA.tier;
        const auto &judgedB = verdict(right);
        const int qualityB = judgedB.priority, b = judgedB.tier;
        if (qualityA != qualityB)
            return sortOrder() == Qt::AscendingOrder ? qualityA < qualityB : qualityA > qualityB;
        // QSortFilterProxyModel reverses the comparator for descending sorting.
        if (a != b) return sortOrder() == Qt::AscendingOrder ? a < b : a > b;
        // Preserve KDE's relevance order within each tier.
        return left.row() < right.row();
    }
private:
    static constexpr const char *NotesService = "io.github.carlsonjm.gooseberry";
    static constexpr const char *NotesPath = "/QuickNote";
    static constexpr const char *NotesInterface = "io.github.carlsonjm.Gooseberry.QuickNote";
    static constexpr uint NotesShown = 5;

    // Asked as each letter is typed: only of a Gooseberry already running,
    // never started for it, and never waited on. An answer to an older query
    // is dropped; a Gooseberry without Find answers with an error, and no
    // note is listed.
    void askNotes(const QString &query) {
        const int ask = ++m_notesAsk;
        if (!m_notesOffered || SearchPolicy::compact(query).size() < 2) {
            m_notes.removeRows(0, m_notes.rowCount());
            return;
        }
        auto request = QDBusMessage::createMethodCall(QString::fromLatin1(NotesService),
            QString::fromLatin1(NotesPath), QString::fromLatin1(NotesInterface), QStringLiteral("Find"));
        request.setArguments({query, NotesShown});
        request.setAutoStartService(false);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, 1000), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, ask]() {
            watcher->deleteLater();
            const QDBusMessage reply = watcher->reply();
            if (ask != m_notesAsk) return;
            // The notes shown stay until the answer replaces them, so they do
            // not blink at each letter.
            showNotes(reply.type() == QDBusMessage::ReplyMessage ? busList(reply.arguments().value(0)) : QVariantList());
        });
    }

    mutable QHash<QString, int> m_verdicts;
    mutable QList<Verdict> m_verdictList;
    mutable QList<int> m_rowVerdict;
    mutable QString m_verdictQuery;
    mutable bool m_verdictAllFiles = false;
    mutable QString m_verdictQuiet;
    mutable QHash<QString, int> m_shownFor;
    mutable int m_shownRows = -1;
    mutable bool m_shownStale = true;
    QList<QMetaObject::Connection> m_rowWatch;
    bool m_refreshQueued = false;
    bool m_notesOffered = false;
    int m_notesAsk = 0;
    QString m_selectedDestination;
    QHash<QString, int> m_frozenOrder;
    bool m_allFiles = false;
    bool m_helpersOnly = false;
    QStringList m_askedHelpers;
    QString m_askedQuery;
    QString m_quietFolders;
    mutable QHash<QString, bool> m_repoDirectories;
    SettingsAliasRunner m_aliasRunner;
    NotesRunner m_notesRunner;
    CoreRunner m_coreRunner;
    WindowsWordsRunner m_windowsWordsRunner;
    std::function<QVariantMap(const QString &)> m_findApplication;
    std::function<bool(const QString &)> m_openApplication;
    std::function<QList<QVariantMap>()> m_coreFacts;
    std::function<void(const QString &)> m_openCore;
    std::function<QList<QVariantMap>()> m_coreActions;
    std::function<void(const QString &, const QString &)> m_openCoreAction;
    SearchSource m_results;
    QStandardItemModel m_aliases;
    QStandardItemModel m_notes;
    QStandardItemModel m_core;
    QStandardItemModel m_windowsWords;
    SearchSources m_combined;
    QList<KPluginMetaData> m_modules;
};
