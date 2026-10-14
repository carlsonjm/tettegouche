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
    return 0;
}
