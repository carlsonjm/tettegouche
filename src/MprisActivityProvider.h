#pragma once
#include <QObject>
#include <QDBusConnection>
#include <QMap>
#include <QVariantList>

class MprisSession;
class MprisActivityProvider : public QObject {
    Q_OBJECT
public:
    explicit MprisActivityProvider(const QDBusConnection &bus, QObject *parent = nullptr);
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
private:
    QDBusConnection m_bus;
    QMap<QString, MprisSession *> m_sessions;
    QMap<QString, int> m_ownerEpochs;
    int m_generation = 0;
};
