/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <QStandardPaths>
#include <QString>

namespace tettegouche
{
// Shuffle's bottom surface is the one part every Shuffle install has.
inline bool shuffleInstalled()
{
    return !QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                   QStringLiteral("plasma/plasmoids/studio.warbler.shuffle.bottomsurface"),
                                   QStandardPaths::LocateDirectory)
                .isEmpty();
}

// The name Tettegouche shows for itself: Search where Shuffle is installed,
// Tettegouche everywhere else. Identifiers, D-Bus names and settings keys
// never follow it.
inline QString productName()
{
    return shuffleInstalled() ? QStringLiteral("Search") : QStringLiteral("Tettegouche");
}
}
