#include "FileThumbnails.h"

#include <KFileItem>
#include <KIO/PreviewJob>
#include <KPluginMetaData>

#include <QCoreApplication>
#include <QHash>
#include <QMimeDatabase>
#include <QPixmap>
#include <QQuickTextureFactory>
#include <QUrl>
#include <QUrlQuery>

#include <atomic>
#include <deque>
#include <mutex>

namespace
{
// Photos, videos, PDFs and documents; fonts, sound, text and folders keep
// their icons.
const QStringList Plugins{
    QStringLiteral("imagethumbnail"),
    QStringLiteral("jpegthumbnail"),
    QStringLiteral("rawthumbnail"),
    QStringLiteral("svgthumbnail"),
    QStringLiteral("exrthumbnail"),
    QStringLiteral("windowsimagethumbnail"),
    QStringLiteral("kraorathumbnail"),
    QStringLiteral("ffmpegthumbs"),
    QStringLiteral("gsthumbnail"),
    QStringLiteral("opendocumentthumbnail"),
    QStringLiteral("ebookthumbnail"),
    QStringLiteral("mobithumbnail"),
    QStringLiteral("comicbookthumbnail"),
    QStringLiteral("djvuthumbnail"),
};
constexpr int MostAtOnce = 4;

std::atomic<int> s_running{0};
std::atomic<int> s_mostRunning{0};

class ThumbnailResponse : public QQuickImageResponse
{
public:
    QQuickTextureFactory *textureFactory() const override
    {
        std::lock_guard lock(m_lock);
        return m_image.isNull() ? nullptr : QQuickTextureFactory::textureFactoryForImage(m_image);
    }
    QString errorString() const override
    {
        std::lock_guard lock(m_lock);
        return m_error;
    }
    void cancel() override;

    // Called once, in the GUI thread; the engine may delete the response after.
    void finish(const QImage &image, const QString &error)
    {
        {
            std::lock_guard lock(m_lock);
            m_image = image;
            m_error = error;
        }
        Q_EMIT finished();
    }

    quint64 id = 0;

private:
    mutable std::mutex m_lock;
    QImage m_image;
    QString m_error;
};

// Runs KDE's preview jobs in the GUI thread, where they belong. Requests are
// known by number, since the engine may delete a response once it finishes.
class ThumbnailQueue : public QObject
{
public:
    struct Request {
        quint64 id = 0;
        ThumbnailResponse *response = nullptr;
        KFileItem item;
        int size = 0;
    };

    static ThumbnailQueue *instance()
    {
        static ThumbnailQueue *queue = [] {
            auto *created = new ThumbnailQueue;
            created->moveToThread(QCoreApplication::instance()->thread());
            return created;
        }();
        return queue;
    }

    void add(const Request &request)
    {
        m_pending.push_back(request);
        startMore();
    }

    void cancel(quint64 id)
    {
        for (auto it = m_pending.begin(); it != m_pending.end(); ++it) {
            if (it->id == id) {
                ThumbnailResponse *response = it->response;
                m_pending.erase(it);
                response->finish({}, QStringLiteral("cancelled"));
                return;
            }
        }
        for (auto it = m_active.begin(); it != m_active.end(); ++it) {
            if (it.value().id == id) {
                KJob *job = it.key();
                const Request request = it.value();
                m_active.erase(it);
                --s_running;
                job->kill(KJob::Quietly);
                request.response->finish({}, QStringLiteral("cancelled"));
                startMore();
                return;
            }
        }
    }

private:
    void startMore()
    {
        while (m_active.size() < MostAtOnce && !m_pending.empty()) {
            const Request request = m_pending.front();
            m_pending.pop_front();
            auto *job = KIO::filePreview(KFileItemList{request.item}, QSize(request.size, request.size), &Plugins);
            m_active.insert(job, request);
            const int now = ++s_running;
            int most = s_mostRunning.load();
            while (now > most && !s_mostRunning.compare_exchange_weak(most, now)) { }
            connect(job, &KIO::PreviewJob::gotPreview, this, [this, job](const KFileItem &, const QPixmap &preview) {
                settle(job, preview.toImage(), QString());
            });
            connect(job, &KIO::PreviewJob::failed, this, [this, job](const KFileItem &) {
                settle(job, {}, QStringLiteral("no preview"));
            });
            connect(job, &KJob::result, this, [this, job](KJob *) {
                settle(job, {}, QStringLiteral("no preview"));
            });
        }
    }

    void settle(KJob *job, const QImage &image, const QString &error)
    {
        const auto it = m_active.find(job);
        if (it == m_active.end()) {
            return;
        }
        const Request request = it.value();
        m_active.erase(it);
        --s_running;
        request.response->finish(image, error);
        startMore();
    }

    std::deque<Request> m_pending;
    QHash<KJob *, Request> m_active;
};

void ThumbnailResponse::cancel()
{
    const quint64 requestId = id;
    QMetaObject::invokeMethod(
        ThumbnailQueue::instance(),
        [requestId] {
            ThumbnailQueue::instance()->cancel(requestId);
        },
        Qt::QueuedConnection);
}
}

QQuickImageResponse *FileThumbnails::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    static std::atomic<quint64> nextId{0};
    auto *response = new ThumbnailResponse;
    response->id = ++nextId;
    const QString path = QUrl::fromPercentEncoding(id.section(QLatin1Char('?'), 0, 0).toUtf8());
    const QUrlQuery query(id.section(QLatin1Char('?'), 1));
    const QString mimeType = query.queryItemValue(QStringLiteral("type"), QUrl::FullyDecoded);
    // KDE's cache keeps 128, 256 and 512 pixel thumbnails; ask for the one
    // that covers the tile.
    const int wanted = std::max(requestedSize.width(), requestedSize.height());
    const int size = wanted <= 128 ? 128 : wanted <= 256 ? 256 : 512;
    // The file is looked at here, off the GUI thread.
    const KFileItem item(QUrl::fromLocalFile(path), mimeType, KFileItem::Unknown);
    const quint64 requestId = response->id;
    QMetaObject::invokeMethod(
        ThumbnailQueue::instance(),
        [requestId, response, item, size] {
            ThumbnailQueue::instance()->add({requestId, response, item, size});
        },
        Qt::QueuedConnection);
    return response;
}

bool FileThumbnails::covers(const QString &mimeType)
{
    static const QStringList covered = [] {
        QStringList types;
        for (const auto &plugin : KPluginMetaData::findPlugins(QStringLiteral("kf6/thumbcreator"))) {
            if (Plugins.contains(plugin.pluginId())) {
                types += plugin.mimeTypes();
            }
        }
        return types;
    }();
    // Sound keeps its icon, even in a container video shares, as Ogg does.
    if (mimeType.startsWith(QLatin1String("audio/"))) {
        return false;
    }
    static QHash<QString, bool> known;
    if (const auto it = known.constFind(mimeType); it != known.cend()) {
        return *it;
    }
    const QMimeType type = QMimeDatabase().mimeTypeForName(mimeType);
    bool result = false;
    for (const auto &name : covered) {
        if (name.endsWith(QLatin1String("/*")) ? mimeType.startsWith(name.chopped(1)) : type.isValid() && type.inherits(name)) {
            result = true;
            break;
        }
    }
    known.insert(mimeType, result);
    return result;
}

QString FileThumbnails::source(const QString &path, const QString &mimeType, qint64 modified)
{
    return QStringLiteral("image://thumbnail/") + QString::fromLatin1(QUrl::toPercentEncoding(path)) + QStringLiteral("?type=")
        + QString::fromLatin1(QUrl::toPercentEncoding(mimeType)) + QStringLiteral("&t=") + QString::number(modified);
}

int FileThumbnails::running()
{
    return s_running.load();
}

int FileThumbnails::mostRunning()
{
    return s_mostRunning.load();
}
