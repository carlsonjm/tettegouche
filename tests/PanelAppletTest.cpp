/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <QApplication>
#include <QFile>
#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <cmath>
#include <memory>

class ToggleEndpoint : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche")
public:
    int calls = 0;
    int typedCalls = 0;
    QStringList drawers;
    // The settings it was asked to leave for, joined; and whether it leaves.
    QStringList leaves;
    bool leaving = false;
public Q_SLOTS:
    Q_SCRIPTABLE void toggle() { ++calls; }
    Q_SCRIPTABLE void toggleToType() { ++typedCalls; }
    Q_SCRIPTABLE bool leaveFor(const QStringList &settings) { leaves << settings.join(QLatin1Char(' ')); return leaving; }
    Q_SCRIPTABLE void openDrawer(const QString &drawer) { drawers << drawer; }
};

#include <KConfigGroup>
#include <KService>
#include <KSycoca>
#include <KPackage/Package>
#include <KPackage/PackageLoader>
#include <KConfigLoader>
#include <Plasma/Applet>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <QAction>

#include "LauncherKeys.h"

// Plasma 6.8 numbers screens with uint where 6.7 used int; the test corona
// overrides screenGeometry with whichever its Plasma declares.
template<typename> struct CoronaScreenArgument;
template<typename Class, typename Result, typename Argument>
struct CoronaScreenArgument<Result (Class::*)(Argument) const> {
    using type = Argument;
};
using CoronaScreenId = CoronaScreenArgument<decltype(&Plasma::Corona::screenGeometry)>::type;

class TestCorona : public Plasma::Corona
{
public:
    QRect screenGeometry(CoronaScreenId) const override { return QRect(0, 0, 1280, 800); }
};

class PanelAppletTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // A click must start a harmless stand-in, never the real launcher.
        QVERIFY(m_fixture.isValid());
        QFile userDirs(m_fixture.filePath(QStringLiteral("user-dirs.dirs")));
        QVERIFY(userDirs.open(QIODevice::WriteOnly));
        userDirs.write("XDG_DOWNLOAD_DIR=\"" + m_fixture.path().toUtf8() + "/Downloads\"\n");
        userDirs.close();
        qputenv("XDG_CONFIG_HOME",m_fixture.path().toUtf8());
        // The stand-in writes down each start, one line of arguments each,
        // and leaves at once.
        m_executable = m_fixture.filePath(QStringLiteral("tettegouche"));
        m_launches = m_fixture.filePath(QStringLiteral("launches"));
        QVERIFY(writeScript(m_executable, m_launches));
        const QByteArray testPath = m_fixture.path().toLocal8Bit() + ':' + qgetenv("PATH");
        qputenv("PATH", testPath);
        QCOMPARE(QStandardPaths::findExecutable(QStringLiteral("tettegouche")), m_executable);

        m_corona = new TestCorona;
        auto shell = KPackage::PackageLoader::self()->loadPackage(QStringLiteral("Plasma/Shell"));
        shell.setPath(QStringLiteral("org.kde.plasma.desktop"));
        m_corona->setKPackage(shell);
        m_panel = m_corona->createContainment(QStringLiteral("null"));
        QVERIFY(m_panel);
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_panel->setLocation(Plasma::Types::BottomEdge);
        m_applet = m_panel->createApplet(QStringLiteral("co.goodinput.tettegouche"));
        QVERIFY(m_applet);
        QVERIFY(!m_applet->failedToLaunch());
        QCOMPARE(m_applet->pluginMetaData().iconName(), QStringLiteral("co.goodinput.tettegouche-logo"));
        const QString expectedPlugin = QString::fromLocal8Bit(qgetenv("TETTE_TEST_PLUGIN_ROOT"))
            + QStringLiteral("/plasma/applets/co.goodinput.tettegouche.so");
        QCOMPARE(QFileInfo(m_applet->pluginMetaData().fileName()).canonicalFilePath(),
                 QFileInfo(expectedPlugin).canonicalFilePath());

        m_face = PlasmaQuick::AppletQuickItem::itemForApplet(m_applet);
        QVERIFY(m_face);
        m_window = new QQuickWindow;
        m_window->setColor(QColor(QStringLiteral("#141414")));
        m_window->resize(120, 100);
        m_face->setParentItem(m_window->contentItem());
        m_face->setPosition(QPointF(30, 20));
        m_face->setSize(QSizeF(44, 42));
        m_window->show();
        QTest::qWait(100);
    }

    void visiblePanelControl_data()
    {
        QTest::addColumn<bool>("vertical");
        QTest::addColumn<QSize>("size");
        QTest::newRow("bottom-panel") << false << QSize(44, 42);
        QTest::newRow("thin-panel") << false << QSize(44, 32);
        QTest::newRow("vertical-panel") << true << QSize(44, 42);
    }

    void visiblePanelControl()
    {
        QFETCH(bool, vertical);
        QFETCH(QSize, size);
        m_panel->setFormFactor(vertical ? Plasma::Types::Vertical : Plasma::Types::Horizontal);
        m_face->setSize(size);
        QTest::qWait(80);
        auto *button = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-button"));
        QVERIFY2(button, "Plasma must instantiate the actual panel button, not just its Component.");
        QVERIFY(button->isVisible());
        QCOMPARE(m_face->implicitWidth(), 44.0);
        QCOMPARE(m_face->implicitHeight(), 42.0);
        QCOMPARE(button->size(), QSizeF(size));
        auto *dot = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-dimple"));
        QVERIFY(dot);
        QVERIFY(dot->isVisible());
        QCOMPARE(dot->size(), QSizeF(20, 20));
        const QPointF localCenter(dot->width() / 2, dot->height() / 2);
        const QPointF dotCenter = dot->mapToItem(button, localCenter);
        QCOMPARE(dotCenter, QPointF(size.width() / 2.0, size.height() / 2.0));

        const QImage image = m_window->grabWindow();
        QVERIFY(!image.isNull());
        const QPoint center = (dot->mapToScene(localCenter) * image.devicePixelRatio()).toPoint();
        const QColor pixel = image.pixelColor(center);
        QVERIFY2(pixel.red() > 230 && pixel.green() > 230 && pixel.blue() > 230,
                 "The rendered control must contain a visible white dimple.");
    }

    // The pearl unless a host asks for the magnifier, which takes the dot's
    // size and place and leaves its button, ring and press as they are.
    void pearlLookFollowsSettings()
    {
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_face->setSize(QSizeF(44, 42));
        QTest::qWait(20);
        auto *button = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-button"));
        auto *dot = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-dimple"));
        auto *mark = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-magnifier"));
        auto *ring = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-active-ring"));
        QVERIFY(button);
        QVERIFY(dot);
        QVERIFY(mark);
        QVERIFY(ring);
        QVERIFY(dot->isVisible());
        QVERIFY(!mark->isVisible());

        configure(QStringLiteral("pearlLook"), QStringLiteral("magnifier"));
        QTRY_VERIFY(mark->isVisible());
        QVERIFY(!dot->isVisible());
        QCOMPARE(mark->size(), dot->size());
        QCOMPARE(mark->mapToItem(button, QPointF(mark->width() / 2, mark->height() / 2)),
                 dot->mapToItem(button, QPointF(dot->width() / 2, dot->height() / 2)));
        // A ring and a handle, and no tile or backing behind them.
        QCOMPARE(mark->childItems().size(), 2);
        QVERIFY(ring->parentItem() == button);
        // The press is the dot's, whichever mark it shows.
        const int before = launches().size();
        const QPoint center = mark->mapToScene(QPointF(mark->width() / 2, mark->height() / 2)).toPoint();
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTRY_COMPARE(launches().size(), before + 1);

        configure(QStringLiteral("pearlLook"), QStringLiteral("pearl"));
        QTRY_VERIFY(dot->isVisible());
        QVERIFY(!mark->isVisible());
    }

    void mouseAndTouchLaunch()
    {
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_face->setSize(QSizeF(44, 42));
        const int before = launches().size();
        const QPoint center = m_face->mapToScene(QPointF(21, 21)).toPoint();
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTRY_COMPARE(launches().size(), before + 1);
        QCOMPARE(launches().constLast(), QString());

        // The usable target includes the panel slot outside the small glyph.
        const QPoint edge = m_face->mapToScene(QPointF(2, 2)).toPoint();
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, edge);
        QTRY_COMPARE(launches().size(), before + 2);

        auto *touchDevice = QTest::createTouchDevice();
        QTest::touchEvent(m_window, touchDevice).press(0, center, m_window);
        QTest::touchEvent(m_window, touchDevice).release(0, center, m_window);
        QTRY_COMPARE(launches().size(), before + 3);
    }

    void pearlSlide()
    {
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_window->resize(520, 100);
        m_face->setSize(QSizeF(400, 42));
        QTest::qWait(50);
        // Apps and Files come first; Notes follows where this computer has
        // it, so only their order is checked.
        const QStringList doors = m_applet->property("pearlDoors").toStringList();
        QCOMPARE(doors.mid(0, 2), (QStringList{QStringLiteral("apps"), QStringLiteral("files")}));
        const QStringList known{QStringLiteral("apps"), QStringLiteral("files"),
                                QStringLiteral("notes")};
        int last = -1;
        for (const QString &door : doors) {
            QVERIFY2(known.indexOf(door) > last, qPrintable(doors.join(QLatin1Char(','))));
            last = known.indexOf(door);
        }
        const int before = launches().size();
        const QPoint center = m_face->mapToScene(QPointF(21, 21)).toPoint();
        // The doors are the row's items rather than its QObject children.
        auto *row = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-pearl-doors"));
        QVERIFY(row);
        const auto door = [row](const QString &name) -> QQuickItem * {
            const auto items = row->childItems();
            for (QQuickItem *item : items) {
                if (item->objectName() == QStringLiteral("tettegouche-pearl-door-") + name) return item;
            }
            return nullptr;
        };
        auto *apps = door(QStringLiteral("apps"));
        auto *files = door(QStringLiteral("files"));
        QVERIFY(apps && files);
        const auto middle = [](QQuickItem *item) {
            return item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
        };

        // Press and slide right: the doors come at once, the one under the
        // pointer is chosen, and letting go opens it.
        QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTest::mouseMove(m_window, center + QPoint(2, 0));
        QVERIFY(!m_face->property("scrubbing").toBool());
        QTest::mouseMove(m_window, center + QPoint(30, 0));
        QVERIFY(m_face->property("scrubbing").toBool());
        QTest::mouseMove(m_window, middle(files));
        QCOMPARE(m_face->property("scrubChoice").toString(), QStringLiteral("files"));
        QTest::mouseMove(m_window, middle(apps));
        QCOMPARE(m_face->property("scrubChoice").toString(), QStringLiteral("apps"));
        QTest::mouseMove(m_window, middle(files));
        QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, middle(files));
        QTRY_COMPARE(launches().size(), before + 1);
        QCOMPARE(launches().constLast(), QStringLiteral("--drawer files"));
        QVERIFY(!m_face->property("scrubbing").toBool());

        // Held still, the doors come too; let go back on the dot, nothing opens.
        QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTRY_VERIFY_WITH_TIMEOUT(m_face->property("scrubbing").toBool(), 1000);
        QTest::mouseMove(m_window, middle(apps));
        QTest::mouseMove(m_window, center);
        QCOMPARE(m_face->property("scrubChoice").toString(), QString());
        QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTest::qWait(50);
        QCOMPARE(launches().size(), before + 1);
        QVERIFY(!m_face->property("scrubbing").toBool());

        // A finger does the same.
        auto *touchDevice = QTest::createTouchDevice();
        QTest::touchEvent(m_window, touchDevice).press(0, center, m_window);
        QTest::touchEvent(m_window, touchDevice).move(0, center + QPoint(30, 0), m_window);
        QTest::touchEvent(m_window, touchDevice).move(0, middle(apps), m_window);
        QTest::touchEvent(m_window, touchDevice).release(0, middle(apps), m_window);
        QTRY_COMPARE(launches().size(), before + 2);
        QCOMPARE(launches().constLast(), QStringLiteral("--drawer apps"));

        // Down a side of the screen the dot keeps its tap alone.
        m_panel->setFormFactor(Plasma::Types::Vertical);
        m_face->setSize(QSizeF(44, 42));
        QTest::qWait(20);
        QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTest::mouseMove(m_window, center + QPoint(30, 0));
        QTest::qWait(400);
        QVERIFY(!m_face->property("scrubbing").toBool());
        QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, center + QPoint(30, 0));
        QTest::qWait(50);
        QCOMPARE(launches().size(), before + 2);

        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_window->resize(120, 100);
        m_face->setSize(QSizeF(44, 42));
        QTest::qWait(20);
    }

    void launcherPrecedesAmbientStrip()
    {
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_face->setSize(QSizeF(300, 42));
        QTest::qWait(20);
        auto *button = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-button"));
        auto *ambient = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-ambient-surface"));
        QVERIFY(button);
        QVERIFY(ambient);
        QCOMPARE(button->x(), 0.0);
        QCOMPARE(button->width(), 44.0);
        QCOMPARE(ambient->x(), 44.0);
        QCOMPARE(ambient->width(), 256.0);
        m_face->setSize(QSizeF(44, 42));
    }

    // A host's spacing reaches the islands as it is written, held to 4 to
    // 32 px; unset, the outlined islands keep 8.
    void islandSpacingFollowsSettings()
    {
        auto *ambient = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-ambient-surface"));
        QVERIFY(ambient);
        QCOMPARE(ambient->property("gap").toReal(), 8.0);
        configure(QStringLiteral("islandSpacing"), 12);
        QTRY_COMPARE(ambient->property("gap").toReal(), 12.0);
        configure(QStringLiteral("islandSpacing"), 2);
        QTRY_COMPARE(ambient->property("gap").toReal(), 4.0);
        configure(QStringLiteral("islandSpacing"), 40);
        QTRY_COMPARE(ambient->property("gap").toReal(), 32.0);
        configure(QStringLiteral("islandSpacing"), 0);
        QTRY_COMPARE(ambient->property("gap").toReal(), 8.0);
    }

    void configuredActivation()
    {
        configure(QStringLiteral("useKadunce"), false);
        const int before = launches().size();
        // The same signal Plasma emits for a configured global shortcut.
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 1);
        QCOMPARE(launches().constLast(), QStringLiteral("--standalone --type"));
        configure(QStringLiteral("useKadunce"), true);
        // With recent use off, Search is told so as it starts.
        configure(QStringLiteral("offerRecent"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 2);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-recent --type"));
        configure(QStringLiteral("offerRecent"), true);
        // With Notes off, Search is told so as it starts.
        configure(QStringLiteral("offerNotes"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 3);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-notes --type"));
        configure(QStringLiteral("offerNotes"), true);
        // With only the Notes pill off, Search is told so as it starts.
        configure(QStringLiteral("showNotesPill"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 4);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-notes-pill --type"));
        configure(QStringLiteral("showNotesPill"), true);
        // Recent apps off alone, then recent files off alone.
        configure(QStringLiteral("recentApps"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 5);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-recent-apps --type"));
        configure(QStringLiteral("recentApps"), true);
        configure(QStringLiteral("recentFiles"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 6);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-recent-files --type"));
        // Both off is recent use off.
        configure(QStringLiteral("recentApps"), false);
        m_applet->activated();
        QTRY_COMPARE(launches().size(), before + 7);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-recent --type"));
        configure(QStringLiteral("recentApps"), true);
        configure(QStringLiteral("recentFiles"), true);
    }

    // A running launcher is known by its name on the bus, whoever started
    // it, and asked rather than started again; once it says it is shown, the
    // widget is open. It is asked first whether it leaves for the widget's
    // settings, and one that stays is asked for the toggle.
    void repeatedActivationToggles()
    {
        ToggleEndpoint endpoint;
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerObject(QStringLiteral("/Launcher"), &endpoint,
            QDBusConnection::ExportScriptableSlots));
        QVERIFY(bus.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QTest::qWait(100);
        const int before = launches().size();
        QDBusMessage shown = QDBusMessage::createSignal(QStringLiteral("/Launcher"),
            QStringLiteral("io.github.carlsonjm.Tettegouche"), QStringLiteral("shown"));
        shown << true;
        QVERIFY(bus.send(shown));
        QTRY_COMPARE(m_applet->status(), Plasma::Types::AcceptingInputStatus);
        // Search's key asks for it ready to type.
        m_applet->activated();
        QTRY_COMPARE(endpoint.typedCalls, 1);
        QCOMPARE(endpoint.calls, 0);
        QCOMPARE(endpoint.leaves, QStringList{QString()});
        QCOMPARE(launches().size(), before); // No duplicate launch.
        bus.unregisterObject(QStringLiteral("/Launcher"));
        bus.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
        QTRY_COMPARE_WITH_TIMEOUT(m_applet->status(), Plasma::Types::ActiveStatus, 10000);
    }

    // A launcher kept ready with other settings leaves when asked, and the
    // request goes to the one started in its place.
    void changedSettingsStartAgain()
    {
        ToggleEndpoint endpoint;
        endpoint.leaving = true;
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerObject(QStringLiteral("/Launcher"), &endpoint,
            QDBusConnection::ExportScriptableSlots));
        QVERIFY(bus.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QTest::qWait(100);
        const int before = launches().size();
        configure(QStringLiteral("offerRecent"), false);
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("apps"))));
        QTRY_COMPARE(endpoint.leaves, QStringList{QStringLiteral("--no-recent")});
        QTest::qWait(100);
        QCOMPARE(launches().size(), before);
        // It goes.
        bus.unregisterObject(QStringLiteral("/Launcher"));
        bus.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
        QTRY_COMPARE(launches().size(), before + 1);
        QCOMPARE(launches().constLast(), QStringLiteral("--no-recent --drawer apps"));
        QCOMPARE(endpoint.drawers, QStringList());
        configure(QStringLiteral("offerRecent"), true);
    }

    void drawerKeys()
    {
        // Meta+G and Meta+E start the launcher on their drawer.
        const int before = launches().size();
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("files"))));
        QTRY_COMPARE(launches().size(), before + 1);
        QCOMPARE(launches().constLast(), QStringLiteral("--drawer files"));
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("elsewhere"))));
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("note:"))));
        QTest::qWait(50);
        QCOMPARE(launches().size(), before + 1);
        // The quick note's island: the quick note, or the note pinned there.
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("note"))));
        QTRY_COMPARE(launches().size(), before + 2);
        QCOMPARE(launches().constLast(), QStringLiteral("--drawer note"));
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("note:n1"))));
        QTRY_COMPARE(launches().size(), before + 3);
        QCOMPARE(launches().constLast(), QStringLiteral("--drawer note:n1"));

        // A running launcher is asked for the drawer instead.
        ToggleEndpoint endpoint;
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerObject(QStringLiteral("/Launcher"), &endpoint,
            QDBusConnection::ExportScriptableSlots));
        QVERIFY(bus.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QTest::qWait(100);
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("apps"))));
        QTRY_COMPARE(endpoint.drawers, QStringList{QStringLiteral("apps")});
        QVERIFY(QMetaObject::invokeMethod(m_applet, "openDrawer", Q_ARG(QString, QStringLiteral("note:n1"))));
        QTRY_COMPARE(endpoint.drawers, (QStringList{QStringLiteral("apps"), QStringLiteral("note:n1")}));
        QCOMPARE(endpoint.calls, 0);
        QCOMPARE(launches().size(), before + 3);
        bus.unregisterObject(QStringLiteral("/Launcher"));
        bus.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
        QTest::qWait(100);
    }

    // Where Shuffle Settings is installed, Configure opens it at Search's
    // page instead of the widget's own: Plasma still connects Configure as
    // the widget expects.
    void configureOpensSuiteSettings()
    {
        const QString record = m_fixture.filePath(QStringLiteral("settings-opened"));
        const QString program = m_fixture.filePath(QStringLiteral("shuffle-settings"));
        QVERIFY(writeScript(program, record));
        const QString applications = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications");
        QVERIFY(QDir().mkpath(applications));
        // KDE's application list notices a change only past the coarsest
        // file system clock, and is read again until it has it.
        const auto installed = [] {
            KSycoca::self()->ensureCacheValid();
            return bool(KService::serviceByDesktopName(QStringLiteral("co.goodinput.Shuffle.Settings")));
        };
        QTest::qSleep(1100);
        QFile entry(applications + QStringLiteral("/co.goodinput.Shuffle.Settings.desktop"));
        QVERIFY(entry.open(QIODevice::WriteOnly));
        entry.write("[Desktop Entry]\nType=Application\nName=Shuffle Settings\nExec=" + program.toUtf8() + " %u\n");
        entry.close();
        QTRY_VERIFY_WITH_TIMEOUT(installed(), 15000);

        QSignalSpy ownPage(m_panel, &Plasma::Containment::configureRequested);
        QAction *configure = m_applet->internalAction(QStringLiteral("configure"));
        QVERIFY(configure);
        configure->trigger();
        // The script makes the record before it writes the page into it.
        const auto said = [&record] {
            QFile opened(record);
            return opened.open(QIODevice::ReadOnly) ? QString::fromUtf8(opened.readAll()).trimmed() : QString();
        };
        QTRY_COMPARE(said(), QStringLiteral("search"));
        QCOMPARE(ownPage.count(), 0);

        // Without it, Configure opens the widget's own page.
        QTest::qSleep(1100);
        QVERIFY(QFile::remove(entry.fileName()));
        QTRY_VERIFY_WITH_TIMEOUT(!installed(), 15000);
        configure->trigger();
        QTRY_COMPARE(ownPage.count(), 1);
    }

    void launcherKeysAnswerOnce()
    {
        // Two widgets in one Plasma share one pair of keys; one launcher answers.
        auto keys = LauncherKeys::acquire();
        QCOMPARE(LauncherKeys::acquire(), keys);
        QVERIFY(keys->action(QStringLiteral("apps")));
        QVERIFY(keys->action(QStringLiteral("files")));
        QCOMPARE(keys->action(QStringLiteral("files"))->property("componentName").toString(),
                 QStringLiteral("tettegouche"));
        QStringList first, second;
        auto *earlier = new QObject;
        QObject later;
        keys->attach(earlier, [&first](const QString &drawer) { first << drawer; });
        keys->attach(&later, [&second](const QString &drawer) { second << drawer; });
        keys->action(QStringLiteral("files"))->trigger();
        QCOMPARE(first, QStringList{QStringLiteral("files")});
        QVERIFY(second.isEmpty());
        delete earlier;
        keys->action(QStringLiteral("apps"))->trigger();
        QCOMPARE(first, QStringList{QStringLiteral("files")});
        QCOMPARE(second, QStringList{QStringLiteral("apps")});
        keys->detach(&later);
        keys->action(QStringLiteral("apps"))->trigger();
        QCOMPARE(second, QStringList{QStringLiteral("apps")});
    }

    void nearestRightTaskBoundaryWidth()
    {
        auto *spacerApplet = m_panel->createApplet(QStringLiteral("org.kde.plasma.panelspacer"));
        auto *taskApplet = m_panel->createApplet(QStringLiteral("co.goodinput.tettegouche"));
        QVERIFY(spacerApplet);
        QVERIFY(taskApplet);
        auto *spacer = PlasmaQuick::AppletQuickItem::itemForApplet(spacerApplet);
        auto *task = PlasmaQuick::AppletQuickItem::itemForApplet(taskApplet);
        QVERIFY(spacer);
        QVERIFY(task);
        spacer->setParentItem(m_window->contentItem());
        task->setParentItem(m_window->contentItem());
        spacer->setPosition(QPointF(100, 20));
        spacer->setSize(QSizeF(560, 42));
        task->setPosition(QPointF(700, 20));
        task->setSize(QSizeF(300, 42));
        m_face->setPosition(QPointF(16, 20));
        m_face->setSize(QSizeF(82, 42));
        QTest::qWait(20);

        int available = 0;
        QVERIFY(QMetaObject::invokeMethod(m_applet, "availablePanelWidth",
            Q_RETURN_ARG(int, available), Q_ARG(QQuickItem *, m_face),
            Q_ARG(int, 42), Q_ARG(int, 6)));
        QCOMPARE(available, 678); // task left 700 - fixed left 16 - gap 6

        QVERIFY(QMetaObject::invokeMethod(m_applet, "watchPanelGeometry",
            Q_ARG(QQuickItem *, m_face)));
        QSignalSpy geometryChanged(m_applet, SIGNAL(panelGeometryChanged()));
        const qreal taskCenter = task->x() + task->width() / 2.0;
        task->setPosition(QPointF(646, 20));
        task->setSize(QSizeF(408, 42));
        QTRY_VERIFY(geometryChanged.count() > 0);
        QVERIFY(QMetaObject::invokeMethod(m_applet, "availablePanelWidth",
            Q_RETURN_ARG(int, available), Q_ARG(QQuickItem *, m_face),
            Q_ARG(int, 42), Q_ARG(int, 6)));
        QCOMPARE(available, 624);
        QCOMPARE(task->x() + task->width() / 2.0, taskCenter);

        task->setVisible(false);
        QVERIFY(QMetaObject::invokeMethod(m_applet, "availablePanelWidth",
            Q_RETURN_ARG(int, available), Q_ARG(QQuickItem *, m_face),
            Q_ARG(int, 42), Q_ARG(int, 6)));
        QCOMPARE(available, 42); // The visible spacer is deliberately excluded.
        spacer->setParentItem(nullptr);
        task->setParentItem(nullptr);
        delete spacerApplet;
        delete taskApplet;
        m_face->setPosition(QPointF(30, 20));
        m_face->setSize(QSizeF(44, 42));
    }

    void normalAndFixtureSources()
    {
        const auto rows=m_applet->property("ambientActivities").toList();
        if (qgetenv("TETTE_AMBIENT_FIXTURE")=="transfer-media") QCOMPARE(rows.size(),2);
        else QVERIFY(rows.isEmpty());
    }

    // The island opens as a tap does, through the widget, on the panel's own
    // display, and closes cleanly; the widget's scripts complain about nothing.
    void islandOpensFromThePanel()
    {
        if (qgetenv("TETTE_AMBIENT_FIXTURE") != "transfer-media") {
            QSKIP("needs the sample activities");
        }
        static QStringList complaints;
        complaints.clear();
        const auto previous = qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &message) {
            if (message.contains(QLatin1String("tettegouche"))) complaints << message;
        });
        m_face->setSize(QSizeF(500, 64));
        QTest::qWait(50);
        QVERIFY(QMetaObject::invokeMethod(m_face, "openIsland", Q_ARG(QVariant, QVariant(QStringLiteral("media")))));
        auto *island = qobject_cast<QQuickWindow *>(m_face->property("island").value<QObject *>());
        QVERIFY(island);
        QTRY_VERIFY(island->isVisible());
        QTRY_VERIFY(island->property("expanded").toBool());
        QCOMPARE(island->screen(), m_window->screen());
        QCOMPARE(island->property("kind").toString(), QStringLiteral("media"));
        // Asked again, it moves to the other activity rather than opening twice.
        QVERIFY(QMetaObject::invokeMethod(m_face, "openIsland", Q_ARG(QVariant, QVariant(QStringLiteral("transfer")))));
        QCOMPARE(m_face->property("island").value<QObject *>(), island);
        QCOMPARE(island->property("kind").toString(), QStringLiteral("transfer"));
        QPointer<QQuickWindow> watched(island);
        QVERIFY(QMetaObject::invokeMethod(island, "dismiss"));
        QTRY_VERIFY(!m_face->property("island").value<QObject *>());
        QTRY_VERIFY(watched.isNull());
        qInstallMessageHandler(previous);
        QVERIFY2(complaints.isEmpty(), qPrintable(complaints.join(QLatin1Char('\n'))));
        m_face->setSize(QSizeF(44, 42));
    }

    void packagedSuiteIconsRender()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine,
            QUrl(QStringLiteral("qrc:/qt/qml/plasma/applet/co/goodinput/tettegouche/SuiteIcon.qml")),
            QQmlComponent::PreferSynchronous);
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        const QStringList glyphs{
            QStringLiteral("skip-back"), QStringLiteral("play"), QStringLiteral("pause"),
            QStringLiteral("skip-forward"), QStringLiteral("download"), QStringLiteral("x"),
            QStringLiteral("folder-open"), QStringLiteral("notes")
        };
        // Stand-ins for a dark and a light Plasma style. The software renderer
        // the test runs on draws no layer effects, so the light glyph's
        // recolour is checked by its settings and the drawing by the dark one.
        const auto makeTheme = [&](const QString &ground, const QString &text) {
            QQmlComponent themeComponent(&engine);
            themeComponent.setData(QStringLiteral("import QtQuick\nQtObject { property color backgroundColor: \"%1\"; "
                "property color textColor: \"%2\" }").arg(ground, text).toUtf8(), QUrl());
            return std::unique_ptr<QObject>(themeComponent.create());
        };
        const auto darkTheme = makeTheme(QStringLiteral("#141414"), QStringLiteral("#E0E0E0"));
        const auto lightTheme = makeTheme(QStringLiteral("#F2F2F2"), QStringLiteral("#102729"));
        QVERIFY(darkTheme && lightTheme);
        for (const QString &glyph : glyphs) {
            QScopedPointer<QObject> icon(component.createWithInitialProperties(
                {{QStringLiteral("glyph"), glyph}}));
            auto *item = qobject_cast<QQuickItem *>(icon.data());
            QVERIFY2(item, qPrintable(glyph));
            item->setSize(QSizeF(20, 20));
            item->setParentItem(m_window->contentItem());
            item->setPosition(QPointF(0, 0));
            QVERIFY2(item->isVisible() && item->width() >= 20 && item->height() >= 20,
                qPrintable(QStringLiteral("Zero-size or invisible SuiteIcon: ") + glyph));
            auto *imageItem = item->findChild<QQuickItem *>(QStringLiteral("suiteIconImage"));
            auto *tone = item->findChild<QObject *>(QStringLiteral("ambientColors"), Qt::FindDirectChildrenOnly);
            QVERIFY2(imageItem && tone, qPrintable(glyph));
            tone->setProperty("theme", QVariant::fromValue(lightTheme.get()));
            auto *layer = imageItem->property("layer").value<QObject *>();
            QVERIFY2(layer && layer->property("enabled").toBool()
                && item->property("ink").value<QColor>() == QColor(QStringLiteral("#102729")),
                qPrintable(QStringLiteral("Not recoloured to a light style's text: ") + glyph));
            tone->setProperty("theme", QVariant::fromValue(darkTheme.get()));
            QVERIFY2(!layer->property("enabled").toBool(),
                qPrintable(QStringLiteral("Recoloured on a dark style: ") + glyph));
            QTRY_COMPARE_WITH_TIMEOUT(imageItem->property("status").toInt(), 1, 3000);
            QVERIFY(imageItem->isVisible());
            const auto grab = item->grabToImage(QSize(40, 40));
            QSignalSpy ready(grab.data(), &QQuickItemGrabResult::ready);
            QVERIFY2(ready.wait(3000), qPrintable(glyph));
            const QImage rendered = grab->image();
            bool hasVisibleInk = false;
            for (int y = 0; y < rendered.height() && !hasVisibleInk; ++y) {
                for (int x = 0; x < rendered.width(); ++x) {
                    const QColor pixel = rendered.pixelColor(x, y);
                    if (pixel.alpha() > 32 && pixel.red() > 180
                        && pixel.green() > 180 && pixel.blue() > 180) {
                        hasVisibleInk = true;
                        break;
                    }
                }
            }
            QVERIFY2(hasVisibleInk,
                qPrintable(QStringLiteral("No visible Ghost White ink for ") + glyph));
            item->setParentItem(nullptr);
        }
    }

    void stockSpacerCentering_data()
    {
        QTest::addColumn<qreal>("panelWidth");
        QTest::addColumn<int>("taskCount");
        QTest::addColumn<bool>("clockPresent");
        QTest::addColumn<qreal>("scale");
        QTest::newRow("tablet-one-task") << 960.0 << 1 << true << 1.0;
        QTest::newRow("tablet-six-tasks-125") << 960.0 << 6 << true << 1.25;
        QTest::newRow("monitor-three-tasks-150") << 1463.0 << 3 << true << 1.5;
        QTest::newRow("monitor-eight-tasks-200") << 1920.0 << 8 << false << 2.0;
    }

    void stockSpacerCentering()
    {
        QFETCH(qreal, panelWidth);
        QFETCH(int, taskCount);
        QFETCH(bool, clockPresent);
        QFETCH(qreal, scale);
        const qreal taskWidth = taskCount * 54.0;
        const qreal leftSurface = 150.0;
        const qreal rightSurface = 172.0 + (clockPresent ? 84.0 : 0.0);
        const qreal leftSpacer = panelWidth / 2.0 - taskWidth / 2.0 - leftSurface;
        const qreal rightSpacer = panelWidth / 2.0 - taskWidth / 2.0 - rightSurface;
        QVERIFY2(leftSpacer >= 0 && rightSpacer >= 0,
                 "Representative layout must not saturate either expanding spacer.");

        const qreal taskLeftPhysical = std::round(
            (leftSurface + leftSpacer) * scale);
        const qreal taskWidthPhysical = std::round(taskWidth * scale);
        const qreal taskCenterPhysical = taskLeftPhysical + taskWidthPhysical / 2.0;
        const qreal panelCenterPhysical = panelWidth * scale / 2.0;
        QVERIFY(std::abs(taskCenterPhysical - panelCenterPhysical) <= 1.0);
    }

    void cleanupTestCase()
    {
        if (m_face) m_face->setParentItem(nullptr);
        delete m_window;
        delete m_corona;
    }

    void keyboardActivation()
    {
        auto *button = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-button"));
        QVERIFY(button);
        button->forceActiveFocus();
        const int before = launches().size();
        QTest::keyClick(m_window, Qt::Key_Return);
        QTRY_COMPARE(launches().size(), before + 1);
        QTest::keyClick(m_window, Qt::Key_Space);
        QTRY_COMPARE(launches().size(), before + 2);
    }

private:
    // As Plasma's settings page and scripting both do: through the
    // configuration main.xml declares.
    void configure(const QString &key, const QVariant &value)
    {
        auto *item = static_cast<KCoreConfigSkeleton *>(m_applet->configScheme())->findItem(key);
        QVERIFY(item);
        item->setProperty(value);
        m_applet->configScheme()->save();
    }

    // A stand-in program that writes its arguments, as one line, to a file.
    static bool writeScript(const QString &path, const QString &record)
    {
        QFile script(path);
        if (!script.open(QIODevice::WriteOnly)) return false;
        script.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> '" + record.toUtf8() + "'\n");
        script.close();
        return script.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }

    // Each start of the stand-in launcher, by its arguments.
    QStringList launches() const
    {
        QFile file(m_launches);
        if (!file.open(QIODevice::ReadOnly)) return {};
        QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
        if (!lines.isEmpty() && lines.constLast().isEmpty()) lines.removeLast();
        return lines;
    }

    QTemporaryDir m_fixture;
    QString m_executable;
    QString m_launches;
    TestCorona *m_corona = nullptr;
    Plasma::Containment *m_panel = nullptr;
    Plasma::Applet *m_applet = nullptr;
    PlasmaQuick::AppletQuickItem *m_face = nullptr;
    QQuickWindow *m_window = nullptr;
};

QTEST_MAIN(PanelAppletTest)
#include "PanelAppletTest.moc"
