#pragma once
#include <QObject>
class FileBrowser;
class TransferActivityBridge : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche.Activities1")
public:
    explicit TransferActivityBridge(FileBrowser *files, QObject *parent = nullptr);
public Q_SLOTS:
    QString snapshot() const;
    void cancel(const QString &id);
Q_SIGNALS:
    void changed(const QString &snapshot);
private:
    FileBrowser *m_files;
    quint64 m_revision = 0;
};
