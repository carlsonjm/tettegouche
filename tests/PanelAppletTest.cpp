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
        m_face->setSize(QSizeF(26, 42));
        m_window->show();
        QTest::qWait(100);
    }

    void visiblePanelControl_data()
    {
        QTest::addColumn<bool>("vertical");
        QTest::addColumn<QSize>("size");
        QTest::newRow("bottom-panel") << false << QSize(26, 42);
        QTest::newRow("thin-panel") << false << QSize(26, 32);
        QTest::newRow("vertical-panel") << true << QSize(42, 26);
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
        m_face->setSize(QSizeF(26, 42));
        QSignalSpy started(m_process, &QProcess::started);
        const QPoint center = m_face->mapToScene(QPointF(13, 21)).toPoint();
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
