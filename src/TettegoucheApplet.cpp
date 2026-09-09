/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "TettegoucheApplet.h"

#include <KConfigGroup>
#include <KPluginFactory>
#include <QProcess>
#include <QStandardPaths>

TettegoucheApplet::TettegoucheApplet(QObject *parent,
                                     const KPluginMetaData &data,
                                     const QVariantList &args)
    : Plasma::Applet(parent, data, args)
    , m_process(new QProcess(this))
{
    setHasConfigurationInterface(true);

    connect(m_process, &QProcess::stateChanged, this,
            [this] { Q_EMIT launcherActiveChanged(); });

    connect(this, &Plasma::Applet::activated, this, [this] {
        launch(config().readEntry(QStringLiteral("useKadunce"), true));
    });
}

bool TettegoucheApplet::launcherActive() const
{
    return m_process->state() != QProcess::NotRunning;
}

void TettegoucheApplet::launch(bool useKadunce)
{
    if (launcherActive()) {
        return;
    }

    const QString executable = QStandardPaths::findExecutable(QStringLiteral("tettegouche"));
    if (executable.isEmpty()) {
        return;
    }

    m_process->setProgram(executable);
    m_process->setArguments(useKadunce ? QStringList{}
                                       : QStringList{QStringLiteral("--standalone")});
    m_process->start();
}

K_PLUGIN_CLASS_WITH_JSON(TettegoucheApplet, "metadata.json")

#include "TettegoucheApplet.moc"
