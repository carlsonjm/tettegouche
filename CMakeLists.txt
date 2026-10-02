cmake_minimum_required(VERSION 3.22)

project(tettegouche VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(ECM 6.26 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(CTest)
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 6.10 REQUIRED COMPONENTS Core DBus Gui Qml Quick Test)
find_package(KF6 6.26 REQUIRED COMPONENTS CoreAddons FileMetaData GlobalAccel I18n KIO Runner Service BluezQt Solid)
find_package(KF6Kirigami 6.26 REQUIRED)
find_package(KF6KirigamiPlatform 6.26 REQUIRED)
find_package(LayerShellQt 6.7 REQUIRED)
find_package(Plasma 6.7 REQUIRED)
find_package(LibNotificationManager REQUIRED)
find_package(AppStreamQt 1.0 REQUIRED)

add_library(tettegouche-activities STATIC
    src/MprisActivityProvider.cpp src/MprisActivityProvider.h
    src/DesktopJobProvider.cpp src/DesktopJobProvider.h
    src/IncomingFileProvider.cpp src/IncomingFileProvider.h
    src/TetteTransferProvider.cpp src/TetteTransferProvider.h
    src/FinishNotices.cpp src/FinishNotices.h
    src/DriveActivityProvider.cpp src/DriveActivityProvider.h src/DriveRules.h
    src/ScreenShareProvider.cpp src/ScreenShareProvider.h
    src/ActivityModel.cpp src/ActivityModel.h src/ActivityUtils.h)
target_include_directories(tettegouche-activities PUBLIC src)
set_target_properties(tettegouche-activities PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(tettegouche-activities PUBLIC Qt6::DBus Qt6::Core KF6::I18n KF6::Solid PW::LibNotificationManager)
# Ambient's words are the panel widget's, in the catalog Plasma gives it.
target_compile_definitions(tettegouche-activities PRIVATE TRANSLATION_DOMAIN="plasma_applet_studio.warbler.tettegouche")

add_library(tettegouche-context STATIC
    src/WorkspaceContext.cpp
    src/WorkspaceContext.h
)
target_link_libraries(tettegouche-context PUBLIC Qt6::Core)
target_include_directories(tettegouche-context PUBLIC src)

add_library(tettegouche-related STATIC
    src/BluetoothContext.h
    src/RelatedInfo.h
    src/RelatedInfo.cpp
)
target_include_directories(tettegouche-related PUBLIC src)
target_link_libraries(tettegouche-related PUBLIC Qt6::DBus KF6::BluezQt KF6::I18n KF6::Solid KF6::Service)
target_compile_definitions(tettegouche-related PRIVATE TRANSLATION_DOMAIN="tettegouche")

qt_add_executable(tettegouche
    src/main.cpp
    src/OmniResults.h
    src/ApplicationCatalog.cpp
    src/ApplicationCatalog.h
    src/FileBrowser.h src/FileDevices.h src/FileQuestions.h
    src/FileDetails.cpp src/FileDetails.h
    src/FileThumbnails.cpp src/FileThumbnails.h
    src/TransferActivityBridge.cpp src/TransferActivityBridge.h
)
qt_add_resources(tettegouche "tettegouche_qml"
    PREFIX "/"
    FILES qml/Launcher.qml qml/FilesPane.qml qml/SuiteIcon.qml
        qml/SheetMenu.qml qml/SheetMenuItem.qml qml/SheetConfirm.qml
        assets/icons/lucide/ellipsis-vertical.svg
        assets/icons/lucide/chevron-down.svg
        assets/icons/lucide/square.svg
        assets/icons/lucide/skip-back.svg
        assets/icons/lucide/play.svg
        assets/icons/lucide/pause.svg
        assets/icons/lucide/skip-forward.svg
        assets/icons/lucide/download.svg
        assets/icons/lucide/x.svg
        assets/icons/lucide/plus.svg
        assets/icons/lucide/arrow-left.svg
        assets/icons/lucide/arrow-right.svg
        assets/icons/lucide/refresh-cw.svg
        assets/icons/lucide/check.svg
        assets/icons/lucide/circle.svg
        assets/icons/lucide/eject.svg
)
target_link_libraries(tettegouche PRIVATE
    tettegouche-context
    tettegouche-related
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    KF6::CoreAddons
    KF6::FileMetaData
    KF6::I18n
    KF6::I18nQml
    KF6::KIOGui
    KF6::Runner
    KF6::Service
    KF6::BluezQt
    KF6::Solid
    AppStreamQt
    KF6Kirigami
    KF6::KirigamiPlatform
    LayerShellQt::Interface
)

target_compile_definitions(tettegouche PRIVATE TRANSLATION_DOMAIN="tettegouche")
install(TARGETS tettegouche RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})
# Translations, one catalog for the launcher and one for the panel widget, as
# po/<language>/<catalog>.po; tools/extract-messages.sh makes their templates.
ki18n_install(po)
install(PROGRAMS io.github.carlsonjm.Tettegouche.desktop io.github.carlsonjm.Tettegouche.Files.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})
# Offered, not switched on: answering "Show in folder" is the product's choice,
# made by placing this where D-Bus looks for services.
configure_file(org.freedesktop.FileManager1.service.in org.freedesktop.FileManager1.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.FileManager1.service
        DESTINATION ${KDE_INSTALL_DATADIR}/tettegouche)
# Widget Explorer prefers an icon named after the plugin ID over metadata.Icon.
# The live panel dimple is drawn independently in applet/main.qml.
install(FILES assets/studio.warbler.tettegouche-logo.png
        DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/512x512/apps
        RENAME studio.warbler.tettegouche.png)
install(FILES assets/studio.warbler.tettegouche-logo.png
        DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/512x512/apps)
plasma_add_applet(studio.warbler.tettegouche
    CPP_SOURCES
        src/TettegoucheApplet.cpp
        src/TettegoucheApplet.h
        src/LauncherKeys.cpp
        src/LauncherKeys.h
    QML_SOURCES
        applet/main.qml
        applet/AmbientSurface.qml
        applet/IslandRoom.js
        applet/SuiteIcon.qml
        applet/AmbientIsland.qml
        applet/ConfigGeneral.qml
        applet/config.qml
    RESOURCES
        applet/main.xml
        assets/studio.warbler.tettegouche.svg
        assets/icons/lucide/skip-back.svg
        assets/icons/lucide/play.svg
        assets/icons/lucide/pause.svg
        assets/icons/lucide/skip-forward.svg
        assets/icons/lucide/download.svg
        assets/icons/lucide/x.svg
        assets/icons/lucide/check.svg
        assets/icons/lucide/folder-open.svg
)
target_link_libraries(studio.warbler.tettegouche PRIVATE
    LayerShellQt::Interface
    tettegouche-activities
    Qt6::Core
    Qt6::DBus
    KF6::CoreAddons
    KF6::GlobalAccel
    KF6::I18n
    Plasma::Plasma
    Plasma::PlasmaQuick
)
target_compile_definitions(studio.warbler.tettegouche PRIVATE TRANSLATION_DOMAIN="plasma_applet_studio.warbler.tettegouche")

if(BUILD_TESTING)
    qt_add_executable(activity-provider-test tests/ActivityProviderTest.cpp
        src/TransferActivityBridge.cpp src/TransferActivityBridge.h src/FileBrowser.h src/FileDevices.h src/FileQuestions.h)
    target_link_libraries(activity-provider-test PRIVATE tettegouche-activities KF6::KIOCore KF6::Service KF6::Solid Qt6::Test Qt6::Quick)
    add_test(NAME activity-provider-test COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/run-panel-test.sh
        $<TARGET_FILE:activity-provider-test> ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
    set_tests_properties(activity-provider-test PROPERTIES TIMEOUT 45
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
    qt_add_executable(file-browser-test tests/FileBrowserTest.cpp src/FileBrowser.h src/FileDevices.h src/FileQuestions.h
        src/FileDetails.cpp src/FileDetails.h src/FileThumbnails.cpp src/FileThumbnails.h)
    target_include_directories(file-browser-test PRIVATE src)
    target_link_libraries(file-browser-test PRIVATE KF6::I18n KF6::KIOCore KF6::KIOGui KF6::FileMetaData KF6::Service KF6::Solid Qt6::Test Qt6::Quick)
    target_compile_definitions(file-browser-test PRIVATE TRANSLATION_DOMAIN="tettegouche" FILES_PANE_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/qml/FilesPane.qml"
        FILES_DESKTOP="${CMAKE_CURRENT_SOURCE_DIR}/io.github.carlsonjm.Tettegouche.Files.desktop"
        FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures")
    # A private bus that starts no desktop service: on an ordinary one, Recent
    # started KDE's activity service on the person's own record.
    add_test(NAME file-browser-test COMMAND dbus-run-session
        --config-file=${CMAKE_CURRENT_SOURCE_DIR}/tests/panel-test-bus.conf -- $<TARGET_FILE:file-browser-test>)
    set_tests_properties(file-browser-test PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
    add_test(NAME files-recent-test COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/verify-recent.sh $<TARGET_FILE:file-browser-test>)
    set_tests_properties(files-recent-test PROPERTIES TIMEOUT 150 SKIP_RETURN_CODE 77)
    add_test(NAME words-test COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/verify-words.sh $<TARGET_FILE:file-browser-test>)
    set_tests_properties(words-test PROPERTIES TIMEOUT 60)
    add_test(NAME files-sealed-test COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/verify-files-sealed.sh $<TARGET_FILE:file-browser-test>)
    set_tests_properties(files-sealed-test PROPERTIES TIMEOUT 150)
    qt_add_executable(application-catalog-test tests/ApplicationCatalogTest.cpp
        src/ApplicationCatalog.cpp src/ApplicationCatalog.h)
    target_include_directories(application-catalog-test PRIVATE src)
    target_link_libraries(application-catalog-test PRIVATE KF6::KIOGui KF6::Service AppStreamQt Qt6::Test)
    add_test(NAME application-catalog-test COMMAND application-catalog-test)
    qt_add_executable(related-info-test tests/RelatedInfoTest.cpp)
    target_link_libraries(related-info-test PRIVATE tettegouche-related Qt6::Test)
    add_test(NAME related-info-test COMMAND related-info-test)
    qt_add_executable(omni-results-test tests/OmniResultsTest.cpp src/OmniResults.h)
    target_include_directories(omni-results-test PRIVATE src)
    target_link_libraries(omni-results-test PRIVATE KF6::Runner Qt6::Gui Qt6::DBus)
    add_test(NAME omni-results-test COMMAND omni-results-test)
    set_tests_properties(omni-results-test PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    qt_add_executable(runner-identity-test tests/RunnerIdentityTest.cpp)
    target_include_directories(runner-identity-test PRIVATE src)
    target_link_libraries(runner-identity-test PRIVATE KF6::Runner Qt6::Core)
    add_test(NAME runner-identity-test COMMAND runner-identity-test)
    find_package(Qt6 REQUIRED COMPONENTS Widgets)
    find_package(PlasmaQuick REQUIRED)
    find_package(KF6Package REQUIRED)
    find_program(DBUS_RUN_SESSION dbus-run-session REQUIRED)

    qt_add_executable(tettegouche-suite-icon-test tests/SuiteIconRenderTest.cpp)
    target_compile_definitions(tettegouche-suite-icon-test PRIVATE
        SUITE_ICON_QML="${CMAKE_CURRENT_SOURCE_DIR}/qml/SuiteIcon.qml")
    target_link_libraries(tettegouche-suite-icon-test PRIVATE
        Qt6::Widgets Qt6::Quick Qt6::Test)
    add_test(NAME suite-icon-render-test COMMAND tettegouche-suite-icon-test)
    set_tests_properties(suite-icon-render-test PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
        TIMEOUT 30)

    qt_add_executable(workspace-context-test tests/WorkspaceContextTest.cpp)
    target_link_libraries(workspace-context-test PRIVATE
        tettegouche-context Qt6::Test)
    add_test(NAME workspace-context-test COMMAND workspace-context-test)

    qt_add_executable(panel-applet-test tests/PanelAppletTest.cpp src/LauncherKeys.cpp src/LauncherKeys.h)
    target_include_directories(panel-applet-test PRIVATE src)
    target_link_libraries(panel-applet-test PRIVATE
        Qt6::Widgets Qt6::Quick Qt6::Test Qt6::DBus Plasma::Plasma Plasma::PlasmaQuick KF6::Package KF6::GlobalAccel KF6::I18n)
    target_compile_definitions(panel-applet-test PRIVATE TRANSLATION_DOMAIN="plasma_applet_studio.warbler.tettegouche")
    add_dependencies(panel-applet-test studio.warbler.tettegouche)
    add_test(NAME panel-applet-test
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/run-panel-test.sh
            $<TARGET_FILE:panel-applet-test> ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
    set_tests_properties(panel-applet-test PROPERTIES TIMEOUT 45)
    add_test(NAME ambient-fixture-applet-test
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/run-panel-test.sh
            $<TARGET_FILE:panel-applet-test> ${CMAKE_LIBRARY_OUTPUT_DIRECTORY} normalAndFixtureSources)
    set_tests_properties(ambient-fixture-applet-test PROPERTIES TIMEOUT 30
        ENVIRONMENT "TETTE_AMBIENT_FIXTURE=transfer-media")
    add_test(NAME ambient-island-open-test
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/run-panel-test.sh
            $<TARGET_FILE:panel-applet-test> ${CMAKE_LIBRARY_OUTPUT_DIRECTORY} islandOpensFromThePanel)
    set_tests_properties(ambient-island-open-test PROPERTIES TIMEOUT 30
        ENVIRONMENT "TETTE_AMBIENT_FIXTURE=transfer-media")
    find_program(QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner
        HINTS /usr/lib/qt6/bin)
    if(QMLTESTRUNNER_EXECUTABLE)
        add_test(NAME ambient-surface-test
            COMMAND ${QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_Ambient.qml)
        set_tests_properties(ambient-surface-test PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            TIMEOUT 60)
        add_test(NAME launcher-controls-test
            COMMAND ${QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_Launcher.qml)
        set_tests_properties(launcher-controls-test PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            TIMEOUT 60)
    endif()
endif()
