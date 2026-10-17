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
    property bool cfg_recentApps
    property bool cfg_recentAppsDefault
    property bool cfg_recentFiles
    property bool cfg_recentFilesDefault
    property bool cfg_offerNotes
    property bool cfg_offerNotesDefault
    property bool cfg_showNotesPill
    property bool cfg_showNotesPillDefault
    property bool cfg_showAmbient
    property bool cfg_showAmbientDefault
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

        // What was used lately: apps, files, both or neither. What is on
        // decides how tall Search rests.
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Search shows:")
            text: i18n("Recent apps")
            checked: cfg_offerRecent && cfg_recentApps
            // Older settings turned both off at once; turning one back on
            // brings only that one.
            onToggled: {
                if (checked && !cfg_offerRecent) { cfg_recentFiles = false; cfg_offerRecent = true }
                cfg_recentApps = checked
            }
        }

        QQC2.CheckBox {
            text: i18n("Recent files")
            checked: cfg_offerRecent && cfg_recentFiles
            onToggled: {
                if (checked && !cfg_offerRecent) { cfg_recentApps = false; cfg_offerRecent = true }
                cfg_recentFiles = checked
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Notes:")
            text: i18n("Show Notes when Gooseberry is installed")
            checked: cfg_offerNotes
            onToggled: cfg_offerNotes = checked
        }

        QQC2.CheckBox {
            text: i18n("Show the Notes pill")
            enabled: cfg_offerNotes
            checked: cfg_showNotesPill
            onToggled: cfg_showNotesPill = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Ambient:")
            text: i18n("Show islands beside the launcher")
            checked: cfg_showAmbient
            onToggled: cfg_showAmbient = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Motion:")
            text: i18n("Animate the launcher indicator")
            checked: cfg_animateIndicator
            onToggled: cfg_animateIndicator = checked
        }
    }
}
