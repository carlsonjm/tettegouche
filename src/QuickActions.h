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
    enum Kind { None, Note, Reminder, KeepAwake, DoNotDisturb, Bluetooth };
    Kind kind = None;
    // The note's words, as they will be written.
    QString text;
    // Reminder only: when it is due, and whether the phrase named a time or
    // the default, the next morning, stands in.
    QDateTime when;
    bool timed = false;
    // A switch only: the way it is to be set. `when` is then the time it
    // goes back by itself, and `timed` whether the phrase named one.
    bool on = true;
    // A switch named alone, with no on, off or time: Search turns it the
    // other way from where it stands.
    bool flips = false;
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
    // The hour a part of the day means; Usual, the time a day named alone
    // is given; Soon, "today".
    static constexpr int Usual = -2, Soon = -1;
    int dayHour = Usual;
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
    else if (words.endsWith(QLatin1String("morning"))) when.dayHour = Morning;
    else if (words == QLatin1String("today")) when.dayHour = When::Soon;
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

// `usual` is the time a day named with no time is given, "tomorrow" or "on
// Friday", and tomorrow's when no day is named either.
inline QDateTime resolve(const When &when, const QDateTime &now, const QTime &usual = QTime(Morning, 0))
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
        if (when.dayHour != When::Soon) {
            const QDateTime due = when.dayHour == When::Usual ? at(when.day, usual.hour(), usual.minute())
                                                              : at(when.day, when.dayHour, 0);
            if (due > now) return due;
        }
        // "today", or a part of the day already gone: the evening while it
        // is ahead, else an hour on, to the minute.
        const QDateTime evening = at(now.date(), Evening, 0);
        if (evening > now.addSecs(3600)) return evening;
        const QDateTime later = now.addSecs(3600);
        return at(later.date(), later.time().hour(), later.time().minute());
    }
    return at(now.date().addDays(1), usual.hour(), usual.minute());
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

// The end a switch phrase names: "1h", "for 20 minutes", "until 3". No words
// are no end; any other words are not a switch phrase at all.
inline bool readEnd(const QString &words, const QDateTime &now, QDateTime &end)
{
    if (words.isEmpty()) return true;
    static const QRegularExpression span(
        QStringLiteral("^(?:for )?(\\d{1,3}|an?|half an) ?(m(?:in(?:ute)?s?)?|h(?:(?:ou)?rs?)?)$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression until(
        QStringLiteral("^(?:until|till|til) (noon|midnight|\\d{1,2}(?::\\d{2})? ?(?:am|pm|a\\.m\\.|p\\.m\\.)?)$"),
        QRegularExpression::CaseInsensitiveOption);
    if (const auto match = span.match(words); match.hasMatch()) {
        bool numbered = false;
        const int count = match.captured(1).toInt(&numbered);
        const qint64 each = match.captured(2).startsWith(QLatin1Char('m'), Qt::CaseInsensitive) ? 60 : 3600;
        const qint64 seconds = match.captured(1).startsWith(QLatin1String("half"), Qt::CaseInsensitive)
            ? each / 2 : each * (numbered ? count : 1);
        if (seconds == 0) return false;
        end = now.addSecs(seconds);
        end.setTime(QTime(end.time().hour(), end.time().minute()));
        return true;
    }
    if (const auto match = until.match(words); match.hasMatch()) {
        const QString clock = match.captured(1).toLower();
        When when;
        readClock(clock.at(0).isDigit() ? clock : QStringLiteral("at ") + clock, when);
        if (!validClock(when)) return false;
        end = resolve(when, now);
        return true;
    }
    return false;
}

// A switch a phrase sets: keep awake, do not disturb, Bluetooth. The name
// alone turns the first two on; Bluetooth alone is a search for its page.
inline Action parseSwitch(const QString &phrase, const QDateTime &now)
{
    static const QRegularExpression awake(
        QStringLiteral("^(?:keep (?:(?:the )?(?:computer|screen) )?awake|stay awake)(?: (.+))?$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression quiet(QStringLiteral("^(?:do not disturb|don[\u2019']?t disturb|dnd)(?: (.+))?$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression bluetooth(
        QStringLiteral("^(?:(?:turn )?bluetooth (on|off)|turn (on|off) bluetooth)$"),
        QRegularExpression::CaseInsensitiveOption);

    if (const auto match = bluetooth.match(phrase); match.hasMatch()) {
        Action action;
        action.kind = Action::Bluetooth;
        action.on = (match.captured(1) + match.captured(2)).toLower() == QLatin1String("on");
        return action;
    }
    for (const auto &[pattern, kind] : {std::pair{&awake, Action::KeepAwake}, std::pair{&quiet, Action::DoNotDisturb}}) {
        const auto match = pattern->match(phrase);
        if (!match.hasMatch()) continue;
        Action action;
        action.kind = kind;
        const QString rest = match.captured(1).toLower();
        if (rest == QLatin1String("off")) {
            action.on = false;
        } else if (rest != QLatin1String("on")) {
            if (!readEnd(rest, now, action.when)) return {};
            action.timed = !rest.isEmpty();
            action.flips = rest.isEmpty();
        }
        return action;
    }
    return {};
}
}

// The action a phrase names at `now`, or none. A reminder with nothing to
// remember, a note with no words and a time no clock shows are no action.
// `usual` is the time a reminder for a day with no time is set for.
inline Action parse(const QString &typed, const QDateTime &now, const QTime &usual = QTime(Detail::Morning, 0))
{
    const QString phrase = typed.simplified();
    static const QRegularExpression note(QStringLiteral("^(?:new )?note(?: ?: ?| )(.+)$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression remind(QStringLiteral("^(?:remind me|reminder ?:|reminder)(?: |$)(.*)$"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression joiner(QStringLiteral("^(?:to|about|that) "),
        QRegularExpression::CaseInsensitiveOption);

    if (const Action action = Detail::parseSwitch(phrase, now)) return action;
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
    return {Action::Reminder, words, Detail::resolve(when, now, usual), when.hasDay || when.hasClock || when.hasSpan};
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
// named first, then this evening while it is ahead and tomorrow at `usual`.
// A switch is `kind` ("keepAwake", "doNotDisturb" or "bluetooth"), `on`,
// `flips` when the name came alone, and `until`, worded as a choice is, when
// the phrase named an end.
inline QVariantMap describe(const QString &typed, const QDateTime &now, const QLocale &locale = QLocale(),
                            const QTime &usual = QTime(Detail::Morning, 0))
{
    const Action action = parse(typed, now, usual);
    if (!action) return {};
    if (action.kind >= Action::KeepAwake) {
        QVariantMap row{
            {QStringLiteral("kind"), action.kind == Action::KeepAwake ? QStringLiteral("keepAwake")
                : action.kind == Action::DoNotDisturb ? QStringLiteral("doNotDisturb") : QStringLiteral("bluetooth")},
            {QStringLiteral("on"), action.on}};
        if (action.flips) row.insert(QStringLiteral("flips"), true);
        if (action.timed) row.insert(QStringLiteral("until"), describeWhen(action.when, now, locale));
        return row;
    }
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
    tomorrow.setTime(usual);
    for (const QDateTime &time : {evening, tomorrow})
        if (time > now && !times.contains(time)) times.append(time);
    QVariantList choices;
    for (const QDateTime &time : std::as_const(times)) choices.append(describeWhen(time, now, locale));
    row.insert(QStringLiteral("choices"), choices);
    return row;
}
}
