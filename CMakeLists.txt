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
find_package(KF6 6.26 REQUIRED COMPONENTS CoreAddons KIO Runner Service)
find_package(KF6Kirigami 6.26 REQUIRED)
find_package(KF6KirigamiPlatform 6.26 REQUIRED)
find_package(LayerShellQt 6.7 REQUIRED)
find_package(Plasma 6.7 REQUIRED)

add_library(tettegouche-context STATIC
    src/WorkspaceContext.cpp
    src/WorkspaceContext.h
)
target_link_libraries(tettegouche-context PUBLIC Qt6::Core)
target_include_directories(tettegouche-context PUBLIC src)

qt_add_executable(tettegouche
    src/main.cpp
    src/ApplicationCatalog.cpp
    src/ApplicationCatalog.h
)
qt_add_resources(tettegouche "tettegouche_qml"
    PREFIX "/"
    FILES qml/Launcher.qml
)
target_link_libraries(tettegouche PRIVATE
    tettegouche-context
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    KF6::CoreAddons
    KF6::KIOGui
    KF6::Runner
    KF6::Service
    KF6Kirigami
    KF6::KirigamiPlatform
    LayerShellQt::Interface
)

install(TARGETS tettegouche RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})
install(PROGRAMS io.github.carlsonjm.Tettegouche.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES assets/studio.warbler.tettegouche.svg
        DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)
plasma_add_applet(studio.warbler.tettegouche
    CPP_SOURCES
        src/TettegoucheApplet.cpp
        src/TettegoucheApplet.h
    QML_SOURCES
        applet/main.qml
        applet/ConfigGeneral.qml
        applet/config.qml
    RESOURCES
        applet/main.xml
        assets/studio.warbler.tettegouche.svg
)
target_link_libraries(studio.warbler.tettegouche PRIVATE
    Qt6::Core
    KF6::CoreAddons
    Plasma::Plasma
)

if(BUILD_TESTING)
    qt_add_executable(runner-identity-test tests/RunnerIdentityTest.cpp)
    target_include_directories(runner-identity-test PRIVATE src)
    target_link_libraries(runner-identity-test PRIVATE KF6::Runner Qt6::Core)
    add_test(NAME runner-identity-test COMMAND runner-identity-test)
    find_package(Qt6 REQUIRED COMPONENTS Widgets)
    find_package(PlasmaQuick REQUIRED)
    find_package(KF6Package REQUIRED)
    find_program(DBUS_RUN_SESSION dbus-run-session REQUIRED)

    qt_add_executable(workspace-context-test tests/WorkspaceContextTest.cpp)
    target_link_libraries(workspace-context-test PRIVATE
        tettegouche-context Qt6::Test)
    add_test(NAME workspace-context-test COMMAND workspace-context-test)

    qt_add_executable(panel-applet-test tests/PanelAppletTest.cpp)
    target_link_libraries(panel-applet-test PRIVATE
        Qt6::Widgets Qt6::Quick Qt6::Test Plasma::Plasma Plasma::PlasmaQuick KF6::Package)
    add_dependencies(panel-applet-test studio.warbler.tettegouche)
    add_test(NAME panel-applet-test
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/run-panel-test.sh
            $<TARGET_FILE:panel-applet-test> ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
    set_tests_properties(panel-applet-test PROPERTIES TIMEOUT 45)
    find_program(QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner
        HINTS /usr/lib/qt6/bin)
    if(QMLTESTRUNNER_EXECUTABLE)
        add_test(NAME launcher-controls-test
            COMMAND ${QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_Launcher.qml)
        set_tests_properties(launcher-controls-test PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            TIMEOUT 30)
    endif()
endif()
