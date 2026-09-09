/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>
#include <QString>

class WorkspaceContext
{
public:
    bool update(const QString &payload);
    void clear();

    bool available() const;
    bool applicationIsOpen(const QString &resultId,
                           const QString &displayName) const;
    QString focusedApplicationId() const;

private:
    static QString normalized(const QString &value);

    bool m_available = false;
    QSet<QString> m_openApplicationIds;
    QSet<QString> m_openTitles;
    QString m_focusedApplicationId;
};
