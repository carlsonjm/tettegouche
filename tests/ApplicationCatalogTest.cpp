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

QStringList order(const ApplicationCatalog &catalog)
{
    QStringList ids;
    for (int row = 0; row < catalog.rowCount(); ++row) {
        ids.append(catalog.applicationId(row));
    }
    return ids;
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
        const int count = catalog.rowCount();
        QSignalSpy hiddenCount(&catalog, &ApplicationCatalog::hiddenCountChanged);
        catalog.setHidden(rowOf(catalog, QStringLiteral("alpha.desktop")), true);
        QCOMPARE(hiddenCount.size(), 1);
        QCOMPARE(catalog.hiddenCount(), 1);
        QCOMPARE(catalog.rowCount(), count - 1);
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
        QCOMPARE(last.rowCount(), count);
    }

    // Nothing can be uninstalled before the software catalog has loaded.
    void offersNoUninstallBeforeTheSoftwareCatalog()
    {
        ApplicationCatalog catalog;
        QVERIFY(!catalog.softwareReady());
        QVERIFY(!catalog.canUninstall(rowOf(catalog, QStringLiteral("alpha.desktop"))));
        QVERIFY(!catalog.uninstall(rowOf(catalog, QStringLiteral("alpha.desktop"))));
    }

    // Each order, over the same applications; an unused application follows
    // the used ones A to Z, and the order chosen is the next catalog's.
    void ordersFourWaysAndKeepsTheChoice()
    {
        const QString alpha = QStringLiteral("alpha.desktop");
        const QString beta = QStringLiteral("beta.desktop");
        const QString zulu = QStringLiteral("zulu.desktop");
        int reads = 0;
        ApplicationCatalog catalog;
        QCOMPARE(catalog.sortOrder(), int(ApplicationCatalog::NameAscending));
        catalog.setUseReader([&reads, beta, zulu] {
            ++reads;
            return QHash<QString, double>{{zulu, 2.0}, {beta, 5.0}};
        });
        // Nothing is read while names decide the order.
        QCOMPARE(reads, 0);
        QCOMPARE(order(catalog), (QStringList{alpha, beta, zulu}));

        QSignalSpy changed(&catalog, &ApplicationCatalog::sortOrderChanged);
        catalog.setSortOrder(ApplicationCatalog::NameDescending);
        QCOMPARE(order(catalog), (QStringList{zulu, beta, alpha}));
        catalog.setSortOrder(ApplicationCatalog::MostUsed);
        QCOMPARE(reads, 1);
        QCOMPARE(order(catalog), (QStringList{beta, zulu, alpha}));
        catalog.refreshUse();
        QCOMPARE(reads, 2);
        catalog.setFilterText(QStringLiteral("a"));
        QCOMPARE(order(catalog), (QStringList{beta, alpha}));
        catalog.setFilterText({});
        catalog.setSortOrder(ApplicationCatalog::NewestInstalled);
        QCOMPARE(order(catalog).constFirst(), zulu);
        catalog.setSortOrder(7);
        QCOMPARE(catalog.sortOrder(), int(ApplicationCatalog::NewestInstalled));
        QCOMPARE(changed.size(), 3);

        ApplicationCatalog next;
        QCOMPARE(next.sortOrder(), int(ApplicationCatalog::NewestInstalled));
        next.setSortOrder(ApplicationCatalog::NameAscending);
        ApplicationCatalog last;
        QCOMPARE(last.sortOrder(), int(ApplicationCatalog::NameAscending));
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
