#pragma once

#include <QString>

namespace Tettegouche {

// Ambient reads Plasma's window list and job list through plasma-workspace's
// own libraries, which keep no promise between releases, so it reads them
// only on the Plasma it was built against. A different Plasma leaves those
// two sources off, and the rest of Ambient and Search runs as before, until a
// rebuild for it arrives. A Plasma that does not say its version, or a build
// that did not record one, is taken as the one built for.
inline bool plasmaMatches(const QString &built, const QString &running)
{
    const QString builtFor = built.trimmed();
    const QString runs = running.trimmed();
    return builtFor.isEmpty() || runs.isEmpty() || runs == builtFor;
}

} // namespace Tettegouche
