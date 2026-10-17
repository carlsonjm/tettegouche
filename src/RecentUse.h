/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "UseRecord.h"

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QString>
#include <QVector>

#include <functional>

// What was used lately, for Search's first screen: applications, then files,
// each newest first, from KDE's record of use. An application the dock holds, one
// already open, or one hidden from Apps is left out, and so is a file that is
// gone, a folder, or anything not on this machine: what is left is what would
// otherwise be reached the long way. The record is read when Search opens and
// filtered again when what is open or pinned changes; nothing is watched.
class RecentUse final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    // The rows before the files: the applications.
    Q_PROPERTY(int applicationCount READ applicationCount NOTIFY countChanged)

public:
    // One use, as KDE's record keeps it: an "applications:" address or a file.
    struct Used {
        QString resource;
        uint lastUsed = 0;
    };
    enum Role {
        NameRole = Qt::UserRole + 1,
        IconRole,
        ThumbnailRole,
        KindRole,
        // The folder a file is in, by name; empty for an application.
        WhereRole,
        // When it was last used.
        WhenRole,
    };
    Q_ENUM(Role)

    using Reader = std::function<QList<Used>()>;
    using Excluded = std::function<bool(const QString &applicationId, const QString &name)>;
    using Thumbnails = std::function<QString(const QString &path, const QString &mimeType, qint64 modified)>;

    // The most kept of each: as many as the first screen ever shows.
    static constexpr int ApplicationsKept = 8;
    static constexpr int FilesKept = 8;

    explicit RecentUse(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_items.size(); }
    int applicationCount() const { return m_applicationCount; }

    void setReader(Reader reader) { m_reader = std::move(reader); }
    void setExcluded(Excluded excluded) { m_excluded = std::move(excluded); }
    void setThumbnails(Thumbnails thumbnails) { m_thumbnails = std::move(thumbnails); }
    // While the screen is shared, nothing is offered, so no file's name is on
    // show to whoever is watching.
    void setWithheld(bool withheld);
    // Which kinds are offered at all, both unless a setting leaves one out.
    void setOffered(bool applications, bool files);

    // Reads the record again.
    void refresh();
    // Applies what is open, pinned and hidden again, to the record last read.
    void refilter();

    // The application a row opens: its own, or a file's usual one.
    Q_INVOKABLE QString applicationFor(int row) const;
    Q_INVOKABLE bool open(int row);

    // KDE's record of use, newest first, under the current activity.
    static QList<Used> readRecord();
    // How much each application has been used, in every activity, by desktop
    // file id: KDE's own score, which favours both often and lately, and when
    // it was last used in any of them.
    static QHash<QString, ApplicationUse> readApplicationUse();

Q_SIGNALS:
    void countChanged();

private:
    struct Item {
        QString kind; // "application" or "file"
        QString name;
        QString icon;
        QString thumbnail;
        QString applicationId;
        QString path;
        QString mimeType;
        QString where;
        uint lastUsed = 0;
    };
    void rebuild();

    Reader m_reader;
    Excluded m_excluded;
    Thumbnails m_thumbnails;
    QList<Used> m_record;
    QVector<Item> m_items;
    int m_applicationCount = 0;
    bool m_withheld = false;
    bool m_applicationsOffered = true;
    bool m_filesOffered = true;
};
