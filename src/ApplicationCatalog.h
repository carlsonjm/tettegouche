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

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        IconRole,
        ApplicationIdRole,
        HiddenRole,
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

Q_SIGNALS:
    void filterTextChanged();
    void sortOrderChanged();
    void showHiddenChanged();
    void hiddenCountChanged();
    void softwareReadyChanged();

private:
    struct Entry {
        KService::Ptr service;
        QString name;
        QString icon;
        QString applicationId;
        // When its desktop file arrived, as near as the file system says.
        QDateTime installed;
    };

    void rebuildVisibleRows();
    [[nodiscard]] const Entry *entryAt(int row) const;
    [[nodiscard]] QString softwareId(const Entry &entry) const;

    QVector<Entry> m_entries;
    QVector<int> m_visibleRows;
    QString m_filterText;
    int m_sortOrder = NameAscending;
    UseReader m_useReader;
    QHash<QString, double> m_use;
    QSet<QString> m_hidden;
    bool m_showHidden = false;
    std::unique_ptr<AppStream::Pool> m_software;
    bool m_softwareReady = false;
};
