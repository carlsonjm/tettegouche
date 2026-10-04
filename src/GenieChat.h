/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>

class QDBusPendingCall;

// Genie's chat, which Search draws in its own window while the assistant
// keeps the conversation. It speaks the assistant's conversation interface on
// the session bus, version 1, and loads none of its code. Genie is offered
// while the assistant is running or can be started from the bus.
class GenieChat : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString phase READ phase NOTIFY conversationChanged)
    Q_PROPERTY(QString assistant READ assistant NOTIFY conversationChanged)
    Q_PROPERTY(QString question READ question NOTIFY conversationChanged)
    Q_PROPERTY(QString answer READ answer NOTIFY conversationChanged)
    Q_PROPERTY(QStringList steps READ steps NOTIFY conversationChanged)
    Q_PROPERTY(QStringList more READ more NOTIFY conversationChanged)
    Q_PROPERTY(QString remember READ remember NOTIFY conversationChanged)
    Q_PROPERTY(bool fixed READ fixed NOTIFY conversationChanged)
    Q_PROPERTY(QStringList suggestions READ suggestions NOTIFY conversationChanged)
    Q_PROPERTY(bool canDoIt READ canDoIt NOTIFY conversationChanged)
    Q_PROPERTY(QString doItReason READ doItReason NOTIFY conversationChanged)
    Q_PROPERTY(bool kept READ kept NOTIFY conversationChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY conversationChanged)

public:
    static constexpr const char *Service = "io.github.carlsonjm.splitrock";
    static constexpr const char *Path = "/Conversation";
    static constexpr const char *Interface = "io.github.carlsonjm.SplitRock.Conversation";
    static constexpr const char *ApplicationId = "io.github.carlsonjm.SplitRock.desktop";
    static constexpr uint Version = 1;

    explicit GenieChat(QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString phase() const { return text(QStringLiteral("phase")); }
    QString assistant() const { return text(QStringLiteral("assistant")); }
    QString question() const { return text(QStringLiteral("question")); }
    QString answer() const { return text(QStringLiteral("answer")); }
    QStringList steps() const { return m_state.value(QStringLiteral("steps")).toStringList(); }
    QStringList suggestions() const { return m_state.value(QStringLiteral("suggestions")).toStringList(); }
    // Added within version 1: the answer's paragraphs after its steps, what
    // the assistant offers to remember about the person, and That fixed it.
    QStringList more() const { return m_state.value(QStringLiteral("more")).toStringList(); }
    QString remember() const { return text(QStringLiteral("remember")); }
    bool fixed() const { return m_state.value(QStringLiteral("fixed")).toBool(); }
    bool canDoIt() const { return m_state.value(QStringLiteral("canDoIt")).toBool(); }
    QString doItReason() const { return text(QStringLiteral("doItReason")); }
    bool kept() const { return m_state.value(QStringLiteral("kept")).toBool(); }
    QString problem() const { return text(QStringLiteral("problem")); }

    // Asks whether the assistant is there and which version it speaks.
    Q_INVOKABLE void refresh();
    // Starts or resumes the conversation.
    Q_INVOKABLE void start();
    Q_INVOKABLE void ask(const QString &question);
    Q_INVOKABLE void cancel();
    // "keep", "show-me-how", "do-it", "remember", "dont-remember" or "fixed".
    Q_INVOKABLE void act(const QString &action);
    // The assistant's full window, on this conversation. The token comes back
    // in windowShown once the window has drawn.
    Q_INVOKABLE bool openWindow(const QString &requestToken);

Q_SIGNALS:
    void availableChanged();
    void conversationChanged();
    void windowShown(const QString &requestToken);

private Q_SLOTS:
    void changedElsewhere(const QVariantMap &state);
    void shown(const QString &requestToken);

private:
    QString text(const QString &key) const { return m_state.value(key).toString(); }
    void call(const QString &method, const QVariantList &arguments = {});
    void setAvailable(bool available);
    void setState(const QVariantMap &state);

    bool m_available = false;
    QVariantMap m_state;
};
