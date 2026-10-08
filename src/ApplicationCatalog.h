/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

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
    // The folder Apps shows the inside of, by id; empty shows Apps itself.
    Q_PROPERTY(QString openFolder READ openFolder WRITE setOpenFolder NOTIFY openFolderChanged)
    Q_PROPERTY(QString openFolderName READ openFolderName NOTIFY openFolderChanged)
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
    };
    Q_ENUM(Role)

    enum Order {
        NameAscending,
        NameDescending,
        MostUsed,
        NewestInstalled,
    };
    Q_ENUM(Order)

    // How much each application has been used, by desktop file id; the
    // higher, the more. An application missing from it has not been used.
    using UseReader = std::function<QHash<QString, double>()>;

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
    // Whether the software centre can show the application to be uninstalled:
    // one handles software links and its catalog lists the application.
    Q_INVOKABLE [[nodiscard]] bool canUninstall(int row) const;
    Q_INVOKABLE bool uninstall(int row);

    // Folders. Apps draws its folders first, A to Z by name, and the
    // applications in none after them in the chosen order; inside a folder its
    // applications keep that order too. A folder is drawn while two or more of
    // its applications are here and shown; otherwise those here show as
    // themselves. Typing searches every application, in folders or not.
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
    [[nodiscard]] QString openFolder() const;
    void setOpenFolder(const QString &folderId);
    [[nodiscard]] QString openFolderName() const;
    [[nodiscard]] int folderCount() const;

Q_SIGNALS:
    void filterTextChanged();
    void sortOrderChanged();
    void showHiddenChanged();
    void hiddenCountChanged();
    void softwareReadyChanged();
    void openFolderChanged();
    void foldersChanged();

private:
    struct Entry {
        KService::Ptr service;
        QString name;
        QString icon;
        QString applicationId;
        // When its desktop file arrived, as near as the file system says.
        QDateTime installed;
    };

    struct Folder {
        QString id;
        QString name;
        QStringList applications;
    };

    void rebuildVisibleRows();
    void sortEntries(QVector<int> &rows) const;
    void storeFolders();
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
    // Each row: an entry's index, or a folder's as -1 - its index.
    QVector<int> m_visibleRows;
    QVector<Folder> m_folders;
    QString m_openFolder;
    int m_drawnFolders = 0;
    QString m_filterText;
    int m_sortOrder = NameAscending;
    UseReader m_useReader;
    QHash<QString, double> m_use;
    QSet<QString> m_hidden;
    bool m_showHidden = false;
    std::unique_ptr<AppStream::Pool> m_software;
    bool m_softwareReady = false;
};
