/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "NotesDoor.h"

#include <KIO/ApplicationLauncherJob>
#include <KService>
#include <KSycoca>

NotesDoor::NotesDoor(QObject *parent)
    : QObject(parent)
{
    // Installed or removed while Search is open, the door follows.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &NotesDoor::refresh);
    refresh();
}

void NotesDoor::refresh()
{
    KServiceAction capture;
    if (const auto service = KService::serviceByStorageId(QString::fromLatin1(ApplicationId))) {
        const auto actions = service->actions();
        for (const KServiceAction &action : actions) {
            if (action.name() == QLatin1String(ActionName)) {
                capture = action;
                break;
            }
        }
    }
    m_capture = capture;
    const bool available = !m_capture.name().isEmpty();
    if (available != m_available) {
        m_available = available;
        Q_EMIT availableChanged();
    }
}

bool NotesDoor::open()
{
    refresh();
    if (!m_available) return false;
    // The action opens a sheet over the screen rather than a window, so
    // nothing waits for a window to arrive.
    auto *job = new KIO::ApplicationLauncherJob(m_capture, this);
    job->start();
    return true;
}
