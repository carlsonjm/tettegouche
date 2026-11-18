#pragma once

#include <QDateTime>
#include <QLocale>
#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <utility>

// What a typed phrase asks Search to do. Fixed phrases only: nothing here
// asks a model, a provider or the network, so a phrase reads the same on
// every computer and at once. A phrase that is not one of these is no
// action, and Search lists what it finds as before.
namespace QuickActions {
struct Action {
    enum Kind { None, Note, Reminder };
    Kind kind = None;
    // The note's words, as they will be written.
    QString text;
    // Reminder only: when it is due, and whether the phrase named a time or
    // the default, the next morning, stands in.
    QDateTime when;
    bool timed = false;
    explicit operator bool() const { return kind != None; }
};

namespace Detail {
inline constexpr int Morning = 9, Afternoon = 15, Evening = 19;

inline QString sentence(QString words)
{
    words = words.simplified();
    if (!words.isEmpty()) words[0] = words.at(0).toUpper();
    return words;
}

inline int weekday(const QString &name)
{
    static const QStringList days{QStringLiteral("mon"), QStringLiteral("tue"), QStringLiteral("wed"),
        QStringLiteral("thu"), QStringLiteral("fri"), QStringLiteral("sat"), QStringLiteral("sun")};
    return days.indexOf(name.left(3)) + 1;
}

struct When {
    bool hasDay = false, hasClock = false, hasSpan = false;
    QDate day;
    int dayHour = Morning;
    int hour = -1, minute = 0;
    // 0 for a bare hour, 1 for am, 2 for pm.
    int half = 0;
    qint64 spanSeconds = 0;
};

inline const QString &dayWords()
{
    static const QString words = QStringLiteral(
        "today|tonight|this (?:morning|afternoon|evening)|tomorrow(?: (?:morning|afternoon|evening|night))?"
        "|(?:on |next )?(?:mon|tues?|wed(?:nes)?|thu(?:rs?)?|fri|sat(?:ur)?|sun)(?:day)?");
    return words;
}

inline const QString &clockWords()
{
    static const QString words = QStringLiteral(
        "at noon|at midnight|(?:at )?\\d{1,2}(?::\\d{2})? ?(?:am|pm|a\\.m\\.|p\\.m\\.)|at \\d{1,2}(?::\\d{2})?");
    return words;
}

inline const QString &spanWords()
{
    static const QString words = QStringLiteral(
        "in (?:\\d{1,3}|an?|half an) (?:min(?:ute)?s?|h(?:ou)?rs?|days?|weeks?)");
    return words;
}

inline void readDay(const QString &words, const QDateTime &now, When &when)
{
    when.hasDay = true;
    when.day = now.date();
    if (words == QLatin1String("tonight") || words.endsWith(QLatin1String("evening"))
        || words.endsWith(QLatin1String("night"))) when.dayHour = Evening;
    else if (words.endsWith(QLatin1String("afternoon"))) when.dayHour = Afternoon;
    else if (words == QLatin1String("today")) when.dayHour = -1;
    if (words.startsWith(QLatin1String("tomorrow"))) {
        when.day = when.day.addDays(1);
        return;
    }
    QString name = words;
    name.remove(QRegularExpression(QStringLiteral("^(?:on|next) ")));
    if (const int wanted = weekday(name); wanted > 0 && !words.startsWith(QLatin1String("to"))
            && !words.startsWith(QLatin1String("this"))) {
        int ahead = (wanted - now.date().dayOfWeek() + 7) % 7;
        if (ahead == 0) ahead = 7;
        when.day = when.day.addDays(ahead);
    }
}

inline void readClock(const QString &words, When &when)
{
    when.hasClock = true;
    if (words == QLatin1String("at noon")) { when.hour = 12; when.half = 2; return; }
    if (words == QLatin1String("at midnight")) { when.hour = 12; when.half = 1; return; }
    static const QRegularExpression clock(QStringLiteral("(\\d{1,2})(?::(\\d{2}))? ?([ap])?"));
    const auto match = clock.match(words);
    when.hour = match.captured(1).toInt();
    when.minute = match.captured(2).toInt();
    when.half = match.captured(3) == QLatin1String("a") ? 1 : match.captured(3) == QLatin1String("p") ? 2 : 0;
}

inline void readSpan(const QString &words, When &when)
{
    when.hasSpan = true;
    const QStringList parts = words.split(QLatin1Char(' '));
    const bool half = parts.value(1) == QLatin1String("half");
    const QString unit = parts.last();
    bool numbered = false;
    const int count = parts.value(1).toInt(&numbered);
    const qint64 each = unit.startsWith(QLatin1Char('m')) ? 60 : unit.startsWith(QLatin1Char('h')) ? 3600
        : unit.startsWith(QLatin1Char('d')) ? 86400 : 604800;
    when.spanSeconds = half ? each / 2 : each * (numbered ? count : 1);
}

inline bool validClock(const When &when)
{
    if (!when.hasClock) return true;
    if (when.minute > 59) return false;
    return when.half == 0 ? when.hour <= 23 : when.hour >= 1 && when.hour <= 12;
}

// The hour a clock time means on a day: "3" is the afternoon's, "8" the
// morning's, as a person saying them at a desk means.
inline int hourOn(const When &when)
{
    if (when.half == 1) return when.hour % 12;
    if (when.half == 2) return when.hour % 12 + 12;
    return when.hour >= 1 && when.hour <= 6 ? when.hour + 12 : when.hour;
}

inline QDateTime resolve(const When &when, const QDateTime &now)
{
    if (when.hasSpan) {
        QDateTime due = now.addSecs(when.spanSeconds);
        due.setTime(QTime(due.time().hour(), due.time().minute()));
        return due;
    }
    // On the clock `now` is read from, whichever that is.
    const auto at = [&now](const QDate &day, int hour, int minute) {
        QDateTime due = now;
        due.setDate(day);
        due.setTime(QTime(hour, minute));
        return due;
    };
    if (when.hasClock) {
        if (when.hasDay) return at(when.day, hourOn(when), when.minute);
        // No day named: the next time the clock reads that. A bare hour
        // may be either half of the day, whichever comes first while people
        // are up.
        QList<int> hours;
        if (when.half != 0 || when.hour == 0 || when.hour > 12) {
            hours = {hourOn(when)};
        } else {
            for (const int hour : {when.hour % 12, when.hour % 12 + 12})
                if (hour >= 7 && hour <= 22) hours.append(hour);
            if (hours.isEmpty()) hours = {hourOn(when)};
        }
        for (int ahead = 0; ahead < 2; ++ahead)
            for (const int hour : std::as_const(hours)) {
                const QDateTime due = at(now.date().addDays(ahead), hour, when.minute);
                if (due > now) return due;
            }
        return at(now.date().addDays(1), hours.first(), when.minute);
    }
    if (when.hasDay) {
        if (when.dayHour >= 0) {
            const QDateTime due = at(when.day, when.dayHour, 0);
            if (due > now) return due;
        }
        // "today", or a part of the day already gone: the evening while it
        // is ahead, else an hour on, to the minute.
        const QDateTime evening = at(now.date(), Evening, 0);
        if (evening > now.addSecs(3600)) return evening;
        const QDateTime later = now.addSecs(3600);
        return at(later.date(), later.time().hour(), later.time().minute());
    }
    return at(now.date().addDays(1), Morning, 0);
}

// Takes the words that say when off one end of what is to be remembered.
inline bool takeWhen(QString &body, bool fromEnd, const QDateTime &now, When &when)
{
    bool took = false;
    for (int round = 0; round < 2; ++round) {
        struct Part { const QString &words; int kind; };
        const Part parts[] = {{spanWords(), 0}, {clockWords(), 1}, {dayWords(), 2}};
        bool found = false;
        for (const Part &part : parts) {
            if ((part.kind == 0 && (when.hasSpan || when.hasDay || when.hasClock)) || (part.kind == 1 && when.hasClock)
                || (part.kind == 2 && when.hasDay) || when.hasSpan) continue;
            const QRegularExpression pattern(
                fromEnd ? QStringLiteral("(?:^| )(%1)$").arg(part.words) : QStringLiteral("^(%1)(?: |$)").arg(part.words),
                QRegularExpression::CaseInsensitiveOption);
            const auto match = pattern.match(body);
            if (!match.hasMatch()) continue;
            const QString words = match.captured(1).toLower();
            if (part.kind == 0) readSpan(words, when);
            else if (part.kind == 1) readClock(words, when);
            else readDay(words, now, when);
            body = fromEnd ? body.left(match.capturedStart(0)) : body.mid(match.capturedEnd(0));
            body = body.trimmed();
            found = took = true;
            break;
        }
        if (!found) break;
    }
    return took;
}
}

// The action a phrase names at `now`, or none. A reminder with nothing to
// remember, a note with no words and a time no clock shows are no action.
inline Action parse(const QString &typed, const QDateTime &now)
{
    const QString phrase = typed.simplified();
    static const QRegularExpression note(QStringLiteral("^(?:new )?note(?: ?: ?| )(.+)$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression remind(QStringLiteral("^(?:remind me|reminder ?:|reminder)(?: |$)(.*)$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression joiner(QStringLiteral("^(?:to|about|that) "),
        QRegularExpression::CaseInsensitiveOption);

    if (const auto match = note.match(phrase); match.hasMatch()) {
        const QString words = Detail::sentence(match.captured(1));
        // "note taking" is as likely a search for an app as a note: a note
        // takes a colon or more than one word.
        if (words.isEmpty() || (!phrase.contains(QLatin1Char(':')) && !words.contains(QLatin1Char(' ')))) return {};
        return {Action::Note, words, {}, false};
    }
    const auto match = remind.match(phrase);
    if (!match.hasMatch()) return {};
    QString body = match.captured(1).trimmed();
    Detail::When when;
    if (!Detail::takeWhen(body, true, now, when)) Detail::takeWhen(body, false, now, when);
    body.remove(joiner);
    // A day at one end and a clock at the other: "tomorrow to call at 3".
    if (!when.hasSpan && when.hasDay != when.hasClock) {
        if (!Detail::takeWhen(body, true, now, when)) Detail::takeWhen(body, false, now, when);
        body.remove(joiner);
    }
    const QString words = Detail::sentence(body);
    if (words.isEmpty() || !Detail::validClock(when)) return {};
    return {Action::Reminder, words, Detail::resolve(when, now), when.hasDay || when.hasClock || when.hasSpan};
}

// A time as Search's row words it: `when` as ISO 8601 with its offset, `day`
// ("today", "evening" for the evening still ahead, "tomorrow", or empty for a
// day further off), and `time` and `date` as the locale writes them.
inline QVariantMap describeWhen(const QDateTime &when, const QDateTime &now, const QLocale &locale = QLocale())
{
    const qint64 days = now.date().daysTo(when.date());
    return {
        {QStringLiteral("when"), when.toOffsetFromUtc(when.offsetFromUtc()).toString(Qt::ISODate)},
        {QStringLiteral("day"), days == 0 ? (when.time().hour() >= 18 ? QStringLiteral("evening") : QStringLiteral("today"))
                                  : days == 1 ? QStringLiteral("tomorrow") : QString()},
        {QStringLiteral("time"), locale.toString(when.time(), QLocale::ShortFormat)},
        {QStringLiteral("date"), locale.toString(when.date(), QStringLiteral("ddd d MMM"))},
    };
}

// The action as the row draws it, or an empty map for none: `kind` ("note"
// or "reminder"), `text`, `typed` (the words to remember as they were typed,
// the day among them) and, for a reminder, `choices`: the time the phrase
// named first, then this evening while it is ahead and tomorrow morning.
inline QVariantMap describe(const QString &typed, const QDateTime &now, const QLocale &locale = QLocale())
{
    const Action action = parse(typed, now);
    if (!action) return {};
    QVariantMap row{{QStringLiteral("text"), action.text}};
    if (action.kind == Action::Note) {
        row.insert(QStringLiteral("kind"), QStringLiteral("note"));
        return row;
    }
    static const QRegularExpression lead(QStringLiteral("^(?:remind me|reminder ?:|reminder) (?:(?:to|about|that) )?"),
        QRegularExpression::CaseInsensitiveOption);
    row.insert(QStringLiteral("kind"), QStringLiteral("reminder"));
    row.insert(QStringLiteral("typed"), Detail::sentence(typed.simplified().remove(lead)));
    QList<QDateTime> times{action.when};
    QDateTime evening = now, tomorrow = now;
    evening.setTime(QTime(Detail::Evening, 0));
    tomorrow.setDate(now.date().addDays(1));
    tomorrow.setTime(QTime(Detail::Morning, 0));
    for (const QDateTime &time : {evening, tomorrow})
        if (time > now && !times.contains(time)) times.append(time);
    QVariantList choices;
    for (const QDateTime &time : std::as_const(times)) choices.append(describeWhen(time, now, locale));
    row.insert(QStringLiteral("choices"), choices);
    return row;
}
}
