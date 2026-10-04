/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KServiceAction>

#include <QObject>

// The Notes door on Search's first screen. It is offered only while the notes
// application is installed with its Capture action, and opening it runs that
// action, which brings the application's quick-note sheet. Tettegouche works
// the same without the application.
class NotesDoor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    static constexpr const char *ApplicationId = "io.github.carlsonjm.Gooseberry.desktop";
    static constexpr const char *ActionName = "Capture";

    explicit NotesDoor(QObject *parent = nullptr);

    bool available() const { return m_available; }

    // Looks again for the application, as when Search opens.
    Q_INVOKABLE void refresh();
    // Runs the Capture action. False when the application is not there.
    Q_INVOKABLE bool open();

Q_SIGNALS:
    void availableChanged();

private:
    KServiceAction m_capture;
    bool m_available = false;
};
