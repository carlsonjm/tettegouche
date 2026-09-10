#include "RunnerIdentity.h"
#include <QCoreApplication>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    KRunner::QueryMatch match;
    match.setId(QStringLiteral("exec:///usr/bin/discord --url --"));
    match.setData(QUrl(QStringLiteral("applications:discord.desktop")));
    if (runnerApplicationId(match) != QStringLiteral("discord.desktop")) return 1;
    match.setData(QUrl(QStringLiteral("applications:spotify.desktop")));
    if (runnerApplicationId(match) != QStringLiteral("spotify.desktop")) return 2;
    match.setData(QVariant());
    if (!runnerApplicationId(match).isEmpty()) return 3;
    match.setUrls({QUrl::fromLocalFile(QStringLiteral("/usr/share/applications/discord.desktop"))});
    if (runnerApplicationId(match) != QStringLiteral("/usr/share/applications/discord.desktop")) return 4;
    return 0;
}
