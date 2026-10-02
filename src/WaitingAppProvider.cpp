#include "WaitingAppProvider.h"
#include <taskmanager/abstracttasksmodel.h>
#include <QAbstractItemModel>
#include <QIcon>
#include <algorithm>

namespace {
using TaskManager::AbstractTasksModel;
const QString Prefix = QStringLiteral("waiting:");

// The roles that can start, end or reword a wait. A window moving, resizing or
// restacking changes none of them, so it asks for no reading.
bool readable(int role) {
    switch (role) {
    case Qt::DisplayRole: case Qt::DecorationRole: case AbstractTasksModel::AppId: case AbstractTasksModel::AppName:
    case AbstractTasksModel::IsDemandingAttention: case AbstractTasksModel::SkipTaskbar:
    case AbstractTasksModel::AppPid: case AbstractTasksModel::WinIdList: case AbstractTasksModel::IsWindow:
        return true;
    }
    return false;
}

QString windowKey(const QModelIndex &index) {
    const auto ids = index.data(AbstractTasksModel::WinIdList).toList();
    return ids.isEmpty() ? QString() : ids.first().toString();
}

// The process a window belongs to, where Plasma knows it; else its application.
QString owner(const QModelIndex &index) {
    const auto pid = index.data(AbstractTasksModel::AppPid).toLongLong();
    if (pid > 0) return QString::number(pid);
    const auto app = index.data(AbstractTasksModel::AppId).toString();
    return app.isEmpty() ? QString() : QStringLiteral("app:") + app;
}

// A dialog's title, less the application's name that Qt and KDE put after it.
QString question(QString title, const QString &name) {
    title = title.trimmed();
    if (!name.isEmpty()) {
        for (const auto &dash : {QStringLiteral(" — "), QStringLiteral(" – "), QStringLiteral(" - ")}) {
            if (title.endsWith(dash + name)) { title.chop(dash.size() + name.size()); break; }
        }
    }
    title = title.trimmed();
    return title == name ? QString() : title;
}
}

WaitingAppProvider::WaitingAppProvider(QAbstractItemModel *windows, QObject *parent) : QObject(parent), m_windows(windows) {
    if (!windows) return;
    const auto reread = [this] { read(); };
    connect(windows, &QAbstractItemModel::rowsInserted, this, reread);
    connect(windows, &QAbstractItemModel::rowsRemoved, this, reread);
    connect(windows, &QAbstractItemModel::rowsMoved, this, reread);
    connect(windows, &QAbstractItemModel::modelReset, this, reread);
    connect(windows, &QAbstractItemModel::layoutChanged, this, reread);
    connect(windows, &QAbstractItemModel::dataChanged, this,
            [this](const QModelIndex &, const QModelIndex &, const QList<int> &roles) {
        if (roles.isEmpty() || std::any_of(roles.cbegin(), roles.cend(), readable)) read();
    });
    read();
}

void WaitingAppProvider::read() {
    QHash<QString, Waiting> next;
    const int rows = m_windows ? m_windows->rowCount() : 0;
    // Windows kept off the task bar, by process: an application's dialogs.
    QHash<QString, QStringList> dialogs;
    for (int row = 0; row < rows; ++row) {
        const auto index = m_windows->index(row, 0);
        if (index.data(AbstractTasksModel::SkipTaskbar).toBool() && !owner(index).isEmpty())
            dialogs[owner(index)].append(index.data(Qt::DisplayRole).toString());
    }
    for (int row = 0; row < rows; ++row) {
        const auto index = m_windows->index(row, 0);
        if (!index.data(AbstractTasksModel::IsWindow).toBool()
                || !index.data(AbstractTasksModel::IsDemandingAttention).toBool()) continue;
        const auto window = windowKey(index);
        if (window.isEmpty()) continue;
        Waiting waiting;
        waiting.window = window;
        waiting.index = index;
        waiting.name = index.data(AbstractTasksModel::AppName).toString();
        if (waiting.name.isEmpty()) waiting.name = index.data(Qt::DisplayRole).toString();
        const auto icon = index.data(Qt::DecorationRole).value<QIcon>();
        waiting.icon = !icon.name().isEmpty() ? icon.name() : index.data(AbstractTasksModel::AppId).toString();
        // A dialog that raises the flag itself asks its own question; else the
        // one window its process keeps off the task bar asks it. With two or
        // more there is no telling which waits, so none is shown.
        const auto asked = index.data(AbstractTasksModel::SkipTaskbar).toBool()
            ? QStringList{index.data(Qt::DisplayRole).toString()} : dialogs.value(owner(index));
        if (asked.size() == 1) waiting.question = question(asked.first(), waiting.name);
        const auto old = m_waiting.constFind(window);
        waiting.generation = old != m_waiting.cend() ? old->generation : ++m_generation;
        next.insert(window, waiting);
    }
    bool differs = next.size() != m_waiting.size();
    for (auto it = next.cbegin(); !differs && it != next.cend(); ++it) {
        const auto old = m_waiting.constFind(it.key());
        differs = old == m_waiting.cend() || old->name != it->name || old->icon != it->icon
            || old->question != it->question || old->generation != it->generation;
    }
    m_waiting = next;
    if (differs) Q_EMIT changed();
}

QVariantList WaitingAppProvider::activities() const {
    QList<Waiting> waiting = m_waiting.values();
    std::sort(waiting.begin(), waiting.end(), [](const Waiting &a, const Waiting &b) { return a.generation < b.generation; });
    const bool raises = dynamic_cast<TaskManager::AbstractTasksModelIface *>(m_windows.data()) != nullptr;
    QVariantList rows;
    for (const auto &app : waiting) {
        rows.append(QVariantMap{{QStringLiteral("id"), QString(Prefix + app.window)}, {QStringLiteral("generation"), app.generation},
            {QStringLiteral("kind"), QStringLiteral("waiting")}, {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("title"), app.name}, {QStringLiteral("icon"), app.icon}, {QStringLiteral("question"), app.question},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("raise"), raises}}}});
    }
    return rows;
}

// Raise: Plasma activates the window, as a tap on it in a task bar would.
void WaitingAppProvider::invoke(const QString &id, int generation, const QString &action) {
    if (!id.startsWith(Prefix) || action != QLatin1String("raise")) return;
    const auto found = m_waiting.constFind(id.mid(Prefix.size()));
    if (found == m_waiting.cend() || found->generation != generation || !found->index.isValid()) return;
    if (auto *tasks = dynamic_cast<TaskManager::AbstractTasksModelIface *>(m_windows.data()))
        tasks->requestActivate(QModelIndex(found->index));
}
