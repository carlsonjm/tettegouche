#pragma once

#include <KCoreDirLister>
#include <KFileItem>
#include <KIO/Job>
#include <QCollator>
#include <QDir>
#include <QFile>
#include <QSettings>
#include <QStandardPaths>
#include <QVariantList>
#include <algorithm>

// Read-only local browsing. Each listing has its own lifetime so late replies
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
public:
    explicit FileBrowser(QObject *parent = nullptr) : QObject(parent) {
        QSettings settings;
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
        if (m_opening || m_busy || !m_lister || selectedPath().isEmpty()) return;
        // Only dispatch a selection from the currently displayed listing.
        // Passing a URL as data avoids shell parsing of filenames.
        const auto url = QUrl::fromLocalFile(selectedPath());
        const auto item = m_lister->findByUrl(url);
        if (item.isNull() || item.isDir()) {
            m_error = tr("This file is no longer available. Refresh the folder.");
            Q_EMIT changed(); return;
        }
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
    void setSelectedPath(const QString &v) { if (selectedPath()==v) return; m_tabs[m_current].selected=v; Q_EMIT selectionChanged(); }
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
        t.history.append(clean); ++t.index; t.scroll=0; t.selected.clear(); refresh(); save();
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
    void openRequested(const QUrl &url);
private:
    struct Tab { QStringList history; int index; double scroll; QString selected; };
    QList<Tab> m_tabs;
    int m_current=0, m_sort=0;
    bool m_hidden=false, m_busy=false, m_opening=false;
    QString m_filter, m_error;
    KCoreDirLister *m_lister=nullptr;
    QVariantList m_entries, m_places;
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
