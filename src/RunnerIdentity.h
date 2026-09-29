#pragma once

#include <KRunner/QueryMatch>
#include <QUrl>
#include <QVariant>

// A runner result ID may be an exec:// deduplication key, not an app ID.
// The services runner carries the launchable desktop identity in match data.
inline QString runnerApplicationId(const KRunner::QueryMatch &match)
{
    const QUrl target = match.data().toUrl();
    if (target.scheme() == QStringLiteral("applications")) {
        return target.path();
    }
    for (const QUrl &url : match.urls()) {
        if (url.isLocalFile() && url.fileName().endsWith(QStringLiteral(".desktop"))) {
            return url.toLocalFile();
        }
    }
    return {};
}
