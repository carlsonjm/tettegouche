/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "OpenWindows.h"

#include <QAbstractItemModel>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlEngine>

namespace
{
const QString Prefix = QStringLiteral("plasma:");
}

OpenWindows::OpenWindows(Source source, QObject *parent)
    : QObject(parent)
    , m_source(std::move(source))
{
}

OpenWindows::Source OpenWindows::plasmaWindowList(QQmlEngine *engine)
{
    return [engine](QObject *owner) -> QAbstractItemModel * {
        if (!engine) return nullptr;
        // Every window, ungrouped, as a task bar showing all of them would
        // have it.
        QQmlComponent component(engine);
        component.setData(QByteArrayLiteral(
            "import org.kde.taskmanager as TaskManager\n"
            "TaskManager.TasksModel {\n"
            "    groupMode: TaskManager.TasksModel.GroupDisabled\n"
            "    filterByVirtualDesktop: false\n"
            "    filterByActivity: false\n"
            "    filterByScreen: false\n"
            "    filterHidden: false\n"
            "    filterMinimized: false\n"
            "}\n"), QUrl());
        QObject *made = component.create();
        auto *windows = qobject_cast<QAbstractItemModel *>(made);
        if (!windows) {
            delete made;
            return nullptr;
        }
        windows->setParent(owner);
        return windows;
    };
}

QAbstractItemModel *OpenWindows::windows()
{
    if (!m_made) {
        m_made = true;
        m_windows = m_source ? m_source(this) : nullptr;
        if (m_windows) {
            const auto changed = [this] { Q_EMIT this->changed(); };
            connect(m_windows, &QAbstractItemModel::rowsInserted, this, changed);
            connect(m_windows, &QAbstractItemModel::rowsRemoved, this, changed);
            connect(m_windows, &QAbstractItemModel::modelReset, this, changed);
            connect(m_windows, &QAbstractItemModel::layoutChanged, this, changed);
            connect(m_windows, &QAbstractItemModel::dataChanged, this, changed);
        }
    }
    return m_windows;
}

bool OpenWindows::available()
{
    return windows() != nullptr;
}

int OpenWindows::role(const char *name) const
{
    if (!m_windows) return -1;
    const QHash<int, QByteArray> roles = m_windows->roleNames();
    for (auto it = roles.cbegin(); it != roles.cend(); ++it) {
        if (it.value() == name) return it.key();
    }
    return -1;
}

QString OpenWindows::windowId(int row) const
{
    const QModelIndex index = m_windows->index(row, 0);
    const QVariant ids = index.data(role("WinIdList"));
    const QVariantList list = ids.toList();
    const QString id = list.isEmpty() ? ids.toString() : list.constFirst().toString();
    return id.isEmpty() ? QString() : Prefix + id;
}

QString OpenWindows::context()
{
    QJsonArray applications;
    QJsonObject focus;
    if (QAbstractItemModel *list = windows()) {
        const int isWindow = role("IsWindow");
        const int skip = role("SkipTaskbar");
        const int appId = role("AppId");
        const int appName = role("AppName");
        const int active = role("IsActive");
        const int lastActivated = role("LastActivated");
        for (int row = 0; row < list->rowCount(); ++row) {
            const QModelIndex index = list->index(row, 0);
            // An application's own windows, not its dialogs or what is still
            // starting.
            if (!index.data(isWindow).toBool() || index.data(skip).toBool()) continue;
            const QString id = windowId(row);
            if (id.isEmpty()) continue;
            QString name = index.data(appName).toString();
            if (name.isEmpty()) name = index.data(Qt::DisplayRole).toString();
            const QDateTime last = index.data(lastActivated).toDateTime();
            const bool focused = index.data(active).toBool();
            const QJsonObject application{
                {QStringLiteral("windowId"), id},
                {QStringLiteral("appId"), index.data(appId).toString()},
                {QStringLiteral("title"), name},
                {QStringLiteral("focused"), focused},
                {QStringLiteral("lastActivated"), last.isValid() ? last.toMSecsSinceEpoch() : 0},
            };
            applications.append(application);
            if (focused) focus = QJsonObject{{QStringLiteral("appId"), application.value(QStringLiteral("appId"))}};
        }
    }
    QJsonObject root{
        {QStringLiteral("schema"), QStringLiteral("co.goodinput.kadunce.workspace-context")},
        {QStringLiteral("version"), 1},
        {QStringLiteral("applications"), applications},
    };
    if (!focus.isEmpty()) root.insert(QStringLiteral("focus"), focus);
    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

bool OpenWindows::activate(const QString &windowId)
{
    QAbstractItemModel *list = windows();
    if (!list || !windowId.startsWith(Prefix)) return false;
    for (int row = 0; row < list->rowCount(); ++row) {
        if (this->windowId(row) != windowId) continue;
        return QMetaObject::invokeMethod(list, "requestActivate", Q_ARG(QModelIndex, list->index(row, 0)));
    }
    return false;
}
