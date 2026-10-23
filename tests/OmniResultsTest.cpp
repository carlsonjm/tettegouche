#include "OmniResults.h"
#include <QGuiApplication>
#include <QJsonObject>
#include <QStandardItemModel>
#include <QTimer>
#include <QAbstractListModel>
#include <QElapsedTimer>
#include <iostream>

struct Runner : KRunner::AbstractRunner {
    explicit Runner(const QString &id) : AbstractRunner(nullptr,
        KPluginMetaData(QJsonObject{{QStringLiteral("KPlugin"), QJsonObject{
            {QStringLiteral("Id"), id}, {QStringLiteral("Name"), id}}}}, id)) {}
    void match(KRunner::RunnerContext &) override {}
};
// Matches arriving the way KDE's providers send them: a batch at a time.
struct Stream : QAbstractListModel {
    QList<KRunner::QueryMatch> matches;
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : matches.size(); }
    QVariant data(const QModelIndex &index, int role) const override {
        if (!index.isValid() || index.row() >= matches.size()) return {};
        if (role == KRunner::ResultsModel::QueryMatchRole) return QVariant::fromValue(matches.at(index.row()));
        if (role == Qt::DisplayRole) return matches.at(index.row()).text();
        return {};
    }
    void add(const QList<KRunner::QueryMatch> &batch) {
        beginInsertRows({}, matches.size(), matches.size() + batch.size() - 1);
        matches.append(batch);
        endInsertRows();
    }
};
struct Results : OmniResults {
    using OmniResults::lessThan;
    QString testQuery;
    QString queryString() const override { return testQuery.isNull() ? OmniResults::queryString() : testQuery; }
    int checks() const { return m_verdictChecks; }
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
        return mapToSource(index).data(role);
    }
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc > 1) {
        KRunner::RunnerManager manager;
        QStringList ids;
        for (const auto &metadata : KRunner::RunnerManager::runnerMetaDataList()) {
            if (searchTier(metadata.pluginId()) < 3) ids.append(metadata.pluginId());
        }
        std::cout << "Providers: " << ids.join(QStringLiteral(", ")).toStdString() << '\n';
        OmniResults results;
        if (argc > 2) results.setAllFiles(QString::fromLocal8Bit(argv[2]) == QStringLiteral("all"));
        results.setRunnerManager(&manager);
        manager.setAllowedRunners(ids);
        results.setLimit(0);
        manager.setupMatchSession();
        results.setQueryString(QString::fromLocal8Bit(argv[1]));
        QTimer::singleShot(4500, &app, [&]() {
            int previous = -2;
            int counts[4] = {};
            for (int i = 0; i < results.rowCount(); ++i) {
                int tier = searchTier(results.getQueryMatch(results.index(i, 0)));
                const int priority = resultPriority(results.getQueryMatch(results.index(i, 0)), results.queryString());
                if (priority < previous) { app.exit(4); return; }
                previous = priority;
                ++counts[tier];
                const auto match = results.getQueryMatch(results.index(i, 0));
                if (!match.runner()) {
                    std::cerr << "Missing match: columns=" << results.columnCount()
                              << " valid=" << results.index(i, 0).isValid() << '\n';
                    app.exit(23); return;
                }
                if (i < 6 && tier != 1) std::cout << "Result " << i << ": " << match.text().toStdString()
                    << " [" << match.id().toStdString() << "]\n";
                if (match.runner()->id().contains(QStringLiteral("systemsettings")))
                    std::cout << "Setting: " << match.id().toStdString() << '\n';
            }
            std::cout << "Apps=" << counts[0] << " files=" << counts[1]
                      << " aids=" << counts[2] << " other=" << counts[3] << '\n';
            // Explicit manual integration check only; never used by ctest or
            // ordinary read-only query probes. Opens a settings page, not a
            // device-changing action.
            if (argc > 2 && QString::fromLocal8Bit(argv[2]) == QStringLiteral("launch-setting")) {
                const auto first = results.index(0, 0);
                const auto match = results.getQueryMatch(first);
                if (!match.runner() || !match.runner()->id().contains(QStringLiteral("systemsettings"))) { app.exit(51); return; }
                const bool launched = results.run(first);
                std::cout << "Settings launch accepted=" << launched << '\n';
                if (!launched) { app.exit(52); return; }
            }
            manager.matchSessionComplete();
            app.quit();
        });
        return app.exec();
    }
    Runner apps(QStringLiteral("krunner_services")), files(QStringLiteral("baloosearch")),
        aids(QStringLiteral("krunner_systemsettings"));
    QStandardItemModel model;
    for (auto *runner : {&apps, &files, &aids}) {
        KRunner::QueryMatch match(runner);
        auto *item = new QStandardItem;
        item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
        model.appendRow(item);
    }
    Results results;
    KRunner::QueryMatch fileA(&files), fileB(&files), fileOther(&files), kcmApp(&apps), kcmSetting(&aids);
    fileA.setData(QUrl::fromLocalFile(QStringLiteral("/home/test/Documents/report.pdf")));
    fileB.setData(QUrl::fromLocalFile(QStringLiteral("/home/test/Documents/report.pdf")));
    fileOther.setData(QUrl::fromLocalFile(QStringLiteral("/home/test/Downloads/report.pdf")));
    if (destinationKey(fileA) != destinationKey(fileB) || destinationKey(fileA) == destinationKey(fileOther)) return 42;
    kcmApp.setData(QUrl(QStringLiteral("applications:kcm_printer_manager.desktop")));
    kcmSetting.setId(QStringLiteral("kcm_printer_manager"));
    if (destinationKey(kcmApp) != destinationKey(kcmSetting)) return 43;
    {
        Results stable;
        stable.testQuery = QStringLiteral("tool");
        QStandardItemModel candidates;
        auto append = [&](const QString &title, const QString &id) {
            KRunner::QueryMatch match(&apps);
            match.setId(id);
            match.setText(title);
            match.setData(QUrl(QStringLiteral("applications:") + id));
            auto *item = new QStandardItem(title);
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            candidates.appendRow(item);
        };
        append(QStringLiteral("Tool Alpha"), QStringLiteral("alpha.desktop"));
        append(QStringLiteral("Tool Beta"), QStringLiteral("beta.desktop"));
        stable.setSourceModel(&candidates);
        stable.invalidate();
        if (stable.rowCount() != 2) return 44;
        stable.pinSelection(1);
        const auto chosen = destinationKey(stable.getQueryMatch(stable.index(1, 0)));
        append(QStringLiteral("Tool"), QStringLiteral("new.desktop"));
        stable.invalidate();
        if (stable.selectedRow() != 1 || destinationKey(stable.getQueryMatch(stable.index(1, 0))) != chosen) return 45;
        append(QStringLiteral("Tool Beta"), QStringLiteral("beta.desktop"));
        stable.invalidate();
        if (stable.rowCount() != 3) return 46;
        // Remove both representations of the chosen destination.
        for (int row = candidates.rowCount() - 1; row >= 0; --row) {
            const auto match = candidates.index(row, 0).data(KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>();
            if (destinationKey(match) == chosen) candidates.removeRow(row);
        }
        stable.invalidate();
        if (!stable.selectionPinned() || stable.selectedRow() != -1) return 47;
        stable.setAllFiles(true);
        if (stable.selectionPinned()) return 48;
        for (auto match : {kcmApp, kcmSetting}) {
            match.setText(QStringLiteral("Tool Printer"));
            auto *item = new QStandardItem(match.text());
            item->setData(QVariant::fromValue(match), KRunner::ResultsModel::QueryMatchRole);
            candidates.appendRow(item);
        }
        stable.invalidate();
        int printerDestinations = 0;
        for (int i = 0; i < stable.rowCount(); ++i) {
            const auto match = stable.getQueryMatch(stable.index(i, 0));
            if (destinationKey(match) == destinationKey(kcmSetting)) {
                ++printerDestinations;
                if (match.runner() != &aids) return 49;
            }
        }
        if (printerDestinations != 1) return 50;
    }
    KRunner::QueryMatch wine(&apps), wifi(&aids), windows(&aids);
    wine.setText(QStringLiteral("Winetricks"));
    wifi.setId(QStringLiteral("kcm_networkmanagement"));
    wifi.setText(QStringLiteral("Wi-Fi & Networking"));
    windows.setId(QStringLiteral("kcm_kwinsupportinfo"));
    windows.setText(QStringLiteral("Window Manager"));
    const auto wi = QStringLiteral("wi");
    if (!(resultPriority(wine, wi) < resultPriority(wifi, wi)
          && resultPriority(wifi, wi) < resultPriority(windows, wi))) return 30;
    if (resultPriority(wifi, QStringLiteral("wifi")) != 200) return 31;
    using namespace SearchPolicy;
    for (const auto &alias : {QStringLiteral("audio"), QStringLiteral("printer"), QStringLiteral("display"), QStringLiteral("battery")}) {
        if (evaluate(QStringLiteral("Localized destination"), {alias}, {}, alias.left(2)).confidence != Prefix) return 32;
        if (evaluate(QStringLiteral("Localized destination"), {alias}, {}, alias.left(3)).confidence != NamedIntent) return 33;
        if (evaluate(QStringLiteral("Localized destination"), {alias}, {}, alias).confidence != Exact) return 34;
    }
    if (name(QStringLiteral("Wi-Fi"), QStringLiteral("wifi")).confidence != Exact) return 35;
    if (name(QStringLiteral("Restore"), QStringLiteral("stor")).confidence != Unrelated) return 36;
    if (evaluate(QStringLiteral("Zen"), {}, QStringLiteral("Web browser"), QStringLiteral("browser")).confidence != Context) return 37;
    if (evaluate(QStringLiteral("KCalc"), {}, QStringLiteral("Scientific Calculator"), QStringLiteral("wifi")).confidence != Unrelated) return 38;
    if (evaluate(QStringLiteral("Sound"), {QStringLiteral("sound")}, {}, QStringLiteral("soundcloud")).confidence != Unrelated) return 39;
    if (priority(name(QStringLiteral("sound.png"), QStringLiteral("sound.png")), 1)
        >= priority(evaluate(QStringLiteral("Sound"), {QStringLiteral("sound")}, {}, QStringLiteral("sound.png")), 2)) return 40;
    // Direct app prefixes must outrank a file's interior word match.
    if (priority(name(QStringLiteral("My report.pdf"), QStringLiteral("report")), 1)
        <= priority(evaluate(QStringLiteral("Report Tools"), {}, QStringLiteral("Work with reports"), QStringLiteral("report")), 0)) return 41;
    if (!withinQuietFolder(QStringLiteral("/home/test/Assets/store.gif"), {QStringLiteral("/home/test/Assets")})) return 24;
    if (withinQuietFolder(QStringLiteral("/home/test/Assets-work/store.gif"), {QStringLiteral("/home/test/Assets")})) return 25;
    if (withinQuietFolder(QStringLiteral("/home/test/Assets/store.gif"), {QString()})) return 26;
    if (!bundledFile(QStringLiteral("/home/test/Old.app/Contents/icons/wide.svg"))) return 27;
    if (bundledFile(QStringLiteral("/home/test/Pictures/wide.svg"))) return 28;
    results.setAllFiles(true);
    if (!results.allFiles()) return 29;
    results.setAllFiles(false);
    for (const auto &pair : QList<QPair<QString, QString>>{
        {QStringLiteral("kcm_networkmanagement"), QStringLiteral("wifi")}, {QStringLiteral("kcm_networkmanagement"), QStringLiteral("wi-fi")},
        {QStringLiteral("kcm_pulseaudio"), QStringLiteral("soun")}, {QStringLiteral("kcm_kscreen"), QStringLiteral("displ")},
        {QStringLiteral("kcm_powerdevilprofilesconfig"), QStringLiteral("power")}, {QStringLiteral("kcm_printer_manager"), QStringLiteral("prin")},
        {QStringLiteral("kcm_solid_actions"), QStringLiteral("storage")}, {QStringLiteral("kcm_nightlight"), QStringLiteral("nig")}}) {
        if (!settingIntent(pair.first, pair.second)) return 20;
        KRunner::QueryMatch setting(&aids);
        setting.setId(pair.first);
        setting.setText(QStringLiteral("Localized setting title"));
        KRunner::QueryMatch file(&files);
        file.setText(pair.second + QStringLiteral(".png"));
        if (resultPriority(setting, pair.second) >= resultPriority(file, pair.second)) return 21;
    }
    if (settingIntent(QStringLiteral("kcm_pulseaudio"), QStringLiteral("soundcloud"))
        || settingIntent(QStringLiteral("kcm_pulseaudio"), QStringLiteral("sound.png"))
        || settingIntent(QStringLiteral("kcm_nightlight"), QStringLiteral("n"))) return 22;
    const QString header = QStringLiteral("/home/test/Documents/project/src/BluetoothContext.h");
    if (usefulFile(header, QStringLiteral("bluetoo"))) return 9;
    if (usefulFile(header, QStringLiteral("BluetoothContext"))) return 10;
    if (!usefulFile(header, QStringLiteral("BluetoothContext.h"))) return 11;
    if (usefulFile(QStringLiteral("/home/test/project/build/app_autogen/moc_BluetoothContext.cpp.d"),
                   QStringLiteral("moc_BluetoothContext.cpp.d"))) return 12;
    if (usefulFile(QStringLiteral("/home/test/project/build-debug/Bluetooth guide.pdf"),
                   QStringLiteral("Bluetooth"))) return 13;
    if (!usefulFile(QStringLiteral("/home/test/Documents/Bluetooth guide.pdf"), QStringLiteral("bluetoo"))) return 14;
    if (!usefulFile(QStringLiteral("/home/test/Pictures/Bluetooth setup.png"), QStringLiteral("bluetoo"))) return 15;
    if (usefulFile(QStringLiteral("/home/test/go/pkg/mod/bluetooth.go"), QStringLiteral("bluetooth"))) return 5;
    if (usefulFile(QStringLiteral("/home/test/Documents/notes.txt"), QStringLiteral("bluetooth"))) return 6;
    if (!usefulFile(QStringLiteral("/home/test/Documents/Bluetooth guide.pdf"), QStringLiteral("bluetooth"))) return 7;
    if (nameMatchQuality(QStringLiteral("Bluetooth"), QStringLiteral("bluetooth"))
        >= nameMatchQuality(QStringLiteral("Bluetooth guide.pdf"), QStringLiteral("bluetooth"))) return 8;
    for (auto order : {Qt::AscendingOrder, Qt::DescendingOrder}) {
        results.sort(0, order);
        for (int i = 0; i < 2; ++i) {
            if (results.lessThan(model.index(i, 0), model.index(i+1, 0))
                != (order == Qt::AscendingOrder)) return 1;
        }
    }
    for (const auto &id : {"krunner_shell", "krunner_kill", "krunner_powerdevil", "krunner_webshortcuts"})
        if (searchTier(QString::fromLatin1(id)) != 3) return 2;
    {
        // A time in another zone answers as a sum does, whatever its words.
        Runner clock(QStringLiteral("org.kde.datetime"));
        if (searchTier(QStringLiteral("org.kde.datetime")) != 2) return 115;
        KRunner::QueryMatch london(&clock);
        london.setText(QStringLiteral("London: 21:00 (5 hours later)"));
        if (resultPriority(london, QStringLiteral("time in london"))
            != SearchPolicy::priority({SearchPolicy::Exact, 0}, 2)) return 116;
    }
    {
        // Notes as Gooseberry answers Find: each listed with its folder or
        // window, a note whose title starts with the words first.
        Results notes;
        notes.testQuery = QStringLiteral("oat");
        notes.showNotes({
            QVariantMap{{QStringLiteral("id"), QStringLiteral("a")}, {QStringLiteral("title"), QStringLiteral("Shopping")},
                        {QStringLiteral("excerpt"), QStringLiteral("buy oat milk")}, {QStringLiteral("folderLabel"), QStringLiteral("Home")},
                        {QStringLiteral("colourHex"), QStringLiteral("#F5D76E")}},
            QVariantMap{{QStringLiteral("id"), QStringLiteral("b")}, {QStringLiteral("title"), QStringLiteral("Oat recipes")},
                        {QStringLiteral("stuck"), true}, {QStringLiteral("window"), QStringLiteral("plan.md")},
                        {QStringLiteral("folderLabel"), QStringLiteral("Inbox")}},
            QVariantMap{{QStringLiteral("id"), QString()}},
        });
        if (notes.rowCount() != 2) return 60;
        if (notes.getQueryMatch(notes.index(0, 0)).data().toString() != QStringLiteral("b")) return 61;
        const auto inside = notes.index(1, 0).data(KRunner::ResultsModel::SubtextRole).toString();
        if (!inside.contains(QStringLiteral("buy oat milk")) || !inside.contains(QStringLiteral("Home"))) return 62;
        if (!notes.index(0, 0).data(KRunner::ResultsModel::SubtextRole).toString().contains(QStringLiteral("plan.md"))) return 63;
        if (!noteMatch(notes.getQueryMatch(notes.index(0, 0)))) return 64;
        notes.clear();
        if (notes.rowCount() != 0) return 65;
        if (searchTier(QStringLiteral("gooseberry-notes")) != 2) return 66;
    }
    {
        // Split Rock's Core: a fact found by the start of its words or a
        // query that holds one, and Core asked to open its card.
        const QVariantMap storage{{QStringLiteral("topic"), QStringLiteral("storage")}, {QStringLiteral("title"), QStringLiteral("Storage")},
            {QStringLiteral("line"), QStringLiteral("91% full")}, {QStringLiteral("detail"), QStringLiteral("45 GB free")},
            {QStringLiteral("actionText"), QStringLiteral("Free up space")}, {QStringLiteral("icon"), QStringLiteral("drive-harddisk")},
            {QStringLiteral("keywords"), QStringList{QStringLiteral("storage"), QStringLiteral("disk"), QStringLiteral("free up space")}}};
        if (!coreFactFits(storage, QStringLiteral("stor")) || !coreFactFits(storage, QStringLiteral("Disk space"))
            || !coreFactFits(storage, QStringLiteral("free up"))) return 70;
        if (coreFactFits(storage, QStringLiteral("st")) || coreFactFits(storage, QStringLiteral("firefox"))) return 71;
        Results core;
        QStringList opened;
        core.setCoreFacts([&storage] { return QList<QVariantMap>{storage}; },
                          [&opened](const QString &topic) { opened.append(topic); });
        core.testQuery = QStringLiteral("storage");
        core.showCore(core.testQuery);
        if (core.rowCount() != 1) return 72;
        const auto match = core.getQueryMatch(core.index(0, 0));
        if (!coreMatch(match) || match.text() != QStringLiteral("Storage · 91% full")) return 73;
        if (core.index(0, 0).data(KRunner::ResultsModel::SubtextRole).toString() != QStringLiteral("45 GB free · Free up space")) return 74;
        if (!core.run(core.index(0, 0)) || opened != QStringList{QStringLiteral("storage")}) return 75;
        if (searchTier(QStringLiteral("split-rock-core")) != 2) return 76;
        // A Core row comes before a folder of the same name, after an app
        // named exactly what was typed.
        KRunner::QueryMatch folder(&files), exactApp(&apps);
        folder.setText(QStringLiteral("update"));
        exactApp.setText(QStringLiteral("Update"));
        if (resultPriority(match, QStringLiteral("update")) >= resultPriority(folder, QStringLiteral("update"))) return 81;
        if (resultPriority(match, QStringLiteral("update")) <= resultPriority(exactApp, QStringLiteral("update"))) return 82;
        // A folder named exactly what was typed still follows an app, a
        // setting or a note that the words only start or describe.
        KRunner::QueryMatch settingsFolder(&files), settingsApp(&apps), browser(&apps), wifiSetting(&aids);
        settingsFolder.setText(QStringLiteral("settings"));
        settingsApp.setText(QStringLiteral("Shuffle Settings"));
        if (resultPriority(settingsApp, QStringLiteral("settings")) >= resultPriority(settingsFolder, QStringLiteral("settings"))) return 83;
        KRunner::QueryMatch browserFolder(&files);
        browserFolder.setText(QStringLiteral("browser"));
        browser.setText(QStringLiteral("Zen"));
        browser.setSubtext(QStringLiteral("Web browser"));
        if (resultPriority(browser, QStringLiteral("browser")) >= resultPriority(browserFolder, QStringLiteral("browser"))) return 84;
        wifiSetting.setId(QStringLiteral("kcm_networkmanagement"));
        wifiSetting.setText(QStringLiteral("Wi-Fi & Networking"));
        KRunner::QueryMatch wifiFolder(&files);
        wifiFolder.setText(QStringLiteral("wifi"));
        if (resultPriority(wifiSetting, QStringLiteral("wifi")) >= resultPriority(wifiFolder, QStringLiteral("wifi"))) return 85;
        // A file typed in full, extension and all, is still asked for by name.
        KRunner::QueryMatch soundFile(&files), soundSetting(&aids);
        soundFile.setText(QStringLiteral("sound.png"));
        soundSetting.setId(QStringLiteral("kcm_pulseaudio"));
        soundSetting.setText(QStringLiteral("Sound"));
        if (resultPriority(soundFile, QStringLiteral("sound.png")) >= resultPriority(soundSetting, QStringLiteral("sound.png"))) return 86;
        // The upkeep cards, found by their words; Install an app gets what was typed.
        const QVariantMap install{{QStringLiteral("id"), QStringLiteral("install")}, {QStringLiteral("title"), QStringLiteral("Install an app")},
            {QStringLiteral("sub"), QStringLiteral("Say what you need, or remove one")}, {QStringLiteral("icon"), QStringLiteral("system-software-install")},
            {QStringLiteral("keywords"), QStringList{QStringLiteral("install"), QStringLiteral("uninstall")}}};
        QStringList actionsOpened;
        core.setCoreActions([&install] { return QList<QVariantMap>{install}; },
                            [&actionsOpened](const QString &id, const QString &query) { actionsOpened.append(id + QStringLiteral(": ") + query); });
        core.testQuery = QStringLiteral("install pdf editor");
        core.showCore(core.testQuery);
        if (core.rowCount() != 1) return 78;
        if (core.getQueryMatch(core.index(0, 0)).text() != QStringLiteral("Install an app")) return 79;
        if (!core.run(core.index(0, 0)) || actionsOpened != QStringList{QStringLiteral("install: install pdf editor")}) return 80;
        core.clear();
        if (core.rowCount() != 0) return 77;
        // The Helpers chip: every upkeep card as a tile, opened on its own
        // with nothing typed, and while it shows, what is typed finds only
        // the cards, never a fact.
        const auto helpers = core.helpers();
        if (helpers.size() != 1) return 107;
        const auto tile = helpers.first().toMap();
        if (tile.value(QStringLiteral("id")).toString() != QStringLiteral("install")
            || tile.value(QStringLiteral("title")).toString() != QStringLiteral("Install an app")
            || tile.value(QStringLiteral("icon")).toString() != QStringLiteral("system-software-install")) return 108;
        if (!core.openHelper(QStringLiteral("install")) || actionsOpened.last() != QStringLiteral("install: ")) return 109;
        if (core.openHelper(QString())) return 110;
        core.testQuery = QStringLiteral("storage install");
        core.showCore(core.testQuery);
        if (core.rowCount() != 2) return 111;
        core.setHelpersOnly(true);
        if (core.rowCount() != 1 || core.getQueryMatch(core.index(0, 0)).text() != QStringLiteral("Install an app")) return 112;
        core.setHelpersOnly(false);
        if (core.rowCount() != 2) return 113;
        // The Helpers an answer from Ask names come first, in its order,
        // whatever was typed.
        const QVariantMap health{{QStringLiteral("id"), QStringLiteral("health")}, {QStringLiteral("title"), QStringLiteral("Health check")},
            {QStringLiteral("icon"), QStringLiteral("security-high")}, {QStringLiteral("keywords"), QStringList{QStringLiteral("health")}}};
        core.setCoreActions([&install, &health] { return QList<QVariantMap>{install, health}; },
                            [&actionsOpened](const QString &id, const QString &query) { actionsOpened.append(id + QStringLiteral(": ") + query); });
        core.setHelpersOnly(true);
        core.testQuery = QStringLiteral("my wifi keeps dropping");
        core.showCore(core.testQuery);
        if (core.rowCount() != 0) return 125;
        core.setAskedHelpers({QStringLiteral("health"), QStringLiteral("install")});
        if (core.rowCount() != 2 || core.getQueryMatch(core.index(0, 0)).text() != QStringLiteral("Health check")
            || core.getQueryMatch(core.index(1, 0)).text() != QStringLiteral("Install an app")) return 126;
        core.setAskedHelpers({});
        if (core.rowCount() != 0) return 127;
        core.setHelpersOnly(false);
        core.clear();
        Results without;
        if (!without.helpers().isEmpty() || without.openHelper(QStringLiteral("install"))) return 114;
    }
    {
        // Windows names find the apps that do those jobs here, once the
        // second word is begun, and only where the app is installed.
        if (windowsWordsReached(QStringLiteral("org.kde.dolphin.desktop"), QStringLiteral("File E")).isEmpty()
            || windowsWordsReached(QStringLiteral("systemsettings"), QStringLiteral("control panel")).isEmpty()
            || windowsWordsReached(QStringLiteral("org.kde.plasma-systemmonitor"), QStringLiteral("task-m")).isEmpty()
            || windowsWordsReached(QStringLiteral("org.kde.kinfocenter"), QStringLiteral("device man")).isEmpty()) return 100;
        if (!windowsWordsReached(QStringLiteral("org.kde.dolphin"), QStringLiteral("file")).isEmpty()
            || !windowsWordsReached(QStringLiteral("org.kde.dolphin"), QStringLiteral("files")).isEmpty()
            || !windowsWordsReached(QStringLiteral("systemsettings"), QStringLiteral("control")).isEmpty()
            || !windowsWordsReached(QStringLiteral("org.kde.kate"), QStringLiteral("task manager")).isEmpty()) return 101;
        Results windows;
        QStringList started;
        windows.setApplications([](const QString &name) {
            if (name != QStringLiteral("org.kde.plasma-systemmonitor")) return QVariantMap();
            return QVariantMap{{QStringLiteral("id"), QStringLiteral("org.kde.plasma-systemmonitor.desktop")},
                               {QStringLiteral("name"), QStringLiteral("System Monitor")}, {QStringLiteral("icon"), QStringLiteral("utilities-system-monitor")},
                               {QStringLiteral("description"), QStringLiteral("System Monitor")}};
        }, [&started](const QString &id) { started.append(id); return true; });
        windows.testQuery = QStringLiteral("task manager");
        windows.showWindowsWords(windows.testQuery);
        if (windows.rowCount() != 1) return 102;
        const auto found = windows.getQueryMatch(windows.index(0, 0));
        if (found.text() != QStringLiteral("System Monitor") || searchTier(found) != 0
            || runnerApplicationId(found) != QStringLiteral("org.kde.plasma-systemmonitor.desktop")
            || destinationKey(found) != QStringLiteral("app:org.kde.plasma-systemmonitor.desktop")) return 103;
        if (!windows.run(windows.index(0, 0)) || started != QStringList{QStringLiteral("org.kde.plasma-systemmonitor.desktop")}) return 104;
        // An app found by its Windows name comes before a folder of that name.
        KRunner::QueryMatch folder(&files);
        folder.setText(QStringLiteral("task manager"));
        if (resultPriority(found, windows.testQuery) >= resultPriority(folder, windows.testQuery)) return 105;
        // Device Manager is not installed here: no row.
        windows.testQuery = QStringLiteral("device manager");
        windows.showWindowsWords(windows.testQuery);
        if (windows.rowCount() != 0) return 106;
        windows.clear();
    }
    {
        // A document KDE's file index found by the words inside it is listed
        // after every file named for them. Everyday leaves out a source file
        // and a cache found that way; a recent document its name does not
        // answer and a two-letter query list nothing inside.
        Runner recent(QStringLiteral("recentdocuments"));
        Results inside;
        inside.testQuery = QStringLiteral("shovel");
        Stream stream;
        inside.setSourceModel(&stream);
        auto file = [](Runner *runner, const QString &path) {
            KRunner::QueryMatch match(runner);
            match.setId(path);
            match.setText(QFileInfo(path).fileName());
            match.setData(QUrl::fromLocalFile(path));
            return match;
        };
        const auto itinerary = file(&files, QStringLiteral("/home/test/Documents/North-Shore-itinerary.docx"));
        const auto photo = file(&files, QStringLiteral("/home/test/Pictures/Shovel Point.jpg"));
        stream.add({itinerary, photo,
                    file(&files, QStringLiteral("/home/test/Documents/trail/map.cpp")),
                    file(&files, QStringLiteral("/home/test/.cache/thumbnails/trip.png")),
                    file(&recent, QStringLiteral("/home/test/Documents/packing.odt")),
                    file(&files, QStringLiteral("/home/test/Documents/work/ZxcvbnData/3/english_wikipedia.txt")),
                    file(&files, QStringLiteral("/home/test/Documents/work/sessions/rollout-2026-09-02.jsonl")),
                    file(&files, QStringLiteral("/home/test/Documents/.drafts/trip.docx"))});
        inside.invalidate();
        if (resultPriority(itinerary, inside.testQuery) <= resultPriority(photo, inside.testQuery)) return 110;
        if (inside.rowCount() != 2) return 111;
        if (destinationKey(inside.getQueryMatch(inside.index(0, 0))) != destinationKey(photo)
            || destinationKey(inside.getQueryMatch(inside.index(1, 0))) != destinationKey(itinerary)) return 112;
        inside.setAllFiles(true);
        if (inside.rowCount() != 7) return 113;
        inside.testQuery = QStringLiteral("ov");
        inside.invalidate();
        if (inside.rowCount() != 1) return 114;
    }
    {
        // Found only by the words inside them, a word list and a log are left
        // out of Everyday; with nothing named for the words, Enter is the web's.
        Results inside;
        inside.testQuery = QStringLiteral("timberwolves schedule");
        Stream stream;
        inside.setSourceModel(&stream);
        auto file = [&files](const QString &path) {
            KRunner::QueryMatch match(&files);
            match.setId(path);
            match.setText(QFileInfo(path).fileName());
            match.setData(QUrl::fromLocalFile(path));
            return match;
        };
        stream.add({file(QStringLiteral("/home/test/Documents/work/ZxcvbnData/3/english_wikipedia.txt")),
                    file(QStringLiteral("/home/test/Documents/work/sessions/rollout-2026-09-02.jsonl"))});
        inside.invalidate();
        if (inside.rowCount() != 0 || inside.onlyFoundInside()) return 128;
        stream.add({file(QStringLiteral("/home/test/Documents/season.pdf"))});
        inside.invalidate();
        if (inside.rowCount() != 1 || !inside.onlyFoundInside()) return 129;
        stream.add({file(QStringLiteral("/home/test/Pictures/timberwolves schedule.png"))});
        inside.invalidate();
        if (inside.rowCount() != 2 || inside.onlyFoundInside()) return 130;
    }
    {
        // Three thousand files arriving a hundred batches at a time, as a
        // short query brings them: each is judged once, never again as later
        // batches arrive or the list is sorted and re-filtered.
        Results many;
        many.testQuery = QStringLiteral("rep");
        Stream stream;
        many.setSourceModel(&stream);
        QElapsedTimer clock;
        clock.start();
        for (int batch = 0; batch < 100; ++batch) {
            QList<KRunner::QueryMatch> arriving;
            for (int i = 0; i < 30; ++i) {
                const int n = batch * 30 + i;
                KRunner::QueryMatch file(&files);
                file.setId(QStringLiteral("file-%1").arg(n));
                file.setText(QStringLiteral("report %1.pdf").arg(n));
                file.setData(QUrl::fromLocalFile(QStringLiteral("/home/test/Documents/d%1/report %2.pdf").arg(n % 50).arg(n)));
                arriving.append(file);
            }
            stream.add(arriving);
            // Search re-filters and re-sorts everything after each batch.
            many.invalidate();
            QCoreApplication::processEvents();
        }
        QCoreApplication::processEvents();
        std::cout << "3000 files in 100 batches: " << clock.elapsed() << " ms, "
                  << many.checks() << " judgements\n";
        const auto failed = [&many](int code) {
            std::cout << "failed " << code << ": " << many.rowCount() << " rows, " << many.checks() << " judgements\n";
            return code;
        };
        if (many.rowCount() != 3000) return failed(90);
        if (many.checks() != 3000) return failed(91);
        // The same file twice stands once.
        stream.add({stream.matches.first()});
        many.invalidate();
        if (many.rowCount() != 3000) return failed(92);
        // A new query judges afresh.
        many.testQuery = QStringLiteral("repo");
        many.invalidate();
        // The list is laid out again when it is next read.
        if (many.rowCount() != 3000 || many.checks() != 6000) return failed(93);
    }
    return 0;
}
