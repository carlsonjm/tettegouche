/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTest>

class SuiteIconRenderTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void packagedGlyphsRender()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(SUITE_ICON_QML)),
            QQmlComponent::PreferSynchronous);
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));

        QQuickWindow window;
        window.setColor(Qt::transparent);
        window.resize(64, 64);
        window.show();

        const QStringList glyphs{
            QStringLiteral("skip-back"), QStringLiteral("play"), QStringLiteral("pause"),
            QStringLiteral("skip-forward"), QStringLiteral("download"), QStringLiteral("x"),
            QStringLiteral("plus"), QStringLiteral("arrow-left"), QStringLiteral("arrow-right"),
            QStringLiteral("refresh-cw"), QStringLiteral("ellipsis"), QStringLiteral("check"),
            QStringLiteral("circle")
        };
        for (const QString &glyph : glyphs) {
            QScopedPointer<QObject> icon(component.createWithInitialProperties(
                {{QStringLiteral("glyph"), glyph}}));
            auto *item = qobject_cast<QQuickItem *>(icon.data());
            QVERIFY2(item, qPrintable(glyph));
            item->setSize(QSizeF(20, 20));
            item->setParentItem(window.contentItem());
            QVERIFY2(item->isVisible() && item->width() >= 20 && item->height() >= 20,
                qPrintable(QStringLiteral("Zero-size or invisible SuiteIcon: ") + glyph));
            auto *imageItem = item->findChild<QQuickItem *>();
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
};

QTEST_MAIN(SuiteIconRenderTest)
#include "SuiteIconRenderTest.moc"
