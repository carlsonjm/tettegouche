#pragma once
#include "MprisActivityProvider.h"
#include "DesktopJobProvider.h"
#include "FinishNotices.h"
#include "IncomingFileProvider.h"
#include "TetteTransferProvider.h"
#include <memory>
#include <QSet>

class ActivityModel : public QObject {
    Q_OBJECT
public:
    static std::shared_ptr<ActivityModel> acquire();
    explicit ActivityModel(const QDBusConnection &bus, const QString &downloads, QObject *parent = nullptr);
    QVariantList activities() const { return m_rows; }
    void invoke(const QString &id, int generation, const QString &action, const QVariant &value = {});
    QUrl destinationForReveal(const QString &id, int generation) const;
    // Show in Files was used on this row; an end waiting there goes no further.
    void revealed(const QString &id, int generation);
Q_SIGNALS:
    void changed();
    // Show in Files was chosen on the notice of a file that arrived.
    void revealRequested(const QString &path);
private:
    friend class ActivityProviderTest;
    void refresh();
    void reconcile(const QVariantList &transfers, const QVariantList &media, const QVariantList &files);
    MprisActivityProvider m_media;
    DesktopJobProvider m_jobs;
    IncomingFileProvider m_files;
    TetteTransferProvider m_tette;
    FinishNotices m_notices;
    QVariantList m_rows;
    QMap<QString, QVariantMap> m_routes;
    QMap<QString, QString> m_presentations;
    QMap<QString, QSet<QString>> m_destinations;
    QMap<QString, QSet<QString>> m_claimedFiles;
    QMap<QString, qint64> m_consumedFiles;
    int m_token = 0;
    bool m_refreshPending = false;
};
