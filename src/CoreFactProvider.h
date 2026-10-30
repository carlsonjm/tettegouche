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
// about it until it gets worse. A fact that asks a question, such as whether
// to bring back the last sign-in's apps, is answered with its tap, the
// choices Core lists beside it, or Not now; each answer is passed to Core
// as Core names it. Core decides when a fact speaks; nothing here
// is asked on a timer. Core also lists the upkeep cards Search can open by
// their words. Without Core there are no rows, facts or actions.
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
    // The upkeep cards Core can open, each with the words it is found by,
    // for Search.
    QList<QVariantMap> actions() const { return m_actions; }
    // Asks Core to open one on its own, with what was typed.
    void openAction(const QString &id, const QString &query);
    // Whether Core removes apps: it lists Install an app.
    bool removesApps() const;
    // Asks Core to remove the application with that desktop file id, named
    // as Search shows it: Core's Install an app finds what owns it and waits
    // for the person's yes. A Core without RemoveApp is asked by its name.
    void removeApp(const QString &applicationId, const QString &name);
    // The facts that want the island, as Ambient's rows. A row that asks
    // carries `asks`, its `choices` ({action, text} each, in Core's order)
    // and the words for Not now Core gives (`dismissText`), if any.
    QVariantList activities() const;
    // Passes Open, Not now on a fact that asks, "never" for Windows programs
    // and any action that fact lists among its choices to Core.
    void invoke(const QString &id, int generation, const QString &action);
    // The person set the row aside.
    void dismiss(const QString &id);
    // Asks Core to open a fact's card, as from Search.
    void open(const QString &topic);
Q_SIGNALS:
    void changed();
    // The upkeep cards Core lists came or went.
    void actionsChanged();
private Q_SLOTS:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void factChanged(const QVariantMap &fact, const QDBusMessage &message);
private:
    // A fact as it arrives, its choices read from the bus into plain maps.
    static QVariantMap readFact(const QVariantMap &fact);
    void ask();
    void act(const QString &topic, const QString &action);
    QDBusConnection m_bus;
    QString m_owner;
    QList<QVariantMap> m_facts;
    QList<QVariantMap> m_actions;
    int m_generation = 0;
};
