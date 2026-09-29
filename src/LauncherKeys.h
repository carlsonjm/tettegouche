/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <QList>
#include <QObject>
#include <QPointer>

#include <functional>
#include <memory>
#include <utility>

class QAction;

// Meta+G for Browse everything and Meta+E for Files, listed once per Plasma
// process in KDE's own shortcut settings under Tettegouche, however many
// Tettegouche widgets that process holds. A press goes to the earliest widget
// still present, so exactly one launcher answers it.
class LauncherKeys final : public QObject
{
    Q_OBJECT

public:
    using Opener = std::function<void(const QString &drawer)>;

    static std::shared_ptr<LauncherKeys> acquire();
    ~LauncherKeys() override;

    void attach(QObject *owner, Opener open);
    void detach(QObject *owner);
    QAction *action(const QString &drawer) const;

private:
    LauncherKeys();
    void press(const QString &drawer);

    QList<std::pair<QPointer<QObject>, Opener>> m_owners;
    QAction *m_apps = nullptr;
    QAction *m_files = nullptr;
};
