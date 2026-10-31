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
// on the person's tap, in Codex's own window and under its own name. An
// answer that would write in one of the person's apps, such as keeping it in
// Notes, comes with a Do it card; the write is made by Split Rock's broker,
// once, only on the person's tap on it, and the card then says how it went.
class AskClient : public QObject {
    Q_OBJECT
    // Ask is installed: the chip is named Ask, and a question gets an answer.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // idle, asking, answered, needsModel, codexOnly, downloading, off or
    // problem.
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
    // The model's name, such as Qwen3 4B, and whose it is, as its licence asks.
    Q_PROPERTY(QString modelName READ modelName NOTIFY changed)
    Q_PROPERTY(QString modelCredit READ modelCredit NOTIFY changed)
    // Codex is installed and signed in, so the answer offers Ask Codex.
    Q_PROPERTY(bool codexReady READ codexReady NOTIFY codexChanged)
    // Ask handed this question on to Codex itself, by the person's switch.
    Q_PROPERTY(bool handedToCodex READ handedToCodex NOTIFY changed)
    // Before the model: llama.cpp, which runs it, isn't installed either.
    Q_PROPERTY(bool needsEngine READ needsEngine NOTIFY changed)
    // Codex is installed, signed in or not, so Codex only can be offered.
    Q_PROPERTY(bool codexInstalled READ codexInstalled NOTIFY codexChanged)
    // The person chose Codex only: every question waits for Ask Codex.
    Q_PROPERTY(bool codexOnly READ codexOnly NOTIFY codexChanged)
    // What the apps' tools read for the answer, by name, such as each note's
    // title.
    Q_PROPERTY(QStringList read READ read NOTIFY changed)
    // The answer's Do it card from an app's tool: its title (the first words
    // it writes), what it does, the app's name and the tool; empty when
    // there is none.
    Q_PROPERTY(QVariantMap doIt READ doIt NOTIFY changed)
    // How the card's write went: empty until the tap, then running, done or
    // failed, with the broker's problem in words when it says one.
    Q_PROPERTY(QString doItState READ doItState NOTIFY changed)
    Q_PROPERTY(QString doItProblem READ doItProblem NOTIFY changed)
    // The notes an answer names where something was written down, each its
    // id and title, for one tap to open; never their words.
    Q_PROPERTY(QVariantList notes READ notes NOTIFY changed)
public:
    static constexpr char Service[] = "io.github.carlsonjm.splitrock.Ask";
    static constexpr char Path[] = "/Ask";
    static constexpr char Interface[] = "io.github.carlsonjm.SplitRock.Ask";
    static constexpr uint Version = 1;
    // Split Rock's broker, which makes a Do it card's write after the tap.
    static constexpr char BrokerService[] = "io.github.carlsonjm.splitrock.Broker";
    static constexpr char BrokerPath[] = "/Broker";
    static constexpr char BrokerInterface[] = "io.github.carlsonjm.SplitRock.Broker";
    // Notes, which opens a note the answer names.
    static constexpr char NotesService[] = "io.github.carlsonjm.gooseberry";
    static constexpr char NotesPath[] = "/QuickNote";
    static constexpr char NotesInterface[] = "io.github.carlsonjm.Gooseberry.QuickNote";

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
    QString modelName() const { return m_modelName; }
    QString modelCredit() const { return m_modelCredit; }
    bool codexReady() const { return m_codexReady; }
    bool handedToCodex() const { return m_handedToCodex; }
    bool needsEngine() const { return m_needsEngine; }
    bool codexInstalled() const { return m_codexInstalled; }
    bool codexOnly() const { return m_codexOnly; }
    QStringList read() const { return m_read; }
    QVariantMap doIt() const;
    QString doItState() const { return m_doItState; }
    QString doItProblem() const { return m_doItProblem; }
    QVariantList notes() const { return m_notes; }

    // What is typed now. A question is sent once the typing pauses and it
    // reads as one; anything else clears the answer.
    Q_INVOKABLE void type(const QString &text);
    // Sends what is typed at once.
    Q_INVOKABLE void askNow();
    Q_INVOKABLE void clear();
    // After the person's tap on Download, and Not now.
    Q_INVOKABLE void download();
    // After the person's tap on a note the answer names: Notes opens it on
    // its own card. False for a note the answer didn't name.
    Q_INVOKABLE bool openNote(const QString &id);
    Q_INVOKABLE void notNow();
    // After the person's tap on Codex only: Ask leaves the model out from
    // now on, and the question asked is asked again.
    Q_INVOKABLE void chooseCodexOnly();
    // After the person's tap on Ask Codex: the question goes to Codex's own
    // window, which signs in first where it must under Codex only. False
    // where there is nothing to hand on.
    Q_INVOKABLE bool askCodex();
    // After the person's tap on Do it: the broker makes the card's write,
    // once. False where there is no card, or it was already tapped.
    Q_INVOKABLE bool runDoIt();

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
    // Stops the question asked, whose end is then ignored.
    void stop();
    void setState(const QString &state);
    void lookAtCodex();
    void lookAtModel();
    // Forgets the answer's card and read line.
    void forgetCard();
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
    QString m_modelName;
    QString m_modelCredit;
    bool m_codexReady = false;
    bool m_handedToCodex = false;
    bool m_needsEngine = false;
    bool m_codexInstalled = false;
    bool m_codexOnly = false;
    QStringList m_read;
    QVariantMap m_card;
    QString m_doItState;
    QString m_doItProblem;
    QVariantList m_notes;
    uint m_id = 0;
    // A question sent whose id hasn't come back yet.
    bool m_sending = false;
    // Questions this Search stopped itself, whose last words are not its own.
    QList<uint> m_stopped;
    // Not now: no download is offered again until the typing is cleared.
    bool m_declined = false;
};
