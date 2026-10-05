#include "TransferActivityBridge.h"
#include "FileBrowser.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
TransferActivityBridge::TransferActivityBridge(FileBrowser *files, QObject *parent)
    : QObject(parent), m_files(files) {
    // KIO reports bytes, files and folders apart in one progress tick, and
    // Files' other news shares the same signal. One pass of the event loop is
    // told once, and only when the rows themselves changed.
    m_pending.setSingleShot(true);
    m_pending.setInterval(0);
    connect(&m_pending, &QTimer::timeout, this, &TransferActivityBridge::publish);
    connect(files, &FileBrowser::operationChanged, &m_pending, qOverload<>(&QTimer::start));
    m_later.setSingleShot(true);
    connect(&m_later, &QTimer::timeout, this, &TransferActivityBridge::publish);
}
namespace {
// How often a change of progress alone is told: Ambient's bar moves no
// faster than this, while anything else about a row is told at once.
constexpr qint64 progressIntervalMs = 1000;
QJsonArray withoutProgress(QJsonArray rows) {
    for (qsizetype i = 0; i < rows.size(); ++i) {
        auto object = rows.at(i).toObject();
        object.remove(QStringLiteral("progress"));
        object.remove(QStringLiteral("processedBytes"));
        rows.replace(i, object);
    }
    return rows;
}
}
QJsonArray TransferActivityBridge::rows() const {
    return QJsonArray::fromVariantList(m_files->activitySnapshot());
}
void TransferActivityBridge::publish() {
    const auto now = rows();
    if (m_published && now == m_lastRows) return;
    if (m_published && m_sinceTold.isValid() && withoutProgress(now) == withoutProgress(m_lastRows)) {
        const auto wait = progressIntervalMs - m_sinceTold.elapsed();
        if (wait > 0) {
            if (!m_later.isActive()) m_later.start(int(wait));
            return;
        }
    }
    m_later.stop(); m_sinceTold.start();
    m_published = true; m_lastRows = now; ++m_revision;
    Q_EMIT changed(snapshot());
}
QString TransferActivityBridge::snapshot() const {
    return QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("revision"), qint64(m_revision)},
        {QStringLiteral("activities"), rows()}}).toJson(QJsonDocument::Compact));
}
void TransferActivityBridge::cancel(const QString &id) { m_files->cancelActivity(id); }
void TransferActivityBridge::suspend(const QString &id) { m_files->suspendActivity(id); }
void TransferActivityBridge::resume(const QString &id) { m_files->resumeActivity(id); }
