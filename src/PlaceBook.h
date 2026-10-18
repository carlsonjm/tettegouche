#pragma once

#include <KBookmark>
#include <KBookmarkManager>
#include <KLocalizedString>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantList>
#include <memory>

// The places beside Files, kept where KDE keeps them, so a place added,
// renamed, hidden or moved here shows the same in Dolphin and in every Open
// dialog, and the other way round. Only local folders and Trash are places
// here: drives come from the hardware, Recent is always first, and network
// and search places belong to Dolphin.
class PlaceBook : public QObject
{
    Q_OBJECT
public:
    explicit PlaceBook(QObject *parent = nullptr) : QObject(parent) {}
    static QString file() {
        return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/user-places.xbel");
    }
    static QString trashLocation() { return QStringLiteral("trash:/"); }

    // Every place in KDE's order, hidden ones too: id, label, path, icon,
    // hidden, and system for the ones KDE made rather than the person.
    QVariantList places() {
        QVariantList result;
        if (!QFile::exists(file()) && !m_manager) {
            for (const auto &standard : standards()) result.append(standard);
            return result;
        }
        const auto root = manager()->root();
        for (auto bookmark = root.first(); !bookmark.isNull(); bookmark = root.next(bookmark)) {
            const auto path = pathOf(bookmark);
            if (path.isEmpty()) continue;
            const bool system = bookmark.metaDataItem(QStringLiteral("isSystemItem")) == QLatin1String("true");
            result.append(QVariantMap{{QStringLiteral("id"), bookmark.address()},
                {QStringLiteral("label"), system ? standardLabel(path, bookmark.text()) : bookmark.text()},
                {QStringLiteral("path"), path}, {QStringLiteral("icon"), bookmark.icon().isEmpty() ? QStringLiteral("folder") : bookmark.icon()},
                {QStringLiteral("hidden"), bookmark.metaDataItem(QStringLiteral("IsHidden")) == QLatin1String("true")},
                {QStringLiteral("system"), system}});
        }
        return result;
    }
    bool contains(const QString &path) {
        for (const auto &place : places()) if (place.toMap().value(QStringLiteral("path")).toString() == path) return true;
        return false;
    }
    // A local folder, at the end, named for itself; one already there is left.
    bool add(const QString &path) {
        const auto clean = QDir::cleanPath(path);
        if (!QDir::isAbsolutePath(clean) || !QFileInfo(clean).isDir() || contains(clean)) return false;
        auto root = manager(true)->root();
        const auto name = clean == QStringLiteral("/") ? clean : QFileInfo(clean).fileName();
        auto bookmark = root.addBookmark(name, QUrl::fromLocalFile(clean), QStringLiteral("folder"));
        stamp(bookmark);
        return save();
    }
    void rename(const QString &id, const QString &text) {
        const auto name = text.trimmed();
        if (name.isEmpty()) return;
        auto bookmark = find(id);
        if (bookmark.isNull()) return;
        bookmark.setFullText(name);
        // KDE names its own places in each language; once renamed, the name
        // is the person's.
        bookmark.setMetaDataItem(QStringLiteral("isSystemItem"), QStringLiteral("false"));
        save();
    }
    void setHidden(const QString &id, bool hidden) {
        auto bookmark = find(id);
        if (bookmark.isNull()) return;
        bookmark.setMetaDataItem(QStringLiteral("IsHidden"), hidden ? QStringLiteral("true") : QStringLiteral("false"));
        save();
    }
    // Only a place the person added goes; KDE's own are hidden instead.
    void remove(const QString &id) {
        auto bookmark = find(id);
        if (bookmark.isNull() || bookmark.metaDataItem(QStringLiteral("isSystemItem")) == QLatin1String("true")) return;
        bookmark.parentGroup().deleteBookmark(bookmark);
        save();
    }
    // Moves a place before another, or to the end when there is none.
    void move(const QString &id, const QString &beforeId) {
        if (id == beforeId) return;
        auto bookmark = find(id);
        if (bookmark.isNull()) return;
        auto root = manager()->root();
        KBookmark after;
        if (beforeId.isEmpty()) {
            for (auto b = root.first(); !b.isNull(); b = root.next(b)) after = b;
        } else {
            const auto before = find(beforeId);
            if (before.isNull()) return;
            after = root.previous(before);
        }
        if (after == bookmark) return;
        root.moveBookmark(bookmark, after);
        save();
    }

Q_SIGNALS:
    void changed();

private:
    // KDE's standard places, as Dolphin makes them on a new account; the
    // ones Files did not show before start hidden.
    static QVariantList standards() {
        QVariantList result;
        const auto add = [&result](const QString &path, const QString &icon, bool hidden) {
            if (path.isEmpty()) return;
            result.append(QVariantMap{{QStringLiteral("id"), QStringLiteral("standard:") + path},
                {QStringLiteral("label"), standardLabel(path, QFileInfo(path).fileName())}, {QStringLiteral("path"), path},
                {QStringLiteral("icon"), icon}, {QStringLiteral("hidden"), hidden}, {QStringLiteral("system"), true}});
        };
        add(QDir::homePath(), QStringLiteral("user-home"), false);
        add(QStandardPaths::writableLocation(QStandardPaths::DesktopLocation), QStringLiteral("user-desktop"), true);
        add(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), QStringLiteral("folder-documents"), false);
        add(QStandardPaths::writableLocation(QStandardPaths::DownloadLocation), QStringLiteral("folder-download"), false);
        add(QStandardPaths::writableLocation(QStandardPaths::MusicLocation), QStringLiteral("folder-music"), true);
        add(QStandardPaths::writableLocation(QStandardPaths::PicturesLocation), QStringLiteral("folder-pictures"), false);
        add(QStandardPaths::writableLocation(QStandardPaths::MoviesLocation), QStringLiteral("folder-videos"), true);
        add(trashLocation(), QStringLiteral("user-trash"), false);
        // Two standard folders can be the same one, such as Home.
        QStringList seen;
        result.removeIf([&seen](const QVariant &place) {
            const auto path = place.toMap().value(QStringLiteral("path")).toString();
            if (seen.contains(path)) return true;
            seen.append(path);
            return false;
        });
        return result;
    }
    static QString standardLabel(const QString &path, const QString &fallback) {
        if (path == trashLocation()) return i18n("Trash");
        if (path == QDir::homePath()) return i18n("Home");
        const std::pair<QStandardPaths::StandardLocation, QString> names[] = {
            {QStandardPaths::DesktopLocation, i18n("Desktop")}, {QStandardPaths::DocumentsLocation, i18n("Documents")},
            {QStandardPaths::DownloadLocation, i18n("Downloads")}, {QStandardPaths::MusicLocation, i18n("Music")},
            {QStandardPaths::PicturesLocation, i18n("Pictures")}, {QStandardPaths::MoviesLocation, i18n("Videos")}};
        for (const auto &[location, name] : names)
            if (QStandardPaths::writableLocation(location) == path) return name;
        return fallback;
    }
    // A place's folder, or Trash; anything else is not a place here.
    static QString pathOf(const KBookmark &bookmark) {
        if (bookmark.isGroup() || bookmark.isSeparator()) return {};
        if (!bookmark.metaDataItem(QStringLiteral("OnlyInApp")).isEmpty()) return {};
        if (!bookmark.metaDataItem(QStringLiteral("UDI")).isEmpty()) return {};
        const auto url = bookmark.url();
        if (url.scheme() == QLatin1String("trash")) return trashLocation();
        return url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QString();
    }
    KBookmarkManager *manager(bool seed = false) {
        if (!m_manager) {
            const bool fresh = !QFile::exists(file());
            QDir().mkpath(QFileInfo(file()).path());
            m_manager = std::make_unique<KBookmarkManager>(file());
            connect(m_manager.get(), &KBookmarkManager::changed, this, &PlaceBook::changed);
            // A first change writes KDE's standard places before it, as
            // Dolphin would have, so the file never holds less than they do.
            if (fresh && seed) {
                auto root = m_manager->root();
                for (const auto &standard : standards()) {
                    const auto map = standard.toMap();
                    const auto path = map.value(QStringLiteral("path")).toString();
                    auto bookmark = root.addBookmark(map.value(QStringLiteral("label")).toString(),
                        path == trashLocation() ? QUrl(path) : QUrl::fromLocalFile(path), map.value(QStringLiteral("icon")).toString());
                    stamp(bookmark);
                    bookmark.setMetaDataItem(QStringLiteral("isSystemItem"), QStringLiteral("true"));
                    if (map.value(QStringLiteral("hidden")).toBool()) bookmark.setMetaDataItem(QStringLiteral("IsHidden"), QStringLiteral("true"));
                }
            }
        }
        return m_manager.get();
    }
    // The identity KDE's places keep for each place, in its own form.
    void stamp(KBookmark &bookmark) {
        static int count = 0;
        bookmark.setMetaDataItem(QStringLiteral("ID"),
            QString::number(QDateTime::currentSecsSinceEpoch()) + QLatin1Char('/') + QString::number(count++));
    }
    KBookmark find(const QString &id) {
        if (id.startsWith(QLatin1String("standard:"))) {
            // A standard place before the file exists: write the file, then
            // find the place by its folder.
            const auto path = id.mid(9);
            const auto root = manager(true)->root();
            for (auto b = root.first(); !b.isNull(); b = root.next(b)) if (pathOf(b) == path) return b;
            return {};
        }
        const auto bookmark = manager()->findByAddress(id);
        return pathOf(bookmark).isEmpty() ? KBookmark() : bookmark;
    }
    bool save() {
        const bool saved = m_manager->save(false);
        Q_EMIT changed();
        return saved;
    }
    std::unique_ptr<KBookmarkManager> m_manager;
};
