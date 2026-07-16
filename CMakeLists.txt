cmake_minimum_required(VERSION 3.21)
project(unisic-kit VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Kit needs no Widgets: ThemeController/IconImageProvider live entirely on
# Gui + Quick + Qml, and the capture stack is Core + DBus (+ optional PipeWire).
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(PkgConfig REQUIRED)
# PipeWire frame capture is OPTIONAL: without it the kit builds fine, only
# PipeWireGrabber is dropped (mirrors Unisic's CMakeLists).
pkg_check_modules(PIPEWIRE IMPORTED_TARGET libpipewire-0.3)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0001 NEW)
# QTP0004 (auto-generate qmldir for qml/ subdirs) only exists since Qt 6.8;
# setting it unguarded is a hard configure error on older Qt.
if(QT_KNOWN_POLICY_QTP0004)
    qt_policy(SET QTP0004 NEW)
endif()

qt_add_library(unisic-kit STATIC
    src/ConfigPath.h
    src/SettingMacro.h
    src/capture/PortalRequest.h src/capture/PortalRequest.cpp
    src/capture/ScreenCastSession.h src/capture/ScreenCastSession.cpp
    src/media/FfmpegUtil.h src/media/FfmpegUtil.cpp
    src/theme/ThemeController.h src/theme/ThemeController.cpp
    src/theme/IconImageProvider.h src/theme/IconImageProvider.cpp
)

# Theme.qml is a QML singleton; ThemeController/IconImageProvider register
# declaratively via QML_ELEMENT/QML_SINGLETON — do NOT add any imperative
# qmlRegisterSingletonInstance into this URI (it would clobber the module's
# other registered types).
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(unisic-kit
    URI Unisic.Kit
    VERSION 1.0
    # On a case-insensitive filesystem (this drive is FAT) the default output
    # dir named after the URI would collide with other paths — mirror Unisic's
    # dedicated qmlmod/ tree.
    OUTPUT_DIRECTORY qmlmod/Unisic/Kit
    QML_FILES
        qml/Theme.qml
        qml/components/UButton.qml
        qml/components/UCard.qml
        qml/components/UIcon.qml
        qml/components/UIconButton.qml
        qml/components/USplitIconButton.qml
        qml/components/UComboBox.qml
        qml/components/UValueCombo.qml
        qml/components/UMenuButton.qml
        qml/components/UConfirmDialog.qml
        qml/components/UColorPopup.qml
        qml/components/UHoverTip.qml
        qml/components/USwitch.qml
        qml/components/USlider.qml
        qml/components/UTextField.qml
        qml/components/UFilterChip.qml
        qml/components/ColorDot.qml
        qml/components/SidebarItem.qml
        qml/components/ToolChip.qml
        qml/components/MiddleScroll.qml
        qml/components/WheelBoost.qml
        qml/components/VideoPreview.qml
)

# PUBLIC src/ so consumers include <capture/ScreenCastSession.h>,
# <theme/ThemeController.h>, <media/FfmpegUtil.h> etc. The per-subdir PRIVATE
# entries are for qmltyperegistration, which includes QML_ELEMENT headers
# (ThemeController.h) by basename.
target_include_directories(unisic-kit
    PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    PRIVATE src/capture src/record src/theme src/media)

target_link_libraries(unisic-kit PUBLIC
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus)

# Symbolic icon set. PREFIX "/" gives ":/resources/icons/sym/<name>.svg",
# exactly the path IconImageProvider::tintedBundled() looks up.
file(GLOB UNISIC_KIT_SYM_ICONS CONFIGURE_DEPENDS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
     resources/icons/sym/*.svg)
qt_add_resources(unisic-kit "sym_icons" PREFIX "/" FILES ${UNISIC_KIT_SYM_ICONS})

if(PIPEWIRE_FOUND)
    target_sources(unisic-kit PRIVATE
        src/record/PipeWireGrabber.h src/record/PipeWireGrabber.cpp)
    target_link_libraries(unisic-kit PUBLIC PkgConfig::PIPEWIRE)
    target_compile_definitions(unisic-kit PUBLIC HAVE_PIPEWIRE)
    message(STATUS "unisic-kit: PipeWire capture enabled (HAVE_PIPEWIRE=ON)")
else()
    message(WARNING "libpipewire-0.3 not found — PipeWireGrabber (screen frame capture) will be unavailable")
endif()
