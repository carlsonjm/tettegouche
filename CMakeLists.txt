cmake_minimum_required(VERSION 3.22)

project(tettegouche VERSION 0.1.0 LANGUAGES CXX)

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
find_package(KF6 6.26 REQUIRED COMPONENTS CoreAddons Runner)
find_package(KF6Kirigami 6.26 REQUIRED)
find_package(KF6KirigamiPlatform 6.26 REQUIRED)
find_package(LayerShellQt 6.7 REQUIRED)

add_library(tettegouche-context STATIC
    src/WorkspaceContext.cpp
    src/WorkspaceContext.h
)
target_link_libraries(tettegouche-context PUBLIC Qt6::Core)
target_include_directories(tettegouche-context PUBLIC src)

qt_add_executable(tettegouche src/main.cpp)
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
    KF6::Runner
    KF6Kirigami
    KF6::KirigamiPlatform
    LayerShellQt::Interface
)

install(TARGETS tettegouche RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})
install(PROGRAMS io.github.carlsonjm.Tettegouche.desktop
        DESTINATION ${KDE_INSTALL_APPDIR})

if(BUILD_TESTING)
    qt_add_executable(workspace-context-test tests/WorkspaceContextTest.cpp)
    target_link_libraries(workspace-context-test PRIVATE
        tettegouche-context Qt6::Test)
    add_test(NAME workspace-context-test COMMAND workspace-context-test)
endif()
