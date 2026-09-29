#pragma once
#include <BluezQt/Manager>
#include <BluezQt/Device>
#include <BluezQt/InitManagerJob>
#include <QStringList>

// Read-only, event-driven context. Never discovers, pairs or connects devices.
class BluetoothContext final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList connectedDevices READ connectedDevices NOTIFY changed)
public:
    explicit BluetoothContext(QObject *parent = nullptr) : QObject(parent) {
        connect(&m_manager, &BluezQt::Manager::deviceAdded, this, &BluetoothContext::refresh);
        connect(&m_manager, &BluezQt::Manager::deviceRemoved, this, &BluetoothContext::refresh);
        connect(&m_manager, &BluezQt::Manager::deviceChanged, this, &BluetoothContext::refresh);
        connect(&m_manager, &BluezQt::Manager::operationalChanged, this, &BluetoothContext::refresh);
        auto *job = m_manager.init();
        connect(job, &BluezQt::InitManagerJob::result, this, &BluetoothContext::refresh);
        job->start();
    }
    QStringList connectedDevices() const { return m_devices; }
Q_SIGNALS:
    void changed();
private:
    void refresh() {
        QStringList devices;
        if (m_manager.isOperational()) {
            for (const auto &device : m_manager.devices())
                if (device->isConnected()) devices.append(device->name());
        }
        devices.sort(Qt::CaseInsensitive);
        if (devices != m_devices) { m_devices = devices; Q_EMIT changed(); }
    }
    BluezQt::Manager m_manager;
    QStringList m_devices;
};
