#include "FileBrowser.h"
#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QQuickView>
#include <QElapsedTimer>
#include <QTimer>
#include <QSignalSpy>

class FileBrowserTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void mountMetadata() {
        const auto places = FileBrowser::localPlaces(QByteArrayLiteral(
            "1 0 8:1 / / rw - ext4 /dev/root rw\n"
            "2 1 8:2 / /run/media/user/External\\040Drive rw - ext4 /dev/test rw\n"
            "3 1 0:1 / /mnt/offline rw - fuse.remote remote rw\n"
            "3 1 0:1 / /mnt/offline rw - fuse.remote remote rw\n"));
        QCOMPARE(places.size(), 6); // four standard folders, two mount points
        QCOMPARE(places[4].toMap().value(QStringLiteral("path")).toString(), QStringLiteral("/run/media/user/External Drive"));
        QCOMPARE(places[5].toMap().value(QStringLiteral("path")).toString(), QStringLiteral("/mnt/offline"));
    }
    void browsing() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("TetteTests"));
        QCoreApplication::setApplicationName(QStringLiteral("Files"));
        QDir root(dir.path());
        QVERIFY(root.mkdir(QStringLiteral("one")));
        QVERIFY(root.mkdir(QStringLiteral("two")));
        const QString first=dir.path()+QStringLiteral("/one");
        const QString second=dir.path()+QStringLiteral("/two");
        for(const auto &name : {QStringLiteral("a.txt"),QStringLiteral("z.txt"),QStringLiteral(".hidden")}) {
            QFile f(first+QLatin1Char('/')+name); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("test");
        }
        FileBrowser browser;
        QVERIFY(browser.places().isEmpty()); // no drive enumeration on Meta
        QQuickView view;
        view.setInitialProperties({{QStringLiteral("browser"), QVariant::fromValue(&browser)}});
        view.setSource(QUrl::fromLocalFile(QStringLiteral(FILES_PANE_SOURCE)));
        QCOMPARE(view.status(), QQuickView::Ready);
        view.setResizeMode(QQuickView::SizeRootObjectToView);
        view.resize(1000, 650);
        view.show();
        QElapsedTimer heartbeat; heartbeat.start();
        qint64 longestGap = 0;
        QTimer pulse;
        connect(&pulse, &QTimer::timeout, this, [&] {
            longestGap = std::max(longestGap, heartbeat.restart());
        });
        pulse.start(10);
        QSignalSpy placesChanged(&browser, &FileBrowser::placesChanged);
        browser.open();
        QVERIFY(browser.places().size() >= 4);
        const auto initialPlaces = browser.places();
        const auto initialSignals = placesChanged.count();
        browser.navigate(first);
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        QVERIFY2(browser.error().isEmpty(),qPrintable(browser.error()));
        QCOMPARE(browser.entries().size(),2);
        browser.setSortMode(1);
        QCOMPARE(browser.entries()[0].toMap().value(QStringLiteral("name")).toString(),QStringLiteral("z.txt"));
        browser.setFilter(QStringLiteral("a.")); QCOMPARE(browser.entries().size(),1);
        browser.setFilter(QString()); browser.setScroll(70);
        browser.addTab(); browser.navigate(second);
        QTRY_VERIFY(!browser.busy()); QCOMPARE(browser.entries().size(),0);
        browser.selectTab(0); QCOMPARE(browser.path(),first); QCOMPARE(browser.scroll(),70.0);
        QTRY_VERIFY(!browser.busy()); QCOMPARE(browser.entries().size(),2);
        browser.navigate(second); browser.back(); browser.forward(); browser.back();
        QTRY_VERIFY(!browser.busy()); QCOMPARE(browser.path(),first); QCOMPARE(browser.entries().size(),2);
        browser.setHidden(true); QTRY_VERIFY(!browser.busy()); QCOMPARE(browser.entries().size(),3);
        browser.navigate(dir.path()+QStringLiteral("/missing"));
        QTRY_VERIFY(!browser.busy()); QVERIFY(!browser.error().isEmpty());
        browser.closeTab(1); QCOMPARE(browser.tabs().size(),1);
        browser.closeTab(0); QCOMPARE(browser.tabs().size(),1);
        QCOMPARE(browser.places(), initialPlaces);
        QCOMPARE(placesChanged.count(), initialSignals); // listings never rebuild Places
        QTest::qWait(100);
        QVERIFY2(longestGap < 500, qPrintable(QStringLiteral("UI heartbeat stalled for %1 ms").arg(longestGap)));
    }
};
QTEST_MAIN(FileBrowserTest)
#include "FileBrowserTest.moc"
