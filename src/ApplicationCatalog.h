/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService/KService>

#include <QAbstractListModel>
#include <QVector>

class ApplicationCatalog final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)
    Q_PROPERTY(bool descending READ descending WRITE setDescending NOTIFY descendingChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        IconRole,
        ApplicationIdRole,
    };
    Q_ENUM(Role)

    explicit ApplicationCatalog(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE [[nodiscard]] QString applicationId(int row) const;
    Q_INVOKABLE [[nodiscard]] QString applicationName(int row) const;

    [[nodiscard]] QString filterText() const;
    void setFilterText(const QString &filterText);
    [[nodiscard]] bool descending() const;
    void setDescending(bool descending);

Q_SIGNALS:
    void filterTextChanged();
    void descendingChanged();

private:
    struct Entry {
        KService::Ptr service;
        QString name;
        QString icon;
        QString applicationId;
    };

    void rebuildVisibleRows();

    QVector<Entry> m_entries;
    QVector<int> m_visibleRows;
    QString m_filterText;
    bool m_descending = false;
};
