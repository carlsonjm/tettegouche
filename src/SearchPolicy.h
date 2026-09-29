#pragma once

#include <QString>
#include <QStringList>
#include <QRegularExpression>
#include <algorithm>

// Provider-independent evidence. No application names, learned history, or
// machine-specific paths participate in this policy.
namespace SearchPolicy {
enum Confidence { Exact, NamedIntent, Prefix, Words, Context, Unrelated };
struct Evidence {
    Confidence confidence = Unrelated;
    int completion = 99;
};
inline QString normalized(QString text) {
    return text.toCaseFolded().replace(QRegularExpression(QStringLiteral("[-_\\s]+")), QStringLiteral(" ")).simplified();
}
inline QString compact(QString text) { return normalized(text).remove(QLatin1Char(' ')); }

inline Evidence name(const QString &title, const QString &query) {
    const auto n = normalized(title), q = normalized(query);
    if (q.isEmpty()) return {};
    const auto nc = compact(n), qc = compact(q);
    if (nc == qc) return {Exact, 0};
    if (nc.startsWith(qc)) return {Prefix, std::min(99, int(nc.size() - qc.size()))};
    const auto words = n.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const auto &word : q.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
        bool found = false;
        for (const auto &candidate : words) if (candidate.startsWith(word)) { found = true; break; }
        if (!found) return {};
    }
    return {Words, 0};
}

inline Evidence evaluate(const QString &title, const QStringList &aliases,
                         const QString &description, const QString &query) {
    auto best = name(title, query);
    const auto size = compact(query).size();
    for (const auto &alias : aliases) {
        auto candidate = name(alias, query);
        // Two-letter intent is ambiguous across the board. Longer meaningful
        // alias prefixes are stronger evidence, regardless of which setting.
        if (candidate.confidence == Prefix && size >= 3) candidate.confidence = NamedIntent;
        if (candidate.confidence < best.confidence
            || (candidate.confidence == best.confidence && candidate.completion < best.completion)) best = candidate;
    }
    if (size >= 3 && best.confidence == Unrelated) {
        const auto context = name(description, query);
        if (context.confidence != Unrelated) best = {Context, 0};
    }
    return best;
}

inline int priority(Evidence evidence, int kind) {
    // Confidence first; apps/files/aids resolve comparable evidence. Shorter
    // completions only break ties within the same confidence and kind.
    return int(evidence.confidence) * 1000 + kind * 100 + evidence.completion;
}
}
