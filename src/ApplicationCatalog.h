/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "UseRecord.h"

#include <KService>

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QUrl>
#include <QVector>

#include <functional>
#include <memory>

namespace AppStream
{
class Pool;
}

class ApplicationCatalog final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)
    // Apps' order, one of Order; the choice is kept for the next time.
    Q_PROPERTY(int sortOrder READ sortOrder WRITE setSortOrder NOTIFY sortOrderChanged)
    // Hidden applications leave Apps; this shows them again.
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(int hiddenCount READ hiddenCount NOTIFY hiddenCountChanged)
    // Whether the software catalog has loaded, so canUninstall can answer.
    Q_PROPERTY(bool softwareReady READ softwareReady NOTIFY softwareReadyChanged)
    // Whether any folder is drawn, so the sheet can offer one to put in.
    Q_PROPERTY(int folderCount READ folderCount NOTIFY foldersChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        IconRole,
        ApplicationIdRole,
        HiddenRole,
        IsFolderRole,
        FolderIdRole,
        // Up to four of a folder's applications' icons, in Apps' order.
        FolderIconsRole,
        // What a row is: "application", "member" for an application inside
        // an open folder, "folder" or "section".
        KindRole,
        // Whether a folder's row is open, its applications below it.
        OpenRole,
        // How many applications a folder's row holds.
        SizeRole,
    };
    Q_ENUM(Role)

    // Each order keeps the number it is stored by; 1 was Z to A, and a
    // kept 1 reads as A to Z.
    enum Order {
        NameAscending = 0,
        MostUsed = 2,
        NewestInstalled = 3,
    };
    Q_ENUM(Order)

    // How much and how lately each application has been used, by desktop
    // file id. An application missing from it has not been used.
    using UseReader = std::function<QHash<QString, ApplicationUse>()>;

    explicit ApplicationCatalog(QObject *parent = nullptr);
    ~ApplicationCatalog() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE [[nodiscard]] QString applicationId(int row) const;
    Q_INVOKABLE [[nodiscard]] QString applicationName(int row) const;
    // The application's desktop file, as a drop elsewhere takes it.
    [[nodiscard]] QUrl applicationUrl(int row) const;
    [[nodiscard]] QString applicationIcon(int row) const;
    // The application's own actions from its desktop file, each {index, name,
    // icon}, in its order; runAction starts one by that index.
    Q_INVOKABLE [[nodiscard]] QVariantList actions(int row) const;
    Q_INVOKABLE bool runAction(int row, int action);
    Q_INVOKABLE [[nodiscard]] bool isHidden(int row) const;
    [[nodiscard]] bool isHiddenApplication(const QString &applicationId) const;
    Q_INVOKABLE void setHidden(int row, bool hidden);
    // Loads the software catalog once, in the background; softwareReady says
    // when it has. Until then canUninstall answers false.
    Q_INVOKABLE void prepareSoftware();
    // Whether the application can be uninstalled from its sheet: by Split
    // Rock's Core where it removes apps, which finds the package that owns
    // the application and asks for a yes; else by the software centre, where
    // one handles software links and its catalog lists the application.
    Q_INVOKABLE [[nodiscard]] bool canUninstall(int row) const;
    Q_INVOKABLE bool uninstall(int row);
    // The same, for an application by its desktop file id, as Search finds
    // it, hidden or not.
    Q_INVOKABLE [[nodiscard]] bool canUninstallApplication(const QString &applicationId) const;
    Q_INVOKABLE bool uninstallApplication(const QString &applicationId);
    // What removes an application, by its desktop file id and name, and
    // whether it is there now.
    void setRemover(std::function<bool()> available, std::function<void(const QString &, const QString &)> remove)
    {
        m_canRemove = std::move(available);
        m_remove = std::move(remove);
    }
    // Whether KDE's menu editor is installed to open the application's menu
    // entry in.
    Q_INVOKABLE [[nodiscard]] bool canEdit(int row) const;
    // Opens the application's menu entry in KDE's menu editor, where its name,
    // icon and command change for this person; Apps reads the change when
    // KDE's application list does.
    Q_INVOKABLE bool edit(int row);
    // Reads KDE's application list again, as it does whenever that list
    // changes, keeping folders, hidden applications, the order and the words
    // typed.
    void reload();
    // Asks KDE whether its application list is out of date, which rebuilds
    // it when an application was installed or removed; called when Apps
    // opens and when a folder applications live in changes.
    Q_INVOKABLE void checkInstalled();
    // The row an application is drawn at, by its desktop file id, or -1.
    Q_INVOKABLE [[nodiscard]] int applicationRow(const QString &applicationId) const;

    // Order and sections. With nothing typed, A to Z is one run by name, each
    // folder at its name's place among the applications. Most used is divided
    // by when each was last used (today, this week, this month, earlier), the
    // most used first inside each; Newest installed by when it arrived (this
    // week, this month, this year, older). Each of their sections opens with a
    // row of its own, then its folders A to Z, then its applications in the
    // order; a folder sits in the section of its first application in the
    // order. An application arrives when Apps first finds it; those already
    // here when Apps began keeping count are Older.
    //
    // Folders. A folder is a row that opens or closes in place, its
    // applications below it in the order; whether each is open is kept. A
    // folder is drawn while two or more of its applications are here and
    // shown; otherwise those here show as themselves. Typing searches every
    // application, in folders or not, with no sections.
    Q_INVOKABLE [[nodiscard]] QString kind(int row) const;
    // A row's roles by name, for a view that draws rows out of a model's own.
    Q_INVOKABLE [[nodiscard]] QVariantMap item(int row) const;
    Q_INVOKABLE [[nodiscard]] bool isOpen(int row) const;
    // Opens or closes a folder's row, and keeps the choice.
    Q_INVOKABLE void setFolderOpen(const QString &folderId, bool open);
    // The row a folder is drawn at, or -1.
    Q_INVOKABLE [[nodiscard]] int folderRow(const QString &folderId) const;
    Q_INVOKABLE [[nodiscard]] bool isFolder(int row) const;
    Q_INVOKABLE [[nodiscard]] QString folderId(int row) const;
    Q_INVOKABLE [[nodiscard]] QString folderName(int row) const;
    // The folder an application's row is in, or empty.
    Q_INVOKABLE [[nodiscard]] QString folderOf(int row) const;
    // Every drawn folder, each {id, name}, A to Z.
    Q_INVOKABLE [[nodiscard]] QVariantList folderList() const;
    // Puts the application with this id into the folder a row is, or makes a
    // new folder of it and the application a row is. Returns the folder's id.
    Q_INVOKABLE QString gather(int row, const QString &applicationId);
    // Makes a new folder of these applications, two or more, each leaving any
    // folder it was in; it starts open. Returns the folder's id, or empty when
    // fewer than two are known.
    Q_INVOKABLE QString makeFolder(const QStringList &applicationIds);
    // Puts an application's row into a folder.
    Q_INVOKABLE void putInFolder(int row, const QString &folderId);
    // Takes an application's row out of its folder; a folder left with one
    // application is no longer a folder.
    Q_INVOKABLE void takeOut(int row);
    Q_INVOKABLE void renameFolder(const QString &folderId, const QString &name);
    // Ends a folder; its applications go back to Apps.
    Q_INVOKABLE void removeFolder(const QString &folderId);
    // A folder's applications' desktop files, as a drop elsewhere takes them.
    [[nodiscard]] QList<QUrl> folderUrls(int row) const;

    [[nodiscard]] QString filterText() const;
    void setFilterText(const QString &filterText);
    [[nodiscard]] int sortOrder() const;
    void setSortOrder(int sortOrder);
    void setUseReader(UseReader reader);
    // Reads how much each application has been used again, while Most used is
    // the order, so it is current each time Apps opens.
    Q_INVOKABLE void refreshUse();
    [[nodiscard]] bool showHidden() const;
    void setShowHidden(bool showHidden);
    [[nodiscard]] int hiddenCount() const;
    [[nodiscard]] bool softwareReady() const;
    [[nodiscard]] int folderCount() const;

Q_SIGNALS:
    void filterTextChanged();
    void sortOrderChanged();
    void showHiddenChanged();
    void hiddenCountChanged();
    void softwareReadyChanged();
    void foldersChanged();

private:
    struct Entry {
        KService::Ptr service;
        QString name;
        QString icon;
        QString applicationId;
        // When Apps first found it; none for one already here when Apps
        // began keeping count.
        QDateTime installed;
    };

    struct Folder {
        QString id;
        QString name;
        QStringList applications;
    };

    enum RowKind {
        ApplicationRow,
        MemberRow,
        FolderRow,
        SectionRow,
    };

    // A drawn row: an application or a folder by its index, or a section by
    // its label. While A to Z is put in order, the label is the name.
    struct Row {
        RowKind kind;
        int at;
        QString label;
    };

    // With `entries`, they replace the list read before, inside the same
    // reset of the model.
    void rebuildVisibleRows(QVector<Entry> *entries = nullptr);
    [[nodiscard]] static QVector<Entry> readEntries();
    void sortEntries(QVector<int> &rows) const;
    void storeFolders();
    void storeOpenFolders();
    // The section an application falls in under the order, as a key that
    // sorts the sections and the label its row shows.
    [[nodiscard]] QPair<QString, QString> sectionOf(int entry) const;
    // When an application was last used, as one of Most used's sections.
    [[nodiscard]] int useSpan(int entry) const;
    // A folder's name as drawn.
    [[nodiscard]] QString folderLabel(int folder) const;
    // The section a folder of these applications sits in.
    [[nodiscard]] QPair<QString, QString> folderSection(const QVector<int> &members) const;
    // Gives each application the time Apps first found it, noting those new
    // to it now.
    static void noteArrivals(QVector<Entry> &entries);
    [[nodiscard]] bool shown(const Entry &entry) const;
    [[nodiscard]] int entryIndex(const QString &applicationId) const;
    [[nodiscard]] int folderIndex(const QString &folderId) const;
    [[nodiscard]] const Folder *folderAt(int row) const;
    // The folders drawn, by index into m_folders, each with its entries.
    [[nodiscard]] QHash<int, QVector<int>> drawnFolders() const;
    [[nodiscard]] QString nameFor(const QStringList &applicationIds) const;
    [[nodiscard]] const Entry *entryAt(int row) const;
    [[nodiscard]] QString softwareId(const Entry &entry) const;

    QVector<Entry> m_entries;
    QVector<Row> m_visibleRows;
    QVector<Folder> m_folders;
    QSet<QString> m_openFolders;
    int m_drawnFolders = 0;
    QString m_filterText;
    int m_sortOrder = NameAscending;
    UseReader m_useReader;
    QHash<QString, ApplicationUse> m_use;
    QSet<QString> m_hidden;
    bool m_showHidden = false;
    std::unique_ptr<AppStream::Pool> m_software;
    bool m_softwareReady = false;
    std::function<bool()> m_canRemove;
    std::function<void(const QString &, const QString &)> m_remove;
};
