/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// People, as a people provider on this computer answers. The provider is a
// command, good-input-people, that keeps the people and decides who is who;
// Search only asks it and draws what it says, one JSON object for each
// question. Without the command there is no People in Search, and
// Tettegouche works the same.
//
//   people [WORDS]       {"count", "found", "people": [{"id", "name", "initials", "summary"}]}
//   person ID            a row, with "handles": [{"kind", "value", "shown", "label"}],
//                        "cards", "joined" ("", "same" or "hand") and "match", a row or null
//   join ID OTHER        the person as it is now
//   not-same ID OTHER    the person as it is now
//   separate ID          the person as it is now
//
// Reaching someone is handed to the application that takes that kind of
// address: sms: for a text, tel: for a call, mailto: for an email. Search
// sends nothing itself.
class PeopleClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QVariantList people READ people NOTIFY peopleChanged)
    Q_PROPERTY(int count READ count NOTIFY peopleChanged)
    Q_PROPERTY(QVariantMap person READ person NOTIFY personChanged)
    Q_PROPERTY(bool personOpen READ personOpen NOTIFY personChanged)
    Q_PROPERTY(bool canText READ canText NOTIFY availableChanged)
    Q_PROPERTY(bool canCall READ canCall NOTIFY availableChanged)
    Q_PROPERTY(bool canEmail READ canEmail NOTIFY availableChanged)

public:
    static constexpr const char *Command = "good-input-people";

    explicit PeopleClient(QObject *parent = nullptr);

    bool available() const { return !m_program.isEmpty(); }
    QVariantList people() const { return m_people; }
    int count() const { return m_count; }
    QVariantMap person() const { return m_person; }
    bool personOpen() const { return !m_person.isEmpty(); }
    bool canText() const { return m_canText; }
    bool canCall() const { return m_canCall; }
    bool canEmail() const { return m_canEmail; }

    // The provider to run, in place of the one found; for tests.
    void setProgram(const QString &program);

    // Looks again for the provider and for what takes a text, a call and an
    // email, as when Search opens.
    Q_INVOKABLE void refresh();
    // Everyone, or those the words find. The newest question wins.
    Q_INVOKABLE void find(const QString &words);
    // One person's page, and leaving it.
    Q_INVOKABLE void open(const QString &id);
    Q_INVOKABLE void close();
    // The person shown and another are one person; are not, which is not
    // asked again; and the person shown taken apart again.
    Q_INVOKABLE void join(const QString &other);
    Q_INVOKABLE void notSame(const QString &other);
    Q_INVOKABLE void separate();
    // Hands a number or an address to what takes it: "text", "call" or
    // "email". False when nothing does.
    Q_INVOKABLE bool reach(const QString &kind, const QString &value);
    Q_INVOKABLE void copy(const QString &value);

    // The address handed over for a kind and a value; empty for neither.
    static QString address(const QString &kind, const QString &value);
    // The application that takes sms, tel or mailto addresses, or none; and
    // the first among some applications that says it takes one, shown in
    // the menus or not.
    static KService::Ptr taker(const QString &scheme);
    static KService::Ptr takerAmong(const KService::List &services, const QString &scheme);
    // Whether an application is KDE Connect's, which passes a number to a
    // phone; and the one phone among those paired and in reach, or none.
    static bool throughPhone(const KService::Ptr &service);
    static QString onlyPhone(const QStringList &phones);

Q_SIGNALS:
    void availableChanged();
    void peopleChanged();
    void personChanged();

private:
    void ask(const QStringList &arguments, bool forPerson);
    void decide(const QString &verb, const QString &other);

    QString m_program;
    bool m_programSet = false;
    QVariantList m_people;
    int m_count = 0;
    QVariantMap m_person;
    QString m_words;
    int m_listAsked = 0;
    int m_personAsked = 0;
    bool m_canText = false;
    bool m_canCall = false;
    bool m_canEmail = false;
};
