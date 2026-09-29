#include "RelatedInfo.h"
#include <QCoreApplication>
#include <QTimer>
#include <iostream>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc > 1) {
        RelatedInfo info;
        const auto key = QString::fromLocal8Bit(argv[1]);
        info.items(key);
        QTimer::singleShot(2500, &app, [&]() {
            std::cout << key.toStdString() << ": " << info.items(key).size() << " child rows\n";
            app.quit();
        });
        return app.exec();
    }
    if (RelatedInfo::keyForSetting(QStringLiteral("krunner_systemsettings_kcm_pulseaudio")) != QStringLiteral("audio")) return 1;
    if (!RelatedInfo::keyForSetting(QStringLiteral("some-file-kcm_pulseaudio.txt")).isEmpty()) return 2;
    const auto audio = RelatedInfo::audioRows(R"([{"name":"speaker","description":"Speakers","mute":true},{"name":"speaker.monitor","description":"Monitor"}])", QStringLiteral("Output"));
    if (audio.size() != 1 || !audio.first().toMap().value(QStringLiteral("status")).toString().contains(QStringLiteral("Muted"))) return 3;
    const auto display = RelatedInfo::displayRows(R"({"outputs":[{"name":"Panel","connected":true,"enabled":true,"currentModeId":"1","scale":1.5,"modes":[{"id":"1","name":"2560x1600@180"}]},{"connected":false}]})");
    if (display.size() != 1 || !display.first().toMap().value(QStringLiteral("status")).toString().contains(QStringLiteral("150%"))) return 4;
    const auto network = RelatedInfo::networkRows("Home:Office:802-11-wireless:wlan0\nlo:loopback:lo\nWork:vpn:tun0\n");
    if (network.size() != 2 || network.first().toMap().value(QStringLiteral("label")).toString() != QStringLiteral("Home:Office")) return 5;
    if (!RelatedInfo::displayRows("invalid").isEmpty() || !RelatedInfo::audioRows("{}", {}).isEmpty()) return 6;
    return 0;
}
