#include "QuickActions.h"
#include <QTest>

using QuickActions::Action;

// Wednesday 18 November 2026, ten in the morning.
static QDateTime morning() { return QDateTime(QDate(2026, 11, 18), QTime(10, 0)); }
static QDateTime on(int day, int hour, int minute = 0) { return QDateTime(QDate(2026, 11, day), QTime(hour, minute)); }

class QuickActionsTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void reminders_data()
    {
        QTest::addColumn<QString>("typed");
        QTest::addColumn<QString>("text");
        QTest::addColumn<QDateTime>("when");
        QTest::addColumn<bool>("timed");
        QTest::newRow("tomorrow") << "remind me to check the build tomorrow" << "Check the build" << on(19, 9) << true;
        QTest::newRow("no time") << "remind me to water the ferns" << "Water the ferns" << on(19, 9) << false;
        QTest::newRow("day first") << "Remind me tomorrow to call the bank" << "Call the bank" << on(19, 9) << true;
        QTest::newRow("bare hour is the afternoon") << "remind me to call the bank at 3" << "Call the bank" << on(18, 15) << true;
        QTest::newRow("bare hour gone today") << "remind me to stretch at 8" << "Stretch" << on(18, 20) << true;
        QTest::newRow("pm") << "remind me about the invoice at 4:30pm" << "The invoice" << on(18, 16, 30) << true;
        QTest::newRow("am gone is tomorrow") << "remind me to run 7 am" << "Run" << on(19, 7) << true;
        QTest::newRow("day and clock") << "remind me to ring Ada tomorrow at 3" << "Ring Ada" << on(19, 15) << true;
        QTest::newRow("clock then day") << "remind me to ring Ada at 8 tomorrow" << "Ring Ada" << on(19, 8) << true;
        QTest::newRow("split ends") << "remind me tomorrow to ring Ada at 3" << "Ring Ada" << on(19, 15) << true;
        QTest::newRow("24 hour") << "remind me to leave at 17:45" << "Leave" << on(18, 17, 45) << true;
        QTest::newRow("tonight") << "remind me to take the bins out tonight" << "Take the bins out" << on(18, 19) << true;
        QTest::newRow("this afternoon") << "remind me that the kiln is on this afternoon" << "The kiln is on" << on(18, 15) << true;
        QTest::newRow("today") << "remind me to post the letter today" << "Post the letter" << on(18, 19) << true;
        QTest::newRow("weekday") << "remind me to pay rent on friday" << "Pay rent" << on(20, 9) << true;
        QTest::newRow("same weekday is next week") << "remind me to pay rent wednesday" << "Pay rent" << on(25, 9) << true;
        QTest::newRow("minutes") << "remind me to check the oven in 20 minutes" << "Check the oven" << on(18, 10, 20) << true;
        QTest::newRow("an hour") << "remind me to stand up in an hour" << "Stand up" << on(18, 11) << true;
        QTest::newRow("half an hour") << "remind me to stand up in half an hour" << "Stand up" << on(18, 10, 30) << true;
        QTest::newRow("days") << "reminder: renew the domain in 2 days" << "Renew the domain" << on(20, 10) << true;
        QTest::newRow("noon") << "remind me to eat at noon" << "Eat" << on(18, 12) << true;
        QTest::newRow("a day in the words stays") << "remind me to book the tomorrow land tour" << "Book the tomorrow land tour" << on(19, 9) << false;
    }
    void reminders()
    {
        QFETCH(QString, typed);
        QFETCH(QString, text);
        QFETCH(QDateTime, when);
        QFETCH(bool, timed);
        const Action action = QuickActions::parse(typed, morning());
        QCOMPARE(action.kind, Action::Reminder);
        QCOMPARE(action.text, text);
        QCOMPARE(action.when, when);
        QCOMPARE(action.timed, timed);
    }

    void lateInTheDay()
    {
        const QDateTime late(QDate(2026, 11, 18), QTime(22, 40));
        // The evening is gone: an hour on, to the minute.
        QCOMPARE(QuickActions::parse(QStringLiteral("remind me to lock up tonight"), late).when, on(18, 23, 40));
        QCOMPARE(QuickActions::parse(QStringLiteral("remind me to lock up at 3"), late).when, on(19, 15));
    }

    void notes_data()
    {
        QTest::addColumn<QString>("typed");
        QTest::addColumn<QString>("text");
        QTest::newRow("words") << "note router password is on the box" << "Router password is on the box";
        QTest::newRow("colon") << "Note: milk" << "Milk";
        QTest::newRow("new note") << "new note call the plumber" << "Call the plumber";
    }
    void notes()
    {
        QFETCH(QString, typed);
        QFETCH(QString, text);
        const Action action = QuickActions::parse(typed, morning());
        QCOMPARE(action.kind, Action::Note);
        QCOMPARE(action.text, text);
    }

    void notActions_data()
    {
        QTest::addColumn<QString>("typed");
        QTest::newRow("empty") << "";
        QTest::newRow("an app") << "notes";
        QTest::newRow("one word after note") << "note taking";
        QTest::newRow("note alone") << "note";
        QTest::newRow("nothing to remember") << "remind me";
        QTest::newRow("only a time") << "remind me tomorrow";
        QTest::newRow("a word that starts the same") << "reminders app";
        QTest::newRow("no such hour") << "remind me to nap at 31";
        QTest::newRow("no such minute") << "remind me to nap at 3:75";
        QTest::newRow("in the middle") << "please remind me to nap";
    }
    void notActions()
    {
        QFETCH(QString, typed);
        QVERIFY(!QuickActions::parse(typed, morning()));
    }

    // What the row is given: the words, and the times Tab offers, the
    // phrase's own first.
    void describesTheRow()
    {
        const QLocale english(QLocale::English, QLocale::UnitedStates);
        QVariantMap row = QuickActions::describe(QStringLiteral("remind me to check the build tomorrow"), morning(), english);
        QCOMPARE(row.value(QStringLiteral("kind")).toString(), QStringLiteral("reminder"));
        QCOMPARE(row.value(QStringLiteral("text")).toString(), QStringLiteral("Check the build"));
        QCOMPARE(row.value(QStringLiteral("typed")).toString(), QStringLiteral("Check the build tomorrow"));
        QVariantList choices = row.value(QStringLiteral("choices")).toList();
        QCOMPARE(choices.size(), 2);
        QCOMPARE(choices.at(0).toMap().value(QStringLiteral("day")).toString(), QStringLiteral("tomorrow"));
        QCOMPARE(choices.at(0).toMap().value(QStringLiteral("time")).toString(), QStringLiteral("9:00 AM"));
        QCOMPARE(QDateTime::fromString(choices.at(0).toMap().value(QStringLiteral("when")).toString(), Qt::ISODate), on(19, 9));
        QCOMPARE(choices.at(1).toMap().value(QStringLiteral("day")).toString(), QStringLiteral("evening"));
        QCOMPARE(choices.at(1).toMap().value(QStringLiteral("time")).toString(), QStringLiteral("7:00 PM"));

        row = QuickActions::describe(QStringLiteral("remind me to pay rent on friday"), morning(), english);
        choices = row.value(QStringLiteral("choices")).toList();
        QCOMPARE(choices.size(), 3);
        QCOMPARE(choices.at(0).toMap().value(QStringLiteral("day")).toString(), QString());
        QCOMPARE(choices.at(0).toMap().value(QStringLiteral("date")).toString(), QStringLiteral("Fri 20 Nov"));

        row = QuickActions::describe(QStringLiteral("note: milk"), morning(), english);
        QCOMPARE(row.value(QStringLiteral("kind")).toString(), QStringLiteral("note"));
        QVERIFY(!row.contains(QStringLiteral("choices")));
        QVERIFY(QuickActions::describe(QStringLiteral("notes"), morning(), english).isEmpty());
    }
};

QTEST_APPLESS_MAIN(QuickActionsTest)
#include "QuickActionsTest.moc"
