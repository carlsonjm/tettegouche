// Ambient reads Plasma's private window and job lists only on the Plasma it
// was built for: a Plasma update ahead of the rebuild leaves them off rather
// than reading a changed library.
#include "PlasmaMatch.h"

#include <cstdlib>
#include <iostream>

using namespace Tettegouche;

namespace {
void require(bool value, const char *message)
{
    if (!value) { std::cerr << message << '\n'; std::exit(1); }
}
} // namespace

int main()
{
    require(plasmaMatches(QStringLiteral("6.7.5"), QStringLiteral("6.7.5")),
        "The Plasma Ambient was built for was refused");
    require(plasmaMatches(QStringLiteral("6.7.5"), QStringLiteral(" 6.7.5\n")),
        "A version with spaces around it was refused");
    require(!plasmaMatches(QStringLiteral("6.7.5"), QStringLiteral("6.8.0")),
        "A newer Plasma was accepted before the rebuild");
    require(!plasmaMatches(QStringLiteral("6.7.5"), QStringLiteral("6.7.4")),
        "An older bugfix release was accepted");
    require(plasmaMatches(QStringLiteral("6.7.5"), QString()),
        "A Plasma that did not say its version turned Ambient's sources off");
    require(plasmaMatches(QString(), QStringLiteral("6.8.0")),
        "A build that did not record its Plasma turned Ambient's sources off");
    require(plasmaMatches(QStringLiteral("  "), QStringLiteral("6.8.0")),
        "A blank recorded Plasma turned Ambient's sources off");
    return 0;
}
