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
    [[nodiscard]] QString applicationId(int row) const;
    [[nodiscard]] QString applicationName(int row) const;

private:
    struct Entry {
        KService::Ptr service;
        QString name;
        QString icon;
        QString applicationId;
    };

    QVector<Entry> m_entries;
};
