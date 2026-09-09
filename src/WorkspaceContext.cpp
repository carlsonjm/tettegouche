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
    const QJsonArray applications =
        root.value(QStringLiteral("applications")).toArray();
    for (const QJsonValue &value : applications) {
        const QJsonObject application = value.toObject();
        const QString appId = normalized(
            application.value(QStringLiteral("appId")).toString());
        const QString title = normalized(
            application.value(QStringLiteral("title")).toString());
        if (!appId.isEmpty()) {
            applicationIds.insert(appId);
        }
        if (!title.isEmpty()) {
            titles.insert(title);
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
    m_focusedApplicationId = focusedId;
    m_available = true;
    return true;
}

void WorkspaceContext::clear()
{
    m_available = false;
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
    const QString id = normalized(resultId);
    const QString executable = normalized(QFileInfo(id).baseName());
    const QString title = normalized(displayName);
    return (!id.isEmpty() && m_openApplicationIds.contains(id))
        || (!executable.isEmpty() && m_openApplicationIds.contains(executable))
        || (!title.isEmpty() && m_openTitles.contains(title));
}

QString WorkspaceContext::focusedApplicationId() const
{
    return m_focusedApplicationId;
}
