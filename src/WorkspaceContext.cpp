/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "WorkspaceContext.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace
{
constexpr auto ExpectedSchema = "co.goodinput.kadunce.workspace-context";
constexpr int SupportedVersion = 1;
}

QString WorkspaceContext::normalized(const QString &value)
{
    QString identity = value.trimmed().toLower();
    if (identity.endsWith(QLatin1String(".desktop"))) {
        identity.chop(8);
    }
    return identity;
}

// What a launcher names is its desktop entry: a storage ID, a file path or an
// older runner key. Only the entry's own name is compared with a window.
QString WorkspaceContext::launcherIdentity(const QString &resultId)
{
    QString identity = normalized(QFileInfo(resultId.trimmed()).fileName());
    if (identity.startsWith(QLatin1String("services_"))) {
        identity.remove(0, 9);
    }
    return identity;
}

// A window is paired with a launcher only by the application it says it
// belongs to, never by its caption, and never when it names none: a window
// with no application ID belongs to no launcher. The two match when they are
// the same, or when the shorter is one whole dot-separated part of the
// longer, as "konsole" is of "org.kde.konsole" and "spotify" of
// "com.spotify.client".
bool WorkspaceContext::identitiesMatch(const QString &launcher,
                                       const QString &window)
{
    if (launcher.isEmpty() || window.isEmpty()) {
        return false;
    }
    if (launcher == window) {
        return true;
    }
    const bool launcherShorter = launcher.size() < window.size();
    const QString &shorter = launcherShorter ? launcher : window;
    const QString &longer = launcherShorter ? window : launcher;
    if (shorter.size() <= 3 || shorter.contains(QLatin1Char('.'))) {
        return false;
    }
    const QStringList parts = longer.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    return parts.contains(shorter);
}

bool WorkspaceContext::update(const QString &payload)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(
        payload.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        clear();
        return false;
    }

    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("schema")).toString()
            != QLatin1String(ExpectedSchema)
        || root.value(QStringLiteral("version")).toInt(-1)
            != SupportedVersion
        || !root.value(QStringLiteral("applications")).isArray()) {
        clear();
        return false;
    }

    QVector<Application> parsedApplications;
    const QJsonArray applications =
        root.value(QStringLiteral("applications")).toArray();
    for (const QJsonValue &value : applications) {
        const QJsonObject application = value.toObject();
        const QString appId = normalized(
            application.value(QStringLiteral("appId")).toString());
        const QString windowId = application
            .value(QStringLiteral("windowId")).toString().trimmed();
        // A window that names no application can never be reached from a
        // launcher, so it is not kept.
        if (!windowId.isEmpty() && !appId.isEmpty()) {
            parsedApplications.append({
                .windowId = windowId,
                .appId = appId,
                .focused = application
                    .value(QStringLiteral("focused")).toBool(),
                .selected = application
                    .value(QStringLiteral("selected")).toBool(),
                .lastActivated = application.value(QStringLiteral("lastActivated")).toInteger(),
            });
        }
    }

    QString focusedId;
    const QJsonValue focusValue = root.value(QStringLiteral("focus"));
    if (focusValue.isObject()) {
        focusedId = normalized(focusValue.toObject()
            .value(QStringLiteral("appId")).toString());
    }

    m_applications = std::move(parsedApplications);
    m_focusedApplicationId = focusedId;
    m_available = true;
    return true;
}

void WorkspaceContext::clear()
{
    m_available = false;
    m_applications.clear();
    m_focusedApplicationId.clear();
}

bool WorkspaceContext::available() const
{
    return m_available;
}

bool WorkspaceContext::applicationIsOpen(const QString &resultId) const
{
    return !windowIdForApplication(resultId).isEmpty();
}

QString WorkspaceContext::windowIdForApplication(const QString &resultId) const
{
    const QString launcher = launcherIdentity(resultId);
    const Application *best = nullptr;
    int bestPriority = -1;
    for (const Application &application : m_applications) {
        if (!identitiesMatch(launcher, application.appId)) {
            continue;
        }
        const int priority = application.focused ? 2
            : application.selected ? 1 : 0;
        if (!best || application.lastActivated > best->lastActivated
            || (application.lastActivated == best->lastActivated && priority >= bestPriority)) {
            best = &application;
            bestPriority = priority;
        }
    }
    return best ? best->windowId : QString();
}

QString WorkspaceContext::focusedApplicationId() const
{
    return m_focusedApplicationId;
}
