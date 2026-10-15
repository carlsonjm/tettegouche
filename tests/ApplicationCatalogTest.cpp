/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Apps' catalog, over three applications of its own: one with
// actions of its own, one without, and one that arrived after both. The applications, their database and the
// settings live in a temporary home, so nothing of the person's is read or
// written.

#include "ApplicationCatalog.h"

#include <KSycoca>

#include <QCoreApplication>
#include <QStringList>
#include <QDir>
#include <QFile>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

namespace
{
void write(const QString &path, const QByteArray &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(text);
}

// The applications drawn, in order, leaving out sections and folders.
QStringList order(const ApplicationCatalog &catalog)
{
    QStringList ids;
    for (int row = 0; row < catalog.rowCount(); ++row) {
        if (!catalog.applicationId(row).isEmpty()) ids.append(catalog.applicationId(row));
    }
    return ids;
}

// Every row drawn: a section as §label, a folder as [name], + when open, an
// application in an open folder as >id, any other by its id.
QStringList layout(const ApplicationCatalog &catalog)
{
    QStringList rows;
    for (int row = 0; row < catalog.rowCount(); ++row) {
        const QString kind = catalog.kind(row);
        if (kind == QStringLiteral("section")) {
            rows.append(QStringLiteral("§") + catalog.data(catalog.index(row), ApplicationCatalog::NameRole).toString());
        } else if (kind == QStringLiteral("folder")) {
            rows.append(QStringLiteral("[") + catalog.folderName(row) + QStringLiteral("]")
                        + (catalog.isOpen(row) ? QStringLiteral("+") : QString()));
        } else if (kind == QStringLiteral("member")) {
            rows.append(QStringLiteral(">") + catalog.applicationId(row));
        } else {
            rows.append(catalog.applicationId(row));
        }
    }
    return rows;
}

int rowOf(const ApplicationCatalog &catalog, const QString &id)
{
    for (int row = 0; row < catalog.rowCount(); ++row) {
        if (catalog.applicationId(row) == id) return row;
    }
    return -1;
}
}

class ApplicationCatalogTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        const QString applications = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/");
        write(applications + QStringLiteral("alpha.desktop"),
              "[Desktop Entry]\nType=Application\nName=Alpha\nExec=true\n"
              "Actions=new-window;quiet;private-window;\n\n"
              "[Desktop Action new-window]\nName=New Window\nExec=true\n\n"
              "[Desktop Action quiet]\nName=Quiet\nExec=true\nNoDisplay=true\n\n"
              "[Desktop Action private-window]\nName=New Private Window\nIcon=view-private\nExec=true\n");
        write(applications + QStringLiteral("beta.desktop"),
              "[Desktop Entry]\nType=Application\nName=Beta\nExec=true\n");
        // KDE's menu editor, kept out of Apps as the real one is not.
        write(applications + QStringLiteral("org.kde.kmenuedit.desktop"),
              "[Desktop Entry]\nType=Application\nName=Menu Editor\nExec=true\nNoDisplay=true\n");
        // Past the coarsest file system clock, so Zulu is plainly newer.
        QTest::qSleep(1100);
        write(applications + QStringLiteral("zulu.desktop"),
              "[Desktop Entry]\nType=Application\nName=Zulu\nExec=true\n");
        KSycoca::self()->ensureCacheValid();
    }

    // Each application's own actions, in its order, without those it keeps
    // out of menus; the index is the one runAction takes.
    void listsAnApplicationsOwnActions()
    {
        ApplicationCatalog catalog;
        const int alpha = rowOf(catalog, QStringLiteral("alpha.desktop"));
        const int beta = rowOf(catalog, QStringLiteral("beta.desktop"));
        QVERIFY(alpha >= 0 && beta >= 0);
        const QVariantList actions = catalog.actions(alpha);
        QCOMPARE(actions.size(), 2);
        QCOMPARE(actions.at(0).toMap().value(QStringLiteral("name")).toString(), QStringLiteral("New Window"));
        QCOMPARE(actions.at(0).toMap().value(QStringLiteral("index")).toInt(), 0);
        QCOMPARE(actions.at(1).toMap().value(QStringLiteral("name")).toString(), QStringLiteral("New Private Window"));
        QCOMPARE(actions.at(1).toMap().value(QStringLiteral("index")).toInt(), 2);
        QCOMPARE(actions.at(1).toMap().value(QStringLiteral("icon")).toString(), QStringLiteral("view-private"));
        QVERIFY(catalog.actions(beta).isEmpty());
        QVERIFY(!catalog.runAction(alpha, 7));
        QVERIFY(!catalog.runAction(-1, 0));
    }

    // A hidden application leaves the list, typed for or not, and stays
    // hidden for the next catalog; the eye shows it again, marked.
    void hidesAnApplicationUntilShown()
    {
        ApplicationCatalog catalog;
        const int count = order(catalog).size();
        QSignalSpy hiddenCount(&catalog, &ApplicationCatalog::hiddenCountChanged);
        catalog.setHidden(rowOf(catalog, QStringLiteral("alpha.desktop")), true);
        QCOMPARE(hiddenCount.size(), 1);
        QCOMPARE(catalog.hiddenCount(), 1);
        QCOMPARE(order(catalog).size(), count - 1);
        QCOMPARE(rowOf(catalog, QStringLiteral("alpha.desktop")), -1);
        catalog.setFilterText(QStringLiteral("alp"));
        QCOMPARE(catalog.rowCount(), 0);
        catalog.setFilterText({});

        ApplicationCatalog next;
        QCOMPARE(rowOf(next, QStringLiteral("alpha.desktop")), -1);
        QCOMPARE(next.hiddenCount(), 1);
        next.setShowHidden(true);
        const int shown = rowOf(next, QStringLiteral("alpha.desktop"));
        QVERIFY(shown >= 0);
        QVERIFY(next.isHidden(shown));
        QCOMPARE(next.data(next.index(shown), ApplicationCatalog::HiddenRole).toBool(), true);
        const int beta = rowOf(next, QStringLiteral("beta.desktop"));
        QCOMPARE(next.data(next.index(beta), ApplicationCatalog::HiddenRole).toBool(), false);

        next.setHidden(shown, false);
        QCOMPARE(next.hiddenCount(), 0);
        next.setShowHidden(false);
        QVERIFY(rowOf(next, QStringLiteral("alpha.desktop")) >= 0);
        ApplicationCatalog last;
        QCOMPARE(order(last).size(), count);
    }

    // Nothing can be uninstalled before the software catalog has loaded.
    void offersNoUninstallBeforeTheSoftwareCatalog()
    {
        ApplicationCatalog catalog;
        QVERIFY(!catalog.softwareReady());
        QVERIFY(!catalog.canUninstall(rowOf(catalog, QStringLiteral("alpha.desktop"))));
        QVERIFY(!catalog.uninstall(rowOf(catalog, QStringLiteral("alpha.desktop"))));
    }

    // With KDE's menu editor installed, an application can be edited there.
    void offersTheMenuEditor()
    {
        ApplicationCatalog catalog;
        QCOMPARE(rowOf(catalog, QStringLiteral("org.kde.kmenuedit.desktop")), -1);
        QVERIFY(catalog.canEdit(rowOf(catalog, QStringLiteral("alpha.desktop"))));
        QVERIFY(!catalog.canEdit(-1));
        QVERIFY(!catalog.edit(-1));
    }

    // A to Z is one run, a folder at its name's place among the
    // applications. A folder keeps its applications out of the run and opens
    // in place,
    // the choice kept; typing finds what is in it, and a folder left with one
    // application is no longer one. Folders are kept for the next catalog.
    void gathersApplicationsIntoFolders()
    {
        const QString alpha = QStringLiteral("alpha.desktop");
        const QString beta = QStringLiteral("beta.desktop");
        const QString zulu = QStringLiteral("zulu.desktop");
        ApplicationCatalog catalog;
        QCOMPARE(layout(catalog), (QStringList{alpha, beta, zulu}));
        QCOMPARE(catalog.folderCount(), 0);
        QVERIFY(catalog.gather(rowOf(catalog, alpha), alpha).isEmpty());
        const QString folder = catalog.gather(rowOf(catalog, alpha), beta);
        QVERIFY(!folder.isEmpty());
        QCOMPARE(catalog.folderCount(), 1);
        // A new folder starts open.
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("[Folder]+"), QStringLiteral(">") + alpha,
                                               QStringLiteral(">") + beta, zulu}));
        const int row = catalog.folderRow(folder);
        QCOMPARE(row, 0);
        QVERIFY(catalog.isFolder(row));
        QVERIFY(!catalog.isFolder(rowOf(catalog, zulu)));
        QCOMPARE(catalog.folderId(row), folder);
        QCOMPARE(catalog.data(catalog.index(row), ApplicationCatalog::FolderIconsRole).toStringList().size(), 2);
        QCOMPARE(catalog.data(catalog.index(row), ApplicationCatalog::SizeRole).toInt(), 2);
        QVERIFY(catalog.applicationId(row).isEmpty());
        QVERIFY(!catalog.launch(row));
        QVERIFY(!catalog.launch(-1));
        QCOMPARE(catalog.folderOf(rowOf(catalog, alpha)), folder);

        catalog.setFolderOpen(folder, false);
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("[Folder]"), zulu}));
        catalog.setFilterText(QStringLiteral("eta"));
        QCOMPARE(layout(catalog), QStringList{beta});
        QCOMPARE(catalog.folderOf(0), folder);
        catalog.setFilterText({});

        catalog.putInFolder(rowOf(catalog, zulu), folder);
        QCOMPARE(catalog.rowCount(), 1);
        catalog.renameFolder(folder, QStringLiteral(" Work "));
        QCOMPARE(layout(catalog), QStringList{QStringLiteral("[Work]")});
        QCOMPARE(catalog.folderUrls(catalog.folderRow(folder)).size(), 3);

        ApplicationCatalog next;
        QCOMPARE(layout(next), QStringList{QStringLiteral("[Work]")});
        next.setFolderOpen(folder, true);
        ApplicationCatalog opened;
        QVERIFY(opened.isOpen(opened.folderRow(folder)));

        catalog.setFolderOpen(folder, true);
        catalog.takeOut(rowOf(catalog, zulu));
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("[Work]+"), QStringLiteral(">") + alpha,
                                               QStringLiteral(">") + beta, zulu}));
        catalog.takeOut(rowOf(catalog, beta));
        // One left is no folder.
        QCOMPARE(catalog.folderCount(), 0);
        QCOMPARE(catalog.folderRow(folder), -1);
        QCOMPARE(order(catalog), (QStringList{alpha, beta, zulu}));

        const QString again = catalog.gather(rowOf(catalog, zulu), alpha);
        // The folder takes its place after beta.
        QCOMPARE(layout(catalog), (QStringList{beta, QStringLiteral("[Folder]+"), QStringLiteral(">") + alpha,
                                               QStringLiteral(">") + zulu}));
        catalog.removeFolder(again);
        QCOMPARE(order(catalog), (QStringList{alpha, beta, zulu}));
        ApplicationCatalog last;
        QCOMPARE(last.folderCount(), 0);
    }

    // New folder makes a folder of the applications chosen, two or more,
    // taking each out of any folder it was in; it starts open.
    void makesAFolderOfChosenApplications()
    {
        const QString alpha = QStringLiteral("alpha.desktop");
        const QString beta = QStringLiteral("beta.desktop");
        const QString zulu = QStringLiteral("zulu.desktop");
        ApplicationCatalog catalog;
        QCOMPARE(catalog.folderCount(), 0);
        QVERIFY(catalog.makeFolder({alpha}).isEmpty());
        QVERIFY(catalog.makeFolder({alpha, alpha}).isEmpty());
        QVERIFY(catalog.makeFolder({alpha, QStringLiteral("missing.desktop")}).isEmpty());
        QCOMPARE(catalog.folderCount(), 0);
        const QString first = catalog.makeFolder({alpha, beta});
        QVERIFY(!first.isEmpty());
        QCOMPARE(catalog.folderCount(), 1);
        QVERIFY(catalog.isOpen(catalog.folderRow(first)));
        // Beta leaves the first folder, which is left with one and ends.
        const QString second = catalog.makeFolder({beta, zulu});
        QVERIFY(!second.isEmpty() && second != first);
        QCOMPARE(catalog.folderCount(), 1);
        QCOMPARE(layout(catalog), (QStringList{alpha, QStringLiteral("[Folder]+"), QStringLiteral(">") + beta,
                                               QStringLiteral(">") + zulu}));
        catalog.removeFolder(second);
        QCOMPARE(catalog.folderCount(), 0);
    }

    // Each order, over the same applications, divided its own way: by when
    // each was last used, the most used first inside each, or by when it
    // arrived, which for those here before Apps kept count is Older. A folder
    // heads the section of its first application in the order. The order
    // chosen is the next catalog's, and Z to A, once kept, reads as A to Z.
    void ordersThreeWaysAndKeepsTheChoice()
    {
        const QString alpha = QStringLiteral("alpha.desktop");
        const QString beta = QStringLiteral("beta.desktop");
        const QString zulu = QStringLiteral("zulu.desktop");
        int reads = 0;
        ApplicationCatalog catalog;
        QCOMPARE(catalog.sortOrder(), int(ApplicationCatalog::NameAscending));
        const QDateTime now = QDateTime::currentDateTime();
        catalog.setUseReader([&reads, beta, zulu, now] {
            ++reads;
            return QHash<QString, ApplicationUse>{{zulu, {2.0, now}}, {beta, {5.0, now.addDays(-10)}}};
        });
        // Nothing is read while names decide the order.
        QCOMPARE(reads, 0);
        QCOMPARE(order(catalog), (QStringList{alpha, beta, zulu}));

        QSignalSpy changed(&catalog, &ApplicationCatalog::sortOrderChanged);
        catalog.setSortOrder(ApplicationCatalog::MostUsed);
        QCOMPARE(reads, 1);
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("§Used today"), zulu, QStringLiteral("§This month"),
                                               beta, QStringLiteral("§Earlier"), alpha}));
        catalog.refreshUse();
        QCOMPARE(reads, 2);
        catalog.setFilterText(QStringLiteral("a"));
        QCOMPARE(layout(catalog), (QStringList{beta, alpha}));
        catalog.setFilterText({});

        const QString folder = catalog.makeFolder({alpha, zulu});
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("§Used today"), QStringLiteral("[Folder]+"),
                                               QStringLiteral(">") + zulu, QStringLiteral(">") + alpha,
                                               QStringLiteral("§This month"), beta}));
        catalog.removeFolder(folder);
        // Beta is the more used, but Zulu was used today and leads the
        // folder, which sits where Zulu does.
        const QString used = catalog.makeFolder({beta, zulu});
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("§Used today"), QStringLiteral("[Folder]+"),
                                               QStringLiteral(">") + zulu, QStringLiteral(">") + beta,
                                               QStringLiteral("§Earlier"), alpha}));
        catalog.removeFolder(used);

        catalog.setSortOrder(ApplicationCatalog::NewestInstalled);
        QCOMPARE(layout(catalog), (QStringList{QStringLiteral("§Older"), alpha, beta, zulu}));
        catalog.setSortOrder(1);
        catalog.setSortOrder(7);
        QCOMPARE(catalog.sortOrder(), int(ApplicationCatalog::NewestInstalled));
        QCOMPARE(changed.size(), 2);

        ApplicationCatalog next;
        QCOMPARE(next.sortOrder(), int(ApplicationCatalog::NewestInstalled));
        QSettings().setValue(QStringLiteral("Browse/sortOrder"), 1);
        ApplicationCatalog kept;
        QCOMPARE(kept.sortOrder(), int(ApplicationCatalog::NameAscending));
        kept.setSortOrder(ApplicationCatalog::NameAscending);
        ApplicationCatalog last;
        QCOMPARE(last.sortOrder(), int(ApplicationCatalog::NameAscending));
    }

    // Installed while Search runs, an application joins Apps once KDE's
    // application list has it, and removed, it leaves. The words typed, the
    // applications hidden and the folders hold over each change; a folder
    // left with one application here is no longer drawn.
    void followsKdesApplicationList()
    {
        const QString yankee = QStringLiteral("yankee.desktop");
        const QString path = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/") + yankee;
        ApplicationCatalog catalog;
        QCOMPARE(rowOf(catalog, yankee), -1);
        catalog.setFilterText(QStringLiteral("ankee"));
        QCOMPARE(catalog.rowCount(), 0);
        QSignalSpy reset(&catalog, &QAbstractItemModel::modelReset);

        write(path, "[Desktop Entry]\nType=Application\nName=Yankee\nExec=true\n");
        QTRY_VERIFY_WITH_TIMEOUT(rowOf(catalog, yankee) >= 0, 15000);
        QVERIFY(reset.size() >= 1);
        QCOMPARE(catalog.filterText(), QStringLiteral("ankee"));
        QCOMPARE(order(catalog), QStringList{yankee});

        catalog.setFilterText({});
        const QString folder = catalog.makeFolder({QStringLiteral("alpha.desktop"), yankee});
        QVERIFY(!folder.isEmpty());
        QCOMPARE(catalog.folderCount(), 1);
        catalog.setHidden(rowOf(catalog, QStringLiteral("beta.desktop")), true);
        QCOMPARE(catalog.hiddenCount(), 1);
        QSignalSpy folders(&catalog, &ApplicationCatalog::foldersChanged);

        QVERIFY(QFile::remove(path));
        QTRY_VERIFY_WITH_TIMEOUT(catalog.applicationRow(yankee) < 0, 15000);
        QCOMPARE(catalog.folderCount(), 0);
        QCOMPARE(folders.size(), 1);
        QVERIFY(catalog.applicationRow(QStringLiteral("alpha.desktop")) >= 0);
        QCOMPARE(catalog.hiddenCount(), 1);
        QCOMPARE(catalog.applicationRow(QStringLiteral("beta.desktop")), -1);

        catalog.removeFolder(folder);
        catalog.setShowHidden(true);
        catalog.setHidden(catalog.applicationRow(QStringLiteral("beta.desktop")), false);
        catalog.setShowHidden(false);
        QCOMPARE(catalog.hiddenCount(), 0);
    }

    // Flatpak exports an application as a link, in a system folder of links
    // that nothing in KDE rebuilds its list for. Apps finds it on its own.
    void followsAFlatpakInstall()
    {
        const QString exports = qEnvironmentVariable("XDG_DATA_DIRS") + QStringLiteral("/applications");
        const QString app = qEnvironmentVariable("HOME") + QStringLiteral("/flatpak/app/org.example.Zulu/export");
        QVERIFY(QDir().mkpath(exports));
        QVERIFY(QDir().mkpath(app));
        const QString zulu = QStringLiteral("org.example.Zulu.desktop");
        write(app + QLatin1Char('/') + zulu, "[Desktop Entry]\nType=Application\nName=Zulu\nExec=true\n");
        ApplicationCatalog catalog;
        QCOMPARE(catalog.applicationRow(zulu), -1);

        QVERIFY(QFile::link(app + QLatin1Char('/') + zulu, exports + QLatin1Char('/') + zulu));
        QTRY_VERIFY_WITH_TIMEOUT(catalog.applicationRow(zulu) >= 0, 15000);

        QVERIFY(QFile::remove(exports + QLatin1Char('/') + zulu));
        QTRY_VERIFY_WITH_TIMEOUT(catalog.applicationRow(zulu) < 0, 15000);
    }

    // An application arrives when Apps first finds it. One updated since,
    // its desktop file written anew, keeps when it arrived. Both happen while
    // Apps is open, as an install does, and Apps follows KDE's list to them.
    void newestInstalledIsWhenAppsFirstFoundIt()
    {
        const QString applications = qEnvironmentVariable("XDG_DATA_HOME") + QStringLiteral("/applications/");
        const QString xray = QStringLiteral("xray.desktop");
        const QStringList expected{QStringLiteral("§This week"), xray, QStringLiteral("§Older"),
                                   QStringLiteral("alpha.desktop"), QStringLiteral("beta.desktop"),
                                   QStringLiteral("zulu.desktop")};
        ApplicationCatalog catalog;
        catalog.setSortOrder(ApplicationCatalog::NewestInstalled);
        QCOMPARE(catalog.applicationRow(xray), -1);

        QVERIFY(QFile::remove(applications + QStringLiteral("beta.desktop")));
        write(applications + QStringLiteral("beta.desktop"),
              "[Desktop Entry]\nType=Application\nName=Beta\nExec=true\nComment=Updated\n");
        write(applications + xray, "[Desktop Entry]\nType=Application\nName=X-ray\nExec=true\n");
        QTRY_COMPARE_WITH_TIMEOUT(layout(catalog), expected, 15000);

        ApplicationCatalog next;
        QCOMPARE(layout(next), expected);
        next.setSortOrder(ApplicationCatalog::NameAscending);

        QVERIFY(QFile::remove(applications + xray));
        QTRY_VERIFY_WITH_TIMEOUT(catalog.applicationRow(xray) < 0, 15000);
    }
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
    QCoreApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("tettegouche-test"));
    app.setApplicationName(QStringLiteral("application-catalog-test"));
    ApplicationCatalogTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "ApplicationCatalogTest.moc"
