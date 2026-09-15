/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <QApplication>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QDBusConnection>
#include <cmath>

class ToggleEndpoint : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche")
public:
    int calls = 0;
public Q_SLOTS:
    Q_SCRIPTABLE void toggle() { ++calls; }
};

#include <KConfigGroup>
#include <KPackage/Package>
#include <KPackage/PackageLoader>
#include <Plasma/Applet>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>

class TestCorona : public Plasma::Corona
{
public:
    QRect screenGeometry(int) const override { return QRect(0, 0, 1280, 800); }
};

class PanelAppletTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // A click must start a harmless stand-in, never the real launcher.
        QVERIFY(m_fixture.isValid());
        m_executable = m_fixture.filePath(QStringLiteral("tettegouche"));
        const QString trueExecutable = QStandardPaths::findExecutable(QStringLiteral("true"));
        QVERIFY(!trueExecutable.isEmpty());
        QVERIFY(QFile::link(trueExecutable, m_executable));
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
        m_applet = m_panel->createApplet(QStringLiteral("studio.warbler.tettegouche"));
        QVERIFY(m_applet);
        QVERIFY(!m_applet->failedToLaunch());
        QCOMPARE(m_applet->pluginMetaData().iconName(), QStringLiteral("studio.warbler.tettegouche-logo"));
        const QString expectedPlugin = QString::fromLocal8Bit(qgetenv("TETTE_TEST_PLUGIN_ROOT"))
            + QStringLiteral("/plasma/applets/studio.warbler.tettegouche.so");
        QCOMPARE(QFileInfo(m_applet->pluginMetaData().fileName()).canonicalFilePath(),
                 QFileInfo(expectedPlugin).canonicalFilePath());

        m_face = PlasmaQuick::AppletQuickItem::itemForApplet(m_applet);
        QVERIFY(m_face);
        m_process = m_applet->findChild<QProcess *>();
        QVERIFY(m_process);
        m_window = new QQuickWindow;
        m_window->setColor(QColor(QStringLiteral("#141414")));
        m_window->resize(120, 100);
        m_face->setParentItem(m_window->contentItem());
        m_face->setPosition(QPointF(30, 20));
        m_face->setSize(QSizeF(42, 42));
        m_window->show();
        QTest::qWait(100);
    }

    void visiblePanelControl_data()
    {
        QTest::addColumn<bool>("vertical");
        QTest::addColumn<QSize>("size");
        QTest::newRow("bottom-panel") << false << QSize(42, 42);
        QTest::newRow("thin-panel") << false << QSize(42, 32);
        QTest::newRow("vertical-panel") << true << QSize(42, 42);
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
        QCOMPARE(m_face->implicitWidth(), 42.0);
        QCOMPARE(m_face->implicitHeight(), 42.0);
        QCOMPARE(button->size(), QSizeF(size));
        auto *dot = m_face->findChild<QQuickItem *>(QStringLiteral("tettegouche-launcher-dimple"));
        QVERIFY(dot);
        QVERIFY(dot->isVisible());
        QCOMPARE(dot->size(), QSizeF(16, 16));
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

    void mouseAndTouchLaunch()
    {
        m_panel->setFormFactor(Plasma::Types::Horizontal);
        m_face->setSize(QSizeF(42, 42));
        QSignalSpy started(m_process, &QProcess::started);
        const QPoint center = m_face->mapToScene(QPointF(21, 21)).toPoint();
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, center);
        QTRY_COMPARE(started.count(), 1);
        QCOMPARE(m_process->program(), m_executable);
        QCOMPARE(m_process->arguments(), QStringList());
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);

        // The usable target includes the panel slot outside the small glyph.
        const QPoint edge = m_face->mapToScene(QPointF(2, 2)).toPoint();
        QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, edge);
        QTRY_COMPARE(started.count(), 2);
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);

        auto *touchDevice = QTest::createTouchDevice();
        QTest::touchEvent(m_window, touchDevice).press(0, center, m_window);
        QTest::touchEvent(m_window, touchDevice).release(0, center, m_window);
        QTRY_COMPARE(started.count(), 3);
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);
    }

    void configuredActivation()
    {
        m_applet->config().writeEntry(QStringLiteral("useKadunce"), false);
        QSignalSpy started(m_process, &QProcess::started);
        // The same signal Plasma emits for a configured global shortcut.
        m_applet->activated();
        QTRY_COMPARE(started.count(), 1);
        QCOMPARE(m_process->arguments(), QStringList{QStringLiteral("--standalone")});
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);
        m_applet->config().writeEntry(QStringLiteral("useKadunce"), true);
    }

    void repeatedActivationToggles()
    {
        ToggleEndpoint endpoint;
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QVERIFY(bus.registerObject(QStringLiteral("/Launcher"), &endpoint,
            QDBusConnection::ExportScriptableSlots));
        // A harmless child represents the running launcher in this private bus.
        m_process->start(QStringLiteral("sleep"), {QStringLiteral("30")});
        QTRY_COMPARE(m_process->state(), QProcess::Running);
        QTRY_COMPARE(m_applet->status(), Plasma::Types::AcceptingInputStatus);
        m_applet->activated();
        QTRY_COMPARE(endpoint.calls, 1);
        QCOMPARE(m_process->state(), QProcess::Running); // No kill/duplicate launch.
        m_process->terminate();
        QVERIFY(m_process->waitForFinished());
        QTRY_COMPARE(m_applet->status(), Plasma::Types::ActiveStatus);
        bus.unregisterObject(QStringLiteral("/Launcher"));
        bus.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
    }

    void nearestLeftNeighborWidth()
    {
        auto *neighborApplet = m_panel->createApplet(QStringLiteral("studio.warbler.tettegouche"));
        QVERIFY(neighborApplet);
        auto *neighbor = PlasmaQuick::AppletQuickItem::itemForApplet(neighborApplet);
        QVERIFY(neighbor);
        neighbor->setParentItem(m_window->contentItem());
        neighbor->setPosition(QPointF(40, 20));
        neighbor->setSize(QSizeF(100, 42));
        m_face->setPosition(QPointF(200, 20));
        m_face->setSize(QSizeF(172, 42));
        QTest::qWait(20);

        int available = 0;
        QVERIFY(QMetaObject::invokeMethod(m_applet, "availablePanelWidth",
            Q_RETURN_ARG(int, available), Q_ARG(QQuickItem *, m_face),
            Q_ARG(int, 42), Q_ARG(int, 6)));
        QCOMPARE(available, 226); // own right 372 - neighbor right 140 - gap 6

        neighbor->setVisible(false);
        QVERIFY(QMetaObject::invokeMethod(m_applet, "availablePanelWidth",
            Q_RETURN_ARG(int, available), Q_ARG(QQuickItem *, m_face),
            Q_ARG(int, 42), Q_ARG(int, 6)));
        QCOMPARE(available, 42);
        neighbor->setParentItem(nullptr);
        delete neighborApplet;
        m_face->setPosition(QPointF(30, 20));
        m_face->setSize(QSizeF(42, 42));
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
        QSignalSpy started(m_process, &QProcess::started);
        QTest::keyClick(m_window, Qt::Key_Return);
        QTRY_COMPARE(started.count(), 1);
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);
        QTest::keyClick(m_window, Qt::Key_Space);
        QTRY_COMPARE(started.count(), 2);
        QTRY_COMPARE(m_process->state(), QProcess::NotRunning);
    }

private:
    QTemporaryDir m_fixture;
    QString m_executable;
    TestCorona *m_corona = nullptr;
    Plasma::Containment *m_panel = nullptr;
    Plasma::Applet *m_applet = nullptr;
    PlasmaQuick::AppletQuickItem *m_face = nullptr;
    QProcess *m_process = nullptr;
    QQuickWindow *m_window = nullptr;
};

QTEST_MAIN(PanelAppletTest)
#include "PanelAppletTest.moc"
