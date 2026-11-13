#include "IslandShare.h"

int main()
{
    const QStringList all{QStringLiteral("media"), QStringLiteral("others"), QStringLiteral("note")};
    const QStringList media{QStringLiteral("media")};
    const QStringList others{QStringLiteral("others"), QStringLiteral("note")};

    // One widget leaves nothing to anyone.
    if (islandsLeftToOthers({all}) != QList<QStringList>{{}}) return 1;
    // A host's split, media on one side and the rest on the other, overlaps
    // nowhere, so each keeps its own.
    if (islandsLeftToOthers({media, others}) != QList<QStringList>{{}, {}}) return 2;
    // Two widgets set alike: the first keeps every island and the second
    // leaves them all, so each shows once.
    if (islandsLeftToOthers({all, all}) != QList<QStringList>{{}, all}) return 3;
    // The second shows only what the first does not.
    if (islandsLeftToOthers({media, all}) != QList<QStringList>{{}, media}) return 4;
    // A widget with its islands off takes nothing, so the next keeps them.
    if (islandsLeftToOthers({{}, all}) != QList<QStringList>{{}, {}}) return 5;
    // The first without the quick note's island leaves it to the second.
    if (islandsLeftToOthers({{QStringLiteral("media"), QStringLiteral("others")}, all})
        != QList<QStringList>{{}, {QStringLiteral("media"), QStringLiteral("others")}}) return 6;
    // Three alike: only the first shows.
    if (islandsLeftToOthers({others, others, others}) != QList<QStringList>{{}, others, others}) return 7;
    return 0;
}
