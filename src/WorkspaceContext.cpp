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
constexpr auto ExpectedSchema = "studio.warbler.kadunce.workspace-context";
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

bool WorkspaceContext::identitiesMatch(const QString &left,
                                       const QString &right)
{
    if (left.isEmpty() || right.isEmpty()) {
        return false;
    }
    return left == right
        || (left.size() > 3 && right.contains(left))
        || (right.size() > 3 && left.contains(right));
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

    QSet<QString> applicationIds;
    QSet<QString> titles;
    QVector<Application> parsedApplications;
    const QJsonArray applications =
        root.value(QStringLiteral("applications")).toArray();
    for (const QJsonValue &value : applications) {
        const QJsonObject application = value.toObject();
        const QString appId = normalized(
            application.value(QStringLiteral("appId")).toString());
        const QString title = normalized(
            application.value(QStringLiteral("title")).toString());
        const QString windowId = application
            .value(QStringLiteral("windowId")).toString().trimmed();
        if (!appId.isEmpty()) {
            applicationIds.insert(appId);
        }
        if (!title.isEmpty()) {
            titles.insert(title);
        }
        if (!windowId.isEmpty()) {
            parsedApplications.append({
                .windowId = windowId,
                .appId = appId,
                .title = title,
                .focused = application
                    .value(QStringLiteral("focused")).toBool(),
                .selected = application
                    .value(QStringLiteral("selected")).toBool(),
            });
        }
    }

    QString focusedId;
    const QJsonValue focusValue = root.value(QStringLiteral("focus"));
    if (focusValue.isObject()) {
        focusedId = normalized(focusValue.toObject()
            .value(QStringLiteral("appId")).toString());
    }

    m_openApplicationIds = std::move(applicationIds);
    m_openTitles = std::move(titles);
    m_applications = std::move(parsedApplications);
    m_focusedApplicationId = focusedId;
    m_available = true;
    return true;
}

void WorkspaceContext::clear()
{
    m_available = false;
    m_applications.clear();
    m_openApplicationIds.clear();
    m_openTitles.clear();
    m_focusedApplicationId.clear();
}

bool WorkspaceContext::available() const
{
    return m_available;
}

bool WorkspaceContext::applicationIsOpen(const QString &resultId,
                                         const QString &displayName) const
{
    return !windowIdForApplication(resultId, displayName).isEmpty();
}

QString WorkspaceContext::windowIdForApplication(
    const QString &resultId, const QString &displayName) const
{
    const QString id = normalized(resultId);
    const QString executable = normalized(QFileInfo(id).baseName());
    const QString title = normalized(displayName);
    const Application *best = nullptr;
    int bestPriority = -1;
    for (const Application &application : m_applications) {
        const bool matches = identitiesMatch(id, application.appId)
            || identitiesMatch(executable, application.appId)
            || identitiesMatch(title, application.title);
        if (!matches) {
            continue;
        }
        const int priority = application.focused ? 2
            : application.selected ? 1 : 0;
        if (priority >= bestPriority) {
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
