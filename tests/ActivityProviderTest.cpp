#include "ActivityModel.h"
#include "ActivityUtils.h"
#include "TransferActivityBridge.h"
#include "FileBrowser.h"
#include <QTest>
#include <QGuiApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusConnectionInterface>
#include <QTemporaryDir>
#include <QSignalSpy>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <fcntl.h>
#include <unistd.h>

class FakePlayer : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus MEMBER status)
    Q_PROPERTY(bool CanControl MEMBER control)
    Q_PROPERTY(bool CanPlay MEMBER canPlay)
    Q_PROPERTY(bool CanPause MEMBER canPause)
    Q_PROPERTY(bool CanGoNext MEMBER next)
    Q_PROPERTY(bool CanGoPrevious MEMBER previous)
    Q_PROPERTY(bool CanSeek MEMBER seek)
    Q_PROPERTY(QVariantMap Metadata MEMBER metadata)
    Q_PROPERTY(qlonglong Position MEMBER position)
    Q_PROPERTY(double Rate MEMBER rate)
public:
    QString status = QStringLiteral("Playing");
    bool control = true, canPlay = true, canPause = true, next = false, previous = false, seek = true;
    QVariantMap metadata;
    qlonglong position = 1000000;
    double rate = 1;
    int actions = 0;
public Q_SLOTS:
    void Play() { ++actions; }
    void Pause() { ++actions; }
    void Next() { ++actions; }
    void Previous() { ++actions; }
    void Seek(qlonglong offset) { position += offset; ++actions; }
};

static QDBusMessage call(const QDBusConnection &bus, const QString &service, const QString &path,
                         const QString &iface, const QString &method, const QVariantList &args = {}) {
    auto message = QDBusMessage::createMethodCall(service,path,iface,method);
    message.setArguments(args);
    QDBusPendingCallWatcher pending(bus.asyncCall(message));
    QEventLoop loop;
    QObject::connect(&pending,&QDBusPendingCallWatcher::finished,&loop,&QEventLoop::quit);
    QTimer::singleShot(3000,&loop,&QEventLoop::quit);
    if (!pending.isFinished()) loop.exec();
    return pending.reply();
}

class ActivityProviderTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void mprisLifecycle() {
        const auto bus = QDBusConnection::sessionBus();
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-media"));
        const QString name = QStringLiteral("org.mpris.MediaPlayer2.AmbientTest");
        const QString path = QStringLiteral("/org/mpris/MediaPlayer2");
        FakePlayer player;
        QVERIFY(peer.registerObject(path,&player,QDBusConnection::ExportAllProperties|QDBusConnection::ExportAllSlots));
        QVERIFY(peer.registerService(name));
        MprisActivityProvider provider(bus);
        QTRY_COMPARE(provider.activities().size(),1);
        auto row = provider.activities().first().toMap();
        const auto generation = row.value(QStringLiteral("generation")).toInt();
        QVERIFY(!row.contains(QStringLiteral("title")));
        QVERIFY(!row.contains(QStringLiteral("durationUs")));
        QVERIFY(!row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("next")).toBool());
        provider.invoke(name,generation,QStringLiteral("next"));
        QTest::qWait(30); QCOMPARE(player.actions,0);
        provider.invoke(name,generation,QStringLiteral("pause"));
        QTRY_COMPARE(player.actions,1);
        auto update = [&](const QVariantMap &properties) {
            auto signal=QDBusMessage::createSignal(path,QStringLiteral("org.freedesktop.DBus.Properties"),QStringLiteral("PropertiesChanged"));
            signal.setArguments({QStringLiteral("org.mpris.MediaPlayer2.Player"),properties,QStringList{}});
            QVERIFY(peer.send(signal));
        };
        player.metadata={{QStringLiteral("xesam:title"),QStringLiteral("A real track")},
            {QStringLiteral("xesam:artist"),QStringList{QStringLiteral("Artist")}},
            {QStringLiteral("mpris:length"),qlonglong(90000000)}};
        update({{QStringLiteral("Metadata"),player.metadata}});
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("artist")).toString(),QStringLiteral("Artist"));
        QCOMPARE(provider.activities().first().toMap().value(QStringLiteral("durationUs")).toLongLong(),qint64(90000000));
        QTest::qWait(30);
        player.status=QStringLiteral("Paused");
        update({{QStringLiteral("PlaybackStatus"),player.status}});
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("state")).toString(),QStringLiteral("paused"));
        row=provider.activities().first().toMap();
        QVERIFY(row.value(QStringLiteral("positionUs")).toLongLong()>1000000);
        QTest::qWait(35);
        QCOMPARE(provider.activities().first().toMap().value(QStringLiteral("positionUs")),row.value(QStringLiteral("positionUs")));
        player.canPlay=false;
        update({{QStringLiteral("CanPlay"),false}});
        QTRY_VERIFY(provider.activities().isEmpty());
        player.canPlay=true;
        update({{QStringLiteral("CanPlay"),true}});
        QTRY_COMPARE(provider.activities().size(),1);
        QVERIFY(peer.unregisterService(name));
        QTRY_VERIFY(provider.activities().isEmpty());
        QVERIFY(peer.registerService(name));
        QTRY_COMPARE(provider.activities().size(),1);
        QVERIFY(provider.activities().first().toMap().value(QStringLiteral("generation")).toInt()!=generation);
        provider.invoke(name,generation,QStringLiteral("play"));
        QTest::qWait(35); QCOMPARE(player.actions,1);
        const auto nextGeneration=provider.activities().first().toMap().value(QStringLiteral("generation")).toInt();
        provider.invoke(name,nextGeneration,QStringLiteral("seek"));
        QTRY_COMPARE(player.actions,2); QCOMPARE(player.position,qlonglong(11000000));
        auto seeked=QDBusMessage::createSignal(path,QStringLiteral("org.mpris.MediaPlayer2.Player"),QStringLiteral("Seeked"));
        seeked.setArguments({qlonglong(11000000)}); QVERIFY(peer.send(seeked));
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("positionUs")).toLongLong(),qint64(11000000));
        peer.unregisterService(name); peer.unregisterObject(path);
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-media"));
    }

    void filesystemEvents() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        QFile baseline(dir.filePath(QStringLiteral("existing"))); QVERIFY(baseline.open(QIODevice::WriteOnly)); baseline.close();
        IncomingFileProvider provider(dir.path(),nullptr,60,180);
        QVERIFY(provider.valid()); QVERIFY(provider.activities().isEmpty());
        QFile file(dir.filePath(QStringLiteral("random.part"))); QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write("abc"),3); file.flush();
        QTRY_COMPARE(provider.activities().size(),1);
        auto row=provider.activities().first().toMap(); const auto id=row.value(QStringLiteral("id"));
        QVERIFY(!row.contains(QStringLiteral("progress"))); QVERIFY(!row.contains(QStringLiteral("processedBytes")));
        QCOMPARE(row.value(QStringLiteral("observedSizeBytes")).toLongLong(),qint64(3));
        QVERIFY(!row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("cancel")).toBool());
        QVERIFY(!row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("open")).toBool());
        const auto final=dir.filePath(QStringLiteral("final.data"));
        QVERIFY(QFile::rename(file.fileName(),final));
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("title")).toString(),QStringLiteral("final.data"));
        QCOMPARE(provider.activities().first().toMap().value(QStringLiteral("id")),id);
        QVERIFY(file.resize(16*1024*1024)); file.flush();
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("observedSizeBytes")).toLongLong(),qint64(16*1024*1024));
        QVERIFY(!provider.activities().first().toMap().contains(QStringLiteral("progress")));
        file.close(); QTRY_VERIFY(provider.activities().isEmpty());
        // A later write is a new lifetime, not a retained completed activity.
        QFile again(final); QVERIFY(again.open(QIODevice::WriteOnly|QIODevice::Append)); again.write("d"); again.flush();
        QTRY_COMPARE(provider.activities().size(),1);
        QVERIFY(provider.activities().first().toMap().value(QStringLiteral("id"))!=id);
        QVERIFY(QFile::remove(final)); QTRY_VERIFY(provider.activities().isEmpty()); again.close();
        QTemporaryDir elsewhere;
        QFile atomic(elsewhere.filePath(QStringLiteral("atomic"))); QVERIFY(atomic.open(QIODevice::WriteOnly)); atomic.write("ready"); atomic.close();
        QVERIFY(QFile::rename(atomic.fileName(),dir.filePath(QStringLiteral("atomic"))));
        QTRY_COMPARE(provider.activities().size(),1);
        QVERIFY(!provider.activities().first().toMap().contains(QStringLiteral("progress")));
        QTRY_VERIFY(provider.activities().isEmpty());
    }

    void filesystemMissingDirectory() {
        QTemporaryDir parent;
        const auto child=parent.filePath(QStringLiteral("Downloads"));
        IncomingFileProvider provider(child,nullptr,50,120);
        QVERIFY(!provider.valid());
        QVERIFY(QDir().mkdir(child)); QTRY_VERIFY(provider.valid());
        QVERIFY(QDir().rmdir(child)); QTRY_VERIFY(!provider.valid());
        QVERIFY(QDir().mkdir(child)); QTRY_VERIFY(provider.valid());
    }

    void mergeAndStaleActions() {
        QTemporaryDir dir;
        const auto path=dir.filePath(QStringLiteral("incoming"));
        QFile file(path); QVERIFY(file.open(QIODevice::WriteOnly)); file.write("abc"); file.close();
        ActivityModel model(QDBusConnection::sessionBus(),QString());
        QTest::qWait(20);
        QVariantMap fs{{QStringLiteral("id"),QStringLiteral("incoming:test")},{QStringLiteral("generation"),1},{QStringLiteral("kind"),QStringLiteral("transfer")},{QStringLiteral("state"),QStringLiteral("running")},
            {QStringLiteral("destinationUrl"),QUrl::fromLocalFile(path).toString()},{QStringLiteral("fileIdentity"),Ambient::fileIdentity(path)},
            {QStringLiteral("observedSizeBytes"),3},{QStringLiteral("evidence"),QStringLiteral("filesystem")},{QStringLiteral("capabilities"),QVariantMap{{QStringLiteral("showInFiles"),true}}}};
        model.reconcile({}, {}, {fs});
        const auto before=model.activities().first().toMap();
        QVERIFY(model.destinationForReveal(before.value(QStringLiteral("id")).toString(),before.value(QStringLiteral("generation")).toInt()).isLocalFile());
        QVariantMap job{{QStringLiteral("id"),QStringLiteral("job:77")},{QStringLiteral("generation"),1},{QStringLiteral("kind"),QStringLiteral("transfer")},{QStringLiteral("state"),QStringLiteral("running")},
            {QStringLiteral("destinationUrl"),QUrl::fromLocalFile(path).toString()},{QStringLiteral("progress"),0.3},{QStringLiteral("capabilities"),QVariantMap{{QStringLiteral("cancel"),true}}}};
        model.reconcile({job},{},{fs});
        QCOMPARE(model.activities().size(),1);
        const auto merged=model.activities().first().toMap();
        QCOMPARE(merged.value(QStringLiteral("id")),before.value(QStringLiteral("id")));
        QVERIFY(merged.value(QStringLiteral("generation"))!=before.value(QStringLiteral("generation")));
        QCOMPARE(merged.value(QStringLiteral("progress")).toDouble(),0.3);
        QVERIFY(model.destinationForReveal(before.value(QStringLiteral("id")).toString(),before.value(QStringLiteral("generation")).toInt()).isEmpty());
        model.reconcile({}, {}, {fs}); QVERIFY(model.activities().isEmpty()); // consumed terminal burst
        model.m_consumedFiles.clear();
        job[QStringLiteral("destinationUrl")]=QUrl::fromLocalFile(dir.path()).toString();
        model.reconcile({job},{},{fs}); QCOMPARE(model.activities().size(),2); // directory is not exact file identity
        QVERIFY(QFile::remove(path));
        model.reconcile({}, {}, {fs}); QVERIFY(model.activities().isEmpty());
    }

    void sharedDesktopJobLifecycle() {
        const auto model=NotificationManager::JobsModel::createJobsModel();
        QVERIFY(model->init()); QVERIFY(model->isValid());
        DesktopJobProvider provider;
        QProcess producer;
        producer.start(QCoreApplication::applicationFilePath(),{QStringLiteral("--job-producer")});
        QVERIFY(producer.waitForStarted());
        QTRY_COMPARE_WITH_TIMEOUT(provider.activities().size(),1,5000);
        auto row=provider.activities().first().toMap();
        QVERIFY(!row.contains(QStringLiteral("progress")));
        const auto id=row.value(QStringLiteral("id")).toString();
        const auto generation=row.value(QStringLiteral("generation")).toInt();
        QVERIFY(row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("cancel")).toBool());
        producer.write("progress\n");
        QTRY_VERIFY(provider.activities().first().toMap().contains(QStringLiteral("progress")));
        row=provider.activities().first().toMap();
        QCOMPARE(row.value(QStringLiteral("progress")).toDouble(),0.25);
        QCOMPARE(row.value(QStringLiteral("processedBytes")).toULongLong(),qulonglong(25));
        provider.invoke(id,generation+1,QStringLiteral("cancel"));
        QTest::qWait(25); QCOMPARE(provider.activities().size(),1);
        provider.invoke(id,generation,QStringLiteral("suspend"));
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("state")).toString(),QStringLiteral("suspended"));
        provider.invoke(id,generation,QStringLiteral("resume"));
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("state")).toString(),QStringLiteral("running"));
        provider.invoke(id,generation,QStringLiteral("cancel"));
        QTRY_VERIFY(provider.activities().isEmpty());
        producer.terminate(); QVERIFY(producer.waitForFinished());
        producer.start(QCoreApplication::applicationFilePath(),{QStringLiteral("--job-producer")});
        QVERIFY(producer.waitForStarted()); QTRY_COMPARE(provider.activities().size(),1);
        producer.kill(); QVERIFY(producer.waitForFinished());
        QTRY_VERIFY_WITH_TIMEOUT(provider.activities().isEmpty(),5000);
    }

    void tetteBridgeLifecycle() {
        QTemporaryDir dir;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QVERIFY(QDir(dir.path()).mkdir(QStringLiteral("target")));
        QFile source(dir.filePath(QStringLiteral("source"))); QVERIFY(source.open(QIODevice::WriteOnly));
        QVERIFY(source.resize(64*1024*1024)); source.close();
        FileBrowser files;
        TransferActivityBridge bridge(&files);
        auto peer=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-tette"));
        QVERIFY(peer.registerObject(QStringLiteral("/Activities"),&bridge,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        TetteTransferProvider provider(QDBusConnection::sessionBus());
        QTest::qWait(50);
        files.navigate(dir.path()); QTRY_VERIFY(!files.busy());
        files.copyDropped({source.fileName()},dir.filePath(QStringLiteral("target")));
        QVERIFY(files.working()); QVERIFY(!files.activitySnapshot().isEmpty());
        QVERIFY(files.m_operationJob->suspend());
        QTRY_COMPARE(provider.activities().size(),1);
        const auto liveRow=provider.activities().first().toMap();
        QCOMPARE(liveRow.value(QStringLiteral("state")).toString(),QStringLiteral("suspended"));
        const auto sourceId=files.activitySnapshot().first().toMap().value(QStringLiteral("id")).toString();
        // Source UUID is checked in the owner, even if a stale cancellation arrives.
        files.cancelActivity(QStringLiteral("stale")); QVERIFY(files.working());
        provider.invoke(liveRow.value(QStringLiteral("id")).toString(),
                        liveRow.value(QStringLiteral("generation")).toInt()+1,QStringLiteral("cancel"));
        QTest::qWait(25); QVERIFY(files.working());
        files.navigate(dir.filePath(QStringLiteral("target"))); // browsing doesn't own the operation lifetime
        QVERIFY(files.working());
        const auto prior=provider.activities().first().toMap();
        QVERIFY(peer.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QTRY_VERIFY(provider.activities().isEmpty()); QVERIFY(files.working());
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        QTRY_COMPARE(provider.activities().size(),1);
        provider.invoke(prior.value(QStringLiteral("id")).toString(),prior.value(QStringLiteral("generation")).toInt(),QStringLiteral("cancel"));
        QTest::qWait(25); QVERIFY(files.working());
        const auto current=provider.activities().first().toMap();
        provider.invoke(current.value(QStringLiteral("id")).toString(),current.value(QStringLiteral("generation")).toInt(),QStringLiteral("cancel"));
        QTRY_VERIFY(!files.working()); QTRY_VERIFY(provider.activities().isEmpty());
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
        peer.unregisterObject(QStringLiteral("/Activities"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-tette"));
    }
};

class JobProducer : public QObject {
    Q_OBJECT
public:
    QDBusConnection bus=QDBusConnection::sessionBus();
    QString path;
    void send(const QString &method,const QVariantList &args={}) {
        auto msg=QDBusMessage::createMethodCall(QStringLiteral("org.kde.JobViewServer"),path,QStringLiteral("org.kde.JobViewV2"),method);
        msg.setArguments(args); bus.asyncCall(msg);
    }
public Q_SLOTS:
    void cancel() { send(QStringLiteral("terminate"),{QStringLiteral("Canceled")}); }
    void suspend() { send(QStringLiteral("setSuspended"),{true}); }
    void resume() { send(QStringLiteral("setSuspended"),{false}); }
};
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    if (app.arguments().contains(QStringLiteral("--job-producer"))) {
        JobProducer producer;
        auto reply=call(producer.bus,QStringLiteral("org.kde.JobViewServer"),QStringLiteral("/JobViewServer"),
            QStringLiteral("org.kde.JobViewServer"),QStringLiteral("requestView"),{QStringLiteral("Ambient Test"),QStringLiteral("folder"),3});
        if (reply.type()==QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) return 2;
        producer.path=qdbus_cast<QDBusObjectPath>(reply.arguments().first()).path();
        for (const auto &pair : {qMakePair("cancelRequested",SLOT(cancel())),qMakePair("suspendRequested",SLOT(suspend())),qMakePair("resumeRequested",SLOT(resume()))})
            producer.bus.connect(QStringLiteral("org.kde.JobViewServer"),producer.path,QStringLiteral("org.kde.JobViewV2"),QString::fromLatin1(pair.first),&producer,pair.second);
        QSocketNotifier input(STDIN_FILENO,QSocketNotifier::Read);
        QObject::connect(&input,&QSocketNotifier::activated,&app,[&] {
            char buffer[128]; if (::read(STDIN_FILENO,buffer,sizeof(buffer))<=0) return;
            producer.send(QStringLiteral("setTotalAmount"),{qulonglong(100),QStringLiteral("bytes")});
            producer.send(QStringLiteral("setProcessedAmount"),{qulonglong(25),QStringLiteral("bytes")});
            producer.send(QStringLiteral("setPercent"),{uint(25)});
        });
        return app.exec();
    }
    ActivityProviderTest test; return QTest::qExec(&test,argc,argv);
}
#include "ActivityProviderTest.moc"
