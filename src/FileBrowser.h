#pragma once

#include "FileDevices.h"
#include "FileQuestions.h"

#include <KApplicationTrader>
#include <KCoreDirLister>
#include <KFileUtils>
#include <KJobUiDelegate>
#include <KIO/EmptyTrashJob>
#include <KIO/ListJob>
#include <KFileItem>
#include <KFormat>
#include <KLocalizedString>
#include <KUrlMimeData>
#include <KIO/DirectorySizeJob>
#include <KIO/Job>
#include <KIO/CopyJob>
#include <KIO/MkdirJob>
#include <KIO/RestoreJob>
#include <KIO/StatJob>
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QCollator>
#include <QDir>
#include <QMimeDatabase>
#include <QThreadPool>
#include <QElapsedTimer>
#include <QTimer>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QVariantList>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QUuid>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <algorithm>
#include <functional>
#include <memory>

// Local browsing and explicit asynchronous copy/create. Each listing has its own lifetime so late replies
// from a previous tab cannot replace the current folder. No shell operations.
//
// A place is a local folder, Recent, or a search of a folder and everything inside it. Recent and a
// search are KDE locations whose items stand for local files elsewhere, so every item is known by
// the local path it stands for, and nothing is created or pasted into them.
class FileBrowser : public QObject
{
    Q_OBJECT
    friend class ActivityProviderTest;
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(QVariantList tabs READ tabs NOTIFY changed)
    Q_PROPERTY(QVariantList places READ places NOTIFY placesChanged)
    Q_PROPERTY(QVariantList crumbs READ crumbs NOTIFY changed)
    Q_PROPERTY(int currentTab READ currentTab NOTIFY changed)
    Q_PROPERTY(QString path READ path NOTIFY changed)
    Q_PROPERTY(QString placeKind READ placeKind NOTIFY changed)
    Q_PROPERTY(bool inFolder READ inFolder NOTIFY changed)
    Q_PROPERTY(QString folder READ folder NOTIFY changed)
    Q_PROPERTY(QString searchText READ searchText NOTIFY changed)
    Q_PROPERTY(bool searching READ searching NOTIFY changed)
    Q_PROPERTY(bool searchOffered READ searchOffered NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool listingFailed READ listingFailed NOTIFY changed)
    Q_PROPERTY(bool canWrite READ canWrite NOTIFY changed)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool opening READ opening NOTIFY changed)
    Q_PROPERTY(bool canBack READ canBack NOTIFY changed)
    Q_PROPERTY(bool canForward READ canForward NOTIFY changed)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY changed)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY changed)
    Q_PROPERTY(bool hidden READ hidden WRITE setHidden NOTIFY changed)
    Q_PROPERTY(double scroll READ scroll WRITE setScroll NOTIFY changed)
    Q_PROPERTY(QString selectedPath READ selectedPath WRITE setSelectedPath NOTIFY selectionChanged)
    Q_PROPERTY(QStringList selectedPaths READ selectedPaths NOTIFY selectionChanged)
    Q_PROPERTY(QString focusedPath READ focusedPath WRITE setFocusedPath NOTIFY selectionChanged)
    Q_PROPERTY(bool selecting READ selecting WRITE setSelecting NOTIFY selectionChanged)
    Q_PROPERTY(bool working READ working NOTIFY operationChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY operationChanged)
    Q_PROPERTY(bool canPaste READ canPaste NOTIFY clipboardChanged)
    Q_PROPERTY(bool canRestoreTrash READ canRestoreTrash NOTIFY operationChanged)
    Q_PROPERTY(QVariantList operations READ operations NOTIFY operationChanged)
    Q_PROPERTY(int tileSize READ tileSize WRITE setTileSize NOTIFY tileSizeChanged)
    Q_PROPERTY(QString revealPath READ revealPath WRITE setRevealPath NOTIFY revealPathChanged)
    Q_PROPERTY(bool revealProperties READ revealProperties WRITE setRevealProperties NOTIFY revealPathChanged)
    Q_PROPERTY(QVariantMap details READ details NOTIFY detailsChanged)
    Q_PROPERTY(QVariantMap question READ question NOTIFY questionChanged)
    Q_PROPERTY(bool canCompress READ canCompress NOTIFY selectionChanged)
    Q_PROPERTY(bool canExtract READ canExtract NOTIFY selectionChanged)
    Q_PROPERTY(bool canHide READ canHide NOTIFY selectionChanged)
    Q_PROPERTY(bool canUnhide READ canUnhide NOTIFY selectionChanged)
    Q_PROPERTY(int trashItems READ trashItems NOTIFY trashChanged)
    Q_PROPERTY(QString trashSize READ trashSize NOTIFY trashChanged)
public:
    // The image a tile shows for a file, or none; set by the launcher, which
    // owns the thumbnails.
    using ThumbnailSource = std::function<QString(const QString &path, const QString &mimeType, qint64 modified)>;
    // A file's own details, as labelled rows, read off the GUI thread.
    using DetailReader = std::function<QVariantList(const QString &path, const QString &mimeType)>;
    explicit FileBrowser(QObject *parent = nullptr) : QObject(parent) {
        m_showArrived.setSingleShot(true);
        connect(&m_showArrived, &QTimer::timeout, this, &FileBrowser::rebuild);
        QSettings settings;
        m_operationStatus = settings.value(QStringLiteral("Files/lastOperationError")).toString();
        settings.remove(QStringLiteral("Files/lastOperationError"));
        connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &FileBrowser::clipboardChanged);
        const auto paths = settings.value(QStringLiteral("Files/paths")).toStringList();
        for (const auto &p : paths.mid(0, 20))
            // Do not stat saved paths during launcher startup. Offline mounts
            // must report through the asynchronous lister, not block Meta.
            if (QDir::isAbsolutePath(p)) m_tabs.append(Tab{{QDir::cleanPath(p)}, 0, 0});
            else if (p == recentLocation()) m_tabs.append(Tab{{p}, 0, 0});
        if (m_tabs.isEmpty()) m_tabs.append(Tab{{QDir::homePath()}, 0, 0});
        m_current = std::clamp(settings.value(QStringLiteral("Files/current"), 0).toInt(), 0, int(m_tabs.size())-1);
        m_tileSize = std::clamp(settings.value(QStringLiteral("Files/tileSize"), 1).toInt(), 0, 3);
    }
    ~FileBrowser() override { *m_alive=false; save(); }
    void setThumbnailSource(ThumbnailSource source) { m_thumbnailSource=std::move(source); rebuild(); }
    void setDetailReader(DetailReader reader) { m_detailReader=std::move(reader); }
    // The drives beside the places; set by the launcher, which owns them.
    void setDevices(FileDevices *devices) {
        m_devices=devices;
        connect(devices,&FileDevices::changed,this,&FileBrowser::drivesChanged);
        connect(devices,&FileDevices::opened,this,[this](const QString &id,const QString &p) {
            if(id!=m_driveOpening)return;
            m_driveOpening.clear(); navigate(p); rebuildPlaces();
        });
        connect(devices,&FileDevices::failed,this,[this](const QString &id,const QString &message) {
            if(id==m_driveOpening)m_driveOpening.clear();
            m_error=message; rebuildPlaces(); Q_EMIT changed();
        });
        connect(devices,&FileDevices::removed,this,[this](const QString &,const QString &label) {
            m_operationStatus=i18n("“%1” can be unplugged.", label); Q_EMIT operationChanged();
        });
    }
    // Opens a drive from the places, mounting it first if it is not.
    Q_INVOKABLE void openDrive(const QString &id) {
        const auto drive=findDrive(id);
        if(drive.id.isEmpty() || drive.busy() || m_ejectAfter.contains(id))return;
        if(drive.mounted) { navigate(drive.path); return; }
        m_driveOpening=id; m_error.clear(); Q_EMIT changed();
        m_devices->open(id);
    }
    // The phone plugged in that a KDE address names, or nothing.
    QString phoneForAddress(const QUrl &url) { return m_devices ? m_devices->phoneForAddress(url) : QString(); }
    // Makes a plugged-in drive safe to pull out. A copy or move Files is making
    // to or from it finishes first, and the drive ejects after it.
    Q_INVOKABLE void ejectDrive(const QString &id) {
        const auto drive=findDrive(id);
        if(drive.id.isEmpty() || !drive.removable || drive.phone || !drive.mounted || drive.busy() || m_ejectAfter.contains(id))return;
        if(touches(drive.path)) { m_ejectAfter.insert(id); rebuildPlaces(); return; }
        m_devices->remove(id);
    }
    // Properties: what is known at once, then a folder's total size or a
    // file's own details as they arrive.
    QVariantMap details() const { return m_details; }
    Q_INVOKABLE void describe(const QString &p) {
        stopDescribing();
        const auto item=listedItem(p);
        if(item.isNull())return;
        const auto generation=++m_detailsGeneration;
        const auto mimeType=item.mimetype();
        const KFormat format;
        QVariantList rows;
        const auto row=[&rows](const QString &label,const QString &value,const QString &key=QString()) {
            if(!value.isEmpty())rows.append(QVariantMap{{QStringLiteral("label"),label},{QStringLiteral("value"),value},{QStringLiteral("key"),key}});
        };
        const auto when=[&format,&item](KFileItem::FileTimes which) {
            const auto time=item.time(which);
            return time.isValid() ? format.formatRelativeDateTime(time,QLocale::ShortFormat) : QString();
        };
        row(i18n("Kind"),item.isDir() ? i18n("Folder") : QMimeDatabase().mimeTypeForName(mimeType).comment());
        if(item.isDir()) { row(i18n("Size"),i18n("Counting…"),QStringLiteral("size")); row(i18n("Contains"),i18n("Counting…"),QStringLiteral("contains")); }
        else row(i18n("Size"),item.size()<1024 ? QLocale().formattedDataSize(item.size())
                 : i18n("%1 (%2 bytes)", QLocale().formattedDataSize(item.size()), QLocale().toString(item.size())));
        row(i18n("Where"),QFileInfo(p).path());
        row(i18n("Modified"),when(KFileItem::ModificationTime));
        row(i18n("Created"),when(KFileItem::CreationTime));
        row(i18n("Last opened"),when(KFileItem::AccessTime));
        m_details=QVariantMap{{QStringLiteral("path"),p},{QStringLiteral("name"),item.text()},{QStringLiteral("icon"),item.iconName()},
            {QStringLiteral("thumbnail"),!item.isDir() && m_thumbnailSource ? m_thumbnailSource(p,mimeType,item.time(KFileItem::ModificationTime).toSecsSinceEpoch()) : QString()},
            {QStringLiteral("rows"),rows}};
        Q_EMIT detailsChanged();
        if(item.isDir()) {
            auto *job=KIO::directorySize(QUrl::fromLocalFile(p));
            job->setUiDelegate(nullptr);
            m_sizeJob=job;
            connect(job,&KJob::result,this,[this,job,generation] {
                if(generation!=m_detailsGeneration)return;
                m_sizeJob=nullptr;
                if(job->error()) { setDetail(QStringLiteral("size"),i18n("Unknown")); setDetail(QStringLiteral("contains"),i18n("Unknown")); return; }
                setDetail(QStringLiteral("size"),QLocale().formattedDataSize(job->totalSize()));
                setDetail(QStringLiteral("contains"),i18nc("what a folder holds: files, folders","%1 and %2",
                    i18np("1 file","%1 files",job->totalFiles()),i18np("1 folder","%1 folders",job->totalSubdirs())));
            });
        } else if(m_detailReader) {
            const auto reader=m_detailReader;
            const auto alive=m_alive;
            QThreadPool::globalInstance()->start([this,reader,alive,p,mimeType,generation] {
                const auto more=reader(p,mimeType);
                QMetaObject::invokeMethod(QCoreApplication::instance(),[this,alive,more,generation] {
                    if(!*alive || generation!=m_detailsGeneration || more.isEmpty())return;
                    auto rows=m_details.value(QStringLiteral("rows")).toList(); rows+=more;
                    m_details[QStringLiteral("rows")]=rows; Q_EMIT detailsChanged();
                },Qt::QueuedConnection);
            });
        }
    }
    // A name already taken, as the person is asked about it: one question at a
    // time, the others waiting behind it.
    QVariantMap question() const { return m_questions.isEmpty() ? QVariantMap{} : m_questions.first().shown; }
    // "replace", "skip" or "keep", for this item or the rest too; anything else
    // stops the copy or move. Nothing is replaced without "replace".
    Q_INVOKABLE void answer(const QString &choice,bool forAll) {
        if(m_questions.isEmpty())return;
        const auto question=m_questions.takeFirst();
        Q_EMIT questionChanged();
        if(!question.asker || !question.job)return;
        auto result=KIO::Result_Cancel;
        QUrl renamed;
        if(choice==QLatin1String("replace")) result=forAll ? KIO::Result_OverwriteAll : KIO::Result_Overwrite;
        else if(choice==QLatin1String("skip")) result=forAll ? KIO::Result_AutoSkip : KIO::Result_Skip;
        else if(choice==QLatin1String("keep")) {
            result=forAll ? KIO::Result_AutoRename : KIO::Result_Rename;
            const auto parent=question.destination.adjusted(QUrl::RemoveFilename|QUrl::StripTrailingSlash);
            renamed=QUrl::fromLocalFile(QDir(parent.toLocalFile()).filePath(KFileUtils::suggestName(parent,question.destination.fileName())));
        }
        question.asker->answerNameTaken(result,renamed,question.job);
    }
    // Open With: the applications for a file's kind, the default first.
    Q_INVOKABLE QVariantMap openWithChoices(const QString &p) const {
        const auto item=listedItem(p);
        if(item.isNull() || item.isDir())return {};
        const auto mimeType=item.mimetype();
        const auto preferred=KApplicationTrader::preferredService(mimeType);
        QVariantList suggested;
        for(const auto &service:KApplicationTrader::queryByMimeType(mimeType))
            suggested.append(applicationEntry(service,preferred && service->storageId()==preferred->storageId()));
        return QVariantMap{{QStringLiteral("path"),p},{QStringLiteral("name"),item.text()},
            {QStringLiteral("kind"),QMimeDatabase().mimeTypeForName(mimeType).comment()},
            {QStringLiteral("suggested"),suggested},{QStringLiteral("hasDefault"),bool(preferred)}};
    }
    Q_INVOKABLE QVariantList allApplications() const {
        auto services=KApplicationTrader::query([](const KService::Ptr &service){ return !service->noDisplay(); });
        QCollator collator; collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::sort(services.begin(),services.end(),[&collator](const KService::Ptr &a,const KService::Ptr &b){ return collator.compare(a->name(),b->name())<0; });
        QVariantList result;
        for(const auto &service:services)result.append(applicationEntry(service,false));
        return result;
    }
    // Opens the file in the chosen application; "always" makes it KDE's
    // default for that kind of file first.
    Q_INVOKABLE void openWith(const QString &p,const QString &applicationId,bool always) {
        if(m_opening)return;
        const auto item=listedItem(p);
        const auto service=KService::serviceByStorageId(applicationId);
        if(item.isNull() || item.isDir() || !service)return;
        if(always)KApplicationTrader::setPreferredService(item.mimetype(),service);
        m_error.clear(); m_opening=true; m_openingUrl=QUrl::fromLocalFile(p); Q_EMIT changed();
        Q_EMIT openWithRequested(QUrl::fromLocalFile(p),applicationId);
    }
    // Compress and Extract are Ark's own batch jobs, which Plasma tracks, so
    // their progress shows in Ambient.
    bool canCompress() const {
        if(arkPath().isEmpty() || selectedPaths().isEmpty())return false;
        for(const auto &p:selectedPaths()) if(listedItem(p).isNull())return false;
        return true;
    }
    bool canExtract() const {
        if(arkPath().isEmpty() || selectedPaths().isEmpty())return false;
        const auto ark=KService::serviceByDesktopName(QStringLiteral("org.kde.ark"));
        if(!ark)return false;
        for(const auto &p:selectedPaths()) { const auto item=listedItem(p); if(item.isNull() || item.isDir() || !ark->hasMimeType(item.mimetype()))return false; }
        return true;
    }
    Q_INVOKABLE void compressSelected() {
        if(!canCompress())return;
        // One item becomes its own name as a zip; several, Archive.zip.
        const QStringList arguments=QStringList{QStringLiteral("--batch"),QStringLiteral("--add"),QStringLiteral("--changetofirstpath"),
            QStringLiteral("--autofilename"),QStringLiteral("zip")}+selectedPaths();
        startArk(arguments,QFileInfo(selectedPaths().first()).path(),i18n("Compressing with Ark…"));
    }
    Q_INVOKABLE void extractSelected() {
        if(!canExtract())return;
        // Beside the archive, in a folder of its own when it holds several.
        for(const auto &p:selectedPaths())
            startArk({QStringLiteral("--batch"),QStringLiteral("--autodestination"),QStringLiteral("--autosubfolder"),p},QFileInfo(p).path(),i18n("Extracting with Ark…"));
    }
    // Hide lists the chosen names in their folder's .hidden, which KDE's file
    // layer and GNOME read, so a file keeps its name. Both are offered only in
    // a folder that can be written; a name starting with a dot is hidden by
    // the name itself, so it offers neither.
    bool canHide() const {
        if(!canWrite() || selectedPaths().isEmpty())return false;
        for(const auto &p:selectedPaths()) { const auto item=listedItem(p); if(!item.isNull() && !item.isHidden())return true; }
        return false;
    }
    bool canUnhide() const {
        if(!canWrite() || selectedPaths().isEmpty())return false;
        for(const auto &p:selectedPaths()) if(!hiddenByList(listedItem(p)))return false;
        return true;
    }
    Q_INVOKABLE void hideSelected() { if(canHide())setListedHidden(true); }
    Q_INVOKABLE void unhideSelected() { if(canUnhide())setListedHidden(false); }
    // What Trash holds, asked when the folder's menu opens.
    int trashItems() const { return m_trashItems; }
    QString trashSize() const { return m_trashSize; }
    Q_INVOKABLE void checkTrash() {
        const QUrl trash(QStringLiteral("trash:/"));
        auto *list=KIO::listDir(trash,KIO::HideProgressInfo); list->setUiDelegate(nullptr);
        auto count=std::make_shared<int>(0);
        connect(list,&KIO::ListJob::entries,this,[count](KIO::Job *,const KIO::UDSEntryList &entries) {
            for(const auto &entry:entries) if(entry.stringValue(KIO::UDSEntry::UDS_NAME)!=QLatin1String("."))++*count;
        });
        connect(list,&KJob::result,this,[this,count](KJob *job){ m_trashItems=job->error() ? 0 : *count; Q_EMIT trashChanged(); });
        auto *size=KIO::directorySize(trash); size->setUiDelegate(nullptr);
        connect(size,&KJob::result,this,[this,size]{ m_trashSize=size->error() ? QString() : QLocale().formattedDataSize(size->totalSize()); Q_EMIT trashChanged(); });
    }
    // The one permanent delete Files offers, after the person confirms it.
    Q_INVOKABLE void emptyTrash() {
        auto *job=KIO::emptyTrash(); job->setUiDelegate(nullptr);
        connect(job,&KJob::result,this,[this](KJob *finished) {
            if(finished->error())return;
            QSettings().remove(QStringLiteral("Files/restoreTrash"));
            m_trashItems=0; m_trashSize.clear(); Q_EMIT trashChanged();
        });
        watchOperation(job,i18n("Emptying Trash…"));
    }
    Q_INVOKABLE void stopDescribing() {
        ++m_detailsGeneration;
        if(m_sizeJob) { m_sizeJob->kill(); m_sizeJob=nullptr; }
        if(!m_details.isEmpty()) { m_details.clear(); Q_EMIT detailsChanged(); }
    }
    // Each copy or move, for Ambient: its own progress and the actions its job
    // supports, and for a few seconds each one that failed, which Ambient
    // keeps its minute. Other operations are too short to be worth a row.
    QVariantList activitySnapshot() const {
        QVariantList rows;
        const auto now=QDateTime::currentMSecsSinceEpoch();
        for (const auto &failure : m_failures) {
            if (failure.until<now) continue;
            rows.append(QVariantMap{{QStringLiteral("id"), failure.id}, {QStringLiteral("generation"), 1},
                {QStringLiteral("kind"), QStringLiteral("transfer")}, {QStringLiteral("state"), QStringLiteral("failed")},
                {QStringLiteral("source"), i18n("Files")}, {QStringLiteral("icon"), QStringLiteral("folder-download-symbolic")},
                {QStringLiteral("title"), failure.title}, {QStringLiteral("description"), failure.why},
                {QStringLiteral("evidence"), QStringLiteral("job")}, {QStringLiteral("capabilities"), QVariantMap{}}});
        }
        for (const auto &op : m_operations) {
            if (!op.job || !op.copying) continue;
            const bool suspended = op.job->isSuspended();
            const bool suspendable = op.job->capabilities().testFlag(KJob::Suspendable);
            QVariantMap row{{QStringLiteral("id"), op.id}, {QStringLiteral("generation"), 1}, {QStringLiteral("kind"), QStringLiteral("transfer")},
                {QStringLiteral("state"), suspended ? QStringLiteral("suspended") : QStringLiteral("running")},
                {QStringLiteral("source"), i18n("Files")}, {QStringLiteral("icon"), QStringLiteral("folder-download-symbolic")},
                {QStringLiteral("title"), op.destination.isEmpty() ? op.label : op.destination.fileName()},
                {QStringLiteral("evidence"), QStringLiteral("job")},
                {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("cancel"), op.job->capabilities().testFlag(KJob::Killable)},
                    {QStringLiteral("suspend"), suspendable && !suspended}, {QStringLiteral("resume"), suspendable && suspended}}}};
            if (op.percentKnown) row[QStringLiteral("progress")] = op.job->percent()/100.0;
            if (op.job->totalAmount(KJob::Bytes) > 0) {
                row[QStringLiteral("totalBytes")] = op.job->totalAmount(KJob::Bytes);
                row[QStringLiteral("processedBytes")] = op.job->processedAmount(KJob::Bytes);
            }
            if (!op.destination.isEmpty()) row[QStringLiteral("destinationUrl")] = op.destination.toString();
            rows.append(row);
        }
        return rows;
    }
    void cancelActivity(const QString &id) { cancelOperation(id); }
    void suspendActivity(const QString &id) { suspendOperation(id); }
    void resumeActivity(const QString &id) { resumeOperation(id); }
    // A copy or move failed a moment ago, and Ambient may not have heard yet.
    bool failedJustNow() const {
        const auto now=QDateTime::currentMSecsSinceEpoch();
        return std::any_of(m_failures.cbegin(),m_failures.cend(),[now](const Failure &f) { return f.until>=now; });
    }
    // What is running now, for Files itself to show: each with its reported
    // progress and the actions its job supports.
    QVariantList operations() const {
        QVariantList rows;
        for (const auto &op : m_operations) {
            if (!op.job) continue;
            QVariantMap row{{QStringLiteral("id"), op.id}, {QStringLiteral("label"), op.label},
                {QStringLiteral("title"), op.destination.isEmpty() ? QString() : op.destination.fileName()},
                {QStringLiteral("suspended"), op.job->isSuspended()},
                {QStringLiteral("canSuspend"), op.job->capabilities().testFlag(KJob::Suspendable)},
                {QStringLiteral("canCancel"), op.job->capabilities().testFlag(KJob::Killable)},
                {QStringLiteral("copying"), op.copying}};
            if (op.percentKnown) row[QStringLiteral("progress")] = op.job->percent()/100.0;
            if (op.job->totalAmount(KJob::Bytes) > 0) {
                row[QStringLiteral("totalBytes")] = op.job->totalAmount(KJob::Bytes);
                row[QStringLiteral("processedBytes")] = op.job->processedAmount(KJob::Bytes);
            }
            rows.append(row);
        }
        return rows;
    }
    Q_INVOKABLE void cancelOperation(const QString &id) {
        if (auto *job = operationJob(id); job && job->capabilities().testFlag(KJob::Killable)) job->kill(KJob::EmitResult);
    }
    Q_INVOKABLE void suspendOperation(const QString &id) {
        if (auto *job = operationJob(id); job && job->capabilities().testFlag(KJob::Suspendable) && !job->isSuspended()) job->suspend();
    }
    Q_INVOKABLE void resumeOperation(const QString &id) {
        if (auto *job = operationJob(id); job && job->isSuspended()) job->resume();
    }
    int tileSize() const { return m_tileSize; }
    void setTileSize(int size) {
        size = std::clamp(size, 0, 3);
        if (size == m_tileSize) return;
        m_tileSize = size; QSettings().setValue(QStringLiteral("Files/tileSize"), size); Q_EMIT tileSizeChanged();
    }
    // A file to bring into view once its folder has listed, as Show in Files asks.
    QString revealPath() const { return m_revealPath; }
    void setRevealPath(const QString &p) { if (p == m_revealPath) return; m_revealPath = p; Q_EMIT revealPathChanged(); }
    // Whether Properties open for the file brought into view, as another
    // application's request for them asks.
    bool revealProperties() const { return m_revealProperties; }
    void setRevealProperties(bool v) { if (v == m_revealProperties) return; m_revealProperties = v; Q_EMIT revealPathChanged(); }
    // Items shown chosen in their folder, as another application's "Show in
    // folder" asks; any outside the first one's folder are left out.
    void reveal(const QStringList &paths, bool properties = false) {
        if (paths.isEmpty() || !QDir::isAbsolutePath(paths.first())) return;
        const auto folder = QFileInfo(paths.first()).absolutePath();
        const bool shown = folder == path();
        navigate(folder);
        auto &t = m_tabs[m_current];
        t.selection.clear();
        for (const auto &p : paths)
            if (QFileInfo(p).absolutePath() == folder && !t.selection.contains(p)) t.selection.append(p);
        t.selected = t.selection.size() == 1 ? t.selection.first() : QString();
        t.anchor = t.focused = t.selection.first();
        Q_EMIT selectionChanged();
        setRevealPath(paths.first());
        setRevealProperties(properties);
        // A folder already shown lists nothing new, so nothing else would say
        // there is a file to bring into view.
        if (shown) Q_EMIT changed();
    }
    // A file from Recent or a search, chosen in the folder that holds it.
    Q_INVOKABLE void showInFolder(const QString &p) { if (QDir::isAbsolutePath(p)) reveal({p}); }
    // A search still looking stops; what it found so far stays.
    Q_INVOKABLE void stopSearch() {
        if (!m_searching || !m_lister) return;
        m_lister->stop(); m_searching=false; Q_EMIT changed();
    }
    // A folder in a tab of its own, or in the tab shown once there are 20.
    Q_INVOKABLE void openTab(const QString &p) {
        if (!QDir::isAbsolutePath(p)) return;
        if (m_tabs.size() >= 20) { navigate(p); return; }
        m_tabs.append(Tab{{QDir::cleanPath(p)}, 0, 0}); m_current = m_tabs.size()-1; refresh(); save();
    }
    void setStatus(const QString &status) { m_operationStatus = status; Q_EMIT operationChanged(); }
    QVariantList entries() const { return m_entries; }
    QVariantList tabs() const {
        QVariantList result;
        for (const auto &t : m_tabs) {
            const auto p = t.history[t.index];
            result.append(QVariantMap{{QStringLiteral("label"), locationLabel(p)}, {QStringLiteral("path"), p}});
        }
        return result;
    }
    QVariantList places() const { return m_places; }
    // The standard places, then folders mounted where removable media go.
    static QVariantList localPlaces(const QByteArray &mounts) {
        QVariantList result;
        QString section = QStringLiteral("places");
        const auto add = [&result, &section](const QString &label, const QString &p, const QString &icon) {
            if (!p.isEmpty()) result.append(QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("path"), p}, {QStringLiteral("icon"), icon},
                {QStringLiteral("section"), section}});
        };
        add(i18n("Recent"), recentLocation(), QStringLiteral("document-open-recent"));
        add(i18n("Home"), QDir::homePath(), QStringLiteral("user-home"));
        add(i18n("Documents"), QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), QStringLiteral("folder-documents"));
        add(i18n("Downloads"), QStandardPaths::writableLocation(QStandardPaths::DownloadLocation), QStringLiteral("folder-download"));
        add(i18n("Pictures"), QStandardPaths::writableLocation(QStandardPaths::PicturesLocation), QStringLiteral("folder-pictures"));
        // Linux mount metadata only: never stat/statvfs mounted filesystems.
        // A disconnected network/FUSE volume can block those calls indefinitely.
        section = QStringLiteral("drives");
        QStringList seen;
        for (const auto &line : mounts.split('\n')) {
            const auto fields = line.split(' ');
            if (fields.size() < 6) continue;
            QByteArray mount = fields[4];
            mount.replace("\\040", " "); mount.replace("\\011", "\t");
            mount.replace("\\012", "\n"); mount.replace("\\134", "\\");
            const QString p = QString::fromUtf8(mount);
            if (!seen.contains(p) && (p.startsWith(QStringLiteral("/run/media/")) || p.startsWith(QStringLiteral("/media/")) || p.startsWith(QStringLiteral("/mnt/")))) {
                seen.append(p);
                add(QDir(p).dirName(), p, QStringLiteral("drive-removable-media"));
            }
        }
        return result;
    }
    QVariantList crumbs() const {
        const auto p = path();
        switch (kindOf(p)) {
        case Kind::Recent:
            return {QVariantMap{{QStringLiteral("label"), i18n("Recent")}, {QStringLiteral("path"), p}}};
        case Kind::Search: {
            // The folder searched, then the search itself.
            auto result = folderCrumbs(searchFolderOf(p));
            result.append(QVariantMap{{QStringLiteral("label"), locationLabel(p)}, {QStringLiteral("path"), p}});
            return result;
        }
        case Kind::Folder:
            break;
        }
        return folderCrumbs(p);
    }
    int currentTab() const { return m_current; }
    QString path() const { return m_tabs[m_current].history[m_tabs[m_current].index]; }
    static QString recentLocation() { return QStringLiteral("recentlyused:/"); }
    QString placeKind() const {
        switch (kindOf(path())) {
        case Kind::Recent: return QStringLiteral("recent");
        case Kind::Search: return QStringLiteral("search");
        case Kind::Folder: break;
        }
        return QStringLiteral("folder");
    }
    // Only a folder takes new folders and pastes.
    bool inFolder() const { return kindOf(path()) == Kind::Folder; }
    // The local folder this place is about: the folder, or the one searched.
    QString folder() const {
        const auto p = path();
        return kindOf(p) == Kind::Folder ? p : kindOf(p) == Kind::Search ? searchFolderOf(p) : QString();
    }
    QString searchText() const { return kindOf(path()) == Kind::Search ? searchTermOf(path()) : QString(); }
    bool searching() const { return m_searching; }
    // What is typed can be looked for inside the folder's subfolders: offered
    // in a folder, and in a search once the text differs from what was searched.
    bool searchOffered() const {
        const auto term = m_filter.trimmed();
        return !term.isEmpty() && kindOf(path()) != Kind::Recent && term != searchText();
    }
    QString error() const { return m_error; }
    // The place shown could not be listed: Files says why where its files
    // would be, and offers the way back.
    bool listingFailed() const { return m_listingFailed; }
    // New folders and pastes are offered only where they can land.
    bool canWrite() const {
        if (kindOf(path()) != Kind::Folder || m_listingFailed) return false;
        const QFileInfo info(path());
        return !info.exists() || info.isWritable();
    }
    QString homePath() const { return QDir::homePath(); }
    bool busy() const { return m_busy; }
    bool opening() const { return m_opening; }
    Q_INVOKABLE void openSelected() {
        if (m_opening || m_busy || !m_lister || selectedPaths().size()!=1) return;
        // Only dispatch a selection from the currently displayed listing.
        // Passing a URL as data avoids shell parsing of filenames.
        const auto url = QUrl::fromLocalFile(selectedPath());
        const auto item = listedItem(selectedPath());
        if (item.isNull()) {
            m_error = i18n("This file is no longer available. Refresh the folder.");
            Q_EMIT changed(); return;
        }
        if (item.isDir()) {
            setSelecting(false);
            // A folder found in Recent or a search opens as itself, not
            // narrowed by the text that found it.
            if (!inFolder() && !m_filter.isEmpty()) { m_filter.clear(); Q_EMIT filterCleared(); }
            noteUsed(url);
            navigate(url.toLocalFile()); return;
        }
        // A file no application claims asks which one to use.
        if (!KApplicationTrader::preferredService(item.mimetype())) {
            m_error.clear(); Q_EMIT changed();
            Q_EMIT applicationChoiceNeeded(selectedPath()); return;
        }
        m_error.clear(); m_opening = true; m_openingUrl = url; Q_EMIT changed();
        Q_EMIT openRequested(url);
    }
    void finishOpen(const QString &error) {
        if (error.isEmpty() && m_openingUrl.isValid()) noteUsed(m_openingUrl);
        m_openingUrl.clear();
        m_opening = false; m_error = error; Q_EMIT changed();
    }
    bool canBack() const { return m_tabs[m_current].index > 0; }
    bool canForward() const { const auto &t=m_tabs[m_current]; return t.index+1<t.history.size(); }
    QString filter() const { return m_filter; }
    int sortMode() const { return m_sort; }
    bool hidden() const { return m_hidden; }
    double scroll() const { return m_tabs[m_current].scroll; }
    QString selectedPath() const { return m_tabs[m_current].selected; }
    QStringList selectedPaths() const { return m_tabs[m_current].selection; }
    QString focusedPath() const { return m_tabs[m_current].focused; }
    void setFocusedPath(const QString &p) { m_tabs[m_current].focused=p; Q_EMIT selectionChanged(); }
    bool selecting() const { return m_selecting; }
    void setSelecting(bool v) { m_selecting=v; if (!v) setSelectedPath(QString()); Q_EMIT selectionChanged(); }
    void setSelectedPath(const QString &v) {
        auto &t=m_tabs[m_current]; t.selected=v; t.anchor=v;
        if (!v.isEmpty()) t.focused=v;
        t.selection=v.isEmpty() ? QStringList{} : QStringList{v}; Q_EMIT selectionChanged();
    }
    Q_INVOKABLE void toggleSelected(const QString &p) {
        if (m_busy || !m_lister || listedItem(p).isNull()) return;
        auto &t=m_tabs[m_current];
        if (!t.selection.removeOne(p)) t.selection.append(p);
        t.anchor=p;
        t.focused=p;
        t.selected=t.selection.size()==1 ? t.selection.first() : QString(); Q_EMIT selectionChanged();
    }
    Q_INVOKABLE void selectRange(const QString &p, bool additive=false) {
        auto &t=m_tabs[m_current];
        QStringList visible;
        for (const auto &entry:m_entries) visible.append(entry.toMap().value(QStringLiteral("path")).toString());
        const int last=visible.indexOf(p);
        if (last<0 || m_busy) return;
        t.focused=p;
        int first=visible.indexOf(t.anchor);
        if (first<0) { first=last; t.anchor=p; }
        if (!additive) t.selection.clear();
        for (int i=std::min(first,last); i<=std::max(first,last); ++i)
            if (!t.selection.contains(visible[i])) t.selection.append(visible[i]);
        t.selected=t.selection.size()==1 ? t.selection.first() : QString(); Q_EMIT selectionChanged();
    }
    bool working() const { return !m_operations.isEmpty(); }
    Q_INVOKABLE void selectPaths(const QStringList &paths) {
        QStringList valid;
        for (const auto &entry : m_entries) {
            const auto p=entry.toMap().value(QStringLiteral("path")).toString();
            if (paths.contains(p)) valid.append(p);
        }
        auto &tab=m_tabs[m_current];
        if (tab.selection==valid) return;
        tab.selection=valid;
        tab.selected=valid.size()==1 ? valid.first() : QString();
        if (!valid.isEmpty()) { tab.focused=valid.last(); tab.anchor=valid.first(); }
        Q_EMIT selectionChanged();
    }
    Q_INVOKABLE void selectAll() {
        auto &t=m_tabs[m_current]; t.selection.clear();
        for (const auto &entry:m_entries) t.selection.append(entry.toMap().value(QStringLiteral("path")).toString());
        t.selected=t.selection.size()==1 ? t.selection.first() : QString();
        if (t.focused.isEmpty() && !t.selection.isEmpty()) t.focused=t.selection.first();
        Q_EMIT selectionChanged();
    }
    QString operationStatus() const { return m_operationStatus; }
    bool canPaste() const {
        const auto *mime=QGuiApplication::clipboard()->mimeData();
        if (!mime || !mime->hasUrls() || mime->urls().isEmpty()) return false;
        for (const auto &u:mime->urls()) if (!u.isLocalFile()) return false;
        return true;
    }
    Q_INVOKABLE void copySelected() {
        if (m_busy || !m_lister || selectedPaths().isEmpty()) return;
        QList<QUrl> urls;
        for (const auto &p:selectedPaths()) {
            const auto url=QUrl::fromLocalFile(p);
            if (listedItem(p).isNull()) { m_error=i18n("Selection changed. Refresh and select again."); Q_EMIT changed(); return; }
            urls.append(url);
        }
        auto *mime=new QMimeData; mime->setUrls(urls); QGuiApplication::clipboard()->setMimeData(mime);
        m_operationStatus=i18np("Copied 1 item to clipboard","Copied %1 items to clipboard",urls.size()); Q_EMIT operationChanged();
    }
    Q_INVOKABLE void paste() {
        if (inFolder()) pasteInto(path());
    }
    Q_INVOKABLE void cutSelected() {
        if(m_busy || m_opening || selectedPaths().isEmpty())return;
        copySelected();
        auto *mime=QGuiApplication::clipboard()->mimeData();
        if(!mime || mime->urls().size()!=selectedPaths().size())return;
        for(const auto &p:selectedPaths())if(!mime->urls().contains(QUrl::fromLocalFile(p)))return;
        auto *cut=new QMimeData;
        cut->setUrls(mime->urls());
        cut->setData(QStringLiteral("application/x-kde-cutselection"),QByteArray("1"));
        QGuiApplication::clipboard()->setMimeData(cut);
        m_operationStatus=i18np("Cut 1 item — paste to move","Cut %1 items — paste to move",selectedPaths().size()); Q_EMIT operationChanged();
    }
    Q_INVOKABLE void renameSelected(const QString &name) {
        if(m_busy || m_opening || selectedPaths().size()!=1 || !m_lister)return;
        if(name.isEmpty() || name==QStringLiteral(".") || name==QStringLiteral("..") || name.contains(QLatin1Char('/')) || name.contains(QChar::Null))return;
        const auto source=QUrl::fromLocalFile(selectedPaths().first());
        if(listedItem(source.toLocalFile()).isNull())return;
        // The new name stays in the item's own folder, which in Recent or a
        // search is not the place shown.
        const auto destination=QUrl::fromLocalFile(QDir(QFileInfo(source.toLocalFile()).path()).filePath(name));
        if(source==destination)return;
        auto *job=KIO::rename(source,destination,KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        const auto originalPath=path();
        connect(job,&KJob::result,this,[this,destination,originalPath](KJob *j){ if(!j->error() && path()==originalPath)setSelectedPath(destination.toLocalFile()); });
        watchOperation(job,i18n("Renaming…"));
    }
    bool canRestoreTrash() const { return !QSettings().value(QStringLiteral("Files/restoreTrash")).toStringList().isEmpty(); }
    Q_INVOKABLE void trashSelected() {
        if(m_busy || m_opening || !m_lister || selectedPaths().isEmpty())return;
        QList<QUrl> urls;
        for(const auto &p:selectedPaths()) { const auto u=QUrl::fromLocalFile(p); if(listedItem(p).isNull())return; urls.append(u); }
        auto *job=KIO::trash(urls,KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        connect(job,&KIO::CopyJob::copyingDone,this,[](KIO::Job*,const QUrl&,const QUrl &to,const QDateTime&,bool,bool){
            if(to.scheme()!=QStringLiteral("trash"))return;
            QSettings s; auto entries=s.value(QStringLiteral("Files/restoreTrash")).toStringList();
            if(!entries.contains(to.toString()))entries.append(to.toString());
            s.setValue(QStringLiteral("Files/restoreTrash"),entries);
        });
        watchOperation(job,i18n("Moving to Trash…"),true);
    }
    Q_INVOKABLE void restoreTrash() {
        if(m_restoring || m_busy || m_opening)return;
        const auto entries=QSettings().value(QStringLiteral("Files/restoreTrash")).toStringList();
        QList<QUrl> urls; for(const auto &s:entries)if(QUrl(s).scheme()==QStringLiteral("trash"))urls.append(QUrl(s));
        if(urls.isEmpty())return;
        // Restore one at a time so partial failure preserves pending recovery.
        // A record whose item has left Trash elsewhere is dropped, so it
        // cannot stand in front of the ones that are still there; one that
        // failed for any other reason, such as a name already taken, stays.
        const QString record=urls.last().toString();
        auto *job=KIO::restoreFromTrash({urls.last()},KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        m_restoring=true;
        // KJob reports finished before result, so this runs after the
        // general finish and can say what actually happened.
        connect(job,&KJob::result,this,[this,record](KJob *j){
            const auto forget=[record]{
                QSettings s; auto remaining=s.value(QStringLiteral("Files/restoreTrash")).toStringList();
                remaining.removeAll(record); s.setValue(QStringLiteral("Files/restoreTrash"),remaining);
            };
            if(!j->error()){ forget(); m_restoring=false; Q_EMIT operationChanged(); return; }
            // Ask Trash itself whether the item is still there.
            auto *stat=KIO::stat(QUrl(record),KIO::StatJob::SourceSide,KIO::StatBasic,KIO::HideProgressInfo);
            stat->setUiDelegate(nullptr);
            connect(stat,&KJob::result,this,[this,forget](KJob *s){
                m_restoring=false;
                if(s->error()){
                    forget();
                    m_operationStatus=i18n("That item is no longer in Trash.");
                    m_error.clear();
                    QSettings().remove(QStringLiteral("Files/lastOperationError"));
                    Q_EMIT changed();
                }
                Q_EMIT operationChanged();
            });
        });
        watchOperation(job,i18n("Restoring from Trash…"));
    }
    Q_INVOKABLE void copyDropped(const QStringList &paths, const QString &destination) {
        if (m_busy || m_opening || !m_lister || paths.isEmpty()) return;
        const auto target=listedItem(destination);
        if (target.isNull() || !target.isDir()) return;
        const auto canonicalTarget=QFileInfo(destination).canonicalFilePath();
        if (canonicalTarget.isEmpty()) return;
        QList<QUrl> sources;
        for (const auto &p:paths) {
            const auto url=QUrl::fromLocalFile(p);
            const auto item=listedItem(p);
            if (item.isNull()) return;
            const auto canonicalSource=QFileInfo(p).canonicalFilePath();
            if (canonicalSource.isEmpty() || canonicalTarget==canonicalSource ||
                (item.isDir() && canonicalTarget.startsWith(canonicalSource+QLatin1Char('/')))) return;
            if (!sources.contains(url)) sources.append(url);
        }
        // Internal drop is an explicit copy, independent of the clipboard.
        auto *job=KIO::copy(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo);
        askAboutNames(job); job->setUiDelegateExtension(nullptr);
        watchOperation(job,i18n("Copying…"),true);
    }
    // What another application receives when listed files are carried out of
    // Files: their addresses. Null if any is no longer listed.
    QMimeData *carriedFiles(const QStringList &paths) const {
        if (m_busy || m_opening || !m_lister || paths.isEmpty()) return nullptr;
        QList<QUrl> urls;
        for (const auto &p:paths) {
            if (listedItem(p).isNull()) return nullptr;
            const auto url=QUrl::fromLocalFile(p);
            if (!urls.contains(url)) urls.append(url);
        }
        auto *mime=new QMimeData;
        KUrlMimeData::setUrls(urls,urls,mime);
        return mime;
    }
    // Files or web addresses dropped in from another application are copied
    // into the folder shown or a folder listed in it, never moved, whatever
    // the other side offered. A file already in that folder, or a folder
    // dropped into itself, is left alone.
    Q_INVOKABLE void copyIncoming(const QList<QUrl> &urls, const QString &destination) {
        if (m_busy || m_opening || !m_lister || urls.isEmpty()) return;
        if (destination==path() ? !inFolder() : !listedItem(destination).isDir()) return;
        const auto canonicalTarget=QFileInfo(destination).canonicalFilePath();
        if (canonicalTarget.isEmpty()) return;
        QList<QUrl> sources;
        for (const auto &url:urls) {
            if (url.isLocalFile()) {
                const auto canonicalSource=QFileInfo(url.toLocalFile()).canonicalFilePath();
                if (canonicalSource.isEmpty() || QFileInfo(canonicalSource).path()==canonicalTarget ||
                    canonicalTarget==canonicalSource || canonicalTarget.startsWith(canonicalSource+QLatin1Char('/'))) continue;
            } else if (url.scheme()!=QStringLiteral("https") && url.scheme()!=QStringLiteral("http")) continue;
            if (!sources.contains(url)) sources.append(url);
        }
        if (sources.isEmpty()) return;
        auto *job=KIO::copy(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo);
        askAboutNames(job); job->setUiDelegateExtension(nullptr);
        watchOperation(job,i18n("Copying…"),true);
    }
    Q_INVOKABLE void pasteInto(const QString &destination) {
        if (m_busy || m_opening || !canPaste()) return;
        // Explicit context destination must be the current folder or a listed folder.
        if (destination==path() && !inFolder()) return;
        if (destination!=path()) {
            const auto item=listedItem(destination);
            if (item.isNull() || !item.isDir()) { m_error=i18n("Destination is no longer available."); Q_EMIT changed(); return; }
        }
        // Honor the native KDE cut marker only for explicit clipboard paste.
        // No Overwrite flag: a name already taken asks the person first.
        const auto sources=QGuiApplication::clipboard()->mimeData()->urls();
        const bool moving=QGuiApplication::clipboard()->mimeData()->data(QStringLiteral("application/x-kde-cutselection"))==QByteArray("1");
        auto *job=moving ? KIO::move(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo)
                         : KIO::copy(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo);
        askAboutNames(job); job->setUiDelegateExtension(nullptr);
        if(moving)connect(job,&KJob::result,this,[sources](KJob *j){
            const auto *mime=QGuiApplication::clipboard()->mimeData();
            if(!j->error() && mime && mime->urls()==sources && mime->data(QStringLiteral("application/x-kde-cutselection"))==QByteArray("1"))QGuiApplication::clipboard()->clear();
        });
        watchOperation(job,moving ? i18n("Moving…") : i18n("Copying…"),true);
    }
    Q_INVOKABLE void newFolder(const QString &name) {
        if (m_busy || m_opening || !inFolder()) return;
        if (name.isEmpty() || name==QStringLiteral(".") || name==QStringLiteral("..") || name.contains(QLatin1Char('/')) || name.contains(QChar::Null)) {
            m_operationStatus=i18n("Enter a folder name without a slash."); Q_EMIT operationChanged(); return;
        }
        const QString destination=QDir(path()).filePath(name);
        const auto generation=m_listingGeneration;
        auto *job=KIO::mkdir(QUrl::fromLocalFile(destination));
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        connect(job,&KJob::result,this,[this,destination,generation](KJob *finished) {
            // Do not steal a tab/navigation change made while mkdir was pending.
            if (!finished->error() && generation==m_listingGeneration) {
                setFilter(QString());
                refresh();
                setSelectedPath(destination);
                Q_EMIT folderCreated();
            }
        });
        watchOperation(job,i18n("Creating folder…"));
    }
    void setScroll(double v) { m_tabs[m_current].scroll=std::max(0.0,v); }
    void setFilter(const QString &v) { if(m_filter==v)return; m_filter=v; rebuild(); }
    void setSortMode(int v) { if(v<0||v>3)return; m_sort=v; rebuild(); }
    void setHidden(bool v) { if(v==m_hidden)return; m_hidden=v; refresh(); }
    Q_INVOKABLE void open() {
        QFile mounts(QStringLiteral("/proc/self/mountinfo"));
        m_mounts = mounts.open(QIODevice::ReadOnly) ? mounts.readAll() : QByteArray{};
        rebuildPlaces();
        m_drivePaths = mountedDrivePaths();
        if(!m_lister) refresh(); else Q_EMIT changed();
    }
    Q_INVOKABLE void navigate(const QString &p) {
        if(p==path())return;
        if(p==recentLocation()) { go(p); return; }
        if(!QDir::isAbsolutePath(p)) { m_error=i18n("Enter an absolute local folder path."); Q_EMIT changed(); return; }
        go(QDir::cleanPath(p));
    }
    // Looks for names containing the text in this folder and every folder
    // inside it. A new search from a search replaces it, so Back returns to
    // the folder.
    Q_INVOKABLE void searchInside(const QString &text) {
        const auto term=text.trimmed();
        const auto base=folder();
        if(term.isEmpty() || base.isEmpty())return;
        const auto location=searchLocation(base,term);
        if(location==path())return;
        if(kindOf(path())==Kind::Search) {
            auto &t=m_tabs[m_current]; t.history[t.index]=location; t.history=t.history.mid(0,t.index+1);
            t.scroll=0; t.selected.clear(); t.selection.clear(); t.focused.clear(); refresh(); save();
            return;
        }
        go(location);
    }
    Q_INVOKABLE void back() { if(canBack()){--m_tabs[m_current].index; m_tabs[m_current].scroll=0; refresh();} }
    Q_INVOKABLE void forward() { if(canForward()){++m_tabs[m_current].index; m_tabs[m_current].scroll=0; refresh();} }
    Q_INVOKABLE void addTab() {
        if(m_tabs.size()>=20)return;
        m_tabs.append(Tab{{path()},0,0}); m_current=m_tabs.size()-1; refresh(); save();
    }
    Q_INVOKABLE void selectTab(int i) {
        if(i<0||i>=m_tabs.size()||i==m_current)return;
        m_current=i; refresh(); save();
    }
    Q_INVOKABLE void closeTab(int i) {
        if(i<0||i>=m_tabs.size()||m_tabs.size()==1)return;
        m_tabs.removeAt(i); if(i<m_current)--m_current;
        m_current=std::min(m_current,int(m_tabs.size())-1); refresh(); save();
    }
    Q_INVOKABLE void refresh() {
        ++m_listingGeneration;
        Q_EMIT selectionChanged();
        if(m_lister){disconnect(m_lister,nullptr,this,nullptr); m_lister->stop(); m_lister->deleteLater();}
        m_lister=new KCoreDirLister(this); m_lister->setAutoErrorHandlingEnabled(false); m_lister->setDelayedMimeTypes(true);
        // A search's results arrive while it runs and can be used at once, so
        // it is searching rather than busy.
        const auto kind=kindOf(path());
        m_lister->setShowHiddenFiles(m_hidden); m_entries.clear(); m_error.clear(); m_listingFailed=false;
        m_busy=kind!=Kind::Search; m_searching=kind==Kind::Search; m_askRecentAgain=kind==Kind::Recent;
        m_showArrived.stop();
        connect(m_lister,&KCoreDirLister::itemsAdded,this,[this]{showArrived();});
        connect(m_lister,&KCoreDirLister::itemsDeleted,this,[this]{showArrived();});
        connect(m_lister,&KCoreDirLister::refreshItems,this,[this]{showArrived();});
        connect(m_lister,qOverload<>(&KCoreDirLister::completed),this,[this]{
            m_busy=false; m_searching=false; m_showArrived.stop(); rebuild();
            // KDE's Recent drops a file that no longer exists while it answers,
            // and can skip the file after it; asked again, it answers whole.
            if(m_askRecentAgain) { m_askRecentAgain=false; m_lister->updateDirectory(m_lister->url()); }
        });
        connect(m_lister,&KCoreDirLister::jobError,this,[this](KIO::Job *job){m_busy=false;m_searching=false;m_listingFailed=true;m_error=listingError(job);Q_EMIT changed();});
        // Recent and a search are asked afresh; KDE watches only folders.
        Q_EMIT changed(); m_lister->openUrl(listingUrl(), kind==Kind::Folder ? KCoreDirLister::NoFlags : KCoreDirLister::Reload);
    }
Q_SIGNALS:
    void changed();
    void placesChanged();
    void selectionChanged();
    void operationChanged();
    void clipboardChanged();
    void folderCreated();
    void tileSizeChanged();
    void revealPathChanged();
    void detailsChanged();
    void questionChanged();
    void trashChanged();
    void openRequested(const QUrl &url);
    void openWithRequested(const QUrl &url, const QString &applicationId);
    // A file no application claims: Files offers Open With instead.
    void applicationChoiceNeeded(const QString &path);
    // The typed text was set aside, as opening a folder from Recent or a search does.
    void filterCleared();
private:
    FileDevices::Drive findDrive(const QString &id) const {
        if(m_devices) for(const auto &drive:m_devices->drives()) if(drive.id==id)return drive;
        return {};
    }
    QStringList mountedDrivePaths() const {
        QStringList paths;
        if(m_devices) for(const auto &drive:m_devices->drives()) if(drive.mounted)paths.append(drive.path);
        return paths;
    }
    // Places, the listed drives after them, and any other mounted media.
    void rebuildPlaces() {
        auto places=localPlaces(m_mounts);
        if(m_devices) {
            const auto drives=m_devices->drives();
            QStringList drivePaths;
            QVariantList rows;
            for(const auto &drive:drives) {
                if(drive.mounted)drivePaths.append(drive.path);
                // What the drive is doing, said on its own row: a copy
                // hides the status line while it runs.
                const bool waiting=m_ejectAfter.contains(drive.id);
                const bool opening=drive.opening || drive.id==m_driveOpening;
                const auto note=waiting ? i18n("Ejects when done") : drive.ejecting ? i18n("Ejecting…") : opening ? i18n("Opening…") : QString();
                rows.append(QVariantMap{{QStringLiteral("label"),drive.label},{QStringLiteral("path"),drive.path},{QStringLiteral("icon"),drive.icon},
                    {QStringLiteral("section"),QStringLiteral("drives")},{QStringLiteral("drive"),drive.id},{QStringLiteral("mounted"),drive.mounted},
                    {QStringLiteral("canEject"),drive.removable && !drive.phone && drive.mounted},
                    {QStringLiteral("busy"),!note.isEmpty()},{QStringLiteral("note"),note}});
            }
            places.removeIf([&drivePaths](const QVariant &place) {
                const auto map=place.toMap();
                return map.value(QStringLiteral("section"))==QLatin1String("drives") && drivePaths.contains(map.value(QStringLiteral("path")).toString());
            });
            int at=0;
            while(at<places.size() && places[at].toMap().value(QStringLiteral("section"))==QLatin1String("places"))++at;
            for(const auto &row:rows)places.insert(at++,row);
        }
        if(places!=m_places) { m_places=places; Q_EMIT placesChanged(); }
    }
    // A drive that went away takes every tab showing it, or searching it, Home.
    void drivesChanged() {
        const auto paths=mountedDrivePaths();
        for(const auto &gone:m_drivePaths) if(!paths.contains(gone))leaveFolder(gone);
        m_drivePaths=paths;
        for(const auto &id:QSet<QString>(m_ejectAfter)) if(!findDrive(id).mounted)m_ejectAfter.remove(id);
        rebuildPlaces();
    }
    static bool within(const QString &p,const QString &root) {
        return p==root || p.startsWith(root.endsWith(QLatin1Char('/')) ? root : root+QLatin1Char('/'));
    }
    void leaveFolder(const QString &root) {
        const auto home=QDir::homePath();
        bool saved=false;
        for(int i=0;i<m_tabs.size();++i) {
            const auto location=m_tabs[i].history[m_tabs[i].index];
            const auto kind=kindOf(location);
            if(kind==Kind::Recent || !within(kind==Kind::Search ? searchFolderOf(location) : location,root))continue;
            if(i==m_current) { go(home); continue; }
            auto &t=m_tabs[i]; t.history=t.history.mid(0,t.index+1); t.history.append(home); ++t.index;
            t.scroll=0; t.selected.clear(); t.selection.clear(); t.focused.clear(); saved=true;
        }
        if(saved) { save(); Q_EMIT changed(); }
    }
    // Whether a copy, move or other file action Files is running reads or
    // writes inside a folder.
    bool touches(const QString &root) const {
        const auto inside=[&root](const QUrl &url){ return url.isLocalFile() && within(url.toLocalFile(),root); };
        for(const auto &op:m_operations) {
            if(!op.job)continue;
            if(inside(op.destination))return true;
            if(auto *copy=qobject_cast<KIO::CopyJob *>(op.job.data())) {
                if(inside(copy->destUrl()))return true;
                for(const auto &url:copy->srcUrls()) if(inside(url))return true;
            } else if(auto *simple=qobject_cast<KIO::SimpleJob *>(op.job.data())) {
                if(inside(simple->url()))return true;
            }
        }
        return false;
    }
    void ejectWhenFree() {
        for(const auto &id:QSet<QString>(m_ejectAfter)) {
            const auto drive=findDrive(id);
            if(drive.mounted && touches(drive.path))continue;
            m_ejectAfter.remove(id);
            if(drive.mounted)m_devices->remove(id);
        }
        rebuildPlaces();
    }
    enum class Kind { Folder, Recent, Search };
    static Kind kindOf(const QString &location) {
        if (location == recentLocation()) return Kind::Recent;
        if (location.startsWith(QStringLiteral("filenamesearch:"))) return Kind::Search;
        return Kind::Folder;
    }
    // A query value exactly as given: QUrlQuery reads a percent sign as the
    // start of an encoded character unless it is itself encoded.
    static QString queryValue(QString value) { return value.replace(QLatin1Char('%'), QStringLiteral("%25")); }
    static QString folderQueryValue(const QString &folder) { return queryValue(QUrl::fromLocalFile(folder).toString(QUrl::FullyEncoded)); }
    // A search is kept as the folder and the text; how KDE is asked is built
    // when it is listed, so showing hidden files applies to it.
    static QString searchLocation(const QString &folder, const QString &term) {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("url"), folderQueryValue(folder));
        query.addQueryItem(QStringLiteral("title"), queryValue(term));
        QUrl url; url.setScheme(QStringLiteral("filenamesearch")); url.setQuery(query);
        return url.toString(QUrl::FullyEncoded);
    }
    static QString searchTermOf(const QString &location) {
        return QUrlQuery(QUrl(location)).queryItemValue(QStringLiteral("title"), QUrl::FullyDecoded);
    }
    static QString searchFolderOf(const QString &location) {
        return QUrl(QUrlQuery(QUrl(location)).queryItemValue(QStringLiteral("url"), QUrl::FullyDecoded)).toLocalFile();
    }
    QString locationLabel(const QString &location) const {
        switch (kindOf(location)) {
        case Kind::Recent: return i18n("Recent");
        case Kind::Search: return QStringLiteral("“%1”").arg(searchTermOf(location));
        case Kind::Folder: break;
        }
        return location == QDir::homePath() ? i18n("Home") : QDir(location).dirName();
    }
    static QVariantList folderCrumbs(const QString &folder) {
        QVariantList result{QVariantMap{{QStringLiteral("label"), QStringLiteral("/")}, {QStringLiteral("path"), QStringLiteral("/")}}};
        QString accumulated;
        for (const auto &part : folder.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
            accumulated += QLatin1Char('/') + part;
            result.append(QVariantMap{{QStringLiteral("label"), part}, {QStringLiteral("path"), accumulated}});
        }
        return result;
    }
    QUrl listingUrl() const {
        const auto p = path();
        switch (kindOf(p)) {
        case Kind::Recent:
            return QUrl(p);
        case Kind::Search: {
            // Names only, matched as typed: the text is a literal, not a pattern.
            const auto term = searchTermOf(p);
            QUrlQuery query;
            query.addQueryItem(QStringLiteral("search"), queryValue(QRegularExpression::escape(term)));
            query.addQueryItem(QStringLiteral("url"), folderQueryValue(searchFolderOf(p)));
            query.addQueryItem(QStringLiteral("checkContent"), QStringLiteral("no"));
            query.addQueryItem(QStringLiteral("includeHidden"), m_hidden ? QStringLiteral("yes") : QStringLiteral("no"));
            query.addQueryItem(QStringLiteral("syntax"), QStringLiteral("regex"));
            query.addQueryItem(QStringLiteral("title"), queryValue(term));
            QUrl url; url.setScheme(QStringLiteral("filenamesearch")); url.setQuery(query);
            return url;
        }
        case Kind::Folder:
            break;
        }
        return QUrl::fromLocalFile(p);
    }
    // The local file an item stands for: itself in a folder, the file KDE
    // points to in Recent, the file found in a search.
    static QString localPathOf(const KFileItem &item) {
        const auto target = item.targetUrl();
        return target.isLocalFile() ? target.toLocalFile() : item.localPath();
    }
    static bool hiddenByList(const KFileItem &item) {
        return !item.isNull() && item.isHidden() && !item.name().startsWith(QLatin1Char('.'));
    }
    // Rewrites the folder's .hidden, keeping every line another application
    // wrote, and removes it once it lists nothing.
    void setListedHidden(bool hide) {
        const auto list=QDir(path()).filePath(QStringLiteral(".hidden"));
        QStringList lines;
        { QFile f(list); if(f.open(QIODevice::ReadOnly))lines=QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'),Qt::SkipEmptyParts); }
        for(const auto &p:selectedPaths()) {
            const auto name=QFileInfo(p).fileName();
            if(hide && !listedItem(p).isHidden() && !name.contains(QLatin1Char('\n')) && !lines.contains(name))lines.append(name);
            if(!hide)lines.removeAll(name);
        }
        bool written;
        if(lines.isEmpty()) written=!QFile::exists(list) || QFile::remove(list);
        else {
            QSaveFile f(list);
            written=f.open(QIODevice::WriteOnly) && f.write((lines.join(QLatin1Char('\n'))+QLatin1Char('\n')).toUtf8())>=0 && f.commit();
        }
        if(!written) { m_error=hide ? i18n("Could not hide that here.") : i18n("Could not unhide that here."); Q_EMIT changed(); return; }
        setSelecting(false);
        // KDE reads .hidden as it lists. It notices the change itself only
        // where it watches the folder, so the folder is listed again.
        m_lister->updateDirectory(m_lister->url());
    }
    KFileItem listedItem(const QString &p) const {
        if (!m_lister) return {};
        if (inFolder()) return m_lister->findByUrl(QUrl::fromLocalFile(p));
        const auto items = m_lister->items();
        for (const auto &item : items) if (localPathOf(item) == p) return item;
        return {};
    }
    // A listed file's type comes from its name, as Dolphin first takes it;
    // only a name that says nothing has the file's start read. Reading every
    // file's start held a large folder, or a phone's, for seconds.
    static QString typeOf(const KFileItem &f) {
        const auto named=f.currentMimeType();
        return named.isValid() && !named.isDefault() ? named.name() : f.mimetype();
    }
    // Where a file in Recent or a search lives: under Home without it, or in full.
    static QString folderLabel(const QString &filePath) {
        const auto parent = QFileInfo(filePath).path();
        const auto home = QDir::homePath();
        if (parent == home) return i18n("Home");
        if (parent.startsWith(home + QLatin1Char('/'))) return parent.mid(home.size() + 1);
        return parent;
    }
    void go(const QString &location) {
        if(location==path())return;
        auto &t=m_tabs[m_current]; t.history=t.history.mid(0,t.index+1);
        t.history.append(location); ++t.index; t.scroll=0; t.selected.clear(); t.selection.clear(); t.focused.clear(); refresh(); save();
    }
    struct Tab { QStringList history; int index; double scroll; QString selected; QStringList selection; QString anchor; QString focused; };
    quint64 m_listingGeneration=0;
    QList<Tab> m_tabs;
    int m_current=0, m_sort=0;
    bool m_hidden=false, m_busy=false, m_opening=false;
    bool m_selecting=false, m_restoring=false, m_searching=false, m_askRecentAgain=false;
    ThumbnailSource m_thumbnailSource;
    DetailReader m_detailReader;
    QVariantMap m_details;
    QPointer<KIO::DirectorySizeJob> m_sizeJob;
    quint64 m_detailsGeneration=0;
    // Details read off the GUI thread are dropped once this browser is gone.
    std::shared_ptr<bool> m_alive=std::make_shared<bool>(true);
    void setDetail(const QString &key,const QString &value) {
        auto rows=m_details.value(QStringLiteral("rows")).toList();
        for(auto &r:rows) { auto map=r.toMap(); if(map.value(QStringLiteral("key"))==key) { map[QStringLiteral("value")]=value; r=map; } }
        m_details[QStringLiteral("rows")]=rows; Q_EMIT detailsChanged();
    }
    int m_tileSize=1;
    QString m_revealPath;
    bool m_revealProperties=false;
    QString m_operationStatus;
    QString m_filter, m_error;
    bool m_listingFailed=false;
    QUrl m_openingUrl;
    // What Files opens is told to KDE's activity service, as Dolphin tells it,
    // so it shows in Recent here and across Plasma. Plasma's own privacy
    // setting decides whether it is kept.
    static void noteUsed(const QUrl &url) {
        auto use = QDBusMessage::createMethodCall(QStringLiteral("org.kde.ActivityManager"),
            QStringLiteral("/ActivityManager/Resources"), QStringLiteral("org.kde.ActivityManager.Resources"),
            QStringLiteral("RegisterResourceEvent"));
        // The application, no window, the file, and Accessed.
        use.setArguments({QStringLiteral("io.github.carlsonjm.Tettegouche.Files"), 0u, url.toString(), 0u});
        QDBusConnection::sessionBus().asyncCall(use);
    }
    // Why a place could not be listed, said plainly; KIO's own words otherwise.
    QString listingError(KIO::Job *job) const {
        const auto p = path();
        const auto name = QFileInfo(p).fileName().isEmpty() ? p : QFileInfo(p).fileName();
        switch (job->error()) {
        case KIO::ERR_ACCESS_DENIED:
        case KIO::ERR_CANNOT_ENTER_DIRECTORY:
        case KIO::ERR_CANNOT_OPEN_FOR_READING:
            return i18n("You don't have permission to open “%1”.", name);
        case KIO::ERR_DOES_NOT_EXIST:
            return i18n("“%1” isn't there any more.", name);
        default:
            return job->errorString();
        }
    }
    KCoreDirLister *m_lister=nullptr;
    // A folder arrives in batches, in no order. It is shown once it is whole,
    // sorted once, so nothing shown moves. One slow to list shows what it has
    // after half a second and fills in once a second until whole, or less
    // often while a fill-in takes long, so drawing never holds up the listing;
    // a search shows its first finds at once. A change to a folder already
    // whole shows at once.
    QTimer m_showArrived;
    qint64 m_rebuildMs=0;
    void showArrived() {
        if((!m_busy && !m_searching) || (m_searching && m_entries.isEmpty())) { m_showArrived.stop(); rebuild(); return; }
        if(!m_showArrived.isActive()) m_showArrived.start(m_entries.isEmpty() ? 500 : std::max<qint64>(1000, 3*m_rebuildMs));
    }
    QVariantList m_entries, m_places;
    QPointer<FileDevices> m_devices;
    QByteArray m_mounts;
    QStringList m_drivePaths;
    QString m_driveOpening;
    QSet<QString> m_ejectAfter;
    // Operations run side by side; each keeps its own job and identity.
    struct Operation { QPointer<KJob> job; QString id; QString label; bool copying=false; bool percentKnown=false; QUrl destination; };
    struct Failure { QString id, title, why; qint64 until=0; };
    QList<Failure> m_failures;
    struct Question { QPointer<FileQuestions> asker; QPointer<KJob> job; QUrl destination; QVariantMap shown; };
    QList<Question> m_questions;
    int m_trashItems=0;
    QString m_trashSize;
    static QString arkPath() { static const QString path=QStandardPaths::findExecutable(QStringLiteral("ark")); return path; }
    static QVariantMap applicationEntry(const KService::Ptr &service,bool isDefault) {
        return QVariantMap{{QStringLiteral("id"),service->storageId()},{QStringLiteral("name"),service->name()},
            {QStringLiteral("icon"),service->icon()},{QStringLiteral("isDefault"),isDefault}};
    }
    void startArk(const QStringList &arguments,const QString &workingDirectory,const QString &status) {
        if(!QProcess::startDetached(arkPath(),arguments,workingDirectory)) { m_error=i18n("Ark could not be started."); Q_EMIT changed(); return; }
        m_operationStatus=status; Q_EMIT operationChanged();
    }
    // A copy or move asks about a name already taken instead of stopping.
    void askAboutNames(KJob *job) {
        auto *ui=new KJobUiDelegate(KJobUiDelegate::Flags{});
        new FileQuestions(ui,[this](FileQuestions *asker,const FileQuestions::NameTaken &taken){ nameTaken(asker,taken); });
        job->setUiDelegate(ui);
    }
    void nameTaken(FileQuestions *asker,const FileQuestions::NameTaken &taken) {
        const KFormat format;
        const auto describe=[&format](KIO::filesize_t size,const QDateTime &when) {
            const auto amount=QLocale().formattedDataSize(size);
            return when.isValid() ? i18n("%1, modified %2", amount, format.formatRelativeDateTime(when,QLocale::ShortFormat)) : amount;
        };
        const bool folder=taken.options.testFlag(KIO::RenameDialog_DestIsDirectory);
        const auto parent=taken.destination.adjusted(QUrl::RemoveFilename|QUrl::StripTrailingSlash).toLocalFile();
        const QVariantMap shown{{QStringLiteral("name"),taken.destination.fileName()},
            {QStringLiteral("folder"),parent==QDir::homePath() ? i18n("Home") : parent==QStringLiteral("/") ? parent : QFileInfo(parent).fileName()},
            {QStringLiteral("isFolder"),folder},
            {QStringLiteral("several"),taken.options.testFlag(KIO::RenameDialog_MultipleItems)},
            {QStringLiteral("canReplace"),taken.options.testFlag(KIO::RenameDialog_Overwrite) && !taken.options.testFlag(KIO::RenameDialog_OverwriteItself)},
            {QStringLiteral("canSkip"),taken.options.testFlag(KIO::RenameDialog_Skip)},
            {QStringLiteral("canKeepBoth"),!taken.options.testFlag(KIO::RenameDialog_NoRename)},
            {QStringLiteral("existing"),folder ? QString() : describe(taken.destinationSize,taken.destinationModified)},
            {QStringLiteral("arriving"),folder ? QString() : describe(taken.sourceSize,taken.sourceModified)}};
        m_questions.append({asker,taken.job,taken.destination,shown});
        if(m_questions.size()==1)Q_EMIT questionChanged();
    }
    QList<Operation> m_operations;
    KJob *operationJob(const QString &id) const {
        for (const auto &op : m_operations) if (op.id == id) return op.job;
        return nullptr;
    }
    Operation *operation(KJob *job) {
        for (auto &op : m_operations) if (op.job == job) return &op;
        return nullptr;
    }
    void watchOperation(KJob *job,const QString &label,bool copying=false) {
        m_operations.append(Operation{job, QUuid::createUuid().toString(QUuid::WithoutBraces), label, copying});
        connect(job, &KJob::percentChanged, this, [this,job] {
            if (auto *op = operation(job)) { op->percentKnown = true; Q_EMIT operationChanged(); }
        });
        connect(job, &KJob::totalAmountChanged, this, &FileBrowser::operationChanged);
        connect(job, &KJob::processedAmountChanged, this, &FileBrowser::operationChanged);
        connect(job, &KJob::suspended, this, &FileBrowser::operationChanged);
        connect(job, &KJob::resumed, this, &FileBrowser::operationChanged);
        if (auto *copy = qobject_cast<KIO::CopyJob *>(job)) {
            const auto destination = [this,job](KIO::Job *, const QUrl &, const QUrl &to) {
                if (auto *op = operation(job)) { op->destination = to; Q_EMIT operationChanged(); }
            };
            connect(copy, &KIO::CopyJob::copying, this, destination);
            connect(copy, &KIO::CopyJob::moving, this, destination);
        }
        m_operationStatus=label; Q_EMIT operationChanged();
        // finished also handles quiet cancellation/destruction; result alone can orphan UI state.
        connect(job,&KJob::finished,this,[this,copying](KJob *finished) {
            QString endedId, endedTitle;
            if (const auto *op = operation(finished)) {
                endedId = op->id;
                endedTitle = op->destination.isEmpty() ? op->label : op->destination.fileName();
            }
            m_operations.removeIf([finished](const Operation &op) { return op.job == finished || !op.job; });
            const bool wasAsking=!m_questions.isEmpty() && m_questions.first().job==finished;
            m_questions.removeIf([finished](const Question &q) { return q.job == finished || !q.job; });
            if(wasAsking) Q_EMIT questionChanged();
            // A job stopped at a question says why: the error KIO asked about,
            // or nothing more when the person chose to stop.
            QString why=finished->errorString();
            const auto *asker=finished->uiDelegate() ? finished->uiDelegate()->findChild<FileQuestions *>() : nullptr;
            if(finished->error()==KIO::ERR_USER_CANCELED) why=asker ? asker->stoppedBy() : QString();
            // Files it could not read were skipped and the rest carried: the
            // copy ends saying what was left behind, as a failure does.
            const QStringList skipped=asker && !finished->error() ? asker->skipped() : QStringList();
            m_operationStatus=!finished->error()
                ? (skipped.isEmpty() ? i18n("Done")
                    : i18np("Done, except one item that could not be read: %2","Done, except %1 items that could not be read: %2",
                        skipped.size(),skipped.first()))
                : why.isEmpty() ? i18n("Stopped.") : i18n("Stopped: %1", why);
            if (finished->error() && copying) m_operationStatus += i18n(" Some items may already have transferred.");
            m_error=finished->error() || !skipped.isEmpty() ? m_operationStatus : QString();
            // A copy or move that failed, not one the person stopped, or that
            // left files behind, is told to Ambient for a few seconds; Ambient
            // keeps it its minute.
            const auto now=QDateTime::currentMSecsSinceEpoch();
            m_failures.removeIf([now](const Failure &f) { return f.until<now; });
            if (copying && !endedId.isEmpty()
                    && ((finished->error() && finished->error()!=KIO::ERR_USER_CANCELED) || !skipped.isEmpty()))
                m_failures.append({endedId, endedTitle, m_operationStatus, now+10000});
            Q_EMIT changed(); // Keep full failure details visible, not elided status only.
            QSettings s;
            if (finished->error()) s.setValue(QStringLiteral("Files/lastOperationError"),m_operationStatus);
            else s.remove(QStringLiteral("Files/lastOperationError"));
            // Keep navigation independent: KDirWatch updates whichever folder is
            // shown. Recent and a search are asked again for what changed.
            if (!inFolder() && m_lister) { m_askRecentAgain=kindOf(path())==Kind::Recent; m_lister->updateDirectory(m_lister->url()); }
            if (!m_ejectAfter.isEmpty()) ejectWhenFree();
            Q_EMIT operationChanged();
        });
    }
    void save() {
        // A search is not run again at startup; its tab comes back on its folder.
        QStringList paths;
        for(const auto &t:m_tabs) { const auto &p=t.history[t.index]; paths.append(kindOf(p)==Kind::Search ? searchFolderOf(p) : p); }
        QSettings s; s.setValue(QStringLiteral("Files/paths"),paths); s.setValue(QStringLiteral("Files/current"),m_current);
    }
    void rebuild() {
        QElapsedTimer took; took.start();
        auto items=m_lister ? m_lister->items() : KFileItemList{};
        const auto kind=kindOf(path());
        QCollator collator; collator.setNumericMode(true); collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::stable_sort(items.begin(),items.end(),[&](const KFileItem &a,const KFileItem &b){
            // Recent keeps KDE's order of use, files and folders together.
            if(kind==Kind::Recent)return a.time(KFileItem::AccessTime)>b.time(KFileItem::AccessTime);
            if(a.isDir()!=b.isDir())return a.isDir();
            if(m_sort==2 && a.time(KFileItem::ModificationTime)!=b.time(KFileItem::ModificationTime))
                return a.time(KFileItem::ModificationTime)>b.time(KFileItem::ModificationTime);
            if(m_sort==3 && a.size()!=b.size())return a.size()>b.size();
            const int c=collator.compare(a.text(),b.text());return m_sort==1 ? c>0 : c<0;
        });
        m_entries.clear();
        for(const auto &f:items) {
            const auto local=localPathOf(f);
            if(local.isEmpty() || !f.text().contains(m_filter,Qt::CaseInsensitive))continue;
            m_entries.append(QVariantMap{{QStringLiteral("name"),f.text()},{QStringLiteral("path"),local},
                {QStringLiteral("directory"),f.isDir()},{QStringLiteral("hidden"),f.isHidden()},{QStringLiteral("icon"),f.iconName()},
                {QStringLiteral("thumbnail"),!f.isDir() && m_thumbnailSource ? m_thumbnailSource(local,typeOf(f),f.time(KFileItem::ModificationTime).toSecsSinceEpoch()) : QString()},
                {QStringLiteral("detail"),kind!=Kind::Folder ? folderLabel(local) : f.isDir()?i18n("Folder"):QLocale().formattedDataSize(f.size())}});
        }
        m_rebuildMs=took.elapsed();
        Q_EMIT changed();
    }
};
