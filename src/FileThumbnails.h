#pragma once

#include <QQuickAsyncImageProvider>
#include <QString>

// Thumbnails for Files' tiles from KDE's previews, which read and fill the
// thumbnail cache Dolphin shares, for photos, videos, PDFs and documents only.
// At most four are made at once and the rest wait in order; a tile that leaves
// the screen or a folder that changes cancels its request. KDE's own file size
// limits apply.
class FileThumbnails : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

    // Whether a file of this type gets a thumbnail.
    static bool covers(const QString &mimeType);
    // The image a tile asks for; a new modification time asks afresh.
    static QString source(const QString &path, const QString &mimeType, qint64 modified);

    // For tests: requests being made now, and the most ever made at once.
    static int running();
    static int mostRunning();
};
