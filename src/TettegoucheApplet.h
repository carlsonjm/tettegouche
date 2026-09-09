/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <Plasma/Applet>

class QProcess;

class TettegoucheApplet final : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(bool launcherActive READ launcherActive NOTIFY launcherActiveChanged)

public:
    TettegoucheApplet(QObject *parent, const KPluginMetaData &data,
                      const QVariantList &args);

    bool launcherActive() const;
    Q_INVOKABLE void launch(bool useKadunce);

Q_SIGNALS:
    void launcherActiveChanged();

private:
    QProcess *m_process = nullptr;
};
