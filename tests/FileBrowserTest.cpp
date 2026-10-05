#include "FileBrowser.h"
#include "FileDetails.h"
#include "FileThumbnails.h"
#include <KApplicationTrader>
#include <KIO/DesktopExecParser>
#include <KService>
#include <KLocalizedString>
#include <QQmlComponent>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QImage>
#include <QStandardPaths>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTest>
#include <QTemporaryDir>
#include <QScopeGuard>
#include <QFile>
#include <QQuickView>
#include <QElapsedTimer>
#include <QTimer>
#include <QSignalSpy>

// kio-fuse and KDE Connect as Files meets them on the bus, serving folders of
// the test's own.
class FakeFuse : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KIOFuse.VFS")
public:
    QString folder;
    QStringList asked;
public Q_SLOTS:
    QString mountUrl(const QString &url) { asked.append(url); return folder; }
};
class FakeConnectDaemon : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.daemon")
public:
    QStringList reachable;
public Q_SLOTS:
    QStringList devices(bool, bool) { return reachable; }
Q_SIGNALS:
    void deviceVisibilityChanged(const QString &id, bool isVisible);
};
class FakeConnectDevice : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.device")
    Q_PROPERTY(QString name READ name)
public:
    QString name() const { return QStringLiteral("Pixel"); }
};
class FakeConnectFiles : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kdeconnect.device.sftp")
public:
    QString folder, error;
    bool up = false;
public Q_SLOTS:
    QString mountPoint() { return folder; }
    bool isMounted() { return up; }
    bool mountAndWait() { up = error.isEmpty(); if (up) Q_EMIT mounted(); return up; }
    QVariantMap getDirectories() {
        if (!up) return {};
        return {{folder + QStringLiteral("/storage/emulated/0/DCIM/Camera"), QStringLiteral("Camera pictures")},
                {folder + QStringLiteral("/storage/emulated/0"), QStringLiteral("Internal shared storage")}};
    }
    QString getMountError() { return error; }
Q_SIGNALS:
    void mounted();
    void unmounted();
};

class FileBrowserTest : public QObject {
    Q_OBJECT
    // Thumbnails KDE makes during these tests go to a throwaway cache.
    QTemporaryDir m_cache;
    static QVariantMap entryNamed(const FileBrowser &browser, const QString &name) {
        for (const auto &e : browser.entries()) if (e.toMap().value(QStringLiteral("name")) == name) return e.toMap();
        return {};
    }
    static QMap<QString, QString> detailRows(const FileBrowser &browser) {
        QMap<QString, QString> rows;
        for (const auto &r : browser.details().value(QStringLiteral("rows")).toList())
            rows.insert(r.toMap().value(QStringLiteral("label")).toString(), r.toMap().value(QStringLiteral("value")).toString());
        return rows;
    }
    static void useThumbnails(FileBrowser &browser) {
        browser.setThumbnailSource([](const QString &path, const QString &mimeType, qint64 modified) {
            return FileThumbnails::covers(mimeType) ? FileThumbnails::source(path, mimeType, modified) : QString();
        });
    }
    // Tiles are found in the visual tree, where a grid puts its delegates.
    static QQuickItem *findItem(QQuickItem *item, const QString &name) {
        if (!item) return nullptr;
        if (item->objectName() == name) return item;
        for (auto *child : item->childItems()) if (auto *found = findItem(child, name)) return found;
        return nullptr;
    }
    static void showPane(QQuickView &view, FileBrowser &browser) {
        view.engine()->addImageProvider(QStringLiteral("thumbnail"), new FileThumbnails);
        view.setInitialProperties({{QStringLiteral("browser"), QVariant::fromValue(&browser)}});
        view.setSource(QUrl::fromLocalFile(QStringLiteral(FILES_PANE_SOURCE)));
        view.setResizeMode(QQuickView::SizeRootObjectToView);
        view.resize(1400, 900);
        view.show();
    }
private Q_SLOTS:
    void initTestCase() {
        QVERIFY(m_cache.isValid());
        qputenv("XDG_CACHE_HOME", m_cache.path().toUtf8());
    }
    void renameMoveTrash() {
        if(!qgetenv("XDG_DATA_HOME").contains("tette-trash-test."))QSKIP("Requires isolated tette-trash-test.* data directory on the home filesystem");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("target")));
        const auto source=root.filePath(QStringLiteral("before.txt"));
        const auto renamed=root.filePath(QStringLiteral("after.txt"));
        { QFile f(source); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("safe content"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(source); browser.renameSelected(QStringLiteral("after.txt"));
        QTRY_VERIFY(!browser.working()); QVERIFY(QFile::exists(renamed)); QVERIFY(!QFile::exists(source));
        browser.refresh(); QTRY_VERIFY(!browser.busy()); browser.setSelectedPath(renamed);
        browser.renameSelected(QStringLiteral("target")); QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(renamed)); QVERIFY(QFileInfo(root.filePath(QStringLiteral("target"))).isDir());
        // The refused rename can leave a re-listing running, and a paste or
        // cut while listing is ignored, so both wait for the folder first.
        QTRY_VERIFY(!browser.busy());
        browser.cutSelected(); QVERIFY(browser.canPaste());
        QTRY_VERIFY(!browser.busy());
        browser.pasteInto(root.filePath(QStringLiteral("target"))); QTRY_VERIFY(!browser.working());
        const auto moved=root.filePath(QStringLiteral("target/after.txt"));
        QVERIFY(QFile::exists(moved)); QVERIFY(!QFile::exists(renamed)); QVERIFY(!browser.canPaste());
        browser.navigate(root.filePath(QStringLiteral("target"))); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(moved); browser.trashSelected(); QTRY_VERIFY(!browser.working());
        QVERIFY2(!QFile::exists(moved),qPrintable(browser.operationStatus())); QVERIFY(browser.canRestoreTrash());
        // Recovery survives a new backend instance.
        FileBrowser recovery; recovery.navigate(dir.path()); QTRY_VERIFY(!recovery.busy());
        { QFile replacement(moved); QVERIFY(replacement.open(QIODevice::WriteOnly)); replacement.write("replacement"); }
        recovery.restoreTrash(); QTRY_VERIFY(!recovery.working());
        QVERIFY(recovery.canRestoreTrash());
        { QFile replacement(moved); QVERIFY(replacement.open(QIODevice::ReadOnly)); QCOMPARE(replacement.readAll(),QByteArray("replacement")); }
        QVERIFY(QFile::remove(moved)); // only the disposable collision fixture
        QVERIFY(recovery.canRestoreTrash()); recovery.restoreTrash(); QTRY_VERIFY(!recovery.working());
        QVERIFY(QFile::exists(moved)); QVERIFY(!recovery.canRestoreTrash());
        QFile f(moved); QVERIFY(f.open(QIODevice::ReadOnly)); QCOMPARE(f.readAll(),QByteArray("safe content"));
    }
    void staleTrashRecordStepsAside() {
        if(!qgetenv("XDG_DATA_HOME").contains("tette-trash-test."))QSKIP("Requires isolated tette-trash-test.* data directory on the home filesystem");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QSettings().remove(QStringLiteral("Files/restoreTrash"));
        QDir root(dir.path());
        const auto kept=root.filePath(QStringLiteral("kept.txt")), gone=root.filePath(QStringLiteral("gone.txt"));
        { QFile f(kept); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("kept"); }
        { QFile f(gone); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("gone"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(kept); browser.trashSelected(); QTRY_VERIFY(!browser.working());
        browser.refresh(); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(gone); browser.trashSelected(); QTRY_VERIFY(!browser.working());
        QCOMPARE(QSettings().value(QStringLiteral("Files/restoreTrash")).toStringList().size(),2);
        // The newest record's item leaves Trash elsewhere.
        const QString trash=qEnvironmentVariable("XDG_DATA_HOME")+QStringLiteral("/Trash");
        QVERIFY(QFile::remove(trash+QStringLiteral("/files/gone.txt")));
        QVERIFY(QFile::remove(trash+QStringLiteral("/info/gone.txt.trashinfo")));
        browser.restoreTrash();
        QTRY_COMPARE(browser.operationStatus(),QStringLiteral("That item is no longer in Trash."));
        QVERIFY(!browser.working());
        QVERIFY(browser.error().isEmpty());
        QVERIFY(browser.canRestoreTrash());
        // The record behind it is no longer blocked.
        browser.restoreTrash(); QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(kept)); QVERIFY(!browser.canRestoreTrash());
    }
    void operationsRunSideBySide() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("target")));
        const auto big=root.filePath(QStringLiteral("big.bin")), note=root.filePath(QStringLiteral("note.txt"));
        { QFile f(big); QVERIFY(f.open(QIODevice::WriteOnly)); QVERIFY(f.resize(64*1024*1024)); }
        { QFile f(note); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("note"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        browser.copyDropped({big},root.filePath(QStringLiteral("target")));
        QCOMPARE(browser.operations().size(),1);
        const auto copy=browser.operations().first().toMap();
        QVERIFY(copy.value(QStringLiteral("copying")).toBool());
        QVERIFY(copy.value(QStringLiteral("canCancel")).toBool());
        browser.suspendOperation(copy.value(QStringLiteral("id")).toString());
        QVERIFY(browser.operations().first().toMap().value(QStringLiteral("suspended")).toBool());
        // With the copy paused, a rename still runs and finishes.
        browser.setSelectedPath(note); browser.renameSelected(QStringLiteral("renamed.txt"));
        QCOMPARE(browser.operations().size(),2);
        QTRY_COMPARE(browser.operations().size(),1);
        QVERIFY(QFile::exists(root.filePath(QStringLiteral("renamed.txt"))));
        QVERIFY(browser.working());
        browser.resumeOperation(copy.value(QStringLiteral("id")).toString());
        QTRY_VERIFY_WITH_TIMEOUT(!browser.working(),10000);
        QCOMPARE(QFileInfo(root.filePath(QStringLiteral("target/big.bin"))).size(),qint64(64*1024*1024));
        // A stale identity acts on nothing.
        browser.cancelOperation(QStringLiteral("stale")); browser.suspendOperation(QStringLiteral("stale"));
        QVERIFY(browser.operations().isEmpty());
    }
    void tileSizeStaysInRangeAndIsKept() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        {
            FileBrowser browser; QCOMPARE(browser.tileSize(),1);
            QSignalSpy changed(&browser,&FileBrowser::tileSizeChanged);
            browser.setTileSize(9); QCOMPARE(browser.tileSize(),3); QCOMPARE(changed.count(),1);
            browser.setTileSize(3); QCOMPARE(changed.count(),1);
        }
        FileBrowser again; QCOMPARE(again.tileSize(),3);
        again.setTileSize(-4); QCOMPARE(again.tileSize(),0);
    }
    void dropCopy() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("target")));
        const QString source=root.filePath(QStringLiteral("source.txt")), target=root.filePath(QStringLiteral("target"));
        { QFile f(source); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("original"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QGuiApplication::clipboard()->setText(QStringLiteral("keep clipboard"));
        browser.copyDropped({target},target); QVERIFY(!browser.working());
        browser.copyDropped({root.filePath(QStringLiteral("missing"))},target); QVERIFY(!browser.working());
        browser.copyDropped({source,source},target); QTRY_VERIFY(!browser.working());
        QFile copied(QDir(target).filePath(QStringLiteral("source.txt"))); QVERIFY(copied.open(QIODevice::ReadOnly));
        QCOMPARE(copied.readAll(),QByteArray("original")); copied.close();
        QVERIFY(QFile::exists(source));
        QCOMPARE(QGuiApplication::clipboard()->text(),QStringLiteral("keep clipboard"));
        QTRY_VERIFY(!browser.busy());
        { QFile f(source); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("changed"); }
        // The name is taken: Files asks, and stopping leaves the original.
        browser.copyDropped({source},target);
        QTRY_VERIFY(!browser.question().isEmpty());
        browser.answer(QStringLiteral("stop"),false);
        QTRY_VERIFY(!browser.working());
        QVERIFY(copied.open(QIODevice::ReadOnly)); QCOMPARE(copied.readAll(),QByteArray("original"));
    }
    void carryOutAndDropIn() {
        QTemporaryDir dir, elsewhere; QVERIFY(dir.isValid()); QVERIFY(elsewhere.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("inner")));
        const QString here=root.filePath(QStringLiteral("here.txt")), inner=root.filePath(QStringLiteral("inner"));
        const QString outside=QDir(elsewhere.path()).filePath(QStringLiteral("outside.txt"));
        for (const auto &p:{here,outside}) { QFile f(p); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("original"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        // Carried out: the listed files' addresses, once each; nothing if one has gone.
        std::unique_ptr<QMimeData> carried(browser.carriedFiles({here,inner,here}));
        QVERIFY(carried);
        QCOMPARE(carried->urls(),QList<QUrl>({QUrl::fromLocalFile(here),QUrl::fromLocalFile(inner)}));
        QVERIFY(!browser.carriedFiles({outside}));
        QVERIFY(!browser.carriedFiles({}));
        // Dropped in: nothing moves, and nothing lands where it already is.
        browser.copyIncoming({QUrl::fromLocalFile(here)},dir.path()); QVERIFY(!browser.working());
        browser.copyIncoming({QUrl::fromLocalFile(inner)},inner); QVERIFY(!browser.working());
        browser.copyIncoming({QUrl(QStringLiteral("ftp://example.org/a.txt"))},dir.path()); QVERIFY(!browser.working());
        browser.copyIncoming({QUrl::fromLocalFile(outside)},elsewhere.path()); QVERIFY(!browser.working());
        browser.copyIncoming({QUrl::fromLocalFile(outside)},dir.path()); QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(root.filePath(QStringLiteral("outside.txt")))); QVERIFY(QFile::exists(outside));
        QTRY_VERIFY(!browser.busy());
        browser.copyIncoming({QUrl::fromLocalFile(outside),QUrl::fromLocalFile(here)},inner); QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(QDir(inner).filePath(QStringLiteral("outside.txt"))));
        QVERIFY(QFile::exists(QDir(inner).filePath(QStringLiteral("here.txt"))));
        QVERIFY(QFile::exists(here)); QVERIFY(QFile::exists(outside));
        // A name already taken asks, as a paste does.
        QTRY_VERIFY(!browser.busy());
        { QFile f(outside); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("changed"); }
        browser.copyIncoming({QUrl::fromLocalFile(outside)},dir.path());
        QTRY_VERIFY(!browser.question().isEmpty());
        browser.answer(QStringLiteral("stop"),false);
        QTRY_VERIFY(!browser.working());
        QFile kept(root.filePath(QStringLiteral("outside.txt"))); QVERIFY(kept.open(QIODevice::ReadOnly));
        QCOMPARE(kept.readAll(),QByteArray("original"));
    }
    void copyingAndFolders() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("TetteTests"));
        QCoreApplication::setApplicationName(QStringLiteral("Files"));
        QDir root(dir.path());
        QVERIFY(root.mkdir(QStringLiteral("source")));
        const QString source=root.filePath(QStringLiteral("source"));
        QVERIFY(QDir(source).mkdir(QStringLiteral("nested")));
        { QFile nested(QDir(source).filePath(QStringLiteral("nested/child.txt"))); QVERIFY(nested.open(QIODevice::WriteOnly)); nested.write("child"); }
        for (const auto &name:{QStringLiteral("one.txt"),QStringLiteral("two space.txt")}) {
            QFile file(QDir(source).filePath(name)); QVERIFY(file.open(QIODevice::WriteOnly)); file.write("original");
        }
        FileBrowser browser; browser.navigate(source); QTRY_VERIFY(!browser.busy());
        const QString listed=QDir(source).filePath(QStringLiteral("one.txt"));
        browser.selectPaths({listed,listed,QStringLiteral("/not-in-the-listing")});
        QCOMPARE(browser.selectedPaths(),QStringList{listed});
        QCOMPARE(browser.focusedPath(),listed);
        browser.selectPaths({});
        QVERIFY(browser.selectedPaths().isEmpty());
        browser.setSelecting(true);
        browser.toggleSelected(QDir(source).filePath(QStringLiteral("one.txt")));
        browser.toggleSelected(QDir(source).filePath(QStringLiteral("two space.txt")));
        browser.toggleSelected(QDir(source).filePath(QStringLiteral("nested")));
        QCOMPARE(browser.selectedPaths().size(),3);
        browser.setSelectedPath(QDir(source).filePath(QStringLiteral("nested")));
        browser.selectRange(QDir(source).filePath(QStringLiteral("two space.txt")));
        QCOMPARE(browser.selectedPaths().size(),3);
        browser.toggleSelected(QDir(source).filePath(QStringLiteral("one.txt")));
        QCOMPARE(browser.selectedPaths().size(),2);
        browser.selectRange(QDir(source).filePath(QStringLiteral("two space.txt")),true);
        QCOMPARE(browser.selectedPaths().size(),3);
        browser.copySelected(); QVERIFY(browser.canPaste());
        browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        browser.newFolder(QStringLiteral("destination")); QTRY_VERIFY(!browser.working());
        const QString dest=root.filePath(QStringLiteral("destination"));
        QVERIFY(QDir(dest).exists());
        QCOMPARE(browser.path(),dir.path());
        QCOMPARE(browser.selectedPath(),dest);
        QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(QString()); QVERIFY(browser.canPaste()); // clipboard independent
        browser.pasteInto(dest); QVERIFY(browser.working());
        QTRY_VERIFY_WITH_TIMEOUT(!browser.working(),5000);
        QCOMPARE(browser.operationStatus(),QStringLiteral("Done"));
        QCOMPARE(browser.path(),dir.path()); // targeted paste never enters destination
        browser.navigate(dest); QTRY_VERIFY(!browser.busy());
        QVERIFY(QFile::exists(QDir(dest).filePath(QStringLiteral("nested/child.txt"))));
        QFile copied(QDir(dest).filePath(QStringLiteral("one.txt")));
        QVERIFY(copied.open(QIODevice::ReadOnly)); QCOMPARE(copied.readAll(),QByteArray("original")); copied.close();
        QFile changed(QDir(source).filePath(QStringLiteral("one.txt")));
        QVERIFY(changed.open(QIODevice::WriteOnly|QIODevice::Truncate)); changed.write("replacement"); changed.close();
        QTRY_VERIFY(!browser.busy());
        browser.paste();
        QTRY_VERIFY(!browser.question().isEmpty());
        browser.answer(QStringLiteral("stop"),false);
        QTRY_VERIFY_WITH_TIMEOUT(!browser.working(),5000);
        QVERIFY(browser.operationStatus().startsWith(QStringLiteral("Stopped")));
        QVERIFY(copied.open(QIODevice::ReadOnly)); QCOMPARE(copied.readAll(),QByteArray("original"));
        browser.newFolder(QStringLiteral("../escape")); QVERIFY(!browser.working());
        QVERIFY(!QDir(root.filePath(QStringLiteral("escape"))).exists());
        browser.newFolder(QStringLiteral("new folder")); QTRY_VERIFY(!browser.working());
        QVERIFY(QDir(QDir(dest).filePath(QStringLiteral("new folder"))).exists());
        browser.navigate(dest); QTRY_VERIFY(!browser.busy());
        browser.newFolder(QStringLiteral("new folder")); QTRY_VERIFY(!browser.working());
        QVERIFY(browser.operationStatus().startsWith(QStringLiteral("Stopped:")));
        QGuiApplication::clipboard()->clear();
    }
    void mountMetadata() {
        const auto places = FileBrowser::localPlaces(QByteArrayLiteral(
            "1 0 8:1 / / rw - ext4 /dev/root rw\n"
            "2 1 8:2 / /run/media/user/External\\040Drive rw - ext4 /dev/test rw\n"
            "3 1 0:1 / /mnt/offline rw - fuse.remote remote rw\n"
            "3 1 0:1 / /mnt/offline rw - fuse.remote remote rw\n"));
        QCOMPARE(places.size(), 7); // Recent, four standard folders, two mount points
        QCOMPARE(places[0].toMap().value(QStringLiteral("path")).toString(), FileBrowser::recentLocation());
        QCOMPARE(places[5].toMap().value(QStringLiteral("path")).toString(), QStringLiteral("/run/media/user/External Drive"));
        QCOMPARE(places[6].toMap().value(QStringLiteral("path")).toString(), QStringLiteral("/mnt/offline"));
    }
    // KDE's own folder search, on a disposable tree: names only, matched as
    // typed, hidden files only when shown, and nothing made or pasted there.
    void searchInsideFolders() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        const QString base=QFileInfo(dir.path()).canonicalFilePath();
        QDir root(base);
        for (const auto &folder:{QStringLiteral("work/2025"),QStringLiteral("plans"),QStringLiteral(".hidden"),QStringLiteral("odd & name+#%41")})
            QVERIFY(root.mkpath(folder));
        const QString odd=QStringLiteral("odd & name+#%41/a&b=c+d #%41 plan.txt");
        for (const auto &file:{QStringLiteral("plan.txt"),QStringLiteral("other.txt"),QStringLiteral("work/2025/Plan (1).md"),
                               QStringLiteral("work/notes.txt"),QStringLiteral(".hidden/plan-secret.txt"),odd}) {
            QFile f(root.filePath(file)); QVERIFY2(f.open(QIODevice::WriteOnly),qPrintable(file)); f.write("x");
        }
        const auto paths=[](const FileBrowser &b){ QStringList result; for(const auto &e:b.entries())result.append(e.toMap().value(QStringLiteral("path")).toString()); result.sort(); return result; };
        const auto sorted=[](QStringList list){ list.sort(); return list; };
        FileBrowser browser; browser.navigate(base); QTRY_VERIFY(!browser.busy());
        QSignalSpy cleared(&browser,&FileBrowser::filterCleared);
        // The filter narrows this folder only; the deeper search is offered.
        browser.setFilter(QStringLiteral("plan"));
        QCOMPARE(paths(browser),sorted({root.filePath(QStringLiteral("plan.txt")),root.filePath(QStringLiteral("plans"))}));
        QVERIFY(browser.searchOffered());
        browser.searchInside(QStringLiteral("plan"));
        QCOMPARE(browser.placeKind(),QStringLiteral("search"));
        QCOMPARE(browser.searchText(),QStringLiteral("plan"));
        QCOMPARE(browser.folder(),base);
        QVERIFY(!browser.inFolder()); QVERIFY(!browser.searchOffered());
        QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QVERIFY2(browser.error().isEmpty(),qPrintable(browser.error()));
        QCOMPARE(paths(browser),sorted({root.filePath(QStringLiteral("plan.txt")),root.filePath(QStringLiteral("plans")),
            root.filePath(QStringLiteral("work/2025/Plan (1).md")),root.filePath(odd)}));
        for (const auto &e:browser.entries()) {
            const auto entry=e.toMap();
            if (entry.value(QStringLiteral("name")).toString()==QStringLiteral("Plan (1).md"))
                QCOMPARE(entry.value(QStringLiteral("detail")).toString(),root.filePath(QStringLiteral("work/2025")));
        }
        QCOMPARE(browser.crumbs().last().toMap().value(QStringLiteral("label")).toString(),QStringLiteral("“plan”"));
        QCOMPARE(browser.crumbs()[browser.crumbs().size()-2].toMap().value(QStringLiteral("path")).toString(),base);
        QCOMPARE(browser.tabs()[browser.currentTab()].toMap().value(QStringLiteral("label")).toString(),QStringLiteral("“plan”"));
        // A search's tab comes back on its folder, not run again.
        { FileBrowser again; QCOMPARE(again.path(),base); }
        // Nothing is made or pasted into a search.
        const auto clipboardFile=root.filePath(QStringLiteral("other.txt"));
        auto *mime=new QMimeData; mime->setUrls({QUrl::fromLocalFile(clipboardFile)}); QGuiApplication::clipboard()->setMimeData(mime);
        browser.paste(); browser.newFolder(QStringLiteral("made")); browser.pasteInto(browser.path());
        QVERIFY(!browser.working()); QVERIFY(!root.exists(QStringLiteral("made")));
        QGuiApplication::clipboard()->clear();
        // What is typed is looked for as written, symbols and all.
        browser.setFilter(QStringLiteral("(1)")); QVERIFY(browser.searchOffered());
        browser.searchInside(QStringLiteral("(1)")); QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QCOMPARE(paths(browser),QStringList{root.filePath(QStringLiteral("work/2025/Plan (1).md"))});
        browser.setFilter(QStringLiteral("a&b=c+d #%41"));
        browser.searchInside(QStringLiteral("a&b=c+d #%41")); QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QCOMPARE(paths(browser),QStringList{root.filePath(odd)});
        // A search from a search replaces it: Back returns to the folder.
        browser.back(); QTRY_VERIFY(!browser.busy());
        QCOMPARE(browser.path(),base); QVERIFY(browser.inFolder());
        browser.forward(); QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QCOMPARE(browser.searchText(),QStringLiteral("a&b=c+d #%41"));
        // Hidden files join when shown.
        browser.setFilter(QStringLiteral("plan")); browser.searchInside(QStringLiteral("plan"));
        QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        browser.setHidden(true); QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QVERIFY(paths(browser).contains(root.filePath(QStringLiteral(".hidden/plan-secret.txt"))));
        browser.setHidden(false); QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QVERIFY(!paths(browser).contains(root.filePath(QStringLiteral(".hidden/plan-secret.txt"))));
        // A renamed result keeps its folder, and the results follow it.
        const auto found=root.filePath(QStringLiteral("work/2025/Plan (1).md"));
        browser.setSelectedPath(found); browser.renameSelected(QStringLiteral("Plan final.md"));
        QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(root.filePath(QStringLiteral("work/2025/Plan final.md"))));
        QTRY_VERIFY_WITH_TIMEOUT(paths(browser).contains(root.filePath(QStringLiteral("work/2025/Plan final.md"))),10000);
        QVERIFY(!paths(browser).contains(found));
        QCOMPARE(browser.placeKind(),QStringLiteral("search"));
        // A folder found opens as itself, the text set aside.
        QCOMPARE(cleared.count(),0);
        browser.setSelectedPath(root.filePath(QStringLiteral("plans"))); browser.openSelected();
        QCOMPARE(cleared.count(),1); QVERIFY(browser.filter().isEmpty());
        QCOMPARE(browser.path(),root.filePath(QStringLiteral("plans"))); QTRY_VERIFY(!browser.busy());
        browser.back(); QCOMPARE(browser.placeKind(),QStringLiteral("search"));
        QTRY_VERIFY_WITH_TIMEOUT(!browser.searching(),10000);
        QVERIFY(paths(browser).contains(root.filePath(QStringLiteral("plan.txt"))));
    }
    // Recent from KDE's own activity service. tests/verify-recent.sh runs this
    // on a private bus with a throwaway home, after recording which files were
    // used; the paths come newest first.
    // What Files opens is told to KDE's activity service, so it comes back
    // first in Recent. Run only by tests/verify-recent.sh, on a sealed bus.
    void filesOpenedAreRecent() {
        if(qEnvironmentVariable("TETTE_RECENT_SEALED")!=QStringLiteral("1"))
            QSKIP("Run by tests/verify-recent.sh against a sealed activity service");
        QTemporaryDir settings; QVERIFY(settings.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,settings.path());
        // A folder: the sealed home has no application claiming a file, and
        // a folder Files opens itself, through the same telling.
        const QString opened=QDir::home().filePath(QStringLiteral("opened-in-files"));
        QVERIFY(QDir::home().mkpath(QStringLiteral("opened-in-files")));
        FileBrowser browser;
        browser.navigate(QDir::homePath()); browser.refresh(); QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        // The service stamps uses by the second; this one comes after the
        // others the sealed run has already made.
        QTest::qWait(2500);
        browser.setSelectedPath(opened); browser.openSelected();
        QCOMPARE(browser.path(),opened);
        browser.navigate(FileBrowser::recentLocation());
        QElapsedTimer waited; waited.start();
        QString first;
        while(waited.elapsed()<45000) {
            QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
            if(!browser.entries().isEmpty()) first=browser.entries().first().toMap().value(QStringLiteral("path")).toString();
            if(first==opened) break;
            QTest::qWait(1500); browser.refresh();
        }
        QCOMPARE(first,opened);
    }

    void recentPlace() {
        const auto expected=qEnvironmentVariable("TETTE_RECENT_FILES").split(QLatin1Char('\n'),Qt::SkipEmptyParts);
        if(expected.size()<3)QSKIP("Run by tests/verify-recent.sh against a sealed activity service");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        const auto listed=[](const FileBrowser &b){ QStringList result; for(const auto &e:b.entries())result.append(e.toMap().value(QStringLiteral("path")).toString()); return result; };
        FileBrowser browser;
        browser.navigate(FileBrowser::recentLocation());
        QCOMPARE(browser.placeKind(),QStringLiteral("recent"));
        QVERIFY(!browser.inFolder()); QVERIFY(browser.folder().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),10000);
        QVERIFY2(browser.error().isEmpty(),qPrintable(browser.error()));
        // Newest first, a folder among the files, a deleted file left out and
        // the file after it kept: KDE's first answer can skip that one.
        QTRY_VERIFY2_WITH_TIMEOUT(listed(browser)==expected,qPrintable(listed(browser).join(QStringLiteral(" | "))),5000);
        for(int i=0;i<expected.size();++i) {
            const auto entry=browser.entries()[i].toMap();
            QCOMPARE(entry.value(QStringLiteral("name")).toString(),QFileInfo(expected[i]).fileName());
            const auto parent=QFileInfo(expected[i]).path();
            QCOMPARE(entry.value(QStringLiteral("detail")).toString(),parent==QDir::homePath() ? QStringLiteral("Home") : parent.mid(QDir::homePath().size()+1));
        }
        QCOMPARE(browser.crumbs().size(),1);
        QCOMPARE(browser.tabs()[browser.currentTab()].toMap().value(QStringLiteral("label")).toString(),QStringLiteral("Recent"));
        { FileBrowser again; QCOMPARE(again.path(),FileBrowser::recentLocation()); }
        // The order is the order of use, whatever the sort.
        browser.setSortMode(1); QCOMPARE(listed(browser),expected); browser.setSortMode(0);
        // Typing narrows Recent; there is no folder to search inside.
        browser.setFilter(QFileInfo(expected[0]).fileName().left(3));
        QCOMPARE(listed(browser),QStringList{expected[0]});
        QVERIFY(!browser.searchOffered());
        browser.searchInside(browser.filter()); QCOMPARE(browser.placeKind(),QStringLiteral("recent"));
        browser.setFilter(QString());
        // Nothing is made or pasted into Recent.
        auto *mime=new QMimeData; mime->setUrls({QUrl::fromLocalFile(expected[0])}); QGuiApplication::clipboard()->setMimeData(mime);
        browser.paste(); browser.newFolder(QStringLiteral("made")); QVERIFY(!browser.working());
        QGuiApplication::clipboard()->clear();
        // A file opens as itself.
        QSignalSpy requests(&browser,&FileBrowser::openRequested);
        browser.setSelectedPath(expected[0]); browser.openSelected();
        QCOMPARE(requests.count(),1); QCOMPARE(requests[0][0].toUrl(),QUrl::fromLocalFile(expected[0]));
        browser.finishOpen(QString());
        // A folder opens in place, the text set aside; Back returns to Recent.
        QString folder;
        for(const auto &e:browser.entries()) if(e.toMap().value(QStringLiteral("directory")).toBool()) folder=e.toMap().value(QStringLiteral("path")).toString();
        QVERIFY(!folder.isEmpty());
        QSignalSpy cleared(&browser,&FileBrowser::filterCleared);
        browser.setFilter(QFileInfo(folder).fileName());
        browser.setSelectedPath(folder); browser.openSelected();
        QCOMPARE(cleared.count(),1); QCOMPARE(browser.path(),folder);
        QTRY_VERIFY(!browser.busy());
        browser.back(); QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),10000);
        // Opening the folder was a use too. The service stamps uses by the
        // second, so the folder leads unless it shares a second with the file.
        auto folderFirst=expected; folderFirst.removeAll(folder); folderFirst.prepend(folder);
        QTRY_VERIFY2_WITH_TIMEOUT(listed(browser)==expected || listed(browser)==folderFirst,
            qPrintable(listed(browser).join(QStringLiteral(" | "))),5000);
        const auto shown=listed(browser);
        // A renamed file stays in its own folder and leaves Recent, which KDE
        // keeps by path.
        const auto oldest=shown.last();
        const auto renamed=QDir(QFileInfo(oldest).path()).filePath(QStringLiteral("renamed.txt"));
        browser.setSelectedPath(oldest); browser.renameSelected(QStringLiteral("renamed.txt"));
        QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(renamed));
        QTRY_VERIFY_WITH_TIMEOUT(!listed(browser).contains(oldest),10000);
        QCOMPARE(listed(browser),shown.mid(0,shown.size()-1));
    }
    // Photos, videos, PDFs and documents show KDE's thumbnail; other files and
    // folders keep their icons.
    void thumbnails() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path());
        QVERIFY(QFile::copy(QStringLiteral(FIXTURES_DIR "/photo.jpg"),root.filePath(QStringLiteral("photo.jpg"))));
        const QString odd=QStringLiteral("a ? b %41 #.png");
        QImage wide(300,200,QImage::Format_RGB32); wide.fill(Qt::darkCyan); QVERIFY(wide.save(root.filePath(odd),"PNG"));
        { QFile f(root.filePath(QStringLiteral("notes.txt"))); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("text"); }
        QVERIFY(QFile::copy(QStringLiteral(FIXTURES_DIR "/tone.ogg"),root.filePath(QStringLiteral("tone.ogg"))));
        QVERIFY(QFile::copy(QStringLiteral(FIXTURES_DIR "/clip.mp4"),root.filePath(QStringLiteral("clip.mp4"))));
        // A name that says nothing has its contents read for its type.
        QVERIFY(wide.save(root.filePath(QStringLiteral("scan")),"PNG"));
        QVERIFY(root.mkdir(QStringLiteral("folder")));
        FileBrowser browser; useThumbnails(browser);
        browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QVERIFY(entryNamed(browser,QStringLiteral("photo.jpg")).value(QStringLiteral("thumbnail")).toString().startsWith(QStringLiteral("image://thumbnail/")));
        QVERIFY(!entryNamed(browser,odd).value(QStringLiteral("thumbnail")).toString().isEmpty());
        QVERIFY(!entryNamed(browser,QStringLiteral("clip.mp4")).value(QStringLiteral("thumbnail")).toString().isEmpty());
        QVERIFY(!entryNamed(browser,QStringLiteral("scan")).value(QStringLiteral("thumbnail")).toString().isEmpty());
        QVERIFY(entryNamed(browser,QStringLiteral("notes.txt")).value(QStringLiteral("thumbnail")).toString().isEmpty());
        // Ogg sound shares its container with video, and still keeps its icon.
        QVERIFY(entryNamed(browser,QStringLiteral("tone.ogg")).value(QStringLiteral("thumbnail")).toString().isEmpty());
        QVERIFY(entryNamed(browser,QStringLiteral("folder")).value(QStringLiteral("thumbnail")).toString().isEmpty());
        QQuickView view; showPane(view,browser);
        QCOMPARE(view.status(),QQuickView::Ready);
        for (const auto &name : {QStringLiteral("photo.jpg"),QStringLiteral("clip.mp4"),odd}) {
            QQuickItem *image=nullptr;
            QTRY_VERIFY2((image=findItem(view.rootObject(),QStringLiteral("file-thumbnail-")+name)),qPrintable(name));
            QTRY_COMPARE_WITH_TIMEOUT(image->property("status").toInt(),1,10000);
            QVERIFY(image->property("implicitWidth").toReal()>0);
        }
        // The wide picture keeps its shape.
        auto *image=findItem(view.rootObject(),QStringLiteral("file-thumbnail-")+odd);
        const auto shape=image->property("implicitWidth").toReal()*2-image->property("implicitHeight").toReal()*3;
        QVERIFY2(std::abs(shape)<=3,qPrintable(QString::number(shape)));
        QTRY_COMPARE(FileThumbnails::running(),0);
    }
    // At most four thumbnails are made at once, and leaving the folder cancels
    // the rest.
    void thumbnailBudget() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("elsewhere")));
        QImage noise(2400,1800,QImage::Format_RGB32);
        for (int y=0;y<noise.height();++y) { auto *line=reinterpret_cast<QRgb *>(noise.scanLine(y)); for (int x=0;x<noise.width();++x) line[x]=qRgb((x*7+y*13)%256,(x*y)%256,(x+y*3)%256); }
        constexpr int Pictures=24;
        for (int i=0;i<Pictures;++i) QVERIFY(noise.save(root.filePath(QStringLiteral("picture-%1.png").arg(i,2,10,QLatin1Char('0'))),"PNG",0));
        FileBrowser browser; useThumbnails(browser); browser.setTileSize(0);
        browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QQuickView view; showPane(view,browser);
        QTRY_VERIFY_WITH_TIMEOUT(FileThumbnails::running()>0,10000);
        browser.navigate(root.filePath(QStringLiteral("elsewhere")));
        QTRY_COMPARE_WITH_TIMEOUT(FileThumbnails::running(),0,5000);
        QVERIFY2(FileThumbnails::mostRunning()<=4,qPrintable(QString::number(FileThumbnails::mostRunning())));
        // What was cancelled never reached KDE's cache.
        QTest::qWait(500);
        const auto cached=QDir(m_cache.path()+QStringLiteral("/thumbnails/normal")).entryList(QDir::Files).size();
        QVERIFY2(cached<Pictures,qPrintable(QString::number(cached)));
    }
    // Properties: a folder's total size counted in the background, and a
    // photo's, song's and video's own details from KDE's readers.
    void properties() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkpath(QStringLiteral("box/sub/deeper")));
        const auto write=[&root](const QString &name,int bytes){ QFile f(root.filePath(name)); return f.open(QIODevice::WriteOnly) && f.write(QByteArray(bytes,'x'))==bytes; };
        QVERIFY(write(QStringLiteral("box/a.bin"),1000)); QVERIFY(write(QStringLiteral("box/sub/b.bin"),2000)); QVERIFY(write(QStringLiteral("box/sub/deeper/c.bin"),3000));
        for (const auto &name:{QStringLiteral("photo.jpg"),QStringLiteral("tone.ogg"),QStringLiteral("clip.mp4")})
            QVERIFY(QFile::copy(QStringLiteral(FIXTURES_DIR "/")+name,root.filePath(name)));
        FileBrowser browser; browser.setDetailReader(readMediaDetails);
        browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        browser.describe(root.filePath(QStringLiteral("box")));
        QCOMPARE(browser.details().value(QStringLiteral("name")).toString(),QStringLiteral("box"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Kind")),QStringLiteral("Folder"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Where")),dir.path());
        QVERIFY(detailRows(browser).contains(QStringLiteral("Modified")));
        QTRY_COMPARE(detailRows(browser).value(QStringLiteral("Size")),QLocale().formattedDataSize(6000));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Contains")),QStringLiteral("3 files and 2 folders"));
        browser.describe(root.filePath(QStringLiteral("photo.jpg")));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Kind")),QMimeDatabase().mimeTypeForName(QStringLiteral("image/jpeg")).comment());
        QCOMPARE(detailRows(browser).value(QStringLiteral("Size")),QLocale().formattedDataSize(791));
        QTRY_COMPARE(detailRows(browser).value(QStringLiteral("Camera")),QStringLiteral("Google Pixel 8"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Dimensions")),QStringLiteral("64 × 48"));
        QVERIFY(!detailRows(browser).value(QStringLiteral("Taken")).isEmpty());
        browser.describe(root.filePath(QStringLiteral("tone.ogg")));
        QTRY_COMPARE(detailRows(browser).value(QStringLiteral("Title")),QStringLiteral("Test Tone"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Artist")),QStringLiteral("Shuffle"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Album")),QStringLiteral("Fixtures"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Length")),QStringLiteral("0:03"));
        QVERIFY(!detailRows(browser).contains(QStringLiteral("Camera")));
        browser.describe(root.filePath(QStringLiteral("clip.mp4")));
        QTRY_COMPARE(detailRows(browser).value(QStringLiteral("Dimensions")),QStringLiteral("320 × 240"));
        QCOMPARE(detailRows(browser).value(QStringLiteral("Length")),QStringLiteral("0:02"));
        // Details still on their way are dropped once the sheet closes.
        browser.describe(root.filePath(QStringLiteral("box"))); browser.stopDescribing();
        QVERIFY(browser.details().isEmpty());
        browser.describe(root.filePath(QStringLiteral("photo.jpg"))); browser.stopDescribing();
        QTest::qWait(500);
        QVERIFY(browser.details().isEmpty());
        // Only what is listed is described.
        browser.describe(QStringLiteral("/not-in-the-listing"));
        QVERIFY(browser.details().isEmpty());
    }
    // A name already taken asks, and nothing is replaced without "replace":
    // keep both, replace, skip the rest, stop, and merge a folder.
    void nameTaken() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path());
        QVERIFY(root.mkpath(QStringLiteral("src/Photos"))); QVERIFY(root.mkpath(QStringLiteral("dst/Photos")));
        const auto write=[&root](const QString &name,const QByteArray &text){ QFile f(root.filePath(name)); return f.open(QIODevice::WriteOnly|QIODevice::Truncate) && f.write(text)==text.size(); };
        const auto read=[&root](const QString &name){ QFile f(root.filePath(name)); return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray(); };
        for (const auto *n:{"a","b","c"}) QVERIFY(write(QStringLiteral("src/%1.txt").arg(QLatin1String(n)),QByteArray("new ")+n));
        QVERIFY(write(QStringLiteral("dst/a.txt"),"old a")); QVERIFY(write(QStringLiteral("dst/b.txt"),"old b"));
        QVERIFY(write(QStringLiteral("src/Photos/x.txt"),"x")); QVERIFY(write(QStringLiteral("dst/Photos/y.txt"),"y"));
        const QString src=root.filePath(QStringLiteral("src")), dst=root.filePath(QStringLiteral("dst"));
        FileBrowser browser;
        const auto copyInto=[&](const QStringList &names) {
            browser.navigate(src); QTRY_VERIFY(!browser.busy());
            QStringList paths; for(const auto &n:names) paths.append(QDir(src).filePath(n));
            browser.selectPaths(paths); QCOMPARE(browser.selectedPaths().size(),names.size());
            browser.copySelected();
            browser.navigate(dst); QTRY_VERIFY(!browser.busy());
            browser.paste();
        };
        // Three arrive, two names are taken: keep both, then replace.
        copyInto({QStringLiteral("a.txt"),QStringLiteral("b.txt"),QStringLiteral("c.txt")});
        QTRY_COMPARE(browser.question().value(QStringLiteral("name")).toString(),QStringLiteral("a.txt"));
        QVERIFY(browser.question().value(QStringLiteral("several")).toBool());
        QVERIFY(browser.question().value(QStringLiteral("canReplace")).toBool());
        QVERIFY(browser.question().value(QStringLiteral("canKeepBoth")).toBool());
        QCOMPARE(browser.question().value(QStringLiteral("folder")).toString(),QStringLiteral("dst"));
        QVERIFY(!browser.question().value(QStringLiteral("existing")).toString().isEmpty());
        QVERIFY(browser.working());
        browser.answer(QStringLiteral("keep"),false);
        QTRY_COMPARE(browser.question().value(QStringLiteral("name")).toString(),QStringLiteral("b.txt"));
        browser.answer(QStringLiteral("replace"),false);
        QTRY_VERIFY(!browser.working());
        QCOMPARE(browser.operationStatus(),QStringLiteral("Done"));
        QCOMPARE(read(QStringLiteral("dst/a.txt")),QByteArray("old a"));
        const auto kept=QDir(dst).entryList({QStringLiteral("a (*).txt")},QDir::Files);
        QCOMPARE(kept.size(),1); QCOMPARE(read(QStringLiteral("dst/")+kept.first()),QByteArray("new a"));
        QCOMPARE(read(QStringLiteral("dst/b.txt")),QByteArray("new b"));
        QCOMPARE(read(QStringLiteral("dst/c.txt")),QByteArray("new c"));
        // Skip for the rest: one answer, nothing changes.
        QVERIFY(write(QStringLiteral("src/a.txt"),"newer a")); QVERIFY(write(QStringLiteral("src/b.txt"),"newer b"));
        copyInto({QStringLiteral("a.txt"),QStringLiteral("b.txt")});
        QTRY_VERIFY(!browser.question().isEmpty());
        browser.answer(QStringLiteral("skip"),true);
        QTRY_VERIFY(!browser.working());
        QVERIFY(browser.question().isEmpty());
        QCOMPARE(read(QStringLiteral("dst/a.txt")),QByteArray("old a"));
        QCOMPARE(read(QStringLiteral("dst/b.txt")),QByteArray("new b"));
        QCOMPARE(QDir(dst).entryList({QStringLiteral("a (*).txt")},QDir::Files).size(),1);
        // Stop: the copy ends and nothing is replaced.
        copyInto({QStringLiteral("a.txt")});
        QTRY_VERIFY(!browser.question().isEmpty());
        QVERIFY(!browser.question().value(QStringLiteral("several")).toBool());
        browser.answer(QStringLiteral("stop"),false);
        QTRY_VERIFY(!browser.working());
        QVERIFY2(browser.operationStatus().startsWith(QStringLiteral("Stopped.")),qPrintable(browser.operationStatus()));
        QCOMPARE(read(QStringLiteral("dst/a.txt")),QByteArray("old a"));
        // A folder is merged, never replaced.
        copyInto({QStringLiteral("Photos")});
        QTRY_VERIFY(browser.question().value(QStringLiteral("isFolder")).toBool());
        browser.answer(QStringLiteral("replace"),false);
        QTRY_VERIFY(!browser.working());
        QCOMPARE(read(QStringLiteral("dst/Photos/x.txt")),QByteArray("x"));
        QCOMPARE(read(QStringLiteral("dst/Photos/y.txt")),QByteArray("y"));
        QGuiApplication::clipboard()->clear();
    }
    // Open With lists the applications for the file's kind, the default first,
    // and opens without changing anything else; a file no application claims
    // asks for one.
    void openWith() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path());
        { QFile f(root.filePath(QStringLiteral("notes.txt"))); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("text"); }
        { QFile f(root.filePath(QStringLiteral("blob.tetteunknown"))); QVERIFY(f.open(QIODevice::WriteOnly)); f.write(QByteArray("\x00\x01\x02\xff\xfe",5)); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        const QString notes=root.filePath(QStringLiteral("notes.txt"));
        const auto choices=browser.openWithChoices(notes);
        const auto suggested=choices.value(QStringLiteral("suggested")).toList();
        if(suggested.isEmpty())QSKIP("No application here opens text");
        QCOMPARE(choices.value(QStringLiteral("name")).toString(),QStringLiteral("notes.txt"));
        QVERIFY(!choices.value(QStringLiteral("kind")).toString().isEmpty());
        QVERIFY(suggested.first().toMap().value(QStringLiteral("isDefault")).toBool());
        QVERIFY(browser.allApplications().size()>=suggested.size());
        QVERIFY(browser.openWithChoices(root.path()).isEmpty());
        const auto before=KApplicationTrader::preferredService(QStringLiteral("text/plain"))->storageId();
        const auto pick=suggested.last().toMap().value(QStringLiteral("id")).toString();
        QSignalSpy launches(&browser,&FileBrowser::openWithRequested);
        browser.openWith(notes,pick,false);
        QCOMPARE(launches.count(),1);
        QCOMPARE(launches[0][0].toUrl(),QUrl::fromLocalFile(notes)); QCOMPARE(launches[0][1].toString(),pick);
        QVERIFY(browser.opening()); browser.finishOpen(QString());
        QCOMPARE(KApplicationTrader::preferredService(QStringLiteral("text/plain"))->storageId(),before);
        // A file nothing claims asks instead of failing.
        if(KApplicationTrader::preferredService(QStringLiteral("application/octet-stream")))QSKIP("Something here claims unknown files");
        QSignalSpy needed(&browser,&FileBrowser::applicationChoiceNeeded);
        QSignalSpy opens(&browser,&FileBrowser::openRequested);
        browser.setSelectedPath(root.filePath(QStringLiteral("blob.tetteunknown"))); browser.openSelected();
        QCOMPARE(needed.count(),1); QCOMPARE(opens.count(),0); QVERIFY(!browser.opening());
        QCOMPARE(browser.openWithChoices(root.filePath(QStringLiteral("blob.tetteunknown"))).value(QStringLiteral("hasDefault")).toBool(),false);
    }
    // The checks below write to Trash, Ark's settings or the default
    // applications; tests/verify-files-sealed.sh runs them in a throwaway home.
    void openWithAlways() {
        if(!qEnvironmentVariableIsSet("TETTE_SEALED"))QSKIP("Run by tests/verify-files-sealed.sh with a throwaway home");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        const QString notes=QDir(dir.path()).filePath(QStringLiteral("notes.txt"));
        { QFile f(notes); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("text"); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        const auto suggested=browser.openWithChoices(notes).value(QStringLiteral("suggested")).toList();
        if(suggested.size()<2)QSKIP("Fewer than two applications open text here");
        const auto pick=suggested.last().toMap().value(QStringLiteral("id")).toString();
        QVERIFY(KApplicationTrader::preferredService(QStringLiteral("text/plain"))->storageId()!=pick);
        browser.openWith(notes,pick,true); browser.finishOpen(QString());
        QTRY_COMPARE(KApplicationTrader::preferredService(QStringLiteral("text/plain"))->storageId(),pick);
        QTRY_VERIFY(browser.openWithChoices(notes).value(QStringLiteral("suggested")).toList().first().toMap().value(QStringLiteral("id"))==pick);
    }
    // The drives beside the places, on Solid's stand-in hardware: a built-in
    // drive, a USB stick, one hidden in Dolphin and one the system ignores.
    void drives() {
        if(qEnvironmentVariableIsEmpty("SOLID_FAKEHW"))QSKIP("Run by tests/verify-files-sealed.sh on Solid's stand-in hardware");
        const QString mount=qEnvironmentVariable("TETTE_FAKE_STICK"), stick=QStringLiteral("/org/kde/solid/fakehw/volume_stick");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        {
            QFile places(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+QStringLiteral("/user-places.xbel"));
            QVERIFY(places.open(QIODevice::WriteOnly));
            places.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE xbel>\n<xbel><separator><info><metadata owner=\"http://www.kde.org\">"
                         "<UDI>/org/kde/solid/fakehw/volume_hidden</UDI><IsHidden>true</IsHidden></metadata></info></separator></xbel>\n");
        }
        const auto place=[](const FileBrowser &browser,const QString &label) {
            for(const auto &p:browser.places()) if(p.toMap().value(QStringLiteral("label"))==label)return p.toMap();
            return QVariantMap{};
        };
        const auto drives=[](const FileBrowser &browser) {
            QStringList labels;
            for(const auto &p:browser.places()) if(p.toMap().contains(QStringLiteral("drive")))labels.append(p.toMap().value(QStringLiteral("label")).toString());
            return labels;
        };
        const auto hardware=[](const QString &method) {
            auto call=QDBusMessage::createMethodCall(QDBusConnection::sessionBus().baseService(),QStringLiteral("/org/kde/solid/fakehw"),QString(),method);
            call.setArguments({QStringLiteral("/org/kde/solid/fakehw/volume_stick")});
            QVERIFY(QDBusConnection::sessionBus().call(call).type()!=QDBusMessage::ErrorMessage);
        };
        FileDevices devices; FileBrowser browser; browser.setDevices(&devices);
        browser.navigate(QDir::homePath()); browser.open(); QTRY_VERIFY(!browser.busy());
        // Built-in first, after the places and under their rule.
        QCOMPARE(drives(browser),QStringList({QStringLiteral("ROOTFS"),QStringLiteral("STICK")}));
        QCOMPARE(place(browser,QStringLiteral("ROOTFS")).value(QStringLiteral("section")).toString(),QStringLiteral("drives"));
        QVERIFY(!place(browser,QStringLiteral("ROOTFS")).value(QStringLiteral("canEject")).toBool());
        QVERIFY(!place(browser,QStringLiteral("STICK")).value(QStringLiteral("mounted")).toBool());
        QVERIFY(!place(browser,QStringLiteral("STICK")).value(QStringLiteral("canEject")).toBool());
        // A tap on a drive not mounted mounts it and shows it.
        browser.openDrive(stick);
        QTRY_COMPARE(browser.path(),mount);
        QVERIFY(place(browser,QStringLiteral("STICK")).value(QStringLiteral("canEject")).toBool());
        QTRY_VERIFY(!browser.busy());
        // Eject waits for a copy into the drive, says so on the row, then goes.
        const QString arriving=dir.filePath(QStringLiteral("arriving.txt"));
        { QFile f(arriving); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("original"); }
        browser.copyIncoming({QUrl::fromLocalFile(arriving)},mount);
        QVERIFY(browser.working());
        const auto copy=browser.operations().first().toMap().value(QStringLiteral("id")).toString();
        browser.suspendOperation(copy);
        browser.ejectDrive(stick);
        QCOMPARE(place(browser,QStringLiteral("STICK")).value(QStringLiteral("note")).toString(),QStringLiteral("Ejects when done"));
        QVERIFY(place(browser,QStringLiteral("STICK")).value(QStringLiteral("busy")).toBool());
        browser.openDrive(stick); browser.ejectDrive(stick); // both wait too
        QTest::qWait(200);
        QVERIFY(place(browser,QStringLiteral("STICK")).value(QStringLiteral("mounted")).toBool());
        browser.resumeOperation(copy);
        QTRY_VERIFY(!browser.working());
        QVERIFY(QFile::exists(QDir(mount).filePath(QStringLiteral("arriving.txt"))));
        // Ejected, the tab that showed it goes Home.
        QTRY_VERIFY(!place(browser,QStringLiteral("STICK")).value(QStringLiteral("mounted")).toBool());
        QTRY_COMPARE(browser.path(),QDir::homePath());
        QTRY_COMPARE(browser.operationStatus(),QStringLiteral("“STICK” can be unplugged."));
        QCOMPARE(place(browser,QStringLiteral("STICK")).value(QStringLiteral("note")).toString(),QString());
        // Opened again in two tabs, then pulled out: both go Home, and it leaves the list.
        browser.openDrive(stick); QTRY_COMPARE(browser.path(),mount);
        browser.addTab(); browser.navigate(QDir::homePath()); browser.searchInside(QStringLiteral("x"));
        QCOMPARE(browser.currentTab(),1);
        browser.selectTab(0); QCOMPARE(browser.path(),mount);
        browser.searchInside(QStringLiteral("arriving"));
        hardware(QStringLiteral("unplug"));
        QTRY_COMPARE(drives(browser),QStringList({QStringLiteral("ROOTFS")}));
        QTRY_COMPARE(browser.path(),QDir::homePath());
        browser.selectTab(1); QVERIFY(browser.path().startsWith(QStringLiteral("filenamesearch:"))); // searching Home, not the drive
        // Plugged back in, it returns.
        hardware(QStringLiteral("plug"));
        QTRY_COMPARE(drives(browser),QStringList({QStringLiteral("ROOTFS"),QStringLiteral("STICK")}));
    }
    // Phones beside the drives: one by cable, on Solid's stand-in hardware and
    // a stand-in kio-fuse, and one through a stand-in KDE Connect.
    void phones() {
        if(qEnvironmentVariableIsEmpty("SOLID_FAKEHW"))QSKIP("Run by tests/verify-files-sealed.sh on Solid's stand-in hardware");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        // KDE Connect's mount is also a network share on the stand-in hardware.
        const QString cabled=dir.filePath(QStringLiteral("cabled")), wireless=qEnvironmentVariable("TETTE_FAKE_PHONE_MOUNT"),
            storage=wireless+QStringLiteral("/storage/emulated/0"), tools=dir.filePath(QStringLiteral("bin")), phone=QStringLiteral("/org/kde/solid/fakehw/phone");
        for(const auto &p:{cabled,storage,tools})QVERIFY(QDir().mkpath(p));
        const auto place=[](const FileBrowser &browser,const QString &label) {
            for(const auto &p:browser.places()) if(p.toMap().value(QStringLiteral("label"))==label)return p.toMap();
            return QVariantMap{};
        };
        const auto listed=[&place](const FileBrowser &browser,const QString &label) { return !place(browser,label).isEmpty(); };
        auto fakes=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fakes"));
        FakeFuse fuse; fuse.folder=cabled;
        QVERIFY(fakes.registerObject(QStringLiteral("/org/kde/KIOFuse"),&fuse,QDBusConnection::ExportAllSlots));
        QVERIFY(fakes.registerService(QStringLiteral("org.kde.KIOFuse")));
        FileDevices devices; FileBrowser browser; browser.setDevices(&devices);
        browser.navigate(QDir::homePath()); browser.open(); QTRY_VERIFY(!browser.busy());

        // By cable: with the plugged-in drives, opened through kio-fuse, never ejected.
        QTRY_VERIFY(listed(browser,QStringLiteral("PHONE")));
        QVERIFY(listed(browser,QStringLiteral("SHARE"))); // a mount alone is a share like any other
        QVERIFY(!place(browser,QStringLiteral("PHONE")).value(QStringLiteral("mounted")).toBool());
        QCOMPARE(browser.phoneForAddress(QUrl(QStringLiteral("mtp:udi=")+phone+QStringLiteral("/"))),phone);
        QVERIFY(browser.phoneForAddress(QUrl(QStringLiteral("mtp:udi=/org/kde/solid/fakehw/other"))).isEmpty());
        browser.openDrive(phone);
        QTRY_COMPARE(browser.path(),cabled);
        QCOMPARE(fuse.asked,QStringList({QStringLiteral("mtp:udi=")+phone}));
        QVERIFY(place(browser,QStringLiteral("PHONE")).value(QStringLiteral("mounted")).toBool());
        QVERIFY(!place(browser,QStringLiteral("PHONE")).value(QStringLiteral("canEject")).toBool());
        // Unplugged, the tab showing it goes Home and it leaves the list.
        auto unplug=QDBusMessage::createMethodCall(QDBusConnection::sessionBus().baseService(),QStringLiteral("/org/kde/solid/fakehw"),QString(),QStringLiteral("unplug"));
        unplug.setArguments({phone});
        QVERIFY(QDBusConnection::sessionBus().call(unplug).type()!=QDBusMessage::ErrorMessage);
        QTRY_COMPARE(browser.path(),QDir::homePath());
        QTRY_VERIFY(!listed(browser,QStringLiteral("PHONE")));

        // Through KDE Connect: listed once its daemon runs and the phone shares its files.
        FakeConnectDaemon daemon; daemon.reachable={QStringLiteral("abc")};
        FakeConnectDevice connected; FakeConnectFiles files; files.folder=wireless;
        QVERIFY(fakes.registerObject(QStringLiteral("/modules/kdeconnect"),&daemon,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(fakes.registerObject(QStringLiteral("/modules/kdeconnect/devices/abc"),&connected,QDBusConnection::ExportAllProperties));
        QVERIFY(fakes.registerObject(QStringLiteral("/modules/kdeconnect/devices/abc/sftp"),&files,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(fakes.registerService(QStringLiteral("org.kde.kdeconnect")));
        QTRY_VERIFY(listed(browser,QStringLiteral("Pixel")));
        // Listed once: the network share KDE Connect mounts it on leaves the drives.
        QTRY_VERIFY(!listed(browser,QStringLiteral("SHARE")));
        const QString id=QStringLiteral("kdeconnect:abc");
        // Without sshfs on this computer, Files says what it needs.
        const auto path=qgetenv("PATH");
        qputenv("PATH",tools.toLocal8Bit());
        browser.openDrive(id);
        QTRY_COMPARE(browser.error(),QStringLiteral("Files needs sshfs to open “Pixel” over Wi-Fi."));
        { QFile sshfs(QDir(tools).filePath(QStringLiteral("sshfs"))); QVERIFY(sshfs.open(QIODevice::WriteOnly)); sshfs.setPermissions(QFile::ReadOwner|QFile::ExeOwner); }
        // A phone that has not let KDE Connect reach its files says so.
        files.error=QStringLiteral("Permissions missing: filesystem access");
        browser.openDrive(id);
        QTRY_COMPARE(browser.error(),QStringLiteral("Allow KDE Connect on “Pixel” to reach its files, then open it again."));
        QCOMPARE(browser.path(),QDir::homePath());
        // Allowed, it opens at the storage it shares, not the mount above it,
        // which the phone does not let be read.
        files.error.clear();
        browser.openDrive(id);
        QTRY_COMPARE(browser.path(),storage);
        QVERIFY(browser.error().isEmpty());
        QTRY_VERIFY(place(browser,QStringLiteral("Pixel")).value(QStringLiteral("mounted")).toBool());
        QVERIFY(!place(browser,QStringLiteral("Pixel")).value(QStringLiteral("canEject")).toBool());
        qputenv("PATH",path);
        // Taken out of reach, KDE Connect unmounts it: the tab goes Home.
        files.up=false; Q_EMIT files.unmounted();
        QTRY_COMPARE(browser.path(),QDir::homePath());
        daemon.reachable.clear(); Q_EMIT daemon.deviceVisibilityChanged(QStringLiteral("abc"),false);
        QTRY_VERIFY(!listed(browser,QStringLiteral("Pixel")));
    }
    // Files answers for folders of every kind: KDE hands it any address, a
    // local one as a path, not a download of the folder.
    void fileManagerEntry() {
        const KService service(QStringLiteral(FILES_DESKTOP));
        QVERIFY(service.isValid());
        QVERIFY(service.hasMimeType(QStringLiteral("inode/directory")));
        QCOMPARE(service.exec(),QStringLiteral("tettegouche --folder %u"));
        const auto protocols=KIO::DesktopExecParser::supportedProtocols(service);
        for(const auto &address:{QStringLiteral("trash:/"),QStringLiteral("mtp:/"),QStringLiteral("smb://nas/share"),QStringLiteral("recentlyused:/")})
            QVERIFY2(KIO::DesktopExecParser::isProtocolInSupportedList(QUrl(address),protocols),qPrintable(address));
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QFile source(QStringLiteral(FILES_DESKTOP)); QVERIFY(source.open(QIODevice::ReadOnly));
        const QString copy=dir.filePath(QStringLiteral("files.desktop"));
        { QFile f(copy); QVERIFY(f.open(QIODevice::WriteOnly)); f.write(source.readAll().replace("Exec=tettegouche","Exec=true")); }
        const KService standIn(copy);
        const auto arguments=[&standIn](const QUrl &url) { KIO::DesktopExecParser parser(standIn,{url}); return parser.resultingArguments().mid(1); };
        QCOMPARE(arguments(QUrl::fromLocalFile(dir.path())),QStringList({QStringLiteral("--folder"),dir.path()}));
        QCOMPARE(arguments(QUrl(QStringLiteral("trash:/"))),QStringList({QStringLiteral("--folder"),QStringLiteral("trash:/")}));
    }
    void emptyTrash() {
        if(!qgetenv("XDG_DATA_HOME").contains("tette-trash-test."))QSKIP("Requires isolated tette-trash-test.* data directory on the home filesystem");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path());
        for(const auto &n:{QStringLiteral("one.txt"),QStringLiteral("two.txt")}) { QFile f(root.filePath(n)); QVERIFY(f.open(QIODevice::WriteOnly)); f.write(QByteArray(2048,'x')); }
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QSignalSpy counted(&browser,&FileBrowser::trashChanged);
        browser.checkTrash(); QTRY_VERIFY(counted.count()>=2);
        const int before=browser.trashItems();
        browser.selectPaths({root.filePath(QStringLiteral("one.txt")),root.filePath(QStringLiteral("two.txt"))});
        browser.trashSelected(); QTRY_VERIFY(!browser.working());
        QVERIFY(browser.canRestoreTrash());
        counted.clear(); browser.checkTrash(); QTRY_VERIFY(counted.count()>=2);
        QCOMPARE(browser.trashItems(),before+2);
        QVERIFY(!browser.trashSize().isEmpty());
        browser.emptyTrash(); QTRY_VERIFY(!browser.working());
        QCOMPARE(browser.operationStatus(),QStringLiteral("Done"));
        QCOMPARE(browser.trashItems(),0);
        QVERIFY(!browser.canRestoreTrash());
        counted.clear(); browser.checkTrash(); QTRY_VERIFY(counted.count()>=2);
        QCOMPARE(browser.trashItems(),0);
        QVERIFY(QDir(qEnvironmentVariable("XDG_DATA_HOME")+QStringLiteral("/Trash/files")).isEmpty());
    }
    void compressAndExtract() {
        if(!qEnvironmentVariableIsSet("TETTE_SEALED"))QSKIP("Run by tests/verify-files-sealed.sh with a throwaway home");
        if(QStandardPaths::findExecutable(QStringLiteral("ark")).isEmpty())QSKIP("Ark is not installed here");
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("Photos")));
        const auto write=[&root](const QString &name,const QByteArray &text){ QFile f(root.filePath(name)); return f.open(QIODevice::WriteOnly) && f.write(text)==text.size(); };
        QVERIFY(write(QStringLiteral("notes.txt"),"one")); QVERIFY(write(QStringLiteral("plan.txt"),"two")); QVERIFY(write(QStringLiteral("Photos/a.txt"),"three"));
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        // One item becomes its own zip.
        browser.selectPaths({root.filePath(QStringLiteral("notes.txt"))});
        QVERIFY(browser.canCompress()); QVERIFY(!browser.canExtract());
        browser.compressSelected();
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(root.filePath(QStringLiteral("notes.zip"))),30000);
        // Several become Archive.zip beside them.
        browser.selectPaths({root.filePath(QStringLiteral("notes.txt")),root.filePath(QStringLiteral("plan.txt")),root.filePath(QStringLiteral("Photos"))});
        browser.compressSelected();
        const QString archive=root.filePath(QStringLiteral("Archive.zip"));
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(archive),30000);
        // Extracting several entries gives them a folder of their own.
        QTRY_VERIFY_WITH_TIMEOUT(!entryNamed(browser,QStringLiteral("Archive.zip")).isEmpty(),10000);
        browser.selectPaths({archive});
        QVERIFY(browser.canExtract());
        browser.extractSelected();
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(root.filePath(QStringLiteral("Archive/Photos/a.txt"))),30000);
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(root.filePath(QStringLiteral("Archive/plan.txt"))),10000);
        QFile plan(root.filePath(QStringLiteral("Archive/plan.txt"))); QVERIFY(plan.open(QIODevice::ReadOnly)); QCOMPARE(plan.readAll(),QByteArray("two"));
    }
    // A copy of several that meets a file it cannot read skips it, carries
    // the rest, and ends saying what was left behind, to Files and to Ambient.
    void unreadableFileIsSkipped() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("TetteTests"));
        QCoreApplication::setApplicationName(QStringLiteral("Files"));
        QDir root(dir.path());
        QVERIFY(root.mkdir(QStringLiteral("source")));
        QVERIFY(root.mkdir(QStringLiteral("destination")));
        const QString source=root.filePath(QStringLiteral("source"));
        const QString dest=root.filePath(QStringLiteral("destination"));
        for (const auto &name:{QStringLiteral("a.txt"),QStringLiteral("b.txt"),QStringLiteral("c.txt")}) {
            QFile file(QDir(source).filePath(name)); QVERIFY(file.open(QIODevice::WriteOnly)); file.write("data");
        }
        const QString unreadable=QDir(source).filePath(QStringLiteral("b.txt"));
        QVERIFY(QFile::setPermissions(unreadable, QFileDevice::Permissions{}));
        const auto restore = qScopeGuard([&] { QFile::setPermissions(unreadable, QFileDevice::ReadOwner | QFileDevice::WriteOwner); });
        FileBrowser browser; browser.navigate(source); QTRY_VERIFY(!browser.busy());
        browser.selectAll();
        QCOMPARE(browser.selectedPaths().size(),3);
        browser.copySelected();
        browser.navigate(dest); QTRY_VERIFY(!browser.busy());
        browser.paste();
        QTRY_VERIFY_WITH_TIMEOUT(!browser.working(),5000);
        QVERIFY(QFile::exists(QDir(dest).filePath(QStringLiteral("a.txt"))));
        QVERIFY(QFile::exists(QDir(dest).filePath(QStringLiteral("c.txt"))));
        QVERIFY(!QFile::exists(QDir(dest).filePath(QStringLiteral("b.txt"))));
        QVERIFY2(browser.operationStatus().startsWith(QStringLiteral("Done, except one item that could not be read: ")),
                 qPrintable(browser.operationStatus()));
        QVERIFY(browser.error().contains(QStringLiteral("b.txt")));
        bool told=false;
        for (const auto &row : browser.activitySnapshot())
            if (row.toMap().value(QStringLiteral("state")) == QStringLiteral("failed")) told=true;
        QVERIFY(told);
    }

    // A place that cannot be opened says why in plain words and is not
    // offered new folders or pastes; nor is a folder that cannot be written.
    void placesThatCannotBeOpened() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("TetteTests"));
        QCoreApplication::setApplicationName(QStringLiteral("Files"));
        QDir root(dir.path());
        QVERIFY(root.mkdir(QStringLiteral("locked")));
        QVERIFY(root.mkdir(QStringLiteral("read-only")));
        QVERIFY(root.mkdir(QStringLiteral("open")));
        const QString locked=dir.filePath(QStringLiteral("locked"));
        const QString readOnly=dir.filePath(QStringLiteral("read-only"));
        QVERIFY(QFile::setPermissions(locked, QFileDevice::Permissions{}));
        QVERIFY(QFile::setPermissions(readOnly, QFileDevice::ReadOwner | QFileDevice::ExeOwner));
        const auto restore = qScopeGuard([&] {
            QFile::setPermissions(locked, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
            QFile::setPermissions(readOnly, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        });
        FileBrowser browser;
        browser.open();
        browser.navigate(dir.filePath(QStringLiteral("open")));
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        QVERIFY(!browser.listingFailed());
        QVERIFY(browser.canWrite());
        browser.navigate(locked);
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        QVERIFY(browser.listingFailed());
        QVERIFY(!browser.canWrite());
        QCOMPARE(browser.error(), QStringLiteral("You don't have permission to open “locked”."));
        browser.navigate(readOnly);
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        QVERIFY(!browser.listingFailed());
        QVERIFY(!browser.canWrite());
        browser.navigate(dir.filePath(QStringLiteral("gone")));
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),5000);
        QVERIFY(browser.listingFailed());
        QCOMPARE(browser.error(), QStringLiteral("“gone” isn't there any more."));
    }


    // Run by tests/verify-words.sh with test catalogs that mark every phrase
    // "xx…xx": every word Files draws comes from the launcher's catalog, and
    // the panel widget's catalog answers by the name its QML asks for.
    void wordsComeFromTheCatalogs() {
        if(!qEnvironmentVariableIsSet("TETTE_WORDS_SEALED"))QSKIP("Run by tests/verify-words.sh with marking test catalogs");
        const auto marked=[](const QString &s){ return s.startsWith(QStringLiteral("xx")) && s.endsWith(QStringLiteral("xx")); };
        QVERIFY2(marked(i18n("Home")),qPrintable(i18n("Home")));
        const char *widget="plasma_applet_studio.warbler.tettegouche";
        QVERIFY2(marked(i18nd(widget,"Open in Files")),qPrintable(i18nd(widget,"Open in Files")));
        QQmlEngine engine; QQmlComponent asks(&engine);
        asks.setData(QByteArrayLiteral("import QtQml\nimport org.kde.ki18n\nKI18nContext {\n"
            "translationDomain: \"plasma_applet_studio.warbler.tettegouche\"\nproperty string said: i18n(\"Open in Files\")\n}"),QUrl());
        std::unique_ptr<QObject> context(asks.create());
        QVERIFY2(context,qPrintable(asks.errorString()));
        QVERIFY2(marked(context->property("said").toString()),qPrintable(context->property("said").toString()));

        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("Folder")));
        { QFile f(root.filePath(QStringLiteral("note.txt"))); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("test"); }
        FileBrowser browser; QQuickView view; showPane(view,browser);
        QCOMPARE(view.status(),QQuickView::Ready);
        browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QTRY_VERIFY(findItem(view.rootObject(),QStringLiteral("files-scroll")));
        // What may show unmarked: what is on disk, by name or size, and drives.
        QStringList named=dir.path().split(QLatin1Char('/'),Qt::SkipEmptyParts);
        named<<QStringLiteral("Folder")<<QStringLiteral("note.txt")<<QLocale().formattedDataSize(4)<<dir.path();
        for(const auto &place:browser.places()) named<<place.toMap().value(QStringLiteral("label")).toString();
        int checked=0; QStringList unmarked;
        for(auto *object:view.rootObject()->findChildren<QObject*>()) {
            for(const char *property:{"text","placeholderText","title","action"}) {
                const auto value=object->property(property);
                if(value.typeId()!=QMetaType::QString)continue;
                const auto text=value.toString();
                if(!text.contains(QRegularExpression(QStringLiteral("[A-Za-z]{2,}"))))continue;
                ++checked;
                if(!marked(text) && !named.contains(text))unmarked<<QStringLiteral("%1.%2: %3").arg(QString::fromLatin1(object->metaObject()->className()),QString::fromLatin1(property),text);
            }
        }
        unmarked.removeDuplicates();
        qInfo()<<checked<<"words checked";
        QVERIFY(checked>50);
        QVERIFY2(unmarked.isEmpty(),qPrintable(unmarked.join(QLatin1Char('\n'))));
    }
    // A large folder arrives in batches, in no order. Files shows it once,
    // whole and sorted, so nothing shown moves.
    void largeFolderShowsOnceWhole() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QDir root(dir.path()); QVERIFY(root.mkdir(QStringLiteral("big")));
        const int count=3000;
        // Made in a scattered order, as a camera folder fills.
        for(int i=0;i<count;++i) {
            QFile f(dir.path()+QStringLiteral("/big/IMG_%1.jpg").arg((i*1999)%count,4,10,QLatin1Char('0')));
            QVERIFY(f.open(QIODevice::WriteOnly));
        }
        FileBrowser browser; useThumbnails(browser);
        browser.navigate(dir.path());
        QTRY_VERIFY(!browser.busy());
        QList<int> shown;
        connect(&browser,&FileBrowser::changed,this,[&]{ if(!browser.entries().isEmpty())shown.append(browser.entries().size()); });
        QElapsedTimer clock; clock.start();
        browser.navigate(root.filePath(QStringLiteral("big")));
        QTRY_VERIFY_WITH_TIMEOUT(!browser.busy(),10000);
        qInfo()<<count<<"files shown in"<<clock.elapsed()<<"ms";
        QVERIFY(!shown.isEmpty());
        QCOMPARE(shown.first(),count);
        const auto entries=browser.entries();
        QCOMPARE(entries.first().toMap().value(QStringLiteral("name")).toString(),QStringLiteral("IMG_0000.jpg"));
        QCOMPARE(entries.last().toMap().value(QStringLiteral("name")).toString(),QStringLiteral("IMG_2999.jpg"));
    }
    // Hide lists a name in its folder's .hidden, which KDE and GNOME honor,
    // so the file keeps its name; Unhide takes it out again. A name starting
    // with a dot is hidden by its name and offers no Unhide.
    void hideAndUnhide() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QDir root(dir.path());
        for (const auto &name : {QStringLiteral("keep.txt"),QStringLiteral("tuck.txt"),QStringLiteral("spare.txt"),QStringLiteral(".dot.txt")}) {
            QFile f(root.filePath(name)); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("test");
        }
        const auto list=root.filePath(QStringLiteral(".hidden"));
        { QFile f(list); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("other-app-entry\ntuck.txt\n"); }
        const auto names=[](const FileBrowser &b) {
            QStringList out; for (const auto &e : b.entries()) out.append(e.toMap().value(QStringLiteral("name")).toString());
            out.sort(); return out;
        };
        const auto listed=[&list] {
            QFile f(list); if (!f.open(QIODevice::ReadOnly)) return QStringList{};
            return QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'),Qt::SkipEmptyParts);
        };
        FileBrowser browser; browser.navigate(dir.path()); QTRY_VERIFY(!browser.busy());
        QCOMPARE(names(browser),(QStringList{QStringLiteral("keep.txt"),QStringLiteral("spare.txt")}));

        // The eye shows every hidden file, dimmed; only a listed one unhides.
        browser.setHidden(true); QTRY_VERIFY(!browser.busy());
        QVERIFY(entryNamed(browser,QStringLiteral("tuck.txt")).value(QStringLiteral("hidden")).toBool());
        QVERIFY(entryNamed(browser,QStringLiteral(".dot.txt")).value(QStringLiteral("hidden")).toBool());
        QVERIFY(!entryNamed(browser,QStringLiteral("keep.txt")).value(QStringLiteral("hidden")).toBool());
        browser.setSelectedPath(root.filePath(QStringLiteral(".dot.txt")));
        QVERIFY(!browser.canHide()); QVERIFY(!browser.canUnhide());
        browser.setSelectedPath(root.filePath(QStringLiteral("tuck.txt")));
        QVERIFY(!browser.canHide()); QVERIFY(browser.canUnhide());
        browser.setSelectedPath(root.filePath(QStringLiteral("keep.txt")));
        QVERIFY(browser.canHide()); QVERIFY(!browser.canUnhide());

        // Hiding two at once keeps what other applications listed.
        browser.selectPaths({root.filePath(QStringLiteral("keep.txt")),root.filePath(QStringLiteral("spare.txt"))});
        browser.hideSelected();
        QCOMPARE(listed(),(QStringList{QStringLiteral("other-app-entry"),QStringLiteral("tuck.txt"),QStringLiteral("keep.txt"),QStringLiteral("spare.txt")}));
        QVERIFY(browser.selectedPaths().isEmpty());
        QTRY_VERIFY(entryNamed(browser,QStringLiteral("keep.txt")).value(QStringLiteral("hidden")).toBool());
        browser.setHidden(false); QTRY_VERIFY(!browser.busy());
        QCOMPARE(names(browser),QStringList{});

        browser.setHidden(true); QTRY_VERIFY(!browser.busy());
        browser.selectPaths({root.filePath(QStringLiteral("tuck.txt")),root.filePath(QStringLiteral("keep.txt"))});
        QVERIFY(browser.canUnhide());
        browser.unhideSelected();
        QCOMPARE(listed(),(QStringList{QStringLiteral("other-app-entry"),QStringLiteral("spare.txt")}));
        QTRY_VERIFY(!entryNamed(browser,QStringLiteral("tuck.txt")).value(QStringLiteral("hidden")).toBool());
        browser.setHidden(false); QTRY_VERIFY(!browser.busy());
        QCOMPARE(names(browser),(QStringList{QStringLiteral("keep.txt"),QStringLiteral("tuck.txt")}));

        // An emptied list leaves no file behind.
        browser.setHidden(true); QTRY_VERIFY(!browser.busy());
        { QFile f(list); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("spare.txt\n"); }
        browser.refresh(); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(root.filePath(QStringLiteral("spare.txt"))); browser.unhideSelected();
        QVERIFY(!QFile::exists(list));

        // Nothing is offered where nothing can be written.
        QVERIFY(root.mkdir(QStringLiteral("locked")));
        { QFile f(root.filePath(QStringLiteral("locked/inside.txt"))); QVERIFY(f.open(QIODevice::WriteOnly)); }
        QVERIFY(QFile::setPermissions(root.filePath(QStringLiteral("locked")),QFileDevice::ReadOwner|QFileDevice::ExeOwner));
        auto unlock=qScopeGuard([&]{ QFile::setPermissions(root.filePath(QStringLiteral("locked")),QFileDevice::ReadOwner|QFileDevice::WriteOwner|QFileDevice::ExeOwner); });
        browser.navigate(root.filePath(QStringLiteral("locked"))); QTRY_VERIFY(!browser.busy());
        browser.setSelectedPath(root.filePath(QStringLiteral("locked/inside.txt")));
        QVERIFY(!browser.canHide());
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
        QSignalSpy requests(&browser, &FileBrowser::openRequested);
        browser.openSelected(); QCOMPARE(requests.count(),0);
        browser.setSelectedPath(first+QStringLiteral("/a.txt"));
        browser.openSelected(); QCOMPARE(requests.count(),1); QVERIFY(browser.opening());
        QCOMPARE(requests[0][0].toUrl(),QUrl::fromLocalFile(first+QStringLiteral("/a.txt")));
        browser.openSelected(); QCOMPARE(requests.count(),1);
        browser.finishOpen(QStringLiteral("No associated application"));
        QVERIFY(!browser.opening()); QCOMPARE(browser.error(),QStringLiteral("No associated application"));
        browser.setSelectedPath(first+QStringLiteral("/missing.txt"));
        browser.openSelected(); QCOMPARE(requests.count(),1); QVERIFY(!browser.error().isEmpty());
        browser.setSelectedPath(QString());
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
