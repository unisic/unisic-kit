cmake_minimum_required(VERSION 3.21)
# C alongside CXX: the wayland-scanner output for zkde_screencast (the
# *-protocol.c interface definitions) is plain C - without the language the
# generated file is silently not compiled and the interface symbol is missing
# at link time.
project(unisic-kit VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Kit needs no Widgets: ThemeController/IconImageProvider live entirely on
# Gui + Quick + Qml, and the capture stack is Core + DBus + PipeWire.
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(PkgConfig REQUIRED)

# NOTHING BELOW IS OPTIONAL. Every dependency the kit probes for is mandatory
# and a missing one stops the configure here, naming the package to install.
#
# This is not tidiness. A gate that quietly switches itself off produces a
# binary whose UI still offers the feature, and the only place that ever
# surfaces is a user's bug report months later: HAVE_LIBINPUT was off in every
# Flatpak ever built, HAVE_X11 in every Nix build, and both jobs stayed green
# the whole time. A build that cannot do what the interface promises is a
# broken build, so it must not be producible.
#
# pkg_check_modules is called WITHOUT its own REQUIRED keyword on purpose: its
# abort message names a pkg-config module, which is not what anyone types into
# a package manager. The helper below names the package on four distros
# instead. The names are the ones the consuming app's CI recipes already use
# (.github/workflows/{rpm,deb,arch}.yml).
function(unisic_kit_require_failed HUMAN_NAME WHAT_BREAKS FEDORA DEBIAN ARCH SUSE)
    message(FATAL_ERROR
        "unisic-kit: ${HUMAN_NAME} not found.\n"
        "  Unisic has no optional features, so this is a hard stop rather than\n"
        "  a build that quietly ships without it.\n"
        "  What would be missing: ${WHAT_BREAKS}\n"
        "  Fedora:   sudo dnf install ${FEDORA}\n"
        "  Debian:   sudo apt install ${DEBIAN}\n"
        "  Arch:     sudo pacman -S ${ARCH}\n"
        "  openSUSE: sudo zypper install ${SUSE}\n")
endfunction()

# PipeWire frame capture: PipeWireGrabber, the frame source on a Wayland
# session (mirrors Unisic's CMakeLists).
pkg_check_modules(PIPEWIRE IMPORTED_TARGET libpipewire-0.3)
if(NOT PIPEWIRE_FOUND)
    unisic_kit_require_failed("libpipewire-0.3"
        "screen and region recording on a Wayland session"
        "pipewire-devel" "libpipewire-0.3-dev" "libpipewire" "pipewire-devel")
endif()
# X11 (XShm + XFixes) frame capture: X11ShmGrabber, the frame source chosen at
# runtime on an X11 session. Needs libX11 (core), libXext (MIT-SHM:
# XShmGetImage) and libXfixes (hardware-cursor capture). One call for all three
# because they share one imported target, which also means the check is
# all-or-nothing: a missing libXfixes.pc alone reports the whole gate as not
# found, and that is precisely how the Nix package lost X11 recording without
# anyone noticing.
pkg_check_modules(X11 IMPORTED_TARGET x11 xext xfixes)
if(NOT X11_FOUND)
    unisic_kit_require_failed("libX11 + libXext + libXfixes (all three)"
        "screen recording on an X11 session (XShm capture)"
        "libX11-devel libXext-devel libXfixes-devel"
        "libx11-dev libxext-dev libxfixes-dev"
        "libx11 libxext libxfixes"
        "libX11-devel libXext-devel libXfixes-devel")
endif()
# Native X11 global hotkeys (XGrabKey) are a SEPARATE probe: they need libX11
# (grab + keysyms) and libxcb (the KeyPress event Qt hands the native event
# filter), but NOT the XShm/XFixes pair the frame grabber wants. Separate
# probes, both mandatory, so the error message can name the right package
# instead of a superset.
pkg_check_modules(XCBX11 IMPORTED_TARGET x11 xcb)
if(NOT XCBX11_FOUND)
    unisic_kit_require_failed("libX11 + libxcb"
        "global capture hotkeys on an X11 session without KGlobalAccel"
        "libX11-devel libxcb-devel"
        "libx11-dev libxcb1-dev"
        "libx11 libxcb"
        "libX11-devel libxcb-devel")
endif()

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
    # Pure + header-only, so it costs nothing to always ship it: the one place
    # that knows the Qt-portable -> X-keysym key vocabulary. X11Hotkeys grabs
    # through it, and consumers that write desktop custom-shortcut stores
    # (COSMIC RON, gsettings, xfconf, labwc rc.xml) parse chords with it.
    src/hotkeys/ShortcutKeyMap.h
    src/media/FfmpegUtil.h src/media/FfmpegUtil.cpp
    # The grabber base is always compiled/moc'd: GifRecorder connects to its
    # signals through the base pointer regardless of which backends are built.
    src/record/IScreenGrabber.h
    src/theme/ThemeController.h src/theme/ThemeController.cpp
    src/theme/ThemeJson.h
    src/theme/IconImageProvider.h src/theme/IconImageProvider.cpp
)

# Theme.qml, UKeys.qml and UFlyout.qml are QML singletons;
# ThemeController/IconImageProvider register declaratively via
# QML_ELEMENT/QML_SINGLETON - do NOT add any imperative
# qmlRegisterSingletonInstance into this URI (it would clobber the module's
# other registered types).
set_source_files_properties(qml/Theme.qml qml/UKeys.qml qml/UFlyout.qml
                            PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(unisic-kit
    URI Unisic.Kit
    VERSION 1.0
    # On a case-insensitive filesystem (this drive is FAT) the default output
    # dir named after the URI would collide with other paths - mirror Unisic's
    # dedicated qmlmod/ tree.
    OUTPUT_DIRECTORY qmlmod/Unisic/Kit
    QML_FILES
        qml/Theme.qml
        qml/UKeys.qml
        qml/UFlyout.qml
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
        qml/components/UFocusRing.qml
        qml/components/USwitch.qml
        qml/components/USlider.qml
        qml/components/USettingRow.qml
        qml/components/UNameBridge.qml
        qml/components/UShortcutRecorder.qml
        qml/components/UShortcutList.qml
        qml/components/UShortcutsHelp.qml
        qml/components/UTextField.qml
        qml/components/UFilterChip.qml
        qml/components/UVarBar.qml
        qml/components/ColorDot.qml
        qml/components/SidebarItem.qml
        qml/components/ToolChip.qml
        qml/components/MiddleScroll.qml
        qml/components/WheelBoost.qml
        qml/components/FocusScroll.qml
        qml/components/VideoPreview.qml
        qml/components/UWindowResizer.qml
)

# PUBLIC src/ so consumers include <capture/ScreenCastSession.h>,
# <theme/ThemeController.h>, <media/FfmpegUtil.h> etc. The per-subdir PRIVATE
# entries are for qmltyperegistration, which includes QML_ELEMENT headers
# (ThemeController.h) by basename.
target_include_directories(unisic-kit
    PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    PRIVATE src/capture src/record src/theme src/media src/hotkeys)

target_link_libraries(unisic-kit PUBLIC
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus)

# Symbolic icon set. PREFIX "/" gives ":/resources/icons/sym/<name>.svg",
# exactly the path IconImageProvider::tintedBundled() looks up.
file(GLOB UNISIC_KIT_SYM_ICONS CONFIGURE_DEPENDS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
     resources/icons/sym/*.svg)
qt_add_resources(unisic-kit "sym_icons" PREFIX "/" FILES ${UNISIC_KIT_SYM_ICONS})

target_sources(unisic-kit PRIVATE
    src/record/PipeWireGrabber.h src/record/PipeWireGrabber.cpp)
target_link_libraries(unisic-kit PUBLIC PkgConfig::PIPEWIRE)
target_compile_definitions(unisic-kit PUBLIC HAVE_PIPEWIRE)

# X11 frame capture (XShmGrabber). Additive: the Wayland/PipeWire path is
# untouched; this backend is only selected at runtime on an X11 session, so
# both are always compiled in and the CHOICE stays a runtime one.
target_sources(unisic-kit PRIVATE
    src/record/X11ShmGrabber.h src/record/X11ShmGrabber.cpp)
target_link_libraries(unisic-kit PUBLIC PkgConfig::X11)
target_compile_definitions(unisic-kit PUBLIC HAVE_X11)

# Native X11 global hotkeys (X11Hotkeys). Additive as well: the KGlobalAccel and
# GlobalShortcuts-portal paths a consumer owns are untouched - this backend is
# only selected at runtime on an xcb session, and only where those are absent.
target_sources(unisic-kit PRIVATE
    src/hotkeys/X11Hotkeys.h src/hotkeys/X11Hotkeys.cpp)
target_link_libraries(unisic-kit PUBLIC PkgConfig::XCBX11)
target_compile_definitions(unisic-kit PUBLIC HAVE_X11_HOTKEYS)

# KWin-native screencasting (zkde_screencast_unstable_v1, the Spectacle path).
# The app names the capture source itself: no portal share dialog, no restore
# tokens. Consumers still gate the RUNTIME choice on
# KWinScreencasting::isAvailable(), which is false off KWin or when the app's
# desktop file lacks X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1; what
# is gone is the build ever shipping without the code.
# Needs Qt6 WaylandClient (+ its wayland-scanner tooling), the Qt6 GUI private
# headers (qpa/qplatformnativeinterface.h, for the per-screen wl_output) and
# plasma-wayland-protocols.
find_package(Qt6 REQUIRED COMPONENTS WaylandClient)
find_package(PlasmaWaylandProtocols 1.7 QUIET)
if(NOT PlasmaWaylandProtocols_FOUND)
    unisic_kit_require_failed("plasma-wayland-protocols >= 1.7"
        "silent KWin-native recording; every clip on Plasma would open the portal share dialog"
        "plasma-wayland-protocols-devel" "plasma-wayland-protocols"
        "plasma-wayland-protocols" "plasma-wayland-protocols-devel")
endif()

# The Qt6 GUI private headers arrive by one of two routes. Normally there is a
# GuiPrivate component whose config file carries the include dirs. Debian 13
# (trixie) is the exception that made this branch necessary: qt6-base-private-dev
# installs the headers but NO Qt6GuiPrivateConfig.cmake at all (sid moved the
# config into qt6-base-dev), so the component probe fails on a system that has
# everything the code needs. Rather than let that distro build a crippled
# package, locate the header directly. Route taken is printed below, because a
# fallback nobody can see is how this class of bug survives in the first place.
find_package(Qt6 QUIET COMPONENTS GuiPrivate)
if(TARGET Qt6::GuiPrivate)
    set(_unisic_kit_qtprivate_route "Qt6::GuiPrivate component")
else()
    # Layout of an installed Qt: <headers>/QtGui is public, and the private
    # tree sits at <headers>/QtGui/<version>/QtGui, which is the directory that
    # has to be on the include path for <qpa/qplatformnativeinterface.h> to
    # resolve. Qt6Gui_INCLUDE_DIRS gives the public dirs to derive it from.
    set(_unisic_kit_qpa_hints "")
    foreach(_unisic_kit_inc IN LISTS Qt6Gui_INCLUDE_DIRS)
        list(APPEND _unisic_kit_qpa_hints
            "${_unisic_kit_inc}/${Qt6Gui_VERSION}/QtGui"
            "${_unisic_kit_inc}/${Qt6_VERSION}/QtGui")
    endforeach()
    find_path(UNISIC_KIT_QPA_INCLUDE_DIR
        NAMES qpa/qplatformnativeinterface.h
        HINTS ${_unisic_kit_qpa_hints}
        DOC "Qt6 GUI private header dir (fallback for distros shipping no Qt6GuiPrivateConfig.cmake)")
    if(NOT UNISIC_KIT_QPA_INCLUDE_DIR)
        unisic_kit_require_failed("the Qt6 GUI private headers (qpa/qplatformnativeinterface.h)"
            "silent KWin-native recording; every clip on Plasma would open the portal share dialog"
            "qt6-qtbase-private-devel" "qt6-base-private-dev"
            "qt6-base" "qt6-gui-private-devel")
    endif()
    set(_unisic_kit_qtprivate_route "header fallback at ${UNISIC_KIT_QPA_INCLUDE_DIR}")
endif()

qt6_generate_wayland_protocol_client_sources(unisic-kit FILES
    ${PLASMA_WAYLAND_PROTOCOLS_DIR}/zkde-screencast-unstable-v1.xml)
target_sources(unisic-kit PRIVATE
    src/capture/KWinScreencasting.h src/capture/KWinScreencasting.cpp)
target_link_libraries(unisic-kit PUBLIC Qt6::WaylandClient)
target_compile_definitions(unisic-kit PUBLIC HAVE_KWIN_SCREENCAST)
if(TARGET Qt6::GuiPrivate)
    target_link_libraries(unisic-kit PRIVATE Qt6::GuiPrivate)
else()
    target_include_directories(unisic-kit PRIVATE ${UNISIC_KIT_QPA_INCLUDE_DIR})
endif()
message(STATUS "unisic-kit: Qt6 GUI private headers via ${_unisic_kit_qtprivate_route}")

# The gate state, handed to the parent project so it can write ONE
# machine-readable manifest that CI asserts on. All four are unconditionally ON
# by the time this runs: anything else stopped the configure above. The list
# exists so a future gate cannot be added here and forgotten there, and so the
# assertion can tell the kit's HAVE_PIPEWIRE from the app's.
if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    set(UNISIC_KIT_FEATURES
        "HAVE_PIPEWIRE;HAVE_X11;HAVE_X11_HOTKEYS;HAVE_KWIN_SCREENCAST"
        PARENT_SCOPE)
endif()
