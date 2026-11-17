/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "ThemeIcons.h"

#include <QDir>
#include <QFile>
#include <QIcon>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

// An icon already drawn follows the icon theme once it is asked to look its
// icon up again, in a window that shows and in one hidden meanwhile.
class ThemeIconsTest : public QObject
{
    Q_OBJECT

    // An icon theme of one application icon, in one colour.
    static bool writeTheme(const QString &root, const QString &name, const QColor &colour)
    {
        const QString folder = root + QLatin1Char('/') + name;
        if (!QDir().mkpath(folder + QStringLiteral("/48x48/apps"))) return false;
        QFile index(folder + QStringLiteral("/index.theme"));
        if (!index.open(QIODevice::WriteOnly)) return false;
        index.write("[Icon Theme]\nName=" + name.toUtf8() + "\nDirectories=48x48/apps\n\n"
                    "[48x48/apps]\nSize=48\nType=Fixed\nContext=Applications\n");
        index.close();
        QImage picture(48, 48, QImage::Format_ARGB32_Premultiplied);
        picture.fill(colour);
        return picture.save(folder + QStringLiteral("/48x48/apps/tettegouche-probe.png"));
    }

private Q_SLOTS:
    void drawnIconsFollowTheTheme()
    {
        QTemporaryDir themes;
        QVERIFY(themes.isValid());
        QVERIFY(writeTheme(themes.path(), QStringLiteral("First"), Qt::red));
        QVERIFY(writeTheme(themes.path(), QStringLiteral("Second"), Qt::blue));
        QVERIFY(writeTheme(themes.path(), QStringLiteral("Third"), Qt::green));
        QIcon::setThemeSearchPaths({themes.path()});
        QIcon::setThemeName(QStringLiteral("First"));

        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport org.kde.kirigami as Kirigami\n"
                          "Item { width: 48; height: 48\n"
                          "    Kirigami.Icon { anchors.fill: parent; source: \"tettegouche-probe\"; animated: false }\n"
                          "    ListView { anchors.fill: parent; model: 1; delegate: Kirigami.Icon { width: 8; height: 8; source: \"tettegouche-probe\" } } }",
                          QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QQuickWindow window;
        window.resize(48, 48);
        std::unique_ptr<QObject> made(component.create());
        auto *item = qobject_cast<QQuickItem *>(made.get());
        QVERIFY(item);
        item->setParentItem(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        const auto drawn = [&window] { return window.grabWindow().pixelColor(40, 40); };
        QTRY_COMPARE(drawn(), QColor(Qt::red));

        // Another theme chosen: both icons, the one in the list's row too,
        // are asked, and the one on screen draws the new theme's.
        QIcon::setThemeName(QStringLiteral("Second"));
        QCOMPARE(tettegouche::lookUpIconsAgain(), 2);
        QTRY_COMPARE(drawn(), QColor(Qt::blue));

        // Chosen while the window is hidden, it shows with the new theme's.
        window.hide();
        QIcon::setThemeName(QStringLiteral("Third"));
        QCOMPARE(tettegouche::lookUpIconsAgain(), 2);
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        QTRY_COMPARE(drawn(), QColor(Qt::green));
    }
};

QTEST_MAIN(ThemeIconsTest)

#include "ThemeIconsTest.moc"
