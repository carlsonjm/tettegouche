#pragma once
#include "BluetoothContext.h"
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <functional>

class RelatedInfo final : public QObject
{
    Q_OBJECT
public:
    explicit RelatedInfo(QObject *parent = nullptr);
    QVariantList items(const QString &key);
    static QString keyForSetting(const QString &identity);
    static QVariantList audioRows(const QByteArray &json, const QString &kind);
    static QVariantList displayRows(const QByteArray &json);
    static QVariantList networkRows(const QByteArray &text);
Q_SIGNALS:
    void changed();
private:
    using Parse = std::function<QVariantList(const QByteArray &)>;
    void request(const QString &key);
    void publish(const QString &key, QVariantList rows);
    void process(const QString &key, const QString &program, const QStringList &args, Parse parse);
    void properties(const QString &key, const QString &service, const QString &path,
                    const QString &interface, bool system,
                    std::function<QVariantList(const QVariantMap &)> parse);
    QHash<QString, QVariantList> m_rows;
    QSet<QString> m_requested;
    BluetoothContext m_bluetooth;
};
