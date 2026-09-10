#include "OmniResults.h"
#include <QGuiApplication>
#include <QJsonObject>
#include <QStandardItemModel>
#include <QTimer>
#include <iostream>

struct Runner : KRunner::AbstractRunner {
    explicit Runner(const QString &id) : AbstractRunner(nullptr,
        KPluginMetaData(QJsonObject{{QStringLiteral("KPlugin"), QJsonObject{
            {QStringLiteral("Id"), id}, {QStringLiteral("Name"), id}}}}, id)) {}
    void match(KRunner::RunnerContext &) override {}
};
struct Results : OmniResults {
    using OmniResults::lessThan;
    QString testQuery;
    QString queryString() const override { return testQuery.isNull() ? OmniResults::queryString() : testQuery; }
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
    return 0;
}
