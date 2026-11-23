/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QStringList>

#include <QDBusMessage>

// The saved layouts pinned to Shuffle's dock, for the Layouts card's "Pin to
// dock" and "Unpin from dock". The dock publishes them on its bus name,
// co.goodinput.BottomSurface, and pins or unpins one when asked, as its own
// sheet does. Without the dock there is nothing to pin to: `present` is false
// and the card offers no pin. The dock's sheet asks for every layout through
// the same name (`layoutsRequested`), on the display it is on.
class DockLayoutPins : public QObject
{
    Q_OBJECT
public:
    static constexpr char Service[] = "co.goodinput.BottomSurface";
    static constexpr char Path[] = "/BottomSurface";
    static constexpr char Interface[] = "co.goodinput.BottomSurface";

    explicit DockLayoutPins(const QDBusConnection &bus, QObject *parent = nullptr);

    // The dock answered what it pins.
    bool present() const { return m_present; }
    // The pinned layouts' ids, in the dock's order.
    QStringList pinned() const { return m_pinned; }
    // Asks the dock to pin or unpin the layout. Shown at once; the dock's
    // own list follows.
    void pin(const QString &id, bool pin);

Q_SIGNALS:
    void changed();
    void layoutsRequested(const QString &output);

private Q_SLOTS:
    void pinnedMoved(const QDBusMessage &message);
    void layoutsAsked(const QString &output, const QDBusMessage &message);

private:
    void ask();
    void ownerChanged(const QString &owner);

    QDBusConnection m_bus;
    QString m_owner;
    bool m_present = false;
    QStringList m_pinned;
    quint64 m_generation = 0;
};
