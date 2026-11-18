/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// People, over a stand-in for the people provider: a script in a temporary
// folder that records what it was asked and answers with made-up people. No
// one's contacts are read, and nothing is handed to another application.

#include "PeopleClient.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class PeopleClientTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_folder;
    QString m_program;

    QByteArray asked() const
    {
        QFile file(m_folder.filePath(QStringLiteral("asked")));
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_folder.isValid());
        m_program = m_folder.filePath(QStringLiteral("provider"));
        QFile file(m_program);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(R"(#!/bin/sh
echo "$*" >> "$(dirname "$0")/asked"
case "$1" in
people)
    if [ -n "$2" ]; then
        echo '{"count": 3, "found": 1, "people": [{"id": "1", "name": "Ana Reyes", "initials": "AR", "summary": "2 numbers"}]}'
    else
        echo '{"count": 3, "found": 3, "people": [{"id": "1", "name": "Ana Reyes", "initials": "AR", "summary": "2 numbers"}, {"id": "4", "name": "Ben Okafor", "initials": "BO", "summary": "1 number"}, {"id": "5", "name": "Joanna Lind", "initials": "JL", "summary": "1 number"}]}'
    fi ;;
person)
    if [ "$2" = "gone" ]; then echo '{"error": "gone"}'; else
        echo '{"id": "1", "name": "Ana Reyes", "initials": "AR", "summary": "2 numbers", "cards": 1, "joined": "", "handles": [{"kind": "tel", "value": "+16125550100", "shown": "(612) 555-0100", "label": "Mobile"}], "match": {"id": "3", "name": "Ana R.", "initials": "AR", "summary": "1 number", "why": "name"}}'
    fi ;;
join)
    echo '{"id": "1", "name": "Ana Reyes", "initials": "AR", "summary": "3 numbers", "cards": 2, "joined": "hand", "handles": [], "match": null}' ;;
*)
    echo '{"id": "1", "name": "Ana Reyes", "initials": "AR", "summary": "2 numbers", "cards": 1, "joined": "", "handles": [], "match": null}' ;;
esac
)");
        file.close();
        QVERIFY(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    }

    void withoutAProviderThereIsNoPeople()
    {
        PeopleClient client;
        client.setProgram(QString());
        QVERIFY(!client.available());
        client.find(QStringLiteral("ana"));
        client.open(QStringLiteral("1"));
        QVERIFY(client.people().isEmpty());
        QVERIFY(!client.personOpen());
    }

    void everyoneThenThoseTheWordsFind()
    {
        PeopleClient client;
        client.setProgram(m_program);
        QVERIFY(client.available());
        QSignalSpy listed(&client, &PeopleClient::peopleChanged);
        client.find(QString());
        QTRY_COMPARE(client.people().size(), 3);
        QCOMPARE(client.count(), 3);
        QCOMPARE(client.people().first().toMap().value(QStringLiteral("name")).toString(), QStringLiteral("Ana Reyes"));
        client.find(QStringLiteral("  an "));
        QTRY_COMPARE(client.people().size(), 1);
        QVERIFY(asked().contains("people an\n"));
    }

    void theNewestQuestionWins()
    {
        PeopleClient client;
        client.setProgram(m_program);
        client.find(QStringLiteral("an"));
        client.find(QString());
        QTRY_COMPARE(client.people().size(), 3);
        // The older answer, when it comes, changes nothing.
        QTest::qWait(300);
        QCOMPARE(client.people().size(), 3);
    }

    void aPersonOpensJoinsAndCloses()
    {
        PeopleClient client;
        client.setProgram(m_program);
        client.open(QStringLiteral("1"));
        QTRY_VERIFY(client.personOpen());
        QCOMPARE(client.person().value(QStringLiteral("match")).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("3"));
        client.join(QStringLiteral("3"));
        QTRY_COMPARE(client.person().value(QStringLiteral("joined")).toString(), QStringLiteral("hand"));
        QVERIFY(asked().contains("join 1 3\n"));
        client.notSame(QStringLiteral("3"));
        QTRY_VERIFY(asked().contains("not-same 1 3\n"));
        client.separate();
        QTRY_VERIFY(asked().contains("separate 1\n"));
        client.close();
        QVERIFY(!client.personOpen());
    }

    void aPersonNoLongerThereClosesThePage()
    {
        PeopleClient client;
        client.setProgram(m_program);
        client.open(QStringLiteral("1"));
        QTRY_VERIFY(client.personOpen());
        client.open(QStringLiteral("gone"));
        QTRY_VERIFY(!client.personOpen());
    }

    void addressesAreHandedOverAsAddresses()
    {
        QCOMPARE(PeopleClient::address(QStringLiteral("text"), QStringLiteral("+16125550100")), QStringLiteral("sms:+16125550100"));
        QCOMPARE(PeopleClient::address(QStringLiteral("call"), QStringLiteral(" +16125550100 ")), QStringLiteral("tel:+16125550100"));
        QCOMPARE(PeopleClient::address(QStringLiteral("email"), QStringLiteral("ana@example.com")), QStringLiteral("mailto:ana@example.com"));
        QVERIFY(PeopleClient::address(QStringLiteral("run"), QStringLiteral("ls")).isEmpty());
        QVERIFY(PeopleClient::address(QStringLiteral("text"), QString()).isEmpty());
        // With nothing to take a text in this bare home, none is handed over.
        PeopleClient client;
        client.setProgram(m_program);
        if (!client.canText()) QVERIFY(!client.reach(QStringLiteral("text"), QStringLiteral("+16125550100")));
    }

    // KDE Connect takes numbers to text and call from an entry kept out of
    // the menus: it counts, and an entry that takes neither does not.
    void anApplicationOutOfTheMenusStillTakesANumber()
    {
        const auto entry = [this](const QString &name, const QByteArray &body) {
            const QString path = m_folder.filePath(name);
            QFile file(path);
            if (file.open(QIODevice::WriteOnly)) file.write("[Desktop Entry]\nType=Application\n" + body);
            file.close();
            return KService::Ptr(new KService(path));
        };
        const auto mail = entry(QStringLiteral("mail.desktop"),
                                "Name=Mail\nExec=mail %u\nMimeType=x-scheme-handler/mailto;\n");
        const auto phone = entry(QStringLiteral("phone.desktop"),
                                 "Name=Phone\nExec=phone-handler %U\nNoDisplay=true\n"
                                 "MimeType=x-scheme-handler/tel;x-scheme-handler/sms;\n");
        const auto empty = entry(QStringLiteral("empty.desktop"),
                                 "Name=Empty\nMimeType=x-scheme-handler/sms;\n");
        const KService::List all{mail, empty, phone};
        QVERIFY(PeopleClient::takerAmong(all, QStringLiteral("sms")) == phone);
        QVERIFY(PeopleClient::takerAmong(all, QStringLiteral("tel")) == phone);
        QVERIFY(PeopleClient::takerAmong(all, QStringLiteral("mailto")) == mail);
        QVERIFY(!PeopleClient::takerAmong({mail}, QStringLiteral("sms")));
    }

    // One phone in reach is the phone; none or several leave KDE Connect to
    // ask, and so does a name that is no device's.
    void onePhoneNeedsNoQuestion()
    {
        QCOMPARE(PeopleClient::onlyPhone({QStringLiteral("780baff359744abd")}), QStringLiteral("780baff359744abd"));
        QVERIFY(PeopleClient::onlyPhone({}).isEmpty());
        QVERIFY(PeopleClient::onlyPhone({QStringLiteral("a1"), QStringLiteral("b2")}).isEmpty());
        QVERIFY(PeopleClient::onlyPhone({QStringLiteral("../share")}).isEmpty());
        QVERIFY(!PeopleClient::throughPhone({}));
    }
};

QTEST_MAIN(PeopleClientTest)
#include "PeopleClientTest.moc"
