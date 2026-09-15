#include "TransferActivityBridge.h"
#include "FileBrowser.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
TransferActivityBridge::TransferActivityBridge(FileBrowser *files, QObject *parent)
    : QObject(parent), m_files(files) {
    connect(files, &FileBrowser::operationChanged, this, [this] { ++m_revision; Q_EMIT changed(snapshot()); });
}
QString TransferActivityBridge::snapshot() const {
    return QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("revision"), qint64(m_revision)},
        {QStringLiteral("activities"), QJsonArray::fromVariantList(m_files->activitySnapshot())}}).toJson(QJsonDocument::Compact));
}
void TransferActivityBridge::cancel(const QString &id) { m_files->cancelActivity(id); }
