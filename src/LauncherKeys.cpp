/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "LauncherKeys.h"

#include <KGlobalAccel>
#include <QAction>

namespace
{
QAction *drawerAction(QObject *parent, const QString &name, const QString &text,
                      const QKeySequence &key)
{
    auto *action = new QAction(text, parent);
    action->setObjectName(name);
    // Its own entry in System Settings, not one more line under Plasma.
    action->setProperty("componentName", QStringLiteral("tettegouche"));
    action->setProperty("componentDisplayName", QStringLiteral("Tettegouche"));
    // A key the person chose in System Settings is kept over this default.
    KGlobalAccel::self()->setGlobalShortcut(action, key);
    return action;
}
}

std::shared_ptr<LauncherKeys> LauncherKeys::acquire()
{
    static std::weak_ptr<LauncherKeys> instance;
    auto keys = instance.lock();
    if (!keys) {
        keys = std::shared_ptr<LauncherKeys>(new LauncherKeys);
        instance = keys;
    }
    return keys;
}

LauncherKeys::LauncherKeys()
{
    m_apps = drawerAction(this, QStringLiteral("open-apps-drawer"),
                          tr("Open Browse everything"), QKeySequence(Qt::META | Qt::Key_G));
    m_files = drawerAction(this, QStringLiteral("open-files-drawer"),
                           tr("Open Files"), QKeySequence(Qt::META | Qt::Key_E));
    connect(m_apps, &QAction::triggered, this, [this] { press(QStringLiteral("apps")); });
    connect(m_files, &QAction::triggered, this, [this] { press(QStringLiteral("files")); });
}

LauncherKeys::~LauncherKeys() = default;

void LauncherKeys::attach(QObject *owner, Opener open)
{
    detach(owner);
    m_owners.append({QPointer<QObject>(owner), std::move(open)});
}

void LauncherKeys::detach(QObject *owner)
{
    m_owners.removeIf([owner](const auto &entry) { return !entry.first || entry.first == owner; });
}

QAction *LauncherKeys::action(const QString &drawer) const
{
    return drawer == QLatin1String("files") ? m_files : drawer == QLatin1String("apps") ? m_apps : nullptr;
}

void LauncherKeys::press(const QString &drawer)
{
    for (const auto &[owner, open] : std::as_const(m_owners)) {
        if (owner) {
            open(drawer);
            return;
        }
    }
}
