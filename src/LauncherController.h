/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "RelatedInfo.h"
#include "ScreenShareProvider.h"
#include "WorkspaceContext.h"

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QRect>
#include <QRectF>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

#include <functional>
#include <memory>
#include <vector>

class ApplicationCatalog;
class FileBrowser;
class NotesDoor;
class OmniResults;
class OpenWindows;
class QIcon;
class QMimeData;
class QQuickView;
class QScreen;
class RecentUse;

namespace KRunner
{
class RunnerManager;
}

// Files' own window answers to the Files entry, so the dock, Kadunce and
// Plasma's window list name it Files, and Kadunce does not take it for the
// launcher's surface.
inline constexpr auto FilesApplicationId = "io.github.carlsonjm.Tettegouche.Files";

// The launcher: what it shows and when, its place as Kadunce's guest, the
// requests it answers on its D-Bus interface, and when it stays ready or
// leaves.
class LauncherController final : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche")
    Q_PROPERTY(bool contextAvailable READ contextAvailable
               NOTIFY contextChanged)
    Q_PROPERTY(bool guestMode READ guestMode NOTIFY guestChanged)
    Q_PROPERTY(bool drawerExpanded READ drawerExpanded NOTIFY guestChanged)
    Q_PROPERTY(int guestX READ guestX NOTIFY guestChanged)
    Q_PROPERTY(int guestY READ guestY NOTIFY guestChanged)
    Q_PROPERTY(int guestWidth READ guestWidth NOTIFY guestChanged)
    Q_PROPERTY(int guestHeight READ guestHeight NOTIFY guestChanged)
    Q_PROPERTY(QRect availableArea READ availableArea NOTIFY guestChanged)
    Q_PROPERTY(int relatedRevision READ relatedRevision NOTIFY relatedChanged)
    // Whether Shuffle's dock answered when Search last asked what it pins.
    Q_PROPERTY(bool dockPresent READ dockPresent NOTIFY pinnedChanged)
    // Files' own window: offered, and whether it is open now.
    Q_PROPERTY(bool filesWindowOffered READ filesWindowOffered CONSTANT)
    Q_PROPERTY(bool filesWindowOpen READ filesWindowOpen NOTIFY filesWindowChanged)

public:
    LauncherController(QQuickView *view,
                       KRunner::RunnerManager *runnerManager,
                       OmniResults *results,
                       ApplicationCatalog *catalog,
                       bool guestAllowed,
                       QObject *parent = nullptr);
    ~LauncherController() override;

    bool contextAvailable() const { return m_context.available(); }
    int relatedRevision() const { return m_relatedRevision; }
    bool dockPresent() const { return m_dockPresent; }
    Q_INVOKABLE bool catalogPinned(int row) const;
    // Asks Shuffle's dock to pin an application from Apps, or to unpin it.
    // The dock does it as its own sheet does and says so with its change
    // signal; until then Search holds what it asked for.
    Q_INVOKABLE void pinCatalog(int row, bool pin);
    Q_INVOKABLE QString relatedOptionLabel(int row);
    Q_INVOKABLE QVariantList relatedItems(int row);
    bool guestMode() const { return m_guestMode; }
    bool drawerExpanded() const { return m_drawerExpanded; }
    bool tabletSurface() const;
    // Drawers open at Search's size; Expand, chosen, fills any screen. Pop out's
    // growth, not chosen, fills only the tablet's screen.
    Q_INVOKABLE void setDrawerExpanded(bool expanded, bool chosen = false);
    int guestX() const { return m_guestRect.x(); }
    int guestY() const { return m_guestRect.y(); }
    int guestWidth() const { return m_guestRect.width(); }
    int guestHeight() const { return m_guestRect.height(); }
    // Floating, Search keeps to the room above Shuffle's dock, as cards do.
    QRect availableArea() const;

    Q_INVOKABLE bool resultIsOpen(int row) const;
    // The desktop file id of the application a result opens, or nothing for
    // any other result.
    Q_INVOKABLE QString resultApplicationId(int row) const;
    // A result or an application in Apps whose window is open: 1 when it was
    // brought forward, -1 when it is open but did not come, 0 when it is not
    // open and should start.
    Q_INVOKABLE int activateIfOpen(int row);
    Q_INVOKABLE int activateCatalogIfOpen(int row);

    // The settings this launcher started with, as the widget passes them.
    void setStartedWith(const QStringList &settings) { m_startedWith = settings; }
    void setFileBrowser(FileBrowser *browser);
    void setNotesDoor(NotesDoor *notes) { m_notes = notes; }
    // What was used lately leaves out what the dock holds, what is open and
    // what is hidden from Apps, and is withheld while the screen is shared.
    void setRecentUse(RecentUse *recent);
    // Plasma's window list, read for what is open where Kadunce does not say.
    void setOpenWindows(OpenWindows *windows);
    // A recent application, or a recent file's usual one, is awaited as a card
    // as any launch from Search is.
    Q_INVOKABLE bool beginGuestRecentLaunch(int row);

    // Files carried past the sheet's edge leave as a drag any application can
    // take, offered only as a copy.
    // From Search's Files, or from the Files in a window of its own given
    // as from.
    Q_INVOKABLE void carryOut(const QStringList &paths, const QRectF &sheet, QObject *from = nullptr);
    // An application carried past its tile leaves as its desktop file, which
    // Shuffle's dock pins where it is let go, as it pins one from any other
    // launcher.
    Q_INVOKABLE void carryApplication(int row, const QRectF &sheet);
    // A folder carried from Apps leaves as its applications' desktop files,
    // which any launcher pins, with the folder's name beside them, which
    // Shuffle's dock reads to pin them as one folder.
    Q_INVOKABLE void carryFolder(int row, const QRectF &sheet);

    Q_INVOKABLE void close();
    Q_INVOKABLE void finishLaunch();
    // A launcher started only to answer as the file manager leaves if no
    // request has shown it.
    void leaveIfUnused();

    Q_INVOKABLE void updateGuestDrag(double horizontalDelta);
    Q_INVOKABLE bool finishGuestDrag(double horizontalDelta);
    Q_INVOKABLE bool beginGuestApplicationLaunch(int row, bool catalog = false);
    // The notes application's board, awaited in Spread as any launch from
    // Search is, so its window takes Search's place.
    Q_INVOKABLE bool beginGuestNotesLaunch();
    Q_INVOKABLE void cancelGuestApplicationLaunch();

    bool filesWindowOffered() const { return m_fileBrowser != nullptr; }
    // Whether any Files window is open.
    bool filesWindowOpen() const;
    // A new Files window, starting with the tabs, folder and view Files in
    // Search has, and keeping its own after that; as many as are asked for.
    // It opens at the size Search has as a card in Spread, or Search's own
    // size elsewhere, and is an ordinary window after that.
    Q_INVOKABLE bool popOutFilesWindow();
    // The Files window last used brought forward, minimized or not; a new
    // one where none is open.
    Q_INVOKABLE bool showFilesWindow();
    // How a Files window gets a Files of its own; without it, there is one
    // window, sharing Search's.
    void setFileBrowserMaker(std::function<std::unique_ptr<FileBrowser>()> make) { m_makeFileBrowser = std::move(make); }
    // Files' window is awaited in Spread as an application started from
    // Search is, and takes Search's card.
    Q_INVOKABLE bool beginGuestFilesLaunch();

    Q_INVOKABLE void showInputMethod();
    Q_INVOKABLE bool searchWeb(const QString &query);
    Q_INVOKABLE bool beginGuestWebLaunch();
    Q_INVOKABLE void completeGuestHandoff();

public Q_SLOTS:
    // Kept ready while hidden, the launcher reads the workspace again when it
    // opens, not at every change while nobody sees it.
    void workspaceUpdated();
    // The applications pinned in Shuffle's dock, which it publishes; with no
    // dock there, none.
    void askPinned();
    // The dock's band changed, or moved to another display, while Search is
    // shown; hidden, it reads the band again as it opens.
    void dockExtentUpdated();
    void contextBarUpdated();
    void bridgeLost();

    Q_SCRIPTABLE void toggle();
    // As toggle, from the key that opens Search rather than its button: it
    // opens ready to type, with the cursor in the field, so keys already
    // under the person's hands, on screen or not, stay in use.
    Q_SCRIPTABLE void toggleToType();
    // Whether Search was last opened by its key, for the field to take the
    // cursor as it shows.
    Q_INVOKABLE bool openedToType() const { return m_openedToType; }
    // A drive plugged in, chosen in Ambient: Files opens it, mounting it first.
    Q_SCRIPTABLE void showDrive(const QString &id);
    Q_SCRIPTABLE void showFile(const QString &file);
    // Another application asks to see a folder, as it would ask a file
    // manager: a local folder opens in Files.
    Q_SCRIPTABLE void showFolder(const QString &location);
    // The first folder opens in the tab shown and each other in a tab of its
    // own. Recent opens Files' Recent, and a phone plugged in opens as its drive
    // does when nothing else was asked for; places Files does not browse, such
    // as Trash or a network share, go on to Dolphin.
    Q_SCRIPTABLE void showFolders(const QStringList &locations);
    // Items shown chosen in their folder, as "Show in folder" asks; any outside
    // the first one's folder are left out.
    Q_SCRIPTABLE void revealItems(const QStringList &locations);
    // The same, with the first one's Properties open.
    Q_SCRIPTABLE void showItemProperties(const QStringList &locations);
    // Meta+G opens Apps and Meta+E Files, and the dot's slide any of Apps,
    // Files or Notes ("notes"); the one already open closes
    // the launcher instead. With Files in its own window, Files brings that
    // window forward. The panel's quick note island asks for "note", a new
    // quick note, and "note:" with an id for its pinned note; each opens in
    // Notes at Search's size.
    Q_SCRIPTABLE void openDrawer(const QString &drawer);
    Q_SCRIPTABLE void open();
    // The widget's settings changed: a launcher started with others leaves
    // for one started with these, when nothing keeps it. True when it is
    // leaving.
    Q_SCRIPTABLE bool leaveFor(const QStringList &settings);

    Q_SCRIPTABLE void dismissGuest();
    Q_SCRIPTABLE void completeGuestLaunch(const QString &requestToken);
    Q_SCRIPTABLE void completeGuestNavigation(int slot);
    // The mode Search shows and whether an application is on its way, for
    // the widget's dot.
    Q_INVOKABLE void reportShowing(const QString &mode, bool loading);
    // Says it again, for a widget that forgot it while Search was hidden.
    void repeatShowing();

Q_SIGNALS:
    void filesRequested();
    void drawerRequested(const QString &drawer);
    void relatedChanged();
    void pinnedChanged();
    void opened();
    void contextChanged();
    void guestChanged();
    void guestLaunchReady();
    void guestNavigationReady(int slot);
    void guestBridgeLost();
    void filesWindowChanged();
    // Search shown or hidden, for the widget: a launcher kept ready runs on
    // hidden, so a running launcher is not an open one.
    Q_SCRIPTABLE void shown(bool visible);
    Q_SCRIPTABLE void showing(const QString &mode, bool loading);

private:
    void openFor(bool toType);
    bool m_openedToType = false;
    QString m_showingMode;
    bool m_showingLoading = false;
    // Starts a carry while the press that began it is still held, which the
    // compositor requires.
    void carry(QMimeData *mime, const QIcon &icon, const QRectF &sheet);
    bool prepareGuestIdentity(QString appId, const QStringList &aliases = {});
    void showFiles();
    // Kadunce brings the window forward as it would any card; without it,
    // Plasma does, and failing both the window asks for itself.
    void raiseFilesWindow();
    void reveal(const QStringList &locations, bool properties);
    // Places Files does not browse open in Dolphin, KDE's file manager.
    void handOn(const QList<QUrl> &urls);
    // An application's open window brought forward: 1 when it came, -1 when
    // it is open but did not come, 0 when none is open.
    int bringForward(const QString &applicationId, const QString &name);
    // A launcher never shown, started only as the file manager, is not kept.
    void finishOrDeferQuit(bool keepReady = true);
    bool stayReady() const;
    // The band Shuffle's dock reserves on Search's display, asked without
    // waiting; until it answers, the band last read stands.
    void readDockBand();
    void readContextBar();
    void askContextBar(const QString &outputName, quint64 generation, int timeout);
    void floatOn(const QString &outputName);
    // Puts Search's surface on a display. Qt's own idea of the window's
    // display can drift from the output its surface was placed on, so Search
    // keeps the display it chose and measures by it.
    void placeOn(QScreen *screen);
    QScreen *placedScreen() const;
    // Asks Kadunce, without waiting on it, whether it takes Search into
    // Spread. Search shows once it answers, or on its own once GuestWait has
    // passed; an answer that comes after that is given back.
    void askGuest();
    void takeGuest(const QByteArray &answer);
    void present();
    // Shown, or on its way to being shown.
    bool openOrOpening() const;
    // A step that needs Search shown: run at once where it is, or as it shows.
    void whenShown(std::function<void()> step);
    void endGuestLease();
    // What is open, read again: from Kadunce where it answers, otherwise from
    // Plasma's window list.
    void refreshContextBlocking();
    void refreshContext();
    void takeContext(bool answered, const QString &payload);
    void watchScreen(QScreen *screen);

    QQuickView *m_view;
    QPointer<QScreen> m_screen;
    KRunner::RunnerManager *m_runnerManager;
    OmniResults *m_results;
    RelatedInfo m_related;
    int m_relatedRevision = 0;
    ApplicationCatalog *m_catalog;
    RecentUse *m_recent = nullptr;
    NotesDoor *m_notes = nullptr;
    OpenWindows *m_openWindows = nullptr;
    FileBrowser *m_fileBrowser = nullptr;
    bool m_quitAfterFiles = false;
    // The second a failed copy is given to reach Ambient; reopening stops it.
    QTimer m_lateQuit;
    // Files carried out are offered until the other application takes them.
    bool m_carrying = false;
    QSet<QString> m_pinned;
    bool m_dockPresent = false;
    ScreenShareProvider m_shares;
    WorkspaceContext m_context;
    // Whether what m_context holds came from Kadunce, which then brings
    // windows forward, or from Plasma's window list.
    bool m_contextFromKadunce = false;
    // A reading of what is open was asked and has not answered.
    bool m_contextPending = false;
    QRect m_guestRect;
    QRect m_compactGuestRect, m_activeGuestRect;
    int m_dockBand = 0;
    // The Context Bar's height along the top of Search's display.
    int m_contextBar = 0;
    quint64 m_barGeneration = 0;
    // A read that went unanswered is asked once more before it is given up.
    bool m_barRetried = false;
    quint64 m_dockGeneration = 0;
    bool m_drawerExpanded = false;
    bool m_requestedExpanded = false;
    bool m_expansionChosen = false;
    bool m_guestExpansionSupported = false;
    quint64 m_presentationGeneration = 0;
    bool m_guestMode = false;
    bool m_guestAllowed = true;
    // Opened, and waiting on Kadunce's answer before it shows.
    bool m_opening = false;
    // A guest asked for and not yet answered.
    bool m_guestAsking = false;
    // Kadunce's guest protocol as it last answered, asked once for each
    // Kadunce; 0 until it answers.
    int m_guestProtocol = 0;
    quint64 m_guestGeneration = 0;
    QTimer m_guestWait;
    QList<std::function<void()>> m_whenShown;
    quint64 m_contextGeneration = 0;
    QString m_launchToken;
    struct FilesWindow {
        std::unique_ptr<FileBrowser> browser;
        // Declared after the Files it shows, so it goes first.
        std::unique_ptr<QQuickView> view;
        FileBrowser *files(FileBrowser *shared) const { return browser ? browser.get() : shared; }
    };
    FilesWindow *frontFilesWindow() const;
    // The Files that requests from elsewhere go to: the window last used,
    // while one is open, or Search's.
    FileBrowser *filesTarget() const;
    bool filesWorking() const;
    void watchFiles(FileBrowser *browser, FilesWindow *window);
    // Closed windows are kept, hidden, while their Files finishes a copy,
    // and are used again for the next window.
    std::vector<std::unique_ptr<FilesWindow>> m_filesWindows;
    QPointer<QQuickView> m_lastFilesWindow;
    std::function<std::unique_ptr<FileBrowser>()> m_makeFileBrowser;
    QString m_launcherApplicationId;
    QStringList m_startedWith;
    const QDateTime m_programModified;
};
