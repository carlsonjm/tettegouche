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
    property string cfg_recentLayout
    property string cfg_recentLayoutDefault
    property int cfg_recentCount
    property int cfg_recentCountDefault
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

        // What was used lately: not at all, one row, or a grid of larger
        // tiles.
        QQC2.ButtonGroup { id: recentChoice }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Recent files and apps:")
            text: i18n("Off")
            QQC2.ButtonGroup.group: recentChoice
            checked: !cfg_offerRecent
            onToggled: if (checked) cfg_offerRecent = false
        }

        QQC2.RadioButton {
            text: i18n("In a row")
            QQC2.ButtonGroup.group: recentChoice
            checked: cfg_offerRecent && cfg_recentLayout === "row"
            onToggled: if (checked) { cfg_offerRecent = true; cfg_recentLayout = "row" }
        }

        QQC2.RadioButton {
            text: i18n("In a grid")
            QQC2.ButtonGroup.group: recentChoice
            checked: cfg_offerRecent && cfg_recentLayout !== "row"
            onToggled: if (checked) { cfg_offerRecent = true; cfg_recentLayout = "grid" }
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("At most:")
            enabled: cfg_offerRecent
            from: 4
            to: 20
            stepSize: 4
            value: cfg_recentCount
            onValueModified: cfg_recentCount = value
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
