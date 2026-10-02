/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QString>

// A use, told to KDE's activity service as Plasma's own launchers tell it, so
// it shows in Recent and on Search's first screen. Plasma's privacy setting
// decides whether it is kept.
inline void noteUsed(const QString &resource)
{
    auto use = QDBusMessage::createMethodCall(QStringLiteral("org.kde.ActivityManager"),
        QStringLiteral("/ActivityManager/Resources"), QStringLiteral("org.kde.ActivityManager.Resources"),
        QStringLiteral("RegisterResourceEvent"));
    // The application, no window, what was used, and Accessed.
    use.setArguments({QStringLiteral("io.github.carlsonjm.Tettegouche"), 0u, resource, 0u});
    QDBusConnection::sessionBus().asyncCall(use);
}

// An application started from Tettegouche, by its desktop file id.
inline void noteApplicationUsed(const QString &applicationId)
{
    if (!applicationId.isEmpty()) {
        noteUsed(QStringLiteral("applications:") + applicationId);
    }
}
