#pragma once

#include <KCoreDirLister>
#include <KFileItem>
#include <KIO/Job>
#include <KIO/CopyJob>
#include <KIO/MkdirJob>
#include <KIO/RestoreJob>
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QCollator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>
#include <QVariantList>
#include <algorithm>

// Local browsing and explicit asynchronous copy/create. Each listing has its own lifetime so late replies
// from a previous tab cannot replace the current folder. No shell operations.
class FileBrowser : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    Q_PROPERTY(QVariantList tabs READ tabs NOTIFY changed)
    Q_PROPERTY(QVariantList places READ places NOTIFY placesChanged)
    Q_PROPERTY(QVariantList crumbs READ crumbs NOTIFY changed)
    Q_PROPERTY(int currentTab READ currentTab NOTIFY changed)
    Q_PROPERTY(QString path READ path NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
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
public:
    explicit FileBrowser(QObject *parent = nullptr) : QObject(parent) {
        QSettings settings;
        m_operationStatus = settings.value(QStringLiteral("Files/lastOperationError")).toString();
        settings.remove(QStringLiteral("Files/lastOperationError"));
        connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &FileBrowser::clipboardChanged);
        const auto paths = settings.value(QStringLiteral("Files/paths")).toStringList();
        for (const auto &p : paths.mid(0, 20))
            // Do not stat saved paths during launcher startup. Offline mounts
            // must report through the asynchronous lister, not block Meta.
            if (QDir::isAbsolutePath(p)) m_tabs.append(Tab{{QDir::cleanPath(p)}, 0, 0});
        if (m_tabs.isEmpty()) m_tabs.append(Tab{{QDir::homePath()}, 0, 0});
        m_current = std::clamp(settings.value(QStringLiteral("Files/current"), 0).toInt(), 0, int(m_tabs.size())-1);
    }
    ~FileBrowser() override { save(); }
    QVariantList entries() const { return m_entries; }
    QVariantList tabs() const {
        QVariantList result;
        for (const auto &t : m_tabs) {
            const auto p = t.history[t.index];
            result.append(QVariantMap{{QStringLiteral("label"), p == QDir::homePath() ? tr("Home") : QDir(p).dirName()}, {QStringLiteral("path"), p}});
        }
        return result;
    }
    QVariantList places() const { return m_places; }
    static QVariantList localPlaces(const QByteArray &mounts) {
        QVariantList result;
        const auto add = [&result](const QString &label, const QString &p, const QString &icon) {
            if (!p.isEmpty()) result.append(QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("path"), p}, {QStringLiteral("icon"), icon}});
        };
        add(tr("Home"), QDir::homePath(), QStringLiteral("user-home"));
        add(tr("Documents"), QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), QStringLiteral("folder-documents"));
        add(tr("Downloads"), QStandardPaths::writableLocation(QStandardPaths::DownloadLocation), QStringLiteral("folder-download"));
        add(tr("Pictures"), QStandardPaths::writableLocation(QStandardPaths::PicturesLocation), QStringLiteral("folder-pictures"));
        // Linux mount metadata only: never stat/statvfs mounted filesystems.
        // A disconnected network/FUSE volume can block those calls indefinitely.
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
        QVariantList result{QVariantMap{{QStringLiteral("label"), QStringLiteral("/")}, {QStringLiteral("path"), QStringLiteral("/")}}};
        QString accumulated;
        for (const auto &part : path().split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
            accumulated += QLatin1Char('/') + part;
            result.append(QVariantMap{{QStringLiteral("label"), part}, {QStringLiteral("path"), accumulated}});
        }
        return result;
    }
    int currentTab() const { return m_current; }
    QString path() const { return m_tabs[m_current].history[m_tabs[m_current].index]; }
    QString error() const { return m_error; }
    bool busy() const { return m_busy; }
    bool opening() const { return m_opening; }
    Q_INVOKABLE void openSelected() {
        if (m_opening || m_busy || m_working || !m_lister || selectedPaths().size()!=1) return;
        // Only dispatch a selection from the currently displayed listing.
        // Passing a URL as data avoids shell parsing of filenames.
        const auto url = QUrl::fromLocalFile(selectedPath());
        const auto item = m_lister->findByUrl(url);
        if (item.isNull()) {
            m_error = tr("This file is no longer available. Refresh the folder.");
            Q_EMIT changed(); return;
        }
        if (item.isDir()) { setSelecting(false); navigate(url.toLocalFile()); return; }
        m_error.clear(); m_opening = true; Q_EMIT changed();
        Q_EMIT openRequested(url);
    }
    void finishOpen(const QString &error) {
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
        if (m_busy || !m_lister || m_lister->findByUrl(QUrl::fromLocalFile(p)).isNull()) return;
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
    bool working() const { return m_working; }
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
            if (m_lister->findByUrl(url).isNull()) { m_error=tr("Selection changed. Refresh and select again."); Q_EMIT changed(); return; }
            urls.append(url);
        }
        auto *mime=new QMimeData; mime->setUrls(urls); QGuiApplication::clipboard()->setMimeData(mime);
        m_operationStatus=tr("Copied %1 item(s) to clipboard").arg(urls.size()); Q_EMIT operationChanged();
    }
    Q_INVOKABLE void paste() {
        pasteInto(path());
    }
    Q_INVOKABLE void cutSelected() {
        if(m_busy || m_working || m_opening || selectedPaths().isEmpty())return;
        copySelected();
        auto *mime=QGuiApplication::clipboard()->mimeData();
        if(!mime || mime->urls().size()!=selectedPaths().size())return;
        for(const auto &p:selectedPaths())if(!mime->urls().contains(QUrl::fromLocalFile(p)))return;
        auto *cut=new QMimeData;
        cut->setUrls(mime->urls());
        cut->setData(QStringLiteral("application/x-kde-cutselection"),QByteArray("1"));
        QGuiApplication::clipboard()->setMimeData(cut);
        m_operationStatus=tr("Cut %1 item(s) — paste to move").arg(selectedPaths().size()); Q_EMIT operationChanged();
    }
    Q_INVOKABLE void renameSelected(const QString &name) {
        if(m_working || m_busy || m_opening || selectedPaths().size()!=1 || !m_lister)return;
        if(name.isEmpty() || name==QStringLiteral(".") || name==QStringLiteral("..") || name.contains(QLatin1Char('/')) || name.contains(QChar::Null))return;
        const auto source=QUrl::fromLocalFile(selectedPaths().first());
        if(m_lister->findByUrl(source).isNull())return;
        const auto destination=QUrl::fromLocalFile(QDir(path()).filePath(name));
        if(source==destination)return;
        auto *job=KIO::rename(source,destination,KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        const auto originalPath=path();
        connect(job,&KJob::result,this,[this,destination,originalPath](KJob *j){ if(!j->error() && path()==originalPath)setSelectedPath(destination.toLocalFile()); });
        watchOperation(job,tr("Renaming…"));
    }
    bool canRestoreTrash() const { return !QSettings().value(QStringLiteral("Files/restoreTrash")).toStringList().isEmpty(); }
    Q_INVOKABLE void trashSelected() {
        if(m_working || m_busy || m_opening || !m_lister || selectedPaths().isEmpty())return;
        QList<QUrl> urls;
        for(const auto &p:selectedPaths()) { const auto u=QUrl::fromLocalFile(p); if(m_lister->findByUrl(u).isNull())return; urls.append(u); }
        auto *job=KIO::trash(urls,KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        connect(job,&KIO::CopyJob::copyingDone,this,[](KIO::Job*,const QUrl&,const QUrl &to,const QDateTime&,bool,bool){
            if(to.scheme()!=QStringLiteral("trash"))return;
            QSettings s; auto entries=s.value(QStringLiteral("Files/restoreTrash")).toStringList();
            if(!entries.contains(to.toString()))entries.append(to.toString());
            s.setValue(QStringLiteral("Files/restoreTrash"),entries);
        });
        watchOperation(job,tr("Moving to Trash…"),true);
    }
    Q_INVOKABLE void restoreTrash() {
        if(m_working || m_busy || m_opening)return;
        const auto entries=QSettings().value(QStringLiteral("Files/restoreTrash")).toStringList();
        QList<QUrl> urls; for(const auto &s:entries)if(QUrl(s).scheme()==QStringLiteral("trash"))urls.append(QUrl(s));
        if(urls.isEmpty())return;
        // Restore one at a time so partial failure preserves pending recovery.
        auto *job=KIO::restoreFromTrash({urls.last()},KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        connect(job,&KJob::result,this,[entries](KJob *j){ if(!j->error()){auto remaining=entries; remaining.removeLast(); QSettings().setValue(QStringLiteral("Files/restoreTrash"),remaining);} });
        watchOperation(job,tr("Restoring from Trash…"));
    }
    Q_INVOKABLE void copyDropped(const QStringList &paths, const QString &destination) {
        if (m_working || m_busy || m_opening || !m_lister || paths.isEmpty()) return;
        const auto target=m_lister->findByUrl(QUrl::fromLocalFile(destination));
        if (target.isNull() || !target.isDir()) return;
        const auto canonicalTarget=QFileInfo(destination).canonicalFilePath();
        if (canonicalTarget.isEmpty()) return;
        QList<QUrl> sources;
        for (const auto &p:paths) {
            const auto url=QUrl::fromLocalFile(p);
            const auto item=m_lister->findByUrl(url);
            if (item.isNull()) return;
            const auto canonicalSource=QFileInfo(p).canonicalFilePath();
            if (canonicalSource.isEmpty() || canonicalTarget==canonicalSource ||
                (item.isDir() && canonicalTarget.startsWith(canonicalSource+QLatin1Char('/')))) return;
            if (!sources.contains(url)) sources.append(url);
        }
        // Internal drop is an explicit copy, independent of the clipboard.
        auto *job=KIO::copy(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        watchOperation(job,tr("Copying…"),true);
    }
    Q_INVOKABLE void pasteInto(const QString &destination) {
        if (m_working || m_busy || m_opening || !canPaste()) return;
        // Explicit context destination must be the current folder or a listed folder.
        if (destination!=path()) {
            const auto item=m_lister ? m_lister->findByUrl(QUrl::fromLocalFile(destination)) : KFileItem{};
            if (item.isNull() || !item.isDir()) { m_error=tr("Destination is no longer available."); Q_EMIT changed(); return; }
        }
        // Honor the native KDE cut marker only for explicit clipboard paste.
        // No Overwrite flag; no conflict dialog that can enable overwriting.
        const auto sources=QGuiApplication::clipboard()->mimeData()->urls();
        const bool moving=QGuiApplication::clipboard()->mimeData()->data(QStringLiteral("application/x-kde-cutselection"))==QByteArray("1");
        auto *job=moving ? KIO::move(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo)
                         : KIO::copy(sources,QUrl::fromLocalFile(destination),KIO::HideProgressInfo);
        job->setUiDelegate(nullptr); job->setUiDelegateExtension(nullptr);
        if(moving)connect(job,&KJob::result,this,[sources](KJob *j){
            const auto *mime=QGuiApplication::clipboard()->mimeData();
            if(!j->error() && mime && mime->urls()==sources && mime->data(QStringLiteral("application/x-kde-cutselection"))==QByteArray("1"))QGuiApplication::clipboard()->clear();
        });
        watchOperation(job,moving ? tr("Moving…") : tr("Copying…"),true);
    }
    Q_INVOKABLE void newFolder(const QString &name) {
        if (m_working || m_busy || m_opening) return;
        if (name.isEmpty() || name==QStringLiteral(".") || name==QStringLiteral("..") || name.contains(QLatin1Char('/')) || name.contains(QChar::Null)) {
            m_operationStatus=tr("Enter a folder name without a slash."); Q_EMIT operationChanged(); return;
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
        watchOperation(job,tr("Creating folder…"));
    }
    void setScroll(double v) { m_tabs[m_current].scroll=std::max(0.0,v); }
    void setFilter(const QString &v) { if(m_filter==v)return; m_filter=v; rebuild(); }
    void setSortMode(int v) { if(v<0||v>3)return; m_sort=v; rebuild(); }
    void setHidden(bool v) { if(v==m_hidden)return; m_hidden=v; refresh(); }
    Q_INVOKABLE void open() {
        QFile mounts(QStringLiteral("/proc/self/mountinfo"));
        const auto places = localPlaces(mounts.open(QIODevice::ReadOnly) ? mounts.readAll() : QByteArray{});
        if (places != m_places) { m_places = places; Q_EMIT placesChanged(); }
        if(!m_lister) refresh(); else Q_EMIT changed();
    }
    Q_INVOKABLE void navigate(const QString &p) {
        if(!QDir::isAbsolutePath(p)) { m_error=tr("Enter an absolute local folder path."); Q_EMIT changed(); return; }
        const auto clean=QDir::cleanPath(p);
        if(clean==path())return;
        auto &t=m_tabs[m_current]; t.history=t.history.mid(0,t.index+1);
        t.history.append(clean); ++t.index; t.scroll=0; t.selected.clear(); t.selection.clear(); t.focused.clear(); refresh(); save();
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
        m_lister=new KCoreDirLister(this); m_lister->setAutoErrorHandlingEnabled(false);
        m_lister->setShowHiddenFiles(m_hidden); m_entries.clear(); m_error.clear(); m_busy=true;
        connect(m_lister,&KCoreDirLister::itemsAdded,this,[this]{rebuild();});
        connect(m_lister,&KCoreDirLister::itemsDeleted,this,[this]{rebuild();});
        connect(m_lister,&KCoreDirLister::refreshItems,this,[this]{rebuild();});
        connect(m_lister,qOverload<>(&KCoreDirLister::completed),this,[this]{m_busy=false;rebuild();});
        connect(m_lister,&KCoreDirLister::jobError,this,[this](KIO::Job *job){m_busy=false;m_error=job->errorString();Q_EMIT changed();});
        Q_EMIT changed(); m_lister->openUrl(QUrl::fromLocalFile(path()));
    }
Q_SIGNALS:
    void changed();
    void placesChanged();
    void selectionChanged();
    void operationChanged();
    void clipboardChanged();
    void folderCreated();
    void openRequested(const QUrl &url);
private:
    struct Tab { QStringList history; int index; double scroll; QString selected; QStringList selection; QString anchor; QString focused; };
    quint64 m_listingGeneration=0;
    QList<Tab> m_tabs;
    int m_current=0, m_sort=0;
    bool m_hidden=false, m_busy=false, m_opening=false;
    bool m_selecting=false, m_working=false;
    QString m_operationStatus;
    QString m_filter, m_error;
    KCoreDirLister *m_lister=nullptr;
    QVariantList m_entries, m_places;
    void watchOperation(KJob *job,const QString &label,bool copying=false) {
        m_working=true; m_operationStatus=label; Q_EMIT operationChanged();
        connect(job,&KJob::result,this,[this,copying](KJob *finished) {
            m_working=false;
            m_operationStatus=finished->error() ? tr("Stopped: %1").arg(finished->errorString()) : tr("Done");
            if (finished->error() && copying) m_operationStatus += tr(" Some items may already have transferred.");
            m_error=finished->error() ? m_operationStatus : QString();
            Q_EMIT changed(); // Keep full failure details visible, not elided status only.
            QSettings s;
            if (finished->error()) s.setValue(QStringLiteral("Files/lastOperationError"),m_operationStatus);
            else s.remove(QStringLiteral("Files/lastOperationError"));
            // Keep navigation independent: KDirWatch updates whichever tab is shown.
            Q_EMIT operationChanged();
        });
    }
    void save() {
        QStringList paths; for(const auto &t:m_tabs)paths.append(t.history[t.index]);
        QSettings s; s.setValue(QStringLiteral("Files/paths"),paths); s.setValue(QStringLiteral("Files/current"),m_current);
    }
    void rebuild() {
        auto items=m_lister ? m_lister->items() : KFileItemList{};
        QCollator collator; collator.setNumericMode(true); collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::stable_sort(items.begin(),items.end(),[&](const KFileItem &a,const KFileItem &b){
            if(a.isDir()!=b.isDir())return a.isDir();
            if(m_sort==2 && a.time(KFileItem::ModificationTime)!=b.time(KFileItem::ModificationTime))
                return a.time(KFileItem::ModificationTime)>b.time(KFileItem::ModificationTime);
            if(m_sort==3 && a.size()!=b.size())return a.size()>b.size();
            const int c=collator.compare(a.name(),b.name());return m_sort==1 ? c>0 : c<0;
        });
        m_entries.clear();
        for(const auto &f:items) {
            if(!f.name().contains(m_filter,Qt::CaseInsensitive))continue;
            m_entries.append(QVariantMap{{QStringLiteral("name"),f.name()},{QStringLiteral("path"),f.url().toLocalFile()},
                {QStringLiteral("directory"),f.isDir()},{QStringLiteral("icon"),f.iconName()},
                {QStringLiteral("detail"),f.isDir()?tr("Folder"):QLocale().formattedDataSize(f.size())}});
        }
        Q_EMIT changed();
    }
};
