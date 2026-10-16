#include "DockBand.h"

int main()
{
    const QByteArray presenting = R"({"schema":"co.goodinput.shuffle.dock-extent","version":1,"output":"DP-1",)"
        R"("presenting":true,"reserving":true,"band":{"height":56}})";
    if (dockBandHeight(presenting) != 56) return 1;
    // Without the reserving field, the band is still held.
    if (dockBandHeight(R"({"schema":"co.goodinput.shuffle.dock-extent","version":1,"presenting":true,"band":{"height":56}})") != 56) return 2;
    // Given up to the keys, or not presenting, or another schema: nothing.
    if (dockBandHeight(R"({"schema":"co.goodinput.shuffle.dock-extent","version":1,"presenting":true,"reserving":false,"band":{"height":56}})") != 0) return 3;
    if (dockBandHeight(R"({"schema":"co.goodinput.shuffle.dock-extent","version":1,"presenting":false,"band":{"height":0}})") != 0) return 4;
    if (dockBandHeight(R"({"schema":"co.goodinput.shuffle.dock-extent","version":2,"presenting":true,"band":{"height":56}})") != 0) return 5;
    if (dockBandHeight("not json") != 0) return 6;

    // A monitor reported whole loses the band at its bottom.
    const QSize monitor(2560, 1440);
    if (workArea(QRect(QPoint(), monitor), monitor, 56) != QRect(0, 0, 2560, 1384)) return 7;
    // A report that already leaves the band out is kept.
    if (workArea(QRect(0, 0, 2560, 1384), monitor, 56) != QRect(0, 0, 2560, 1384)) return 8;
    // No dock, no change.
    if (workArea(QRect(QPoint(), monitor), monitor, 0) != QRect(QPoint(), monitor)) return 9;

    const QByteArray bar = R"({"available":{"left":648,"right":650},"bar":{"height":24},)"
        R"("clock":{"center":732,"left":678,"right":787},"output":"eDP-1","presenting":true,)"
        R"("schema":"co.goodinput.shuffle.clock-extent","version":1})";
    if (contextBarHeight(bar) != 24) return 10;
    // No bar on that display, another schema, or not an answer: nothing.
    if (contextBarHeight(R"({"schema":"co.goodinput.shuffle.clock-extent","version":1,"presenting":false,"bar":{"height":24}})") != 0) return 11;
    if (contextBarHeight(R"({"schema":"co.goodinput.shuffle.dock-extent","version":1,"presenting":true,"bar":{"height":24}})") != 0) return 12;
    if (contextBarHeight("not json") != 0) return 13;
    // A display reported whole loses the bar at its top and the band at its
    // bottom.
    if (workArea(QRect(QPoint(), monitor), monitor, 56, 24) != QRect(0, 24, 2560, 1360)) return 14;
    // A report that already starts below the bar keeps its own edge.
    if (workArea(QRect(0, 30, 2560, 1354), monitor, 56, 24) != QRect(0, 30, 2560, 1354)) return 15;
    // A report that stops short of the edges, but not of the bar and band,
    // is cut back to them.
    if (workArea(QRect(0, 8, 2560, 1424), monitor, 56, 24) != QRect(0, 24, 2560, 1360)) return 16;
    return 0;
}
