/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    property bool cfg_useKadunce
    property bool cfg_useKadunceDefault
    property bool cfg_animateIndicator
    property bool cfg_animateIndicatorDefault

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Kadunce:")
            text: i18n("Open inside Card Line when available")
            checked: cfg_useKadunce
            onToggled: cfg_useKadunce = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Motion:")
            text: i18n("Animate the launcher indicator")
            checked: cfg_animateIndicator
            onToggled: cfg_animateIndicator = checked
        }
    }
}
