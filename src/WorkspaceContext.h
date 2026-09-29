/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>
#include <QString>
#include <QVector>

class WorkspaceContext
{
public:
    bool update(const QString &payload);
    void clear();

    bool available() const;
    bool applicationIsOpen(const QString &resultId,
                           const QString &displayName) const;
    QString windowIdForApplication(const QString &resultId,
                                   const QString &displayName) const;
    QString focusedApplicationId() const;

private:
    static QString normalized(const QString &value);
    static bool identitiesMatch(const QString &left, const QString &right);

    struct Application {
        QString windowId;
        QString appId;
        QString title;
        bool focused = false;
        bool selected = false;
        qint64 lastActivated = 0;
    };

    bool m_available = false;
    QVector<Application> m_applications;
    QSet<QString> m_openApplicationIds;
    QSet<QString> m_openTitles;
    QString m_focusedApplicationId;
};
