#pragma once
#include <QHash>
#include <QObject>
#include <QPersistentModelIndex>
#include <QPointer>
#include <QVariantList>

class QAbstractItemModel;

// An application waiting on the person, from Plasma's window list: a window
// that raises Plasma's standard attention flag, as an application does while
// its dialog waits behind other work. The row names the application by its
// icon and name and, where its process has one window kept off the task bar,
// that window's title: the dialog's question. Raise asks Plasma to activate
// the window, which brings the application and its dialog forward. The row
// lasts while the flag does; the list is followed as it changes, and nothing
// is asked on a timer.
class WaitingAppProvider : public QObject {
    Q_OBJECT
public:
    // `windows` is Plasma's window list, with libtaskmanager's roles; with
    // none, nothing waits.
    explicit WaitingAppProvider(QAbstractItemModel *windows, QObject *parent = nullptr);
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
Q_SIGNALS:
    void changed();
private:
    struct Waiting { QString window, name, icon, question; QPersistentModelIndex index; int generation = 0; };
    void read();
    QPointer<QAbstractItemModel> m_windows;
    QHash<QString, Waiting> m_waiting;
    int m_generation = 0;
};
