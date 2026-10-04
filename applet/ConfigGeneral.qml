/* SPDX-License-Identifier: GPL-2.0-or-later */

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    property bool cfg_useKadunce
    property bool cfg_useKadunceDefault
    property bool cfg_offerRecent
    property bool cfg_offerRecentDefault
    property bool cfg_offerNotes
    property bool cfg_offerNotesDefault
    property bool cfg_offerGenie
    property bool cfg_offerGenieDefault
    property bool cfg_animateIndicator
    property bool cfg_animateIndicatorDefault

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Kadunce:")
            text: i18n("Open inside Spread when available")
            checked: cfg_useKadunce
            onToggled: cfg_useKadunce = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Search:")
            text: i18n("Show recent files and apps")
            checked: cfg_offerRecent
            onToggled: cfg_offerRecent = checked
        }

        QQC2.CheckBox {
            text: i18n("Show Notes when Gooseberry is installed")
            checked: cfg_offerNotes
            onToggled: cfg_offerNotes = checked
        }

        QQC2.CheckBox {
            text: i18n("Show Genie when Split Rock is installed")
            checked: cfg_offerGenie
            onToggled: cfg_offerGenie = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Motion:")
            text: i18n("Animate the launcher indicator")
            checked: cfg_animateIndicator
            onToggled: cfg_animateIndicator = checked
        }
    }
}
