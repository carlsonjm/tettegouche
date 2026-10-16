#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRect>
#include <QSize>

#include <algorithm>

// The height Shuffle's dock reserves along the bottom of a display, read from
// its dock-extent answer (version 1). Zero when the answer is not one, the
// surface does not present there, or it has given its band up to the keys.
inline int dockBandHeight(const QByteArray &payload)
{
    const QJsonObject extent = QJsonDocument::fromJson(payload).object();
    if (extent.value(QStringLiteral("schema")).toString() != QStringLiteral("co.goodinput.shuffle.dock-extent")
        || extent.value(QStringLiteral("version")).toInt() != 1
        || !extent.value(QStringLiteral("presenting")).toBool()
        || !extent.value(QStringLiteral("reserving")).toBool(true)) return 0;
    return std::max(0, extent.value(QStringLiteral("band")).toObject().value(QStringLiteral("height")).toInt());
}

// The height of Shuffle's Context Bar along the top of a display, read from
// its clock-extent answer (version 1). Zero when the answer is not one or no
// bar presents there.
inline int contextBarHeight(const QByteArray &payload)
{
    const QJsonObject extent = QJsonDocument::fromJson(payload).object();
    if (extent.value(QStringLiteral("schema")).toString() != QStringLiteral("co.goodinput.shuffle.clock-extent")
        || extent.value(QStringLiteral("version")).toInt() != 1
        || !extent.value(QStringLiteral("presenting")).toBool()) return 0;
    return std::max(0, extent.value(QStringLiteral("bar")).toObject().value(QStringLiteral("height")).toInt());
}

// The room Search may fill on a display: what the screen reports as
// available, less a dock band along the bottom and a Context Bar along the
// top that the report still reaches over. Qt on Wayland reports the whole
// display, so both come off here; a report that already stops short of an
// edge keeps its own where it stops farther, and is cut back to the bar or
// band where it stops short of them.
inline QRect workArea(QRect available, const QSize &screen, int band, int bar = 0)
{
    if (band > 0 && available.bottom() > screen.height() - 1 - band)
        available.setBottom(std::max(available.top(), screen.height() - 1 - band));
    if (bar > 0 && available.top() < bar)
        available.setTop(std::min(available.bottom(), bar));
    return available;
}
