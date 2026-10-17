/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The launcher against a stand-in Kadunce on a private bus: the guest
// handshake it speaks, what it asks and tells as it opens, launches and
// closes, a slow Kadunce that holds nothing up, an open application brought
// forward, and, with no Kadunce, Plasma's window list in its place. The stand-in answers from a thread of its own on
// a connection of its own, so the launcher's waiting calls are answered as
// KWin answers them. Nothing of the person's is read or written.

#include "ApplicationCatalog.h"
#include "LauncherController.h"
#include "OmniResults.h"
#include "OpenWindows.h"

#include <KRunner/RunnerManager>
#include <KSycoca>

#include <QDBusConnection>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QMutexLocker>
#include <QQuickView>
#include <QScreen>
#include <QSignalSpy>
#include <QStandardItemModel>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>

#include <memory>

namespace
{
const QString KWinName = QStringLiteral("org.kde.KWin");

QString contextWith(const QString &appId, const QString &windowId)
{
    const QJsonObject application{{QStringLiteral("windowId"), windowId}, {QStringLiteral("appId"), appId},
                                  {QStringLiteral("title"), appId}};
    return QString::fromUtf8(QJsonDocument(QJsonObject{
        {QStringLiteral("schema"), QStringLiteral("co.goodinput.kadunce.workspace-context")},
        {QStringLiteral("version"), 1},
        {QStringLiteral("applications"), QJsonArray{application}}}).toJson(QJsonDocument::Compact));
}
}

// Kadunce as the launcher sees it: each call it was asked, in order, and the
// answers it is set to give.
class StandInKadunce : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "co.goodinput.Kadunce")
public:
    int protocol = 3;
    bool accepts = true;
    bool activates = true;
    // How long a guest's begin takes to answer, as a busy KWin takes.
    int delay = 0;
    QString output;
    QString context;

    QStringList calls()
    {
        QMutexLocker locked(&m_lock);
        return m_calls;
    }
    void forget()
    {
        QMutexLocker locked(&m_lock);
        m_calls.clear();
    }
    void set(const std::function<void(StandInKadunce &)> &change)
    {
        QMutexLocker locked(&m_lock);
        change(*this);
    }

public Q_SLOTS:
    Q_SCRIPTABLE int launcherGuestProtocolVersion() { return note(QStringLiteral("launcherGuestProtocolVersion"), protocol); }
    Q_SCRIPTABLE QString beginLauncherGuest(const QString &launcher)
    {
        int wait = 0;
        {
            QMutexLocker locked(&m_lock);
            wait = delay;
        }
        QThread::msleep(wait);
        QMutexLocker locked(&m_lock);
        m_calls << QStringLiteral("beginLauncherGuest ") + launcher;
        const QJsonObject card{{QStringLiteral("x"), 100}, {QStringLiteral("y"), 50},
                               {QStringLiteral("width"), 600}, {QStringLiteral("height"), 400}};
        return QString::fromUtf8(QJsonDocument(QJsonObject{
            {QStringLiteral("protocol"), 3}, {QStringLiteral("accepted"), accepts},
            {QStringLiteral("output"), output}, {QStringLiteral("card"), accepts ? card : QJsonObject()},
            {QStringLiteral("active"), card}}).toJson(QJsonDocument::Compact));
    }
    Q_SCRIPTABLE void endLauncherGuest() { note(QStringLiteral("endLauncherGuest"), 0); }
    Q_SCRIPTABLE void updateLauncherGuest(double delta) { note(QStringLiteral("updateLauncherGuest ") + QString::number(delta), 0); }
    Q_SCRIPTABLE bool finishLauncherGuest(double delta) { return note(QStringLiteral("finishLauncherGuest ") + QString::number(delta), true); }
    Q_SCRIPTABLE bool prepareLauncherGuestLaunch(const QStringList &identities, const QString &token)
    {
        QMutexLocker locked(&m_lock);
        m_calls << QStringLiteral("prepareLauncherGuestLaunch ") + identities.join(QLatin1Char(','));
        m_token = token;
        return true;
    }
    Q_SCRIPTABLE void cancelLauncherGuestLaunch() { note(QStringLiteral("cancelLauncherGuestLaunch"), 0); }
    Q_SCRIPTABLE bool activateApplicationWindow(const QString &window)
    {
        return note(QStringLiteral("activateApplicationWindow ") + window, activates);
    }
    Q_SCRIPTABLE QString workspaceContext()
    {
        QMutexLocker locked(&m_lock);
        m_calls << QStringLiteral("workspaceContext");
        return context;
    }

public:
    QString token()
    {
        QMutexLocker locked(&m_lock);
        return m_token;
    }

private:
    template<typename T>
    T note(const QString &call, T answer)
    {
        QMutexLocker locked(&m_lock);
        m_calls << call;
        return answer;
    }
    QMutex m_lock;
    QStringList m_calls;
    QString m_token;
};

// Plasma's window list as its QML module serves it: rows with its role
// names, and requestActivate.
class StandInWindows : public QStandardItemModel
{
    Q_OBJECT
public:
    StandInWindows()
    {
        setItemRoleNames({{Qt::DisplayRole, "display"}, {Qt::UserRole + 1, "AppId"}, {Qt::UserRole + 2, "AppName"},
                          {Qt::UserRole + 3, "IsWindow"}, {Qt::UserRole + 4, "WinIdList"},
                          {Qt::UserRole + 5, "SkipTaskbar"}, {Qt::UserRole + 6, "IsActive"}});
    }
    void addWindow(const QString &appId, const QString &name, const QString &window, bool skip = false)
    {
        auto *item = new QStandardItem(name);
        item->setData(appId, Qt::UserRole + 1);
        item->setData(name, Qt::UserRole + 2);
        item->setData(true, Qt::UserRole + 3);
        item->setData(QVariantList{window}, Qt::UserRole + 4);
        item->setData(skip, Qt::UserRole + 5);
        appendRow(item);
    }
    QStringList activated;
    Q_INVOKABLE void requestActivate(const QModelIndex &index)
    {
        activated << index.data(Qt::UserRole + 4).toList().value(0).toString();
    }
};

class LauncherControllerTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        const QString applications = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/");
        QVERIFY(QDir().mkpath(applications));
        QFile alpha(applications + QStringLiteral("alpha.desktop"));
        QVERIFY(alpha.open(QIODevice::WriteOnly));
        alpha.write("[Desktop Entry]\nType=Application\nName=Alpha\nExec=true\n");
        alpha.close();
        KSycoca::self()->ensureCacheValid();

        m_kadunce.output = QGuiApplication::primaryScreen()->name();
        m_kadunce.moveToThread(&m_kwinThread);
        m_kwinThread.start();
        m_kwin = std::make_unique<QDBusConnection>(
            QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("stand-in-kwin")));
        QVERIFY(m_kwin->isConnected());
        QVERIFY(m_kwin->registerObject(QStringLiteral("/Kadunce"), &m_kadunce, QDBusConnection::ExportScriptableSlots));
        QVERIFY(m_kwin->registerService(KWinName));

        m_view = std::make_unique<QQuickView>();
        m_view->resize(1280, 800);
        m_results.setRunnerManager(&m_runners);
        m_catalog = std::make_unique<ApplicationCatalog>();
        m_controller = std::make_unique<LauncherController>(m_view.get(), &m_runners, &m_results, m_catalog.get(), true);
        m_openWindows = std::make_unique<OpenWindows>([this](QObject *) -> QAbstractItemModel * { return &m_windows; });
        m_controller->setOpenWindows(m_openWindows.get());
        QTest::qWait(100);
        QVERIFY(m_catalog->applicationRow(QStringLiteral("alpha.desktop")) >= 0);
    }

    // Kadunce speaking protocol 3 takes the launcher as its guest, knowing it
    // by its connection's name; closing ends the guest.
    void becomesKadunceGuest()
    {
        m_kadunce.forget();
        m_controller->open();
        QTRY_VERIFY(m_view->isVisible());
        QVERIFY(m_controller->guestMode());
        QCOMPARE(m_controller->guestWidth(), 600);
        QCOMPARE(m_controller->guestHeight(), 400);
        // What is open is read alongside, in whichever order it is answered.
        QStringList calls = m_kadunce.calls();
        calls.removeAll(QStringLiteral("workspaceContext"));
        QCOMPARE(calls.value(0), QStringLiteral("launcherGuestProtocolVersion"));
        QCOMPARE(calls.value(1), QStringLiteral("beginLauncherGuest ") + QDBusConnection::sessionBus().baseService());

        m_controller->updateGuestDrag(12);
        QVERIFY(m_controller->finishGuestDrag(30));
        QTRY_VERIFY(m_kadunce.calls().contains(QStringLiteral("updateLauncherGuest 12")));
        QVERIFY(m_kadunce.calls().contains(QStringLiteral("finishLauncherGuest 30")));

        m_controller->close();
        QVERIFY(!m_view->isVisible());
        QVERIFY(!m_controller->guestMode());
        QTRY_VERIFY(m_kadunce.calls().contains(QStringLiteral("endLauncherGuest")));
    }

    // The protocol is asked once for each Kadunce. Any other protocol, from
    // a Kadunce come since, or a guest declined, leaves the launcher floating.
    void floatsOtherwise()
    {
        m_kadunce.forget();
        m_controller->open();
        QTRY_VERIFY(m_view->isVisible());
        QVERIFY(!m_kadunce.calls().contains(QStringLiteral("launcherGuestProtocolVersion")));
        m_controller->close();

        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.protocol = 2; });
        QVERIFY(QMetaObject::invokeMethod(m_controller.get(), "bridgeLost"));
        m_kadunce.forget();
        m_controller->open();
        QTRY_VERIFY(m_view->isVisible());
        QVERIFY(!m_controller->guestMode());
        QVERIFY(m_kadunce.calls().contains(QStringLiteral("launcherGuestProtocolVersion")));
        QVERIFY(!m_kadunce.calls().join(QLatin1Char('\n')).contains(QStringLiteral("beginLauncherGuest")));
        m_controller->close();

        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.protocol = 3; kadunce.accepts = false; });
        m_controller->open();
        QTRY_VERIFY(m_view->isVisible());
        QVERIFY(!m_controller->guestMode());
        m_controller->close();
        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.accepts = true; });
    }

    // A Kadunce slow to answer holds nothing up: open returns at once, the
    // launcher shows on its own once its wait has passed, and the place
    // Kadunce made when it does answer is given back.
    void showsWithoutWaitingOnKadunce()
    {
        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.delay = 1500; });
        m_kadunce.forget();
        QElapsedTimer opening;
        opening.start();
        m_controller->open();
        QVERIFY(opening.elapsed() < 300);
        QVERIFY(!m_view->isVisible());
        QTRY_VERIFY_WITH_TIMEOUT(m_view->isVisible(), 1000);
        QVERIFY(opening.elapsed() < 1200);
        QVERIFY(!m_controller->guestMode());
        QTRY_VERIFY_WITH_TIMEOUT(m_kadunce.calls().contains(QStringLiteral("endLauncherGuest")), 3000);
        m_controller->close();
        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.delay = 0; });
    }

    // A launch from Search as a guest is awaited as a card, by the
    // application's identity, until Kadunce says its window came.
    void awaitsALaunchedWindow()
    {
        m_controller->open();
        QTRY_VERIFY(m_controller->guestMode());
        const int alpha = m_catalog->applicationRow(QStringLiteral("alpha.desktop"));
        QVERIFY(m_controller->beginGuestApplicationLaunch(alpha, true));
        QVERIFY(m_kadunce.calls().contains(QStringLiteral("prepareLauncherGuestLaunch alpha.desktop")));
        QSignalSpy ready(m_controller.get(), &LauncherController::guestLaunchReady);
        m_controller->completeGuestLaunch(QStringLiteral("another"));
        QCOMPARE(ready.count(), 0);
        m_controller->completeGuestLaunch(m_kadunce.token());
        QCOMPARE(ready.count(), 1);
        m_controller->finishLaunch();
        QVERIFY(!m_view->isVisible());
        QTest::qWait(800);
        QVERIFY(!m_view->isVisible());
    }

    // An application Kadunce says is open is brought forward rather than
    // started; one no longer open is started.
    void bringsAnOpenApplicationForward()
    {
        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.context = contextWith(QStringLiteral("alpha"), QStringLiteral("w1")); });
        m_kadunce.forget();
        m_controller->open();
        QTRY_VERIFY(m_controller->contextAvailable());
        const int alpha = m_catalog->applicationRow(QStringLiteral("alpha.desktop"));
        QCOMPARE(m_controller->activateCatalogIfOpen(alpha), 1);
        QVERIFY(m_kadunce.calls().contains(QStringLiteral("activateApplicationWindow w1")));

        m_kadunce.set([](StandInKadunce &kadunce) {
            kadunce.activates = false;
            kadunce.context = contextWith(QStringLiteral("zulu"), QStringLiteral("w2"));
        });
        QCOMPARE(m_controller->activateCatalogIfOpen(alpha), 0);
        m_kadunce.set([](StandInKadunce &kadunce) { kadunce.activates = true; kadunce.context.clear(); });
        m_controller->close();
    }

    // With no Kadunce, the launcher floats, and what is open comes from
    // Plasma's window list, which brings the window forward.
    void withoutKadunceReadsPlasma()
    {
        QVERIFY(m_kwin->unregisterService(KWinName));
        QTest::qWait(100);
        m_windows.addWindow(QStringLiteral("alpha"), QStringLiteral("Alpha"), QStringLiteral("{uuid-1}"));
        m_windows.addWindow(QStringLiteral("beta"), QStringLiteral("Beta question"), QStringLiteral("{uuid-2}"), true);
        m_controller->open();
        QTRY_VERIFY(m_view->isVisible());
        QVERIFY(!m_controller->guestMode());
        QTRY_VERIFY(m_controller->contextAvailable());
        const int alpha = m_catalog->applicationRow(QStringLiteral("alpha.desktop"));
        QCOMPARE(m_controller->activateCatalogIfOpen(alpha), 1);
        QCOMPARE(m_windows.activated, QStringList{QStringLiteral("{uuid-1}")});
        m_windows.clear();
        QTRY_COMPARE(m_controller->activateCatalogIfOpen(alpha), 0);
        m_controller->close();
    }

    // Asked to leave for other settings, a hidden launcher with nothing
    // keeping it leaves; shown, or for its own settings, it stays.
    void leavesOnlyForOtherSettings()
    {
        m_controller->setStartedWith({QStringLiteral("--no-recent")});
        QVERIFY(!m_controller->leaveFor({QStringLiteral("--no-recent")}));
        m_controller->open();
        QVERIFY(!m_controller->leaveFor({}));
        m_controller->close();
        QVERIFY(m_controller->leaveFor({}));
    }

    void cleanupTestCase()
    {
        m_controller.reset();
        m_kwin->unregisterObject(QStringLiteral("/Kadunce"));
        m_kwinThread.quit();
        m_kwinThread.wait();
    }

private:
    StandInKadunce m_kadunce;
    QThread m_kwinThread;
    std::unique_ptr<QDBusConnection> m_kwin;
    StandInWindows m_windows;
    KRunner::RunnerManager m_runners;
    OmniResults m_results;
    std::unique_ptr<QQuickView> m_view;
    std::unique_ptr<ApplicationCatalog> m_catalog;
    std::unique_ptr<OpenWindows> m_openWindows;
    std::unique_ptr<LauncherController> m_controller;
};

int main(int argc, char **argv)
{
    QTemporaryDir home;
    if (!home.isValid()) return 1;
    qputenv("HOME", home.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (home.path() + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_DATA_HOME", (home.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_DATA_DIRS", (home.path() + QStringLiteral("/system")).toUtf8());
    qputenv("XDG_CACHE_HOME", (home.path() + QStringLiteral("/cache")).toUtf8());
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("tettegouche-test"));
    app.setApplicationName(QStringLiteral("launcher-controller-test"));
    LauncherControllerTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "LauncherControllerTest.moc"
