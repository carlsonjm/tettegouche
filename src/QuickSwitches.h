#pragma once

#include <BluezQt/Adapter>
#include <BluezQt/InitManagerJob>
#include <BluezQt/Manager>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDateTime>
#include <QObject>
#include <notificationmanager/settings.h>

// The switches a quick action sets from Search: Do not disturb, Bluetooth and
// Keep awake. Each is set where it is kept, so the notification bell, Status
// and System Settings all show the change and none of it needs Search to
// stay open: Do not disturb is Plasma's own timed setting, Bluetooth is the
// adapters' own power, and Keep awake is Temperance's, asked at its door on
// the session bus (Temperance's docs/PANELS.md, Keep awake) and offered only
// while that door is there. The last change can be taken back.
class QuickSwitches final : public QObject
{
    Q_OBJECT
    // Whether this computer has Bluetooth to switch.
    Q_PROPERTY(bool bluetoothThere READ bluetoothThere NOTIFY changed)
    Q_PROPERTY(bool bluetoothOn READ bluetoothOn NOTIFY changed)
    Q_PROPERTY(bool doNotDisturbOn READ doNotDisturbOn NOTIFY changed)
    // Whether Temperance's Keep awake is there to ask, and how it stands.
    Q_PROPERTY(bool keepAwakeThere READ keepAwakeThere NOTIFY changed)
    Q_PROPERTY(bool keepAwakeOn READ keepAwakeOn NOTIFY changed)
    // Whether the last change can still be taken back.
    Q_PROPERTY(bool undoable READ undoable NOTIFY undoableChanged)
public:
    static constexpr char AwakeService[] = "co.goodinput.Temperance";
    static constexpr char AwakePath[] = "/KeepAwake";
    static constexpr char AwakeInterface[] = "co.goodinput.Temperance.KeepAwake";

    explicit QuickSwitches(QObject *parent = nullptr) : QObject(parent)
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        auto *watcher = new QDBusServiceWatcher(QLatin1String(AwakeService), bus,
            QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
        connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { awakeThere(true); });
        connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] { awakeThere(false); });
        bus.connect(QLatin1String(AwakeService), QLatin1String(AwakePath), QLatin1String(AwakeInterface),
                    QStringLiteral("Changed"), this, SLOT(awakeChanged(bool, QString)));
        awakeThere(bus.isConnected() && bus.interface()
                   && bus.interface()->isServiceRegistered(QLatin1String(AwakeService)));

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
    bool keepAwakeThere() const { return m_awakeThere; }
    bool keepAwakeOn() const { return m_awakeOn; }
    bool undoable() const { return !m_undoKind.isEmpty(); }

    // Sets the switch `kind` ("doNotDisturb", "bluetooth" or "keepAwake").
    // `until`, ISO 8601, is when Do not disturb or Keep awake ends by
    // itself. Without it Do not disturb stays on until it is turned off,
    // which Plasma keeps as a year ahead, and Keep awake until sign-out.
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
        if (kind == QLatin1String("keepAwake")) {
            if (!m_awakeThere) return false;
            const bool beforeOn = m_awakeOn;
            const QString beforeUntil = m_awakeUntil;
            if (!awake(on, on ? until : QString())) return false;
            m_awakeBeforeOn = beforeOn;
            m_awakeBeforeUntil = beforeUntil;
            remember(kind, {});
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
        else if (m_undoKind == QLatin1String("keepAwake")) {
            // A time it had before that has since gone is off.
            const QDateTime end = QDateTime::fromString(m_awakeBeforeUntil, Qt::ISODate);
            const bool gone = !m_awakeBeforeUntil.isEmpty() && end <= QDateTime::currentDateTime();
            awake(m_awakeBeforeOn && !gone, gone ? QString() : m_awakeBeforeUntil);
        }
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

private Q_SLOTS:
    void awakeChanged(bool on, const QString &until)
    {
        if (on == m_awakeOn && until == m_awakeUntil) return;
        m_awakeOn = on;
        m_awakeUntil = until;
        Q_EMIT changed();
    }

private:
    static QDBusMessage awakeCall(const QString &method)
    {
        return QDBusMessage::createMethodCall(QLatin1String(AwakeService), QLatin1String(AwakePath),
                                              QLatin1String(AwakeInterface), method);
    }
    // Asks the door and waits a moment for its answer: the row says at once
    // whether it was done.
    bool awake(bool on, const QString &until)
    {
        QDBusMessage message = awakeCall(QStringLiteral("Set"));
        message << on << until;
        const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 1500);
        if (reply.type() != QDBusMessage::ReplyMessage || !reply.arguments().value(0).toBool()) return false;
        awakeChanged(on, until);
        return true;
    }
    void awakeThere(bool there)
    {
        if (!there) {
            m_awakeOn = false;
            m_awakeUntil.clear();
        }
        if (m_awakeThere != there) {
            m_awakeThere = there;
            Q_EMIT changed();
        }
        if (!there) return;
        // How it stands now; Changed keeps it from here on.
        auto *active = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(awakeCall(QStringLiteral("Active"))), this);
        connect(active, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
            watcher->deleteLater();
            const QDBusPendingReply<bool> on = *watcher;
            if (on.isError()) return;
            auto *until = new QDBusPendingCallWatcher(
                QDBusConnection::sessionBus().asyncCall(awakeCall(QStringLiteral("Until"))), this);
            connect(until, &QDBusPendingCallWatcher::finished, this, [this, on](QDBusPendingCallWatcher *watcher) {
                watcher->deleteLater();
                const QDBusPendingReply<QString> end = *watcher;
                awakeChanged(on.value(), end.isError() ? QString() : end.value());
            });
        });
    }
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
    bool m_awakeThere = false;
    bool m_awakeOn = false;
    QString m_awakeUntil;
    bool m_awakeBeforeOn = false;
    QString m_awakeBeforeUntil;
};
