/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QVector>

class WorkspaceContext
{
public:
    bool update(const QString &payload);
    void clear();

    bool available() const;
    // A launcher is matched to open windows by its desktop entry only.
    bool applicationIsOpen(const QString &resultId) const;
    QString windowIdForApplication(const QString &resultId) const;
    QString focusedApplicationId() const;

private:
    static QString normalized(const QString &value);
    static QString launcherIdentity(const QString &resultId);
    static bool identitiesMatch(const QString &launcher, const QString &window);

    struct Application {
        QString windowId;
        QString appId;
        bool focused = false;
        bool selected = false;
        qint64 lastActivated = 0;
    };

    bool m_available = false;
    QVector<Application> m_applications;
    QString m_focusedApplicationId;
};
