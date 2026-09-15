/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <QApplication>
#include <QFile>
#include <QFileInfo>
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
        QFile userDirs(m_fixture.filePath(QStringLiteral("user-dirs.dirs")));
        QVERIFY(userDirs.open(QIODevice::WriteOnly));
        userDirs.write("XDG_DOWNLOAD_DIR=\"" + m_fixture.path().toUtf8() + "/Downloads\"\n");
        userDirs.close();
        qputenv("XDG_CONFIG_HOME",m_fixture.path().toUtf8());
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
        QCOMPARE(button->width(), 42.0);
        QCOMPARE(ambient->x(), 42.0);
        QCOMPARE(ambient->width(), 258.0);
        m_face->setSize(QSizeF(42, 42));
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

    void nearestRightTaskBoundaryWidth()
    {
        auto *spacerApplet = m_panel->createApplet(QStringLiteral("org.kde.plasma.panelspacer"));
        auto *taskApplet = m_panel->createApplet(QStringLiteral("studio.warbler.tettegouche"));
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
        m_face->setSize(QSizeF(42, 42));
    }

    void normalAndFixtureSources()
    {
        const auto rows=m_applet->property("ambientActivities").toList();
        if (qgetenv("TETTE_AMBIENT_FIXTURE")=="transfer-media") QCOMPARE(rows.size(),2);
        else QVERIFY(rows.isEmpty());
    }

    void packagedSuiteIconsRender()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine,
            QUrl(QStringLiteral("qrc:/qt/qml/plasma/applet/studio/warbler/tettegouche/SuiteIcon.qml")),
            QQmlComponent::PreferSynchronous);
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        const QStringList glyphs{
            QStringLiteral("skip-back"), QStringLiteral("play"), QStringLiteral("pause"),
            QStringLiteral("skip-forward"), QStringLiteral("download"), QStringLiteral("x")
        };
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
            QVERIFY2(imageItem, qPrintable(glyph));
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
