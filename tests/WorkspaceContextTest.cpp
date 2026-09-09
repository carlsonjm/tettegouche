/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "WorkspaceContext.h"

#include <QTest>

class WorkspaceContextTest final : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void acceptsVersionOne()
    {
        WorkspaceContext context;
        const QString payload = QStringLiteral(R"json({
            "schema":"studio.warbler.kadunce.workspace-context",
            "version":1,
            "focus":{"appId":"org.kde.konsole"},
            "applications":[
                {"appId":"org.kde.konsole","title":"Terminal"},
                {"appId":"com.spotify.Client","title":"Spotify"}
            ]
        })json");

        QVERIFY(context.update(payload));
        QVERIFY(context.available());
        QCOMPARE(context.focusedApplicationId(),
                 QStringLiteral("org.kde.konsole"));
        QVERIFY(context.applicationIsOpen(
            QStringLiteral("org.kde.konsole.desktop"), QString()));
        QVERIFY(context.applicationIsOpen(QString(),
                                          QStringLiteral("Spotify")));
        QVERIFY(!context.applicationIsOpen(
            QStringLiteral("org.kde.dolphin"), QStringLiteral("Dolphin")));
    }

    void rejectsUnknownVersion()
    {
        WorkspaceContext context;
        const QString payload = QStringLiteral(R"json({
            "schema":"studio.warbler.kadunce.workspace-context",
            "version":2,
            "applications":[]
        })json");

        QVERIFY(!context.update(payload));
        QVERIFY(!context.available());
    }

    void invalidUpdateClearsOldState()
    {
        WorkspaceContext context;
        QVERIFY(context.update(QStringLiteral(R"json({
            "schema":"studio.warbler.kadunce.workspace-context",
            "version":1,
            "applications":[{"appId":"org.example.App","title":"App"}]
        })json")));

        QVERIFY(!context.update(QStringLiteral("not json")));
        QVERIFY(!context.available());
        QVERIFY(!context.applicationIsOpen(
            QStringLiteral("org.example.App"), QStringLiteral("App")));
    }
};

QTEST_GUILESS_MAIN(WorkspaceContextTest)

#include "WorkspaceContextTest.moc"
