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
    // Folder and Stuck to, from an application that offers them; one that
    // does not offers only Belongs to, in choices.
    Q_PROPERTY(bool offersFolders READ offersFolders NOTIFY noteChanged)
    Q_PROPERTY(QString folder READ folder NOTIFY noteChanged)
    Q_PROPERTY(QString folderLabel READ folderLabel NOTIFY noteChanged)
    Q_PROPERTY(QVariantList folders READ folders NOTIFY noteChanged)
    Q_PROPERTY(bool stuck READ stuck NOTIFY noteChanged)
    Q_PROPERTY(QString stuckWindow READ stuckWindow NOTIFY noteChanged)
    Q_PROPERTY(QVariantList windows READ windows NOTIFY noteChanged)
    Q_PROPERTY(QString noteId READ noteId NOTIFY noteChanged)
    Q_PROPERTY(bool kept READ kept NOTIFY noteChanged)
    // Notes 1.1 offers the pin: one note kept in sight on the panel.
    Q_PROPERTY(bool offersPin READ offersPin NOTIFY noteChanged)
    Q_PROPERTY(bool pinned READ pinned NOTIFY noteChanged)
    Q_PROPERTY(bool readOnly READ readOnly NOTIFY noteChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY noteChanged)
    // The reminder and the checklist, from an application that offers them.
    Q_PROPERTY(bool offersReminders READ offersReminders NOTIFY noteChanged)
    Q_PROPERTY(QString remindLabel READ remindLabel NOTIFY noteChanged)
    Q_PROPERTY(QVariantList remindChoices READ remindChoices NOTIFY noteChanged)
    Q_PROPERTY(bool checklist READ checklist NOTIFY noteChanged)
    Q_PROPERTY(QVariantList lines READ lines NOTIFY noteChanged)
    // Every note the application keeps, or those with the words last asked
    // for, newest change first; see findNotes.
    Q_PROPERTY(QVariantList notes READ notes NOTIFY notesChanged)
    Q_PROPERTY(QString notesWords READ notesWords NOTIFY notesChanged)

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
    bool offersFolders() const { return m_state.contains(QStringLiteral("folders")); }
    QString folder() const { return m_state.value(QStringLiteral("folder")).toString(); }
    QString folderLabel() const { return m_state.value(QStringLiteral("folderLabel")).toString(); }
    QVariantList folders() const { return m_state.value(QStringLiteral("folders")).toList(); }
    bool stuck() const { return m_state.value(QStringLiteral("stuck")).toBool(); }
    QString stuckWindow() const { return m_state.value(QStringLiteral("window")).toString(); }
    QVariantList windows() const { return m_state.value(QStringLiteral("windows")).toList(); }
    QString noteId() const { return m_state.value(QStringLiteral("id")).toString(); }
    bool kept() const { return m_state.value(QStringLiteral("kept")).toBool(); }
    bool offersPin() const { return m_state.contains(QStringLiteral("pinned")); }
    bool pinned() const { return m_state.value(QStringLiteral("pinned")).toBool(); }
    bool readOnly() const { return m_state.value(QStringLiteral("readOnly")).toBool(); }
    QString problem() const { return m_state.value(QStringLiteral("problem")).toString(); }
    bool offersReminders() const { return m_state.contains(QStringLiteral("remindChoices")); }
    QString remindLabel() const { return m_state.value(QStringLiteral("remindLabel")).toString(); }
    QVariantList remindChoices() const { return m_state.value(QStringLiteral("remindChoices")).toList(); }
    bool checklist() const { return m_state.value(QStringLiteral("checklist")).toBool(); }
    QVariantList lines() const { return m_state.value(QStringLiteral("lines")).toList(); }
    QVariantList notes() const { return m_notes; }
    QString notesWords() const { return m_notesWords; }

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
    // Keeps the note in that folder, made when new; empty is Inbox.
    Q_INVOKABLE void setFolder(const QString &name);
    // Sticks the note to that window, as windows gives it; empty unsticks it.
    Q_INVOKABLE void setStuck(const QString &window, const QString &app);
    // A time in ISO 8601, "opens", or empty to take the reminder away.
    Q_INVOKABLE void setReminder(const QString &when);
    Q_INVOKABLE void setChecklist(bool on);
    Q_INVOKABLE void setLineChecked(int line, bool checked);
    Q_INVOKABLE void done();
    Q_INVOKABLE void tuckAway();
    Q_INVOKABLE void setPinned(bool on);
    Q_INVOKABLE void remove();
    // The board, as the application's own window, on this note. The token
    // comes back in boardShown once the window has drawn.
    Q_INVOKABLE bool openBoard(const QString &requestToken);
    // Asks for the notes with these words, or every note for none; the
    // answer arrives in notes, and an answer to older words is dropped.
    Q_INVOKABLE void findNotes(const QString &words);
    // Makes that note the open one, to write on as on a started note.
    Q_INVOKABLE void edit(const QString &noteId);
    // Finishes the open note and starts a new one with this text.
    Q_INVOKABLE void startWith(const QString &text);

Q_SIGNALS:
    void availableChanged();
    void noteChanged();
    void boardShown(const QString &requestToken);
    void notesChanged();

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
    QVariantList m_notes;
    QString m_notesWords;
    quint64 m_findSerial = 0;
};
