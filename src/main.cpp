/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "ApplicationCatalog.h"
#include "CoreFactProvider.h"
#include "FileBrowser.h"
#include "FileDetails.h"
#include "FileThumbnails.h"
#include "LauncherController.h"
#include "NotesDoor.h"
#include "OmniResults.h"
#include "OpenWindows.h"
#include "ProductName.h"
#include "QuickNote.h"
#include "RecentUse.h"
#include "RunnerIdentity.h"
#include "TransferActivityBridge.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>
#include <KRunner/RunnerManager>
#include <KService/KService>
#include <LayerShellQt/Window>

#include <QCursor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QLockFile>
#include <QLoggingCategory>
#include <QProcess>
#include <QQmlEngine>
#include <QQuickView>
#include <QScreen>
#include <QThread>
#include <QTimer>

#include <functional>
#include <memory>

namespace
{
constexpr auto ServiceName = "io.github.carlsonjm.Tettegouche";

QStringList applicationRunnerIds()
{
    QStringList ids;
    const auto metadata = KRunner::RunnerManager::runnerMetaDataList();
    for (const KPluginMetaData &plugin : metadata) {
        if (searchTier(plugin.pluginId()) < 3) {
            ids.append(plugin.pluginId());
        }
    }
    ids.removeDuplicates();
    return ids;
}

QScreen *preferredScreen()
{
    if (QScreen *screen = QGuiApplication::screenAt(QCursor::pos())) {
        return screen;
    }
    return QGuiApplication::primaryScreen();
}

void configureSurface(QQuickView *view, QScreen *screen)
{
    view->setScreen(screen);
    view->setColor(Qt::transparent);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->setGeometry(screen->geometry());

    auto *surface = LayerShellQt::Window::get(view);
    surface->setScreen(screen);
    surface->setScope(QStringLiteral("tettegouche-launcher"));
    // Top, not overlay: KWin keeps the on-screen keyboard in the overlay layer,
    // and a later overlay surface stacks above it and takes every touch meant
    // for the keys. Opening activates the launcher, which takes a full-screen
    // window out of the layer above, so nothing covers the search either.
    surface->setLayer(LayerShellQt::Window::LayerTop);
    LayerShellQt::Window::Anchors anchors;
    anchors.setFlag(LayerShellQt::Window::AnchorTop);
    anchors.setFlag(LayerShellQt::Window::AnchorBottom);
    anchors.setFlag(LayerShellQt::Window::AnchorLeft);
    anchors.setFlag(LayerShellQt::Window::AnchorRight);
    surface->setAnchors(anchors);
    surface->setDesiredSize(QSize(0, 0));
    surface->setExclusiveZone(-1);
    surface->setKeyboardInteractivity(
        LayerShellQt::Window::KeyboardInteractivityExclusive);
    surface->setActivateOnShow(true);
}
}

// org.freedesktop.FileManager1, which a desktop asks to show folders and
// files, as in another application's "Show in folder". Each request goes to
// answer by the name of the launcher's own method for it.
class FileManagerService final : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.FileManager1")
public:
    using Answer = std::function<void(const QString &method, const QStringList &locations)>;
    explicit FileManagerService(Answer answer, QObject *parent = nullptr)
        : QObject(parent), m_answer(std::move(answer)) {}
public Q_SLOTS:
    Q_SCRIPTABLE void ShowFolders(const QStringList &uris, const QString &) { m_answer(QStringLiteral("showFolders"), uris); }
    Q_SCRIPTABLE void ShowItems(const QStringList &uris, const QString &) { m_answer(QStringLiteral("revealItems"), uris); }
    Q_SCRIPTABLE void ShowItemProperties(const QStringList &uris, const QString &) { m_answer(QStringLiteral("showItemProperties"), uris); }
private:
    Answer m_answer;
};

namespace
{
// Asks the running launcher; false when it did not answer.
bool launcherCall(const QString &method, const QVariantList &arguments)
{
    QDBusMessage request = QDBusMessage::createMethodCall(
        QString::fromLatin1(ServiceName), QStringLiteral("/Launcher"),
        QString::fromLatin1(ServiceName), method);
    request.setArguments(arguments);
    return QDBusConnection::sessionBus().call(request, QDBus::Block, 1000).type() != QDBusMessage::ErrorMessage;
}

// Another process holds the launcher's lock. One still starting holds it
// before its name is on the bus, and one leaving lets go of it as its name
// goes, so this asks until the launcher answers or the lock is free, for a
// few seconds at most. True when the lock was taken and this process is now
// the launcher.
bool forwardOrTakeOver(QLockFile &lock, const QString &method, const QVariantList &request)
{
    QElapsedTimer waited;
    waited.start();
    while (waited.elapsed() < 10000) {
        if (launcherCall(method, request)) return false;
        if (lock.tryLock(0)) return true;
        QThread::msleep(100);
    }
    return false;
}

// The widget's settings among a launcher's arguments, which it compares with
// the widget's own when it is asked to leave for them.
QStringList settingsIn(const QStringList &arguments)
{
    const QStringList settings{QStringLiteral("--standalone"), QStringLiteral("--no-recent"),
                               QStringLiteral("--no-recent-apps"), QStringLiteral("--no-recent-files"),
                               QStringLiteral("--no-notes"), QStringLiteral("--no-notes-pill")};
    QStringList given;
    for (const QString &argument : arguments) {
        if (settings.contains(argument) && !given.contains(argument))
            given.append(argument);
    }
    return given;
}

// Started by D-Bus as the file manager while a launcher already runs: each
// request goes on to it, and this process leaves once nothing has come for a
// few seconds. A launcher that left meanwhile is started again for the request.
int answerForRunningLauncher(QGuiApplication &application)
{
    QTimer idle;
    idle.setSingleShot(true);
    idle.setInterval(3000);
    QObject::connect(&idle, &QTimer::timeout, &application, &QCoreApplication::quit);
    FileManagerService service([&idle](const QString &method, const QStringList &locations) {
        idle.start();
        if (launcherCall(method, {locations}) || locations.isEmpty()) return;
        QStringList arguments;
        if (method == QLatin1String("showFolders")) arguments = {QStringLiteral("--folder"), locations.first()};
        else if (method == QLatin1String("showItemProperties")) arguments = {QStringLiteral("--properties"), locations.first()};
        else arguments = QStringList{QStringLiteral("--reveal")} + locations;
        QProcess::startDetached(QCoreApplication::applicationFilePath(), arguments);
    });
    auto session = QDBusConnection::sessionBus();
    session.registerObject(QStringLiteral("/org/freedesktop/FileManager1"), &service, QDBusConnection::ExportScriptableSlots);
    if (!session.registerService(QStringLiteral("org.freedesktop.FileManager1"))) return 1;
    idle.start();
    return application.exec();
}
}

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("wayland"));
    }

    // KIO's file worker runs in this process and writes a debug line for each
    // file it copies, which on a large copy floods the system journal. Its
    // debug output stays off unless QT_LOGGING_RULES asks for it.
    QLoggingCategory::setFilterRules(QStringLiteral("kf.kio.*.debug=false"));
    QGuiApplication application(argc, argv);
    // The launcher's words, in C++ and in QML through KI18n, come from this catalog.
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("tettegouche"));
    application.setApplicationName(QStringLiteral("tettegouche"));
    application.setDesktopFileName(
        QStringLiteral("io.github.carlsonjm.Tettegouche"));
    application.setOrganizationDomain(QStringLiteral("github.com/carlsonjm"));
    application.setQuitOnLastWindowClosed(false); // a hidden Files job still owns this process
    const QStringList arguments = application.arguments();
    const auto valueAfter = [&arguments](const QString &flag) {
        const int index = arguments.indexOf(flag);
        return index >= 0 ? arguments.value(index + 1) : QString();
    };
    const QString showFile = valueAfter(QStringLiteral("--show-file"));
    const QString drawer = valueAfter(QStringLiteral("--drawer"));
    // A folder another application asks to open, and the items it asks to
    // show, all given after --reveal, or whose Properties it asks for.
    const QString folder = valueAfter(QStringLiteral("--folder"));
    // A drive by its device identifier, to open in Files.
    const QString drive = valueAfter(QStringLiteral("--drive"));
    const QString properties = valueAfter(QStringLiteral("--properties"));
    const int revealIndex = arguments.indexOf(QStringLiteral("--reveal"));
    QStringList reveal = revealIndex >= 0 ? arguments.mid(revealIndex + 1) : QStringList();
    reveal.removeIf([](const QString &argument) { return argument.startsWith(QLatin1String("--")); });
    // Opened by Search's key rather than its button: ready to type.
    const bool toType = arguments.contains(QStringLiteral("--type"));
    // Started by D-Bus to answer as the file manager.
    const bool fileManager = arguments.contains(QStringLiteral("--file-manager"));

    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    QLockFile instanceLock(QString::fromLocal8Bit(runtime)
                           + QStringLiteral("/tettegouche.lock"));
    instanceLock.setStaleLockTime(0);
    if (!instanceLock.tryLock()) {
        if (fileManager) return answerForRunningLauncher(application);
        QString method = toType ? QStringLiteral("toggleToType") : QStringLiteral("toggle");
        QVariantList request;
        if (!showFile.isEmpty()) { method = QStringLiteral("showFile"); request = {showFile}; }
        else if (!folder.isEmpty()) { method = QStringLiteral("showFolder"); request = {folder}; }
        else if (!drive.isEmpty()) { method = QStringLiteral("showDrive"); request = {drive}; }
        else if (!reveal.isEmpty()) { method = QStringLiteral("revealItems"); request = {reveal}; }
        else if (!properties.isEmpty()) { method = QStringLiteral("showItemProperties"); request = {QStringList{properties}}; }
        else if (!drawer.isEmpty()) { method = QStringLiteral("openDrawer"); request = {drawer}; }
        // This forwarding process exits once its request is delivered: it
        // waits for delivery, not an asynchronous call whose connection may
        // disappear before dispatch. A launcher on its way out lets go of the
        // lock; this process then takes its place.
        if (!forwardOrTakeOver(instanceLock, method, request)) return 0;
    }

    const QStringList runners = applicationRunnerIds();
    if (runners.isEmpty()) {
        qCritical("The installed-application search provider is unavailable.");
        return 2;
    }

    KRunner::RunnerManager runnerManager;
    runnerManager.setAllowedRunners(runners);
    OmniResults results;
    results.setRunnerManager(&runnerManager);
    results.setLimit(0);
    ApplicationCatalog catalog;
    catalog.setUseReader(&RecentUse::readApplicationUse);
    FileDevices fileDevices;
    // Search's Files and each Files window's own are set up alike.
    const auto prepareFiles = [&fileDevices](FileBrowser &files) {
        files.setDevices(&fileDevices);
        files.setThumbnailSource([](const QString &path, const QString &mimeType, qint64 modified) {
            return FileThumbnails::covers(mimeType) ? FileThumbnails::source(path, mimeType, modified) : QString();
        });
        files.setDetailReader(readMediaDetails);
    };
    FileBrowser fileBrowser;
    prepareFiles(fileBrowser);
    const bool guestAllowed =
        !application.arguments().contains(QStringLiteral("--standalone"));

    QScreen *screen = preferredScreen();
    if (!screen) {
        return 1;
    }

    QQuickView view;
    view.setTitle(tettegouche::productName());
    view.engine()->addImageProvider(QStringLiteral("thumbnail"), new FileThumbnails);
    configureSurface(&view, screen);
    LauncherController controller(&view, &runnerManager, &results, &catalog,
                                  guestAllowed);
    controller.setStartedWith(settingsIn(arguments));
    controller.setFileBrowser(&fileBrowser);
    // Where Kadunce does not say what is open, Plasma's window list does.
    OpenWindows openWindows(OpenWindows::plasmaWindowList(view.engine()));
    controller.setOpenWindows(&openWindows);
    // Recent apps and recent files each have a setting; with both off,
    // nothing used lately is read or offered.
    const bool recentApps = !application.arguments().contains(QStringLiteral("--no-recent"))
        && !application.arguments().contains(QStringLiteral("--no-recent-apps"));
    const bool recentFiles = !application.arguments().contains(QStringLiteral("--no-recent"))
        && !application.arguments().contains(QStringLiteral("--no-recent-files"));
    const bool offerRecent = recentApps || recentFiles;
    RecentUse recent;
    recent.setOffered(recentApps, recentFiles);
    recent.setThumbnails([](const QString &path, const QString &mimeType, qint64 modified) {
        return FileThumbnails::covers(mimeType) ? FileThumbnails::source(path, mimeType, modified) : QString();
    });
    if (offerRecent) controller.setRecentUse(&recent);
    // With the setting off, the Notes door is never offered.
    const bool offerNotes = !application.arguments().contains(QStringLiteral("--no-notes"));
    NotesDoor notes;
    if (offerNotes) controller.setNotesDoor(&notes);
    // Notes found by their words are listed among the results, as Gooseberry
    // answers, only while Notes is offered.
    results.setNotesOffered(offerNotes);
    // Split Rock's Core, where it is installed: its facts and its upkeep
    // cards are found by their words, and Core opens the card.
    CoreFactProvider core(QDBusConnection::sessionBus());
    results.setCoreFacts([&core] { return core.facts(); }, [&core](const QString &topic) { core.open(topic); });
    results.setCoreActions([&core] { return core.actions(); },
                           [&core](const QString &id, const QString &query) { core.openAction(id, query); });
    // Where Core removes apps, an application's Uninstall goes to it.
    catalog.setRemover([&core] { return core.removesApps(); },
                       [&core](const QString &id, const QString &name) { core.removeApp(id, name); });
    // The quick note itself, written in Search's window and kept by the notes
    // application; asked for only while Notes is offered.
    std::unique_ptr<QuickNote> quickNote;
    if (offerNotes) quickNote = std::make_unique<QuickNote>();
    // A note handed from Notes to the notes application's card leads back to
    // Notes from there.
    if (quickNote) {
        QObject::connect(quickNote.get(), &QuickNote::backRequested, &controller,
                         [&controller] { controller.openDrawer(QStringLiteral("notes")); });
    }
    QObject::connect(&application, &QGuiApplication::lastWindowClosed,
                     &controller, &LauncherController::close);
    const auto openFrom = [&controller](FileBrowser *files) {
        QObject::connect(files, &FileBrowser::openRequested, &controller, [files, &controller](const QUrl &url) {
            auto *job = new KIO::OpenUrlJob(url);
            job->setRunExecutables(false);
            job->setShowOpenOrExecuteDialog(false);
            QObject::connect(job, &KJob::result, files, [files, &controller](KJob *completed) {
                const QString error = completed->error() ? completed->errorString() : QString();
                files->finishOpen(error);
                if (!completed->error()) controller.finishLaunch();
            });
            job->start();
        });
        QObject::connect(files, &FileBrowser::openWithRequested, &controller,
                         [files, &controller](const QUrl &url, const QString &applicationId) {
            auto *job = new KIO::ApplicationLauncherJob(KService::serviceByStorageId(applicationId));
            job->setUrls({url});
            QObject::connect(job, &KJob::result, files, [files, &controller](KJob *completed) {
                const QString error = completed->error() ? completed->errorString() : QString();
                files->finishOpen(error);
                if (!completed->error()) controller.finishLaunch();
            });
            job->start();
        });
    };
    openFrom(&fileBrowser);
    view.setInitialProperties({
        {QStringLiteral("fileBrowser"), QVariant::fromValue(static_cast<QObject *>(&fileBrowser))},
        {QStringLiteral("launcherController"),
         QVariant::fromValue(static_cast<QObject *>(&controller))},
        {QStringLiteral("searchResults"),
         QVariant::fromValue(static_cast<QObject *>(&results))},
        {QStringLiteral("applicationCatalog"),
         QVariant::fromValue(static_cast<QObject *>(&catalog))},
        // What is not offered is passed as null; an empty QVariant would
        // reach QML as undefined, which its "!== null" checks let through.
        {QStringLiteral("recentUse"), QVariant::fromValue<QObject *>(offerRecent ? &recent : nullptr)},
        // Which sections the first screen shows, and so how tall it rests.
        {QStringLiteral("recentApps"), recentApps},
        {QStringLiteral("recentFiles"), recentFiles},
        {QStringLiteral("notesDoor"), QVariant::fromValue<QObject *>(offerNotes ? &notes : nullptr)},
        // The Notes pill can be left off the first screen on its own.
        {QStringLiteral("notesPillShown"),
         !application.arguments().contains(QStringLiteral("--no-notes-pill"))},
        {QStringLiteral("quickNote"), QVariant::fromValue<QObject *>(quickNote.get())},
    });
    view.setSource(QUrl(QStringLiteral("qrc:/qml/Launcher.qml")));
    if (view.status() == QQuickView::Error) {
        return 3;
    }

    QDBusConnection session = QDBusConnection::sessionBus();
    TransferActivityBridge activities(&fileBrowser);
    // Each Files window has a Files of its own, whose copies Ambient hears of
    // too.
    controller.setFileBrowserMaker([&prepareFiles, &openFrom, &activities] {
        auto files = std::make_unique<FileBrowser>();
        prepareFiles(*files);
        openFrom(files.get());
        activities.add(files.get());
        return files;
    });
    session.registerObject(QStringLiteral("/Activities"), &activities,
                           QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    session.registerObject(QStringLiteral("/Launcher"), &controller,
                           QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals);
    QObject::connect(&view, &QWindow::visibleChanged, &controller, &LauncherController::shown);
    session.registerService(QString::fromLatin1(ServiceName));
    // Answering as the file manager is switched on by pointing D-Bus at this
    // launcher; a launcher started any other way leaves it to whoever answers
    // now.
    FileManagerService fileManagerService([&controller](const QString &method, const QStringList &locations) {
        if (method == QLatin1String("showFolders")) controller.showFolders(locations);
        else if (method == QLatin1String("revealItems")) controller.revealItems(locations);
        else if (method == QLatin1String("showItemProperties")) controller.showItemProperties(locations);
    });
    if (fileManager) {
        session.registerObject(QStringLiteral("/org/freedesktop/FileManager1"), &fileManagerService,
                               QDBusConnection::ExportScriptableSlots);
        session.registerService(QStringLiteral("org.freedesktop.FileManager1"));
        QTimer::singleShot(5000, &controller, &LauncherController::leaveIfUnused);
    }

    QTimer::singleShot(0, &controller, [&controller, showFile, drawer, folder, drive, reveal, properties, fileManager, toType] {
        if (!showFile.isEmpty()) controller.showFile(showFile);
        else if (!folder.isEmpty()) controller.showFolder(folder);
        else if (!drive.isEmpty()) controller.showDrive(drive);
        else if (!reveal.isEmpty()) controller.revealItems(reveal);
        else if (!properties.isEmpty()) controller.showItemProperties({properties});
        else if (!drawer.isEmpty()) controller.openDrawer(drawer);
        else if (toType) controller.toggleToType();
        else if (!fileManager) controller.open();
    });
    const int result = application.exec();
    view.setSource(QUrl());
    return result;
}

#include "main.moc"
