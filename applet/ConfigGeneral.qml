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
    property bool cfg_showHelpersPill
    property bool cfg_showHelpersPillDefault
    property bool cfg_quickActions
    property bool cfg_quickActionsDefault
    property string cfg_quickActionsPlace
    property string cfg_quickActionsPlaceDefault
    property bool cfg_quickSwitchesOpenPage
    property bool cfg_quickSwitchesOpenPageDefault
    property string cfg_quickReminderTime
    property string cfg_quickReminderTimeDefault
    property bool cfg_quickActionReminder
    property bool cfg_quickActionReminderDefault
    property bool cfg_quickActionNote
    property bool cfg_quickActionNoteDefault
    property bool cfg_quickActionKeepAwake
    property bool cfg_quickActionKeepAwakeDefault
    property bool cfg_quickActionDoNotDisturb
    property bool cfg_quickActionDoNotDisturbDefault
    property bool cfg_quickActionBluetooth
    property bool cfg_quickActionBluetoothDefault
    property bool cfg_showAmbient
    property bool cfg_showAmbientDefault
    property bool cfg_showQuickNote
    property bool cfg_showQuickNoteDefault
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
            Kirigami.FormData.label: i18n("Helpers:")
            text: i18n("Show the Helpers pill when Split Rock is installed")
            checked: cfg_showHelpersPill
            onToggled: cfg_showHelpersPill = checked
        }

        // Quick actions: whether typed words such as "remind me to call the
        // bank at 3" are offered as something to do, where, and which.
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Quick actions:")
            text: i18n("Offer to do what the typed words say")
            checked: cfg_quickActions
            onToggled: cfg_quickActions = checked
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("The action shows:")
            enabled: cfg_quickActions
            model: [i18n("Above the results"), i18n("Among the results")]
            currentIndex: cfg_quickActionsPlace === "among" ? 1 : 0
            onActivated: index => cfg_quickActionsPlace = index === 1 ? "among" : "above"
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Switches such as Bluetooth:")
            enabled: cfg_quickActions
            model: [i18n("Change in Search"), i18n("Open the switch's page")]
            currentIndex: cfg_quickSwitchesOpenPage ? 1 : 0
            onActivated: index => cfg_quickSwitchesOpenPage = index === 1
        }

        // The time a reminder for a day with no time, "tomorrow" or "on
        // Friday", is set for, as hours and minutes on a 24-hour clock.
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Default reminder time:")
            enabled: cfg_quickActions
            text: cfg_quickReminderTime
            placeholderText: "09:00"
            inputMask: "99:99"
            validator: RegularExpressionValidator { regularExpression: /^([01][0-9]|2[0-3]):[0-5][0-9]$/ }
            onEditingFinished: if (acceptableInput) cfg_quickReminderTime = text
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Actions:")
            enabled: cfg_quickActions
            text: i18n("Reminder")
            checked: cfg_quickActionReminder
            onToggled: cfg_quickActionReminder = checked
        }

        QQC2.CheckBox {
            enabled: cfg_quickActions
            text: i18n("Note")
            checked: cfg_quickActionNote
            onToggled: cfg_quickActionNote = checked
        }

        QQC2.CheckBox {
            enabled: cfg_quickActions
            text: i18n("Keep awake")
            checked: cfg_quickActionKeepAwake
            onToggled: cfg_quickActionKeepAwake = checked
        }

        QQC2.CheckBox {
            enabled: cfg_quickActions
            text: i18n("Do not disturb")
            checked: cfg_quickActionDoNotDisturb
            onToggled: cfg_quickActionDoNotDisturb = checked
        }

        QQC2.CheckBox {
            enabled: cfg_quickActions
            text: i18n("Bluetooth")
            checked: cfg_quickActionBluetooth
            onToggled: cfg_quickActionBluetooth = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Ambient:")
            text: i18n("Show islands beside the launcher")
            checked: cfg_showAmbient
            onToggled: cfg_showAmbient = checked
        }

        QQC2.CheckBox {
            text: i18n("Show the quick note island")
            enabled: cfg_showAmbient
            checked: cfg_showQuickNote
            onToggled: cfg_showQuickNote = checked
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Motion:")
            text: i18n("Animate the launcher indicator")
            checked: cfg_animateIndicator
            onToggled: cfg_animateIndicator = checked
        }
    }
}
