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
    void mostRecentlyActivatedWinsOverSelectedCard()
    {
        WorkspaceContext context;
        QVERIFY(context.update(QStringLiteral(R"({
            "schema":"co.goodinput.kadunce.workspace-context","version":1,
            "applications":[
              {"windowId":"recent","appId":"org.example.App","lastActivated":12},
              {"windowId":"old","appId":"org.example.App","selected":true,"lastActivated":3}
            ]})")));
        QCOMPARE(context.windowIdForApplication(QStringLiteral("org.example.App")), QStringLiteral("recent"));
        QVERIFY(context.update(QStringLiteral(R"({
            "schema":"co.goodinput.kadunce.workspace-context","version":1,
            "applications":[{"windowId":"old","appId":"org.example.App","lastActivated":3}]})")));
        QCOMPARE(context.windowIdForApplication(QStringLiteral("org.example.App")), QStringLiteral("old"));
    }
    void acceptsVersionOne()
    {
        WorkspaceContext context;
        const QString payload = QStringLiteral(R"json({
            "schema":"co.goodinput.kadunce.workspace-context",
            "version":1,
            "focus":{"appId":"org.kde.konsole"},
            "applications":[
                {"windowId":"terminal-window","appId":"org.kde.konsole","title":"Terminal","focused":true},
                {"windowId":"spotify-window","appId":"com.spotify.Client","title":"Spotify"}
            ]
        })json");

        QVERIFY(context.update(payload));
        QVERIFY(context.available());
        QCOMPARE(context.focusedApplicationId(),
                 QStringLiteral("org.kde.konsole"));
        QVERIFY(context.applicationIsOpen(
            QStringLiteral("org.kde.konsole.desktop")));
        QVERIFY(context.applicationIsOpen(
            QStringLiteral("/usr/share/applications/org.kde.konsole.desktop")));
        QVERIFY(context.applicationIsOpen(
            QStringLiteral("com.spotify.Client.desktop")));
        QCOMPARE(context.windowIdForApplication(
                     QStringLiteral("services_org.kde.konsole.desktop")),
                 QStringLiteral("terminal-window"));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("org.kde.dolphin")));
        QVERIFY(!context.applicationIsOpen(QString()));
    }

    void rejectsUnknownVersion()
    {
        WorkspaceContext context;
        const QString payload = QStringLiteral(R"json({
            "schema":"co.goodinput.kadunce.workspace-context",
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
            "schema":"co.goodinput.kadunce.workspace-context",
            "version":1,
            "applications":[{"windowId":"app-window","appId":"org.example.App","title":"App"}]
        })json")));

        QVERIFY(!context.update(QStringLiteral("not json")));
        QVERIFY(!context.available());
        QVERIFY(!context.applicationIsOpen(QStringLiteral("org.example.App")));
    }

    // A window that names no application belongs to no launcher, whatever its
    // caption says: the browser's own Settings window once brought itself
    // forward in place of Shuffle's Settings.
    void windowWithoutApplicationIdMatchesNoLauncher()
    {
        WorkspaceContext context;
        QVERIFY(context.update(QStringLiteral(R"json({
            "schema":"co.goodinput.kadunce.workspace-context","version":1,
            "applications":[
              {"windowId":"browser-settings","appId":"","title":"Settings \u2013 Output Browser","focused":true,"lastActivated":40}
            ]})json")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("co.goodinput.Shuffle.Settings.desktop")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("/usr/share/applications/systemsettings.desktop")));
        QVERIFY(context.windowIdForApplication(QStringLiteral("settings")).isEmpty());
        QVERIFY(context.windowIdForApplication(QString()).isEmpty());
    }

    // The caption is never read: a window whose caption names an application
    // is still only the application its ID says it is.
    void captionNeverMatches()
    {
        WorkspaceContext context;
        QVERIFY(context.update(QStringLiteral(R"json({
            "schema":"co.goodinput.kadunce.workspace-context","version":1,
            "applications":[
              {"windowId":"editor","appId":"org.kde.kate","title":"Settings - Spotify notes"}
            ]})json")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("co.goodinput.Shuffle.Settings.desktop")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("com.spotify.Client.desktop")));
        QCOMPARE(context.windowIdForApplication(QStringLiteral("org.kde.kate.desktop")),
                 QStringLiteral("editor"));
    }

    // Names match as whole parts, not as fragments of one another.
    void partialNamesDoNotMatch()
    {
        WorkspaceContext context;
        QVERIFY(context.update(QStringLiteral(R"json({
            "schema":"co.goodinput.kadunce.workspace-context","version":1,
            "applications":[
              {"windowId":"ghostty","appId":"com.mitchellh.ghostty"},
              {"windowId":"settings","appId":"systemsettings"}
            ]})json")));
        QVERIFY(context.applicationIsOpen(QStringLiteral("ghostty.desktop")));
        QVERIFY(context.applicationIsOpen(QStringLiteral("systemsettings.desktop")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("co.goodinput.Shuffle.Settings.desktop")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("ghost.desktop")));
        QVERIFY(!context.applicationIsOpen(QStringLiteral("org.kde.ghostwriter.desktop")));
    }
};

QTEST_GUILESS_MAIN(WorkspaceContextTest)

#include "WorkspaceContextTest.moc"
