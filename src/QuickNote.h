/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class QDBusPendingCall;

// The quick note Search draws in its own window while the notes application
// keeps it. It speaks the application's quick-note interface on the session
// bus, version 1, and loads none of its code; every change is written by the
// application before its reply, and the reply is the note as it is kept.
class QuickNote : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool open READ isOpen NOTIFY noteChanged)
    Q_PROPERTY(QString text READ text NOTIFY noteChanged)
    Q_PROPERTY(QString colour READ colour NOTIFY noteChanged)
    Q_PROPERTY(QStringList colours READ colours NOTIFY noteChanged)
    Q_PROPERTY(QStringList colourHexes READ colourHexes NOTIFY noteChanged)
    Q_PROPERTY(QString colourHex READ colourHex NOTIFY noteChanged)
    Q_PROPERTY(QVariantList choices READ choices NOTIFY noteChanged)
    Q_PROPERTY(QString noteId READ noteId NOTIFY noteChanged)
    Q_PROPERTY(bool kept READ kept NOTIFY noteChanged)
    Q_PROPERTY(bool readOnly READ readOnly NOTIFY noteChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY noteChanged)

public:
    static constexpr const char *Service = "io.github.carlsonjm.gooseberry";
    static constexpr const char *Path = "/QuickNote";
    static constexpr const char *Interface = "io.github.carlsonjm.Gooseberry.QuickNote";
    static constexpr uint Version = 1;
    // As the application's own card: written half a second after the typing
    // pauses, and never more than three seconds after the first change.
    static constexpr int PauseMs = 500;
    static constexpr int LongestWaitMs = 3000;

    explicit QuickNote(QObject *parent = nullptr);
    ~QuickNote() override;

    bool available() const { return m_available; }
    bool isOpen() const { return m_state.value(QStringLiteral("open")).toBool(); }
    QString text() const { return m_state.value(QStringLiteral("text")).toString(); }
    QString colour() const { return m_state.value(QStringLiteral("colour")).toString(); }
    QStringList colours() const { return m_state.value(QStringLiteral("colours")).toStringList(); }
    QStringList colourHexes() const { return m_state.value(QStringLiteral("colourHexes")).toStringList(); }
    QString colourHex() const;
    QVariantList choices() const;
    QString noteId() const { return m_state.value(QStringLiteral("id")).toString(); }
    bool kept() const { return m_state.value(QStringLiteral("kept")).toBool(); }
    bool readOnly() const { return m_state.value(QStringLiteral("readOnly")).toBool(); }
    QString problem() const { return m_state.value(QStringLiteral("problem")).toString(); }

    // Asks the application which version it speaks, starting it if needed.
    Q_INVOKABLE void refresh();
    // Starts a note, or resumes the one the last start began.
    Q_INVOKABLE void start();
    // Typing: kept here and sent at the next pause.
    Q_INVOKABLE void setText(const QString &text);
    // Sends typing still waiting for a pause.
    Q_INVOKABLE void flush();
    Q_INVOKABLE void setColour(const QString &name);
    Q_INVOKABLE void setBelongs(const QString &kind, const QString &project);
    Q_INVOKABLE void done();
    Q_INVOKABLE void tuckAway();
    Q_INVOKABLE void remove();
    // The board, as the application's own window, on this note. The token
    // comes back in boardShown once the window has drawn.
    Q_INVOKABLE bool openBoard(const QString &requestToken);

Q_SIGNALS:
    void availableChanged();
    void noteChanged();
    void boardShown(const QString &requestToken);

private Q_SLOTS:
    void changedElsewhere(const QVariantMap &state);
    void shown(const QString &requestToken);

private:
    void call(const QString &method, const QVariantList &arguments = {});
    void take(const QDBusPendingCall &call);
    void setState(const QVariantMap &state);

    bool m_available = false;
    QVariantMap m_state;
    QString m_pending;
    bool m_hasPending = false;
    QTimer m_pause;
    QElapsedTimer m_waiting;
};
