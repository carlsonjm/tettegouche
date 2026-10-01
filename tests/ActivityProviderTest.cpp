#include "ActivityModel.h"
#include "ActivityUtils.h"
#include "TransferActivityBridge.h"
#include "FileBrowser.h"
#include <notification.h>
#include <server.h>
#include <QTest>
#include <QGuiApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <QDBusVirtualObject>
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
    void SetPosition(const QDBusObjectPath &track, qlonglong to) { positionedTrack = track.path(); position = to; ++actions; }
public:
    QString positionedTrack;
};

class FakePlayerRoot : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanRaise MEMBER canRaise)
    Q_PROPERTY(QString Identity MEMBER identity)
public:
    explicit FakePlayerRoot(QObject *parent) : QDBusAbstractAdaptor(parent) {}
    bool canRaise = true;
    QString identity = QStringLiteral("Stand-in player");
    int raises = 0;
public Q_SLOTS:
    void Raise() { ++raises; }
};

// The desktop's notification server, as FinishNotices meets it.
class FakeNotifications : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
public:
    struct Notice { QString application, summary, body; QStringList actions; QVariantMap hints; };
    QList<Notice> notices;
    QList<uint> closed;
public Q_SLOTS:
    void CloseNotification(uint id) { closed.append(id); }
    uint Notify(const QString &application, uint, const QString &, const QString &summary, const QString &body,
                const QStringList &actions, const QVariantMap &hints, int) {
        notices.append({application, summary, body, actions, hints});
        return uint(notices.size());
    }
Q_SIGNALS:
    void ActionInvoked(uint id, const QString &action);
    void NotificationClosed(uint id, uint reason);
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

// Plasma's tray, the portal's item on it and the item's menu, as the screen
// share provider meets them.
struct TipPixmap { int width = 0, height = 0; QByteArray data; };
Q_DECLARE_METATYPE(TipPixmap)
QDBusArgument &operator<<(QDBusArgument &a, const TipPixmap &p) { a.beginStructure(); a << p.width << p.height << p.data; a.endStructure(); return a; }
const QDBusArgument &operator>>(const QDBusArgument &a, TipPixmap &p) { a.beginStructure(); a >> p.width >> p.height >> p.data; a.endStructure(); return a; }
struct Tip { QString icon; QList<TipPixmap> pixmaps; QString title, subtitle; };
Q_DECLARE_METATYPE(Tip)
QDBusArgument &operator<<(QDBusArgument &a, const Tip &t) { a.beginStructure(); a << t.icon << t.pixmaps << t.title << t.subtitle; a.endStructure(); return a; }
const QDBusArgument &operator>>(const QDBusArgument &a, Tip &t) { a.beginStructure(); a >> t.icon >> t.pixmaps >> t.title >> t.subtitle; a.endStructure(); return a; }
struct MenuNode { int id = 0; QVariantMap properties; QList<MenuNode> children; };
Q_DECLARE_METATYPE(MenuNode)
QDBusArgument &operator<<(QDBusArgument &a, const MenuNode &n) {
    a.beginStructure(); a << n.id << n.properties;
    a.beginArray(QMetaType::fromType<QDBusVariant>());
    for (const auto &child : n.children) a << QDBusVariant(QVariant::fromValue(child));
    a.endArray(); a.endStructure(); return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a, MenuNode &n) { a.beginStructure(); a >> n.id >> n.properties; a.beginArray(); while (!a.atEnd()) { QDBusVariant v; a >> v; } a.endArray(); a.endStructure(); return a; }
class FakeTray : public QDBusVirtualObject {
public:
    QString id = QStringLiteral("xdg-desktop-portal-kde"), status = QStringLiteral("Active");
    QStringList items;
    QList<int> clicked;
    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        const auto member = message.member();
        if (message.path() == QLatin1String("/StatusNotifierWatcher") && member == QLatin1String("Get")) {
            connection.send(message.createReply(QVariant::fromValue(QDBusVariant(items))));
        } else if (message.path() == QLatin1String("/StatusNotifierItem") && member == QLatin1String("GetAll")) {
            const Tip tip{QStringLiteral("monitor"), {}, QStringLiteral("Screen casting"), QStringLiteral("Sharing contents to Zen Browser")};
            connection.send(message.createReply(QVariant::fromValue(QVariantMap{{QStringLiteral("Id"), id}, {QStringLiteral("Status"), status},
                {QStringLiteral("Title"), QStringLiteral("Screen casting")}, {QStringLiteral("IconName"), QStringLiteral("zen-browser")},
                {QStringLiteral("Menu"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/MenuBar")))},
                {QStringLiteral("ToolTip"), QVariant::fromValue(tip)}})));
        } else if (message.path() == QLatin1String("/MenuBar") && member == QLatin1String("GetLayout")) {
            const MenuNode root{0, {}, {MenuNode{7, {{QStringLiteral("label"), QStringLiteral("End")}}, {}}}};
            connection.send(message.createReply({uint(1), QVariant::fromValue(root)}));
        } else if (message.path() == QLatin1String("/MenuBar") && member == QLatin1String("Event")) {
            clicked.append(message.arguments().value(0).toInt());
            connection.send(message.createReply());
        } else {
            return false;
        }
        return true;
    }
};

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

    void mprisArtRaiseAndSeek() {
        const auto bus = QDBusConnection::sessionBus();
        auto peer = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-art-media"));
        const QString name = QStringLiteral("org.mpris.MediaPlayer2.AmbientArtTest");
        const QString path = QStringLiteral("/org/mpris/MediaPlayer2");
        FakePlayer player;
        auto *root = new FakePlayerRoot(&player);
        player.position = 40000000;
        player.metadata = {{QStringLiteral("xesam:title"), QStringLiteral("Holocene")},
            {QStringLiteral("xesam:album"), QStringLiteral("Bon Iver")},
            {QStringLiteral("mpris:artUrl"), QStringLiteral("file:///tmp/cover.png")},
            {QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/mpris/MediaPlayer2/Track/7")))},
            {QStringLiteral("mpris:length"), qlonglong(90000000)}};
        QVERIFY(peer.registerObject(path, &player, QDBusConnection::ExportAllProperties
            | QDBusConnection::ExportAllSlots | QDBusConnection::ExportAdaptors));
        QVERIFY(peer.registerService(name));
        MprisActivityProvider provider(bus);
        QTRY_COMPARE(provider.activities().size(), 1);
        QTRY_VERIFY(provider.activities().first().toMap().value(QStringLiteral("capabilities")).toMap()
            .value(QStringLiteral("raise")).toBool());
        auto row = provider.activities().first().toMap();
        const auto generation = row.value(QStringLiteral("generation")).toInt();
        QCOMPARE(row.value(QStringLiteral("artUrl")).toString(), QStringLiteral("file:///tmp/cover.png"));
        QCOMPARE(row.value(QStringLiteral("album")).toString(), QStringLiteral("Bon Iver"));
        const auto capabilities = row.value(QStringLiteral("capabilities")).toMap();
        QVERIFY(capabilities.value(QStringLiteral("seekBack")).toBool());
        QVERIFY(capabilities.value(QStringLiteral("seekTo")).toBool());

        provider.invoke(name, generation, QStringLiteral("raise"));
        QTRY_COMPARE(root->raises, 1);
        provider.invoke(name, generation, QStringLiteral("seekBack"));
        QTRY_COMPARE(player.position, qlonglong(30000000));
        // A jump names the track, and is held inside the track's length.
        provider.invoke(name, generation, QStringLiteral("seekTo"), qlonglong(60000000));
        QTRY_COMPARE(player.position, qlonglong(60000000));
        QCOMPARE(player.positionedTrack, QStringLiteral("/org/mpris/MediaPlayer2/Track/7"));
        provider.invoke(name, generation, QStringLiteral("seekTo"), qlonglong(500000000));
        QTRY_COMPARE(player.position, qlonglong(89999999));
        const int before = player.actions;
        provider.invoke(name, generation, QStringLiteral("seekTo"), QStringLiteral("not a time"));
        QTest::qWait(40);
        QCOMPARE(player.actions, before);

        // Artwork from any other kind of address is left out.
        player.metadata[QStringLiteral("mpris:artUrl")] = QStringLiteral("smb://server/cover.png");
        auto signal = QDBusMessage::createSignal(path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
        signal.setArguments({QStringLiteral("org.mpris.MediaPlayer2.Player"),
            QVariantMap{{QStringLiteral("Metadata"), player.metadata}}, QStringList{}});
        QVERIFY(peer.send(signal));
        QTRY_VERIFY(!provider.activities().first().toMap().contains(QStringLiteral("artUrl")));

        // A player that cannot be raised offers no way to bring it forward.
        root->canRaise = false;
        auto rootSignal = QDBusMessage::createSignal(path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
        rootSignal.setArguments({QStringLiteral("org.mpris.MediaPlayer2"),
            QVariantMap{{QStringLiteral("CanRaise"), false}}, QStringList{}});
        QVERIFY(peer.send(rootSignal));
        QTRY_VERIFY(!provider.activities().first().toMap().value(QStringLiteral("capabilities")).toMap()
            .value(QStringLiteral("raise")).toBool());
        provider.invoke(name, provider.activities().first().toMap().value(QStringLiteral("generation")).toInt(),
            QStringLiteral("raise"));
        QTest::qWait(40);
        QCOMPARE(root->raises, 1);
        peer.unregisterService(name); peer.unregisterObject(path);
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-art-media"));
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

    // Set aside: media stays away until it starts playing again; a transfer
    // until its source ends. An end waiting out its minute is filed now, and a
    // transfer set aside is filed as soon as it ends.
    // Paused media stays its few minutes, then leaves until it plays again;
    // paused again, its minutes start over.
    void pausedMediaRests() {
        QTemporaryDir downloads;
        ActivityModel model(QDBusConnection::sessionBus(),downloads.path());
        model.m_pausedLingerUs=300000;
        QTest::qWait(20); // the model's own first look at its sources
        QVariantMap player{{QStringLiteral("id"),QStringLiteral("org.mpris.MediaPlayer2.phone")},{QStringLiteral("generation"),1},
            {QStringLiteral("kind"),QStringLiteral("media")},{QStringLiteral("state"),QStringLiteral("paused")},{QStringLiteral("title"),QStringLiteral("Song")}};
        model.reconcile({},{player},{});
        QCOMPARE(model.activities().size(),1);
        QTest::qWait(150);
        QCOMPARE(model.activities().size(),1);
        QTRY_VERIFY_WITH_TIMEOUT(model.activities().isEmpty(),2000);
        model.reconcile({},{player},{});
        QVERIFY(model.activities().isEmpty());
        player[QStringLiteral("state")]=QStringLiteral("playing");
        model.reconcile({},{player},{});
        QCOMPARE(model.activities().size(),1);
        QTest::qWait(400);
        model.reconcile({},{player},{});
        QCOMPARE(model.activities().size(),1);
        player[QStringLiteral("state")]=QStringLiteral("paused");
        model.reconcile({},{player},{});
        QCOMPARE(model.activities().size(),1);
        QTRY_VERIFY_WITH_TIMEOUT(model.activities().isEmpty(),2000);
    }

    void setAsideLasts() {
        QTemporaryDir downloads;
        auto fakes=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-notifications-aside"));
        FakeNotifications notifications;
        QVERIFY(fakes.registerObject(QStringLiteral("/org/freedesktop/Notifications"),&notifications,
                                     QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(fakes.registerService(QStringLiteral("org.freedesktop.Notifications")));
        {
            ActivityModel model(QDBusConnection::sessionBus(),downloads.path());
            QTest::qWait(20);
            QVariantMap player{{QStringLiteral("id"),QStringLiteral("org.mpris.MediaPlayer2.phone")},{QStringLiteral("generation"),1},
                {QStringLiteral("kind"),QStringLiteral("media")},{QStringLiteral("state"),QStringLiteral("paused")},{QStringLiteral("title"),QStringLiteral("Song")}};
            const QVariantMap copy{{QStringLiteral("id"),QStringLiteral("tette:1")},{QStringLiteral("generation"),1},
                {QStringLiteral("kind"),QStringLiteral("transfer")},{QStringLiteral("state"),QStringLiteral("running")},{QStringLiteral("title"),QStringLiteral("Photos")}};
            const auto titled=[&model](const QString &title) {
                for (const auto &row : model.activities()) if (row.toMap().value(QStringLiteral("title"))==title) return row.toMap();
                return QVariantMap{};
            };
            const auto setAside=[&model](const QVariantMap &row) {
                model.invoke(row.value(QStringLiteral("id")).toString(),row.value(QStringLiteral("generation")).toInt(),QStringLiteral("setAside"));
            };
            model.reconcile({copy},{player},{});
            QCOMPARE(model.activities().size(),2);
            // Paused media set aside stays away while paused, and returns as it plays.
            setAside(titled(QStringLiteral("Song")));
            QVERIFY(titled(QStringLiteral("Song")).isEmpty());
            model.reconcile({copy},{player},{});
            QVERIFY(titled(QStringLiteral("Song")).isEmpty());
            player[QStringLiteral("state")]=QStringLiteral("playing");
            model.reconcile({copy},{player},{});
            QVERIFY(!titled(QStringLiteral("Song")).isEmpty());
            // Set aside while playing, it returns only when it plays again.
            setAside(titled(QStringLiteral("Song")));
            model.reconcile({copy},{player},{});
            QVERIFY(titled(QStringLiteral("Song")).isEmpty());
            player[QStringLiteral("state")]=QStringLiteral("paused");
            model.reconcile({copy},{player},{});
            QVERIFY(titled(QStringLiteral("Song")).isEmpty());
            player[QStringLiteral("state")]=QStringLiteral("playing");
            model.reconcile({copy},{player},{});
            QVERIFY(!titled(QStringLiteral("Song")).isEmpty());
            // A transfer stays away until its source ends; one after it shows.
            setAside(titled(QStringLiteral("Photos")));
            QVERIFY(titled(QStringLiteral("Photos")).isEmpty());
            model.reconcile({copy},{player},{});
            QVERIFY(titled(QStringLiteral("Photos")).isEmpty());
            model.reconcile({},{player},{});
            model.reconcile({copy},{player},{});
            QVERIFY(!titled(QStringLiteral("Photos")).isEmpty());
            // An end waiting out its minute, set aside, is filed now.
            QFile photo(QDir(downloads.path()).filePath(QStringLiteral("photo.png"))); QVERIFY(photo.open(QIODevice::WriteOnly)); photo.write("x"); photo.close();
            model.m_notices.report({{QStringLiteral("id"),QStringLiteral("job:5")},{QStringLiteral("generation"),1},{QStringLiteral("application"),QStringLiteral("Ambient Test")},
                {QStringLiteral("error"),0},{QStringLiteral("destinationUrl"),QUrl::fromLocalFile(photo.fileName()).toString()}});
            model.reconcile(model.m_notices.activities(),{},{});
            QVERIFY(!titled(QStringLiteral("photo.png")).isEmpty());
            setAside(titled(QStringLiteral("photo.png")));
            QTRY_COMPARE(notifications.notices.size(),1);
            QCOMPARE(notifications.notices.first().summary,QStringLiteral("photo.png"));
            QVERIFY(model.m_notices.activities().isEmpty());
            // A running job set aside is filed the moment it ends, with no minute.
            const QVariantMap job{{QStringLiteral("id"),QStringLiteral("job:6")},{QStringLiteral("generation"),1},{QStringLiteral("kind"),QStringLiteral("transfer")},
                {QStringLiteral("state"),QStringLiteral("running")},{QStringLiteral("title"),QStringLiteral("Video")}};
            model.reconcile({job},{},{});
            setAside(titled(QStringLiteral("Video")));
            QVERIFY(titled(QStringLiteral("Video")).isEmpty());
            Q_EMIT model.m_jobs.finished({{QStringLiteral("id"),QStringLiteral("job:6")},{QStringLiteral("generation"),1},{QStringLiteral("application"),QStringLiteral("Ambient Test")},
                {QStringLiteral("error"),0},{QStringLiteral("destinationUrl"),QUrl::fromLocalFile(photo.fileName()).toString()}});
            QTRY_COMPARE(notifications.notices.size(),2);
            QVERIFY(model.m_notices.activities().isEmpty());
        }
        fakes.unregisterService(QStringLiteral("org.freedesktop.Notifications"));
        fakes.unregisterObject(QStringLiteral("/org/freedesktop/Notifications"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-notifications-aside"));
    }

    // Where nothing holds the job service, Ambient holds it, and each job that
    // ends is routed: a file that arrived in Downloads, or a failure, stays in
    // Ambient for its minute, then is filed as a transfer notice; one used
    // there is filed at once; a cancelled job or one writing elsewhere ends
    // quietly.
    void heldJobServiceRoutesEnds() {
        QTemporaryDir downloads, elsewhere;
        auto fakes=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-notifications"));
        FakeNotifications notifications;
        QVERIFY(fakes.registerObject(QStringLiteral("/org/freedesktop/Notifications"),&notifications,
                                     QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(fakes.registerService(QStringLiteral("org.freedesktop.Notifications")));
        {
            DesktopJobProvider provider;
            constexpr int Linger=400;
            FinishNotices notices(QDBusConnection::sessionBus(),downloads.path(),nullptr,Linger);
            connect(&provider,&DesktopJobProvider::finished,&notices,&FinishNotices::report);
            QSignalSpy reveals(&notices,&FinishNotices::revealRequested);
            QTRY_VERIFY(provider.holding());
            const auto end=[&](const QByteArray &command) {
                QProcess producer;
                producer.start(QCoreApplication::applicationFilePath(),{QStringLiteral("--job-producer-v2")});
                QVERIFY(producer.waitForStarted());
                QTRY_COMPARE_WITH_TIMEOUT(provider.activities().size(),1,5000);
                producer.write(command+'\n');
                QTRY_VERIFY_WITH_TIMEOUT(provider.activities().isEmpty(),5000);
                producer.kill(); producer.waitForFinished();
            };
            const auto file=[](const QTemporaryDir &dir,const QString &name) {
                QFile f(dir.filePath(name)); f.open(QIODevice::WriteOnly); f.write("picture"); return f.fileName();
            };
            const auto category=[&](int i) { return notifications.notices.at(i).hints.value(QStringLiteral("category")).toString(); };
            // Received into Downloads, as KDE Connect reports it: in Ambient,
            // in the job's place, with Show in Files, and filed after its minute.
            const auto photo=file(downloads,QStringLiteral("photo.png"));
            end("receive "+photo.toUtf8()); if (QTest::currentTestFailed()) return;
            QTRY_COMPARE(notices.activities().size(),1);
            auto row=notices.activities().first().toMap();
            QVERIFY(row.value(QStringLiteral("id")).toString().startsWith(QStringLiteral("job:")));
            QCOMPARE(row.value(QStringLiteral("state")).toString(),QStringLiteral("finished"));
            QCOMPARE(row.value(QStringLiteral("title")).toString(),QStringLiteral("photo.png"));
            QCOMPARE(row.value(QStringLiteral("description")).toString(),QStringLiteral("Arrived in Downloads"));
            QVERIFY(row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("showInFiles")).toBool());
            QCOMPARE(QUrl(row.value(QStringLiteral("destinationUrl")).toString()).toLocalFile(),photo);
            QVERIFY(notifications.notices.isEmpty());
            QTRY_VERIFY(notices.activities().isEmpty());
            QTRY_COMPARE(notifications.notices.size(),1);
            QCOMPARE(notifications.notices.first().application,QStringLiteral("Ambient Test"));
            QCOMPARE(notifications.notices.first().summary,QStringLiteral("photo.png"));
            QCOMPARE(notifications.notices.first().body,QStringLiteral("Arrived in Downloads"));
            QCOMPARE(category(0),QStringLiteral("transfer.complete"));
            QVERIFY(notifications.notices.first().actions.contains(QStringLiteral("Show in Files")));
            QTest::qWait(50);
            Q_EMIT notifications.ActionInvoked(1,QStringLiteral("show"));
            QTRY_COMPARE(reveals.size(),1);
            QCOMPARE(reveals.first().first().toString(),photo);
            Q_EMIT notifications.NotificationClosed(1,2);
            // A producer naming the file itself; used in Ambient, it is filed at once.
            end("arrive "+file(downloads,QStringLiteral("song.ogg")).toUtf8()); if (QTest::currentTestFailed()) return;
            QTRY_COMPARE(notices.activities().size(),1);
            notices.used(notices.activities().first().toMap().value(QStringLiteral("id")).toString());
            QVERIFY(notices.activities().isEmpty());
            QTRY_COMPARE(notifications.notices.size(),2);
            QCOMPARE(notifications.notices.last().summary,QStringLiteral("song.ogg"));
            // Written elsewhere, or cancelled: quiet.
            end("arrive "+file(elsewhere,QStringLiteral("copy.png")).toUtf8()); if (QTest::currentTestFailed()) return;
            end("receive "+file(elsewhere,QStringLiteral("other.png")).toUtf8()); if (QTest::currentTestFailed()) return;
            end("cancel"); if (QTest::currentTestFailed()) return;
            QVERIFY(notices.activities().isEmpty());
            QTest::qWait(Linger+200);
            QCOMPARE(notifications.notices.size(),2);
            // Failed: its minute in Ambient saying why, then filed, with nothing to show.
            end("fail"); if (QTest::currentTestFailed()) return;
            QTRY_COMPARE(notices.activities().size(),1);
            row=notices.activities().first().toMap();
            QCOMPARE(row.value(QStringLiteral("state")).toString(),QStringLiteral("failed"));
            QCOMPARE(row.value(QStringLiteral("description")).toString(),QStringLiteral("The phone went out of reach"));
            QVERIFY(!row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("showInFiles")).toBool());
            QTRY_COMPARE(notifications.notices.size(),3);
            QCOMPARE(notifications.notices.last().summary,QStringLiteral("Transfer failed"));
            QCOMPARE(category(2),QStringLiteral("transfer.error"));
            QVERIFY(!notifications.notices.last().actions.contains(QStringLiteral("Show in Files")));
            Q_EMIT notifications.ActionInvoked(3,QStringLiteral("show"));
            QTest::qWait(50);
            QCOMPARE(reveals.size(),1);
        }
        fakes.unregisterService(QStringLiteral("org.freedesktop.Notifications"));
        fakes.unregisterObject(QStringLiteral("/org/freedesktop/Notifications"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-notifications"));
    }

    // A drive plugged in and not mounted waits its minute in Ambient with
    // Open. Tapped, it leaves and Files is asked to open it; ignored or set
    // aside, it is filed quietly with Open in Files; mounted elsewhere, it
    // leaves quietly; unplugged, its filed notice closes.
    void driveWaitsOpensAndFiles() {
        auto fakes=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-drive-notifications"));
        FakeNotifications notifications;
        QVERIFY(fakes.registerObject(QStringLiteral("/org/freedesktop/Notifications"),&notifications,
                                     QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(fakes.registerService(QStringLiteral("org.freedesktop.Notifications")));
        const DriveActivityProvider::Drive stick{QStringLiteral("/org/freedesktop/UDisks2/block_devices/sdz1"),
            QStringLiteral("STICK"),QStringLiteral("drive-removable-media-usb-pendrive"),qint64(32000000000)};
        const auto id=QStringLiteral("drive:")+stick.udi;
        {
            constexpr int Linger=300;
            DriveActivityProvider drives(QDBusConnection::sessionBus(),nullptr,Linger,false);
            QSignalSpy opens(&drives,&DriveActivityProvider::openRequested);
            drives.plugged(stick);
            QCOMPARE(drives.activities().size(),1);
            const auto row=drives.activities().first().toMap();
            QCOMPARE(row.value(QStringLiteral("id")).toString(),id);
            QCOMPARE(row.value(QStringLiteral("kind")).toString(),QStringLiteral("drive"));
            QCOMPARE(row.value(QStringLiteral("title")).toString(),QStringLiteral("STICK"));
            QCOMPARE(row.value(QStringLiteral("sizeBytes")).toLongLong(),qint64(32000000000));
            QVERIFY(row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("open")).toBool());
            drives.open(id);
            QCOMPARE(opens.size(),1);
            QCOMPARE(opens.first().first().toString(),stick.udi);
            QVERIFY(drives.activities().isEmpty());
            QTest::qWait(Linger+100);
            QVERIFY(notifications.notices.isEmpty());

            drives.plugged(stick);
            QTRY_COMPARE_WITH_TIMEOUT(notifications.notices.size(),1,2000);
            QVERIFY(drives.activities().isEmpty());
            const auto notice=notifications.notices.first();
            QCOMPARE(notice.summary,QStringLiteral("STICK"));
            QCOMPARE(notice.body,QStringLiteral("32.0 GB, plugged in"));
            QCOMPARE(notice.hints.value(QStringLiteral("category")).toString(),QStringLiteral("device.added"));
            QVERIFY(notice.actions.contains(QStringLiteral("open")));
            QVERIFY(notice.actions.contains(QStringLiteral("Open in Files")));
            QTest::qWait(50);
            Q_EMIT notifications.ActionInvoked(1,QStringLiteral("open"));
            QTRY_COMPARE(opens.size(),2);
            // Expired from view, it stays in the history, its action alive.
            Q_EMIT notifications.NotificationClosed(1,1);
            QTest::qWait(50);
            Q_EMIT notifications.ActionInvoked(1,QStringLiteral("default"));
            QTRY_COMPARE(opens.size(),3);
            drives.unplugged(stick.udi);
            QTRY_COMPARE(notifications.closed,QList<uint>{1});

            drives.plugged(stick);
            drives.setAside(id);
            QVERIFY(drives.activities().isEmpty());
            QTRY_COMPARE(notifications.notices.size(),2);
            drives.plugged(stick);
            drives.mounted(stick.udi);
            QVERIFY(drives.activities().isEmpty());
            QTest::qWait(Linger+100);
            QCOMPARE(notifications.notices.size(),2);
            QCOMPARE(opens.size(),3);
        }
        {
            // Through the model, as the panel meets it.
            QTemporaryDir downloads;
            ActivityModel model(QDBusConnection::sessionBus(),downloads.path());
            QSignalSpy opens(&model,&ActivityModel::driveOpenRequested);
            model.m_drives.plugged(stick);
            QTRY_COMPARE(model.activities().size(),1);
            auto row=model.activities().first().toMap();
            model.invoke(row.value(QStringLiteral("id")).toString(),row.value(QStringLiteral("generation")).toInt(),QStringLiteral("open"));
            QCOMPARE(opens.size(),1);
            QCOMPARE(opens.first().first().toString(),stick.udi);
            QTRY_VERIFY(model.activities().isEmpty());
            model.m_drives.plugged(stick);
            QTRY_COMPARE(model.activities().size(),1);
            row=model.activities().first().toMap();
            model.setAside(row.value(QStringLiteral("id")).toString(),row.value(QStringLiteral("generation")).toInt());
            QVERIFY(model.activities().isEmpty());
            QTRY_COMPARE(notifications.notices.size(),3);
        }
        fakes.unregisterService(QStringLiteral("org.freedesktop.Notifications"));
        fakes.unregisterObject(QStringLiteral("/org/freedesktop/Notifications"));
    }

    // In the panel, the notification server runs in the same process as
    // Ambient, so a notice is a call to itself: it must still arrive, and its
    // action must still come back.
    void noticeToItsOwnProcess() {
        QTemporaryDir downloads;
        auto &server=NotificationManager::Server::self();
        QVERIFY(server.init());
        uint id=0; QString summary;
        connect(&server,&NotificationManager::Server::notificationAdded,this,[&](const NotificationManager::Notification &added) {
            id=added.id(); summary=added.summary();
        });
        FinishNotices notices(QDBusConnection::sessionBus(),downloads.path(),nullptr,100);
        QSignalSpy reveals(&notices,&FinishNotices::revealRequested);
        QFile photo(downloads.filePath(QStringLiteral("photo.png"))); QVERIFY(photo.open(QIODevice::WriteOnly)); photo.write("x"); photo.close();
        notices.report({{QStringLiteral("application"),QStringLiteral("Ambient Test")},{QStringLiteral("error"),0},
                        {QStringLiteral("destinationUrl"),QUrl::fromLocalFile(photo.fileName()).toString()}});
        QTRY_VERIFY(id!=0);
        QCOMPARE(summary,QStringLiteral("photo.png"));
        QTest::qWait(50);
        server.invokeAction(id,QStringLiteral("show"),QString(),NotificationManager::Notifications::None);
        QTRY_COMPARE(reveals.size(),1);
        QCOMPARE(reveals.first().first().toString(),photo.fileName());
    }

    void sharedDesktopJobLifecycle() {
        const auto model=NotificationManager::JobsModel::createJobsModel();
        QVERIFY(model->init()); QVERIFY(model->isValid());
        DesktopJobProvider provider;
        // The service already has a holder in this process, as Plasma's
        // Notifications widget would be: Ambient shares it.
        QTest::qWait(50); QVERIFY(!provider.holding());
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

    // A copy in Files that fails is an end: the panel hears it once, with why,
    // and it leaves the running rows; one the person cancels ends quietly.
    void tetteFailureIsAnEnd() {
        QTemporaryDir dir;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QVERIFY(QDir(dir.path()).mkdir(QStringLiteral("locked")));
        const auto locked=dir.filePath(QStringLiteral("locked"));
        QFile source(dir.filePath(QStringLiteral("photo.png"))); QVERIFY(source.open(QIODevice::WriteOnly));
        source.write("picture"); source.close();
        QVERIFY(QFile::setPermissions(locked,QFile::ReadOwner|QFile::ExeOwner));
        FileBrowser files;
        TransferActivityBridge bridge(&files);
        auto peer=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-tette-failure"));
        QVERIFY(peer.registerObject(QStringLiteral("/Activities"),&bridge,QDBusConnection::ExportAllSlots|QDBusConnection::ExportAllSignals));
        QVERIFY(peer.registerService(QStringLiteral("io.github.carlsonjm.Tettegouche")));
        TetteTransferProvider provider(QDBusConnection::sessionBus());
        QSignalSpy ends(&provider,&TetteTransferProvider::finished);
        QTest::qWait(50);
        files.navigate(dir.path()); QTRY_VERIFY(!files.busy());
        files.copyDropped({source.fileName()},locked);
        QTRY_VERIFY_WITH_TIMEOUT(!files.working(),5000);
        QVERIFY(files.failedJustNow());
        QTRY_COMPARE(ends.size(),1);
        const auto job=ends.first().first().toMap();
        QVERIFY(job.value(QStringLiteral("id")).toString().startsWith(QStringLiteral("tette:")));
        QVERIFY(job.value(QStringLiteral("error")).toInt()>1);
        QVERIFY(job.value(QStringLiteral("errorText")).toString().startsWith(QStringLiteral("Stopped")));
        QVERIFY(provider.activities().isEmpty());
        // Heard once, however many snapshots still carry it.
        Q_EMIT files.operationChanged();
        QTest::qWait(100);
        QCOMPARE(ends.size(),1);
        QVERIFY(QFile::setPermissions(locked,QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner));
        peer.unregisterService(QStringLiteral("io.github.carlsonjm.Tettegouche"));
        peer.unregisterObject(QStringLiteral("/Activities"));
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-tette-failure"));
    }

    // A screen shared through Plasma's portal is a row naming who receives
    // it, and Stop clicks the portal item's End; the row leaves when the item
    // goes passive or away. Other tray items are not shares.
    void screenShareFromPortalItem() {
        qDBusRegisterMetaType<TipPixmap>(); qDBusRegisterMetaType<QList<TipPixmap>>();
        qDBusRegisterMetaType<Tip>(); qDBusRegisterMetaType<MenuNode>();
        auto peer=QDBusConnection::connectToBus(QDBusConnection::SessionBus,QStringLiteral("fake-tray"));
        FakeTray tray;
        QVERIFY(peer.registerVirtualObject(QStringLiteral("/"),&tray,QDBusConnection::SubPath));
        QVERIFY(peer.registerService(QStringLiteral("org.kde.StatusNotifierWatcher")));
        const auto item=peer.baseService()+QStringLiteral("/StatusNotifierItem");
        const auto announce=[&](const char *signal) {
            auto message=QDBusMessage::createSignal(QStringLiteral("/StatusNotifierWatcher"),QStringLiteral("org.kde.StatusNotifierWatcher"),QString::fromLatin1(signal));
            message.setArguments({QVariant(item)}); QVERIFY(peer.send(message));
        };
        {
            ScreenShareProvider screen(QDBusConnection::sessionBus());
            QTest::qWait(50);
            QVERIFY(screen.activities().isEmpty());
            tray.items={item};
            announce("StatusNotifierItemRegistered");
            QTRY_COMPARE(screen.activities().size(),1);
            const auto row=screen.activities().first().toMap();
            QCOMPARE(row.value(QStringLiteral("kind")).toString(),QStringLiteral("screen"));
            QCOMPARE(row.value(QStringLiteral("title")).toString(),QStringLiteral("Sharing contents to Zen Browser"));
            QCOMPARE(row.value(QStringLiteral("icon")).toString(),QStringLiteral("zen-browser"));
            QVERIFY(row.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("stop")).toBool());
            screen.invoke(row.value(QStringLiteral("id")).toString(),row.value(QStringLiteral("generation")).toInt()+1,QStringLiteral("stop"));
            QTest::qWait(50); QVERIFY(tray.clicked.isEmpty());
            screen.invoke(row.value(QStringLiteral("id")).toString(),row.value(QStringLiteral("generation")).toInt(),QStringLiteral("stop"));
            QTRY_COMPARE(tray.clicked,QList<int>{7});
            tray.status=QStringLiteral("Passive");
            auto changed=QDBusMessage::createSignal(QStringLiteral("/StatusNotifierItem"),QStringLiteral("org.kde.StatusNotifierItem"),QStringLiteral("NewStatus"));
            changed.setArguments({QStringLiteral("Passive")}); QVERIFY(peer.send(changed));
            QTRY_VERIFY(screen.activities().isEmpty());
            tray.status=QStringLiteral("Active");
            announce("StatusNotifierItemRegistered");
            QTRY_COMPARE(screen.activities().size(),1);
            announce("StatusNotifierItemUnregistered");
            QTRY_VERIFY(screen.activities().isEmpty());
            tray.id=QStringLiteral("some-application");
            announce("StatusNotifierItemRegistered");
            QTest::qWait(100);
            QVERIFY(screen.activities().isEmpty());
        }
        {
            // Already sharing when Ambient starts.
            tray.id=QStringLiteral("xdg-desktop-portal-kde");
            ScreenShareProvider screen(QDBusConnection::sessionBus());
            QTRY_COMPARE(screen.activities().size(),1);
        }
        peer.unregisterService(QStringLiteral("org.kde.StatusNotifierWatcher"));
        peer.unregisterObject(QStringLiteral("/"),QDBusConnection::UnregisterTree);
        QDBusConnection::disconnectFromBus(QStringLiteral("fake-tray"));
    }

    void tetteBridgeLifecycle() {
        QTemporaryDir dir;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,dir.path());
        QVERIFY(QDir(dir.path()).mkdir(QStringLiteral("target")));
        QVERIFY(QDir(dir.path()).mkdir(QStringLiteral("second")));
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
        const auto operationId=files.operations().first().toMap().value(QStringLiteral("id")).toString();
        QVERIFY(files.operations().first().toMap().value(QStringLiteral("canSuspend")).toBool());
        files.suspendOperation(operationId);
        QTRY_VERIFY(files.operations().first().toMap().value(QStringLiteral("suspended")).toBool());
        QTRY_COMPARE(provider.activities().size(),1);
        QTRY_COMPARE(provider.activities().first().toMap().value(QStringLiteral("state")).toString(),QStringLiteral("suspended"));
        auto liveRow=provider.activities().first().toMap();
        QVERIFY(liveRow.value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("resume")).toBool());
        // A second copy runs beside the first, each its own row; the bridge
        // pauses it, and Ambient cancels it alone.
        files.copyDropped({source.fileName()},dir.filePath(QStringLiteral("second")));
        QCOMPARE(files.operations().size(),2);
        const auto secondId=files.operations().last().toMap().value(QStringLiteral("id")).toString();
        bridge.suspend(secondId);
        QVERIFY(files.operations().last().toMap().value(QStringLiteral("suspended")).toBool());
        QTRY_COMPARE(provider.activities().size(),2);
        QVariantMap secondRow;
        for (const auto &row : provider.activities())
            if (row.toMap().value(QStringLiteral("sourceId")).toString() == secondId) secondRow = row.toMap();
        QVERIFY(!secondRow.isEmpty());
        provider.invoke(secondRow.value(QStringLiteral("id")).toString(),secondRow.value(QStringLiteral("generation")).toInt(),QStringLiteral("cancel"));
        QTRY_COMPARE(files.operations().size(),1);
        QTRY_COMPARE(provider.activities().size(),1);
        QVERIFY(!files.failedJustNow()); // cancelled by the person: no end to tell
        QCOMPARE(files.operations().first().toMap().value(QStringLiteral("id")).toString(),operationId);
        liveRow=provider.activities().first().toMap();
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
        // Resumed from Ambient, the paused copy runs on and finishes.
        QTRY_VERIFY(provider.activities().first().toMap().value(QStringLiteral("capabilities")).toMap().value(QStringLiteral("resume")).toBool());
        const auto current=provider.activities().first().toMap();
        provider.invoke(current.value(QStringLiteral("id")).toString(),current.value(QStringLiteral("generation")).toInt(),QStringLiteral("resume"));
        QTRY_VERIFY_WITH_TIMEOUT(!files.working(),10000); QTRY_VERIFY(provider.activities().isEmpty());
        QCOMPARE(files.operationStatus(),QStringLiteral("Done"));
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
    // A producer on the newer interface, as KDE Connect reports: it ends as
    // the line on its input says.
    if (app.arguments().contains(QStringLiteral("--job-producer-v2"))) {
        QDBusConnection bus=QDBusConnection::sessionBus();
        auto reply=call(bus,QStringLiteral("org.kde.JobViewServer"),QStringLiteral("/JobViewServer"),
            QStringLiteral("org.kde.JobViewServerV2"),QStringLiteral("requestView"),
            {QString(),3,QVariantMap{{QStringLiteral("application-display-name"),QStringLiteral("Ambient Test")},
                                     {QStringLiteral("application-icon-name"),QStringLiteral("folder")}}});
        if (reply.type()==QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) return 2;
        const auto path=qdbus_cast<QDBusObjectPath>(reply.arguments().first()).path();
        const auto send=[&](const QString &method,const QVariantList &args) {
            auto msg=QDBusMessage::createMethodCall(QStringLiteral("org.kde.JobViewServer"),path,QStringLiteral("org.kde.JobViewV3"),method);
            msg.setArguments(args); bus.asyncCall(msg);
        };
        QSocketNotifier input(STDIN_FILENO,QSocketNotifier::Read);
        QObject::connect(&input,&QSocketNotifier::activated,&app,[&] {
            char buffer[4096]; const auto count=::read(STDIN_FILENO,buffer,sizeof(buffer)-1);
            if (count<=0) return;
            const auto line=QString::fromUtf8(buffer,count).trimmed();
            if (line.startsWith(QStringLiteral("receive "))) {
                // As KDE Connect reports a file it receives: the folder as the
                // destination, the file itself as a description value.
                const auto file=line.mid(8);
                send(QStringLiteral("update"),{QVariantMap{{QStringLiteral("destUrl"),QUrl::fromLocalFile(QFileInfo(file).absolutePath()).toString()},
                    {QStringLiteral("title"),QStringLiteral("Receiving file")},{QStringLiteral("totalFiles"),qulonglong(1)},
                    {QStringLiteral("descriptionLabel1"),QStringLiteral("Source")},{QStringLiteral("descriptionValue1"),QStringLiteral("Pixel")},
                    {QStringLiteral("descriptionLabel2"),QStringLiteral("Destination")},{QStringLiteral("descriptionValue2"),file}}});
                send(QStringLiteral("terminate"),{uint(0),QString(),QVariantMap{}});
            } else if (line.startsWith(QStringLiteral("arrive "))) {
                send(QStringLiteral("update"),{QVariantMap{{QStringLiteral("destUrl"),QUrl::fromLocalFile(line.mid(7)).toString()}}});
                send(QStringLiteral("terminate"),{uint(0),QString(),QVariantMap{}});
            } else if (line==QStringLiteral("cancel")) {
                send(QStringLiteral("terminate"),{uint(1),QStringLiteral("Canceled"),QVariantMap{}});
            } else if (line==QStringLiteral("fail")) {
                send(QStringLiteral("terminate"),{uint(100),QStringLiteral("The phone went out of reach"),QVariantMap{}});
            }
        });
        return app.exec();
    }
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
