#pragma once
#include <QDBusConnection>
#include <QList>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QDBusMessage;

// Facts from Split Rock's Core, the front desk that watches the computer, such
// as "Storage · 91% full": read from its bus interface while it runs, and
// started by the first call where it is installed. A fact is a row while Core
// says it wants the island; Open asks Core to open the fact's card, and
// setting it aside tells Core the person dismissed it, so Core stays quiet
// about it until it gets worse. Core decides when a fact speaks; nothing here
// is asked on a timer. Without Core there are no rows and no facts.
class CoreFactProvider : public QObject {
    Q_OBJECT
public:
    static constexpr char Service[] = "io.github.carlsonjm.splitrock.Core";
    static constexpr char Path[] = "/Core";
    static constexpr char Interface[] = "io.github.carlsonjm.SplitRock.Core";
    static constexpr uint Version = 1;

    explicit CoreFactProvider(const QDBusConnection &bus, QObject *parent = nullptr);
    // Every fact Core has now, for Search, whatever it asks of the island.
    QList<QVariantMap> facts() const { return m_facts; }
    // The facts that want the island, as Ambient's rows.
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
    // The person set the row aside.
    void dismiss(const QString &id);
    // Asks Core to open a fact's card, as from Search.
    void open(const QString &topic);
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void factChanged(const QVariantMap &fact, const QDBusMessage &message);
private:
    void ask();
    void act(const QString &topic, const QString &action);
    QDBusConnection m_bus;
    QString m_owner;
    QList<QVariantMap> m_facts;
    int m_generation = 0;
};
