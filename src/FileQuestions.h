#pragma once

#include <KIO/AskUserActionInterface>

#include <QDateTime>
#include <QTimer>
#include <QUrl>

#include <functional>

// What KIO asks while Files copies or moves. A name already taken goes to
// Files, which shows the person the choice. A file that cannot be read in a
// copy of several is skipped, and the rest go on; Files says at the end what
// was left behind. Anything else is answered no, so an error stops the job as
// it did before KIO could ask, and the error is kept for Files to report.
class FileQuestions : public KIO::AskUserActionInterface
{
    Q_OBJECT
public:
    struct NameTaken {
        KJob *job = nullptr;
        QUrl source;
        QUrl destination;
        KIO::RenameDialog_Options options;
        KIO::filesize_t sourceSize = 0;
        KIO::filesize_t destinationSize = 0;
        QDateTime sourceModified;
        QDateTime destinationModified;
    };

    FileQuestions(QObject *parent, std::function<void(FileQuestions *, const NameTaken &)> onNameTaken)
        : KIO::AskUserActionInterface(parent)
        , m_onNameTaken(std::move(onNameTaken))
    {
    }

    // The last error KIO asked about, which stopped the job.
    QString stoppedBy() const { return m_stoppedBy; }
    // What KIO could not carry and Files skipped, in KIO's words.
    QStringList skipped() const { return m_skipped; }

    // Answers KIO after the question, never inside it.
    void answerNameTaken(KIO::RenameDialog_Result result, const QUrl &newUrl, KJob *job)
    {
        QTimer::singleShot(0, this, [this, result, newUrl, job] {
            Q_EMIT askUserRenameResult(result, newUrl, job);
        });
    }

    void askUserRename(KJob *job,
                       const QString &,
                       const QUrl &source,
                       const QUrl &destination,
                       KIO::RenameDialog_Options options,
                       KIO::filesize_t sourceSize,
                       KIO::filesize_t destinationSize,
                       const QDateTime &,
                       const QDateTime &,
                       const QDateTime &sourceModified,
                       const QDateTime &destinationModified) override
    {
        m_onNameTaken(this, {job, source, destination, options, sourceSize, destinationSize, sourceModified, destinationModified});
    }

    void askUserSkip(KJob *job, KIO::SkipDialog_Options options, const QString &errorText) override
    {
        // Skipping the one file there is would carry nothing; that stops.
        const bool several = options & KIO::SkipDialog_MultipleItems;
        if (several) m_skipped.append(errorText);
        else m_stoppedBy = errorText;
        QTimer::singleShot(0, this, [this, job, several] {
            Q_EMIT askUserSkipResult(several ? KIO::Result_Skip : KIO::Result_Cancel, job);
        });
    }

    void askUserDelete(const QList<QUrl> &urls, DeletionType deletionType, ConfirmationType, QWidget *parent) override
    {
        QTimer::singleShot(0, this, [this, urls, deletionType, parent] {
            Q_EMIT askUserDeleteResult(false, urls, deletionType, parent);
        });
    }

    void requestUserMessageBox(MessageDialogType,
                               const QString &,
                               const QString &,
                               const QString &,
                               const QString &,
                               const QString &,
                               const QString &,
                               const QString &,
                               const QString &,
                               QWidget *) override
    {
        // KIO's Cancel button.
        QTimer::singleShot(0, this, [this] {
            Q_EMIT messageBoxResult(2);
        });
    }

    void askIgnoreSslErrors(const QVariantMap &, QWidget *) override
    {
        QTimer::singleShot(0, this, [this] {
            Q_EMIT askIgnoreSslErrorsResult(0);
        });
    }

private:
    std::function<void(FileQuestions *, const NameTaken &)> m_onNameTaken;
    QString m_stoppedBy;
    QStringList m_skipped;
};
