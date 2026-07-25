cmake_minimum_required(VERSION 3.21)
# C alongside CXX: the wayland-scanner output for zkde_screencast (the
# *-protocol.c interface definitions) is plain C — without the language the
# generated file is silently not compiled and the interface symbol is missing
# at link time.
project(unisic-kit VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Kit needs no Widgets: ThemeController/IconImageProvider live entirely on
# Gui + Quick + Qml, and the capture stack is Core + DBus (+ optional PipeWire).
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(PkgConfig REQUIRED)
# PipeWire frame capture is OPTIONAL: without it the kit builds fine, only
# PipeWireGrabber is dropped (mirrors Unisic's CMakeLists).
pkg_check_modules(PIPEWIRE IMPORTED_TARGET libpipewire-0.3)
# X11 (XShm + XFixes) frame capture is OPTIONAL too: enables X11ShmGrabber, the
# frame source chosen at runtime on an X11 session. Needs libX11 (core), libXext
# (MIT-SHM: XShmGetImage) and libXfixes (hardware-cursor capture).
pkg_check_modules(X11 IMPORTED_TARGET x11 xext xfixes)
# Native X11 global hotkeys (XGrabKey) are a SEPARATE optional gate: they need
# libX11 (grab + keysyms) and libxcb (the KeyPress event Qt hands the native
# event filter), but NOT the XShm/XFixes pair the frame grabber wants. A
# consumer can end up with hotkeys and no X11 recording, or the reverse.
pkg_check_modules(XCBX11 IMPORTED_TARGET x11 xcb)

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
    # dir named after the URI would collide with other paths — mirror Unisic's
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
        qml/components/ColorDot.qml
        qml/components/SidebarItem.qml
        qml/components/ToolChip.qml
        qml/components/MiddleScroll.qml
        qml/components/WheelBoost.qml
        qml/components/FocusScroll.qml
        qml/components/VideoPreview.qml
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

if(PIPEWIRE_FOUND)
    target_sources(unisic-kit PRIVATE
        src/record/PipeWireGrabber.h src/record/PipeWireGrabber.cpp)
    target_link_libraries(unisic-kit PUBLIC PkgConfig::PIPEWIRE)
    target_compile_definitions(unisic-kit PUBLIC HAVE_PIPEWIRE)
    message(STATUS "unisic-kit: PipeWire capture enabled (HAVE_PIPEWIRE=ON)")
else()
    message(WARNING "libpipewire-0.3 not found — PipeWireGrabber (screen frame capture) will be unavailable")
endif()

# X11 frame capture (XShmGrabber). Additive: the Wayland/PipeWire path is
# untouched; this backend is only selected at runtime on an X11 session.
if(X11_FOUND)
    target_sources(unisic-kit PRIVATE
        src/record/X11ShmGrabber.h src/record/X11ShmGrabber.cpp)
    target_link_libraries(unisic-kit PUBLIC PkgConfig::X11)
    target_compile_definitions(unisic-kit PUBLIC HAVE_X11)
    message(STATUS "unisic-kit: X11 (XShm) screen capture enabled (HAVE_X11=ON)")
else()
    message(STATUS "unisic-kit: X11 capture disabled (needs libX11 + libXext + libXfixes) - X11-session recording unavailable")
endif()

# Native X11 global hotkeys (X11Hotkeys). Additive as well: the KGlobalAccel and
# GlobalShortcuts-portal paths a consumer owns are untouched - this backend is
# only selected at runtime on an xcb session, and only where those are absent.
if(XCBX11_FOUND)
    target_sources(unisic-kit PRIVATE
        src/hotkeys/X11Hotkeys.h src/hotkeys/X11Hotkeys.cpp)
    target_link_libraries(unisic-kit PUBLIC PkgConfig::XCBX11)
    target_compile_definitions(unisic-kit PUBLIC HAVE_X11_HOTKEYS)
    message(STATUS "unisic-kit: X11 global hotkeys enabled (HAVE_X11_HOTKEYS=ON)")
else()
    message(STATUS "unisic-kit: X11 global hotkeys disabled (needs libX11 + libxcb) - non-KDE X11 falls back to portal/compositor binds")
endif()

# Optional: KWin-native screencasting (zkde_screencast_unstable_v1 — the
# Spectacle path). The app names the capture source itself: no portal share
# dialog, no restore tokens. Consumers gate on HAVE_KWIN_SCREENCAST and fall
# back to the portal when KWinScreencasting::isAvailable() is false (non-KWin,
# or the app's desktop file lacks
# X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1).
# Needs Qt6 WaylandClient (+ its wayland-scanner tooling), Qt6 GuiPrivate (qpa
# native interface for the per-screen wl_output) and plasma-wayland-protocols.
# GuiPrivate is its own find_package component (distros ship the private
# configs separately — e.g. Fedora's qt6-qtbase-private-devel).
find_package(Qt6 QUIET COMPONENTS WaylandClient GuiPrivate)
find_package(PlasmaWaylandProtocols 1.7 QUIET)
if(TARGET Qt6::WaylandClient AND TARGET Qt6::GuiPrivate AND PlasmaWaylandProtocols_FOUND)
    qt6_generate_wayland_protocol_client_sources(unisic-kit FILES
        ${PLASMA_WAYLAND_PROTOCOLS_DIR}/zkde-screencast-unstable-v1.xml)
    target_sources(unisic-kit PRIVATE
        src/capture/KWinScreencasting.h src/capture/KWinScreencasting.cpp)
    target_link_libraries(unisic-kit PUBLIC Qt6::WaylandClient PRIVATE Qt6::GuiPrivate)
    target_compile_definitions(unisic-kit PUBLIC HAVE_KWIN_SCREENCAST)
    message(STATUS "unisic-kit: KWin-native screencasting enabled (HAVE_KWIN_SCREENCAST=ON)")
else()
    message(STATUS "unisic-kit: KWin-native screencasting disabled (needs qt6-qtwayland-devel + plasma-wayland-protocols) — recording falls back to the portal everywhere")
endif()
