/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include "shared/SuitePresence.h"

#include <QString>

namespace tettegouche
{
using suite::shuffleInstalled;

// The name Tettegouche shows for itself: Search where Shuffle is installed,
// Tettegouche everywhere else. Identifiers, D-Bus names and settings keys
// never follow it.
inline QString productName()
{
    return shuffleInstalled() ? QStringLiteral("Search") : QStringLiteral("Tettegouche");
}
}
