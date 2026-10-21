/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once
#include <QDBusConnection>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

class QDBusMessage;

// Ask, from Split Rock, where it is installed: a plain question answered on
// the computer, under Search's Ask chip. Search sends what is typed once the
// typing pauses, shows the words as they come, and lists the Helpers the
// answer names. Ask changes nothing; a Helper opens only from its row. The bus
// starts Ask on the first question. Without it, the chip stays Helpers and
// nothing here is asked. Where Codex is signed in, a bigger fix goes on to it
// on the person's tap, in Codex's own window and under its own name.
class AskClient : public QObject {
    Q_OBJECT
    // Ask is installed: the chip is named Ask, and a question gets an answer.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // idle, asking, answered, needsModel, downloading, off or problem.
    Q_PROPERTY(QString state READ state NOTIFY changed)
    // The question the words answer, and the words so far.
    Q_PROPERTY(QString question READ question NOTIFY changed)
    Q_PROPERTY(QString text READ text NOTIFY changed)
    // Who gave the answer: "computer" for Ask itself.
    Q_PROPERTY(QString who READ who NOTIFY changed)
    // The Helpers the answer names, by Core's ids, best first.
    Q_PROPERTY(QStringList helpers READ helpers NOTIFY changed)
    // What Install an app looks for, where the answer names it.
    Q_PROPERTY(QString query READ query NOTIFY changed)
    // While the model downloads: how far, and its size in words.
    Q_PROPERTY(double progress READ progress NOTIFY changed)
    Q_PROPERTY(QString size READ size NOTIFY changed)
    // Codex is installed and signed in, so the answer offers Ask Codex.
    Q_PROPERTY(bool codexReady READ codexReady NOTIFY codexChanged)
    // Ask handed this question on to Codex itself, by the person's switch.
    Q_PROPERTY(bool handedToCodex READ handedToCodex NOTIFY changed)
public:
    static constexpr char Service[] = "io.github.carlsonjm.splitrock.Ask";
    static constexpr char Path[] = "/Ask";
    static constexpr char Interface[] = "io.github.carlsonjm.SplitRock.Ask";
    static constexpr uint Version = 1;

    explicit AskClient(const QDBusConnection &bus, QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString state() const { return m_state; }
    QString question() const { return m_question; }
    QString text() const { return m_text; }
    QString who() const { return m_who; }
    QStringList helpers() const { return m_helpers; }
    QString query() const { return m_query; }
    double progress() const { return m_progress; }
    QString size() const { return m_size; }
    bool codexReady() const { return m_codexReady; }
    bool handedToCodex() const { return m_handedToCodex; }

    // What is typed now. A question is sent once the typing pauses and it
    // reads as one; anything else clears the answer.
    Q_INVOKABLE void type(const QString &text);
    // Sends what is typed at once.
    Q_INVOKABLE void askNow();
    Q_INVOKABLE void clear();
    // After the person's tap on Download, and Not now.
    Q_INVOKABLE void download();
    Q_INVOKABLE void notNow();
    // After the person's tap on Ask Codex: the question goes to Codex's own
    // window. False where there is nothing to hand on.
    Q_INVOKABLE bool askCodex();

    // Whether these words read as a question to answer, rather than a
    // Helper's name: three words or more, or a question mark.
    static bool readsAsQuestion(const QString &text);
    // How long typing must pause before the question is sent, in ms.
    void setPause(int ms) { m_pause.setInterval(ms); }
Q_SIGNALS:
    void availableChanged();
    void changed();
    void codexChanged();
private Q_SLOTS:
    void said(uint id, const QString &text);
    void answered(uint id, const QVariantMap &result);
    void modelChanged(const QVariantMap &model);
    void codexStateChanged(const QVariantMap &codex);

private:
    void look();
    void send();
    void setState(const QString &state);
    void lookAtCodex();
    QDBusConnection m_bus;
    QTimer m_pause;
    bool m_available = false;
    QString m_typed;
    QString m_question;
    QString m_state = QStringLiteral("idle");
    QString m_text;
    QString m_who;
    QStringList m_helpers;
    QString m_query;
    double m_progress = 0;
    QString m_size;
    bool m_codexReady = false;
    bool m_handedToCodex = false;
    uint m_id = 0;
    // A question sent whose id hasn't come back yet.
    bool m_sending = false;
    // Not now: no download is offered again until the typing is cleared.
    bool m_declined = false;
};
