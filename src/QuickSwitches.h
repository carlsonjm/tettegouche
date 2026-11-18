#pragma once

#include <BluezQt/Adapter>
#include <BluezQt/InitManagerJob>
#include <BluezQt/Manager>
#include <QDateTime>
#include <QObject>
#include <notificationmanager/settings.h>

// The switches a quick action sets from Search: Do not disturb and Bluetooth.
// Each is set where Plasma itself keeps it, so the notification bell, Status
// and System Settings all show the change and none of it needs Search to
// stay open: Do not disturb is Plasma's own timed setting, and Bluetooth is
// the adapters' own power. The last change can be taken back.
class QuickSwitches final : public QObject
{
    Q_OBJECT
    // Whether this computer has Bluetooth to switch.
    Q_PROPERTY(bool bluetoothThere READ bluetoothThere NOTIFY changed)
    Q_PROPERTY(bool bluetoothOn READ bluetoothOn NOTIFY changed)
    Q_PROPERTY(bool doNotDisturbOn READ doNotDisturbOn NOTIFY changed)
    // Whether the last change can still be taken back.
    Q_PROPERTY(bool undoable READ undoable NOTIFY undoableChanged)
public:
    explicit QuickSwitches(QObject *parent = nullptr) : QObject(parent)
    {
        m_settings.setLive(true);
        connect(&m_settings, &NotificationManager::Settings::settingsChanged, this, &QuickSwitches::changed);
        connect(&m_manager, &BluezQt::Manager::adapterAdded, this, &QuickSwitches::changed);
        connect(&m_manager, &BluezQt::Manager::adapterRemoved, this, &QuickSwitches::changed);
        connect(&m_manager, &BluezQt::Manager::adapterChanged, this, &QuickSwitches::changed);
        connect(&m_manager, &BluezQt::Manager::bluetoothBlockedChanged, this, &QuickSwitches::changed);
        connect(&m_manager, &BluezQt::Manager::bluetoothOperationalChanged, this, &QuickSwitches::changed);
        auto *job = m_manager.init();
        connect(job, &BluezQt::InitManagerJob::result, this, &QuickSwitches::changed);
        job->start();
    }

    bool bluetoothThere() const { return !m_manager.adapters().isEmpty() || m_manager.isBluetoothBlocked(); }
    bool bluetoothOn() const { return m_manager.isBluetoothOperational(); }
    bool doNotDisturbOn() const
    {
        const QDateTime until = m_settings.notificationsInhibitedUntil();
        return until.isValid() && until > QDateTime::currentDateTime();
    }
    bool undoable() const { return !m_undoKind.isEmpty(); }

    // Sets the switch `kind` ("doNotDisturb" or "bluetooth"). `until`, ISO
    // 8601, is when Do not disturb ends by itself; without it, it stays on
    // until it is turned off, which Plasma keeps as a year ahead.
    Q_INVOKABLE bool set(const QString &kind, bool on, const QString &until = {})
    {
        if (kind == QLatin1String("doNotDisturb")) {
            const QDateTime before = doNotDisturbOn() ? m_settings.notificationsInhibitedUntil() : QDateTime();
            QDateTime end;
            if (on) {
                end = QDateTime::fromString(until, Qt::ISODate);
                if (!until.isEmpty() && (!end.isValid() || end <= QDateTime::currentDateTime())) return false;
                if (!end.isValid()) end = QDateTime::currentDateTime().addYears(1);
            }
            quiet(end);
            remember(kind, before);
            return true;
        }
        if (kind == QLatin1String("bluetooth")) {
            if (!bluetoothThere()) return false;
            const bool before = bluetoothOn();
            power(on);
            m_bluetoothBefore = before;
            remember(kind, {});
            return true;
        }
        return false;
    }

    // Puts the last switch back as it was before `set`.
    Q_INVOKABLE void undo()
    {
        if (m_undoKind == QLatin1String("doNotDisturb"))
            quiet(m_quietBefore.isValid() && m_quietBefore > QDateTime::currentDateTime() ? m_quietBefore : QDateTime());
        else if (m_undoKind == QLatin1String("bluetooth"))
            power(m_bluetoothBefore);
        forget();
    }

    // What was set stands: there is nothing to take back any more.
    Q_INVOKABLE void forget()
    {
        if (m_undoKind.isEmpty()) return;
        m_undoKind.clear();
        Q_EMIT undoableChanged();
    }

Q_SIGNALS:
    void changed();
    void undoableChanged();

private:
    void quiet(const QDateTime &until)
    {
        m_settings.setNotificationsInhibitedUntil(until);
        // Off is off for all of it, as Plasma's own switch is.
        if (!until.isValid()) m_settings.revokeApplicationInhibitions();
        m_settings.save();
        Q_EMIT changed();
    }
    void power(bool on)
    {
        m_manager.setBluetoothBlocked(!on);
        const auto adapters = m_manager.adapters();
        for (const BluezQt::AdapterPtr &adapter : adapters) adapter->setPowered(on);
    }
    void remember(const QString &kind, const QDateTime &quietBefore)
    {
        m_undoKind = kind;
        m_quietBefore = quietBefore;
        Q_EMIT undoableChanged();
    }

    NotificationManager::Settings m_settings;
    BluezQt::Manager m_manager;
    QString m_undoKind;
    QDateTime m_quietBefore;
    bool m_bluetoothBefore = false;
};
