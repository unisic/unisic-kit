# Windows (MinGW-w64, MSYS2 UCRT64) platform block of unisic-kit, included by
# CMakeLists.txt in place of the Linux backends. Every Linux backend class keeps
# its header and gets a *_win.cpp sibling: hotkeys are real (RegisterHotKey),
# the direct-grab recording source is real (X11ShmGrabber_win: DXGI Desktop
# Duplication with a GDI fallback), PipeWire and KWin screencasting are stubs
# that report "unavailable", so the shared code that names them links and
# takes its existing fallback path. Nothing here touches the Linux build.

target_sources(unisic-kit PRIVATE
    src/record/PipeWireGrabber.h src/record/PipeWireGrabber_win.cpp
    src/record/X11ShmGrabber.h src/record/X11ShmGrabber_win.cpp
    src/hotkeys/X11Hotkeys.h src/hotkeys/X11Hotkeys_win.cpp
    src/capture/KWinScreencasting.h src/capture/KWinScreencasting_win.cpp)
target_link_libraries(unisic-kit PUBLIC user32)
target_link_libraries(unisic-kit PRIVATE gdi32 d3d11 dxgi)

# POSIX shims for MinGW (fsync, O_CLOEXEC, fcntl...), force-included so shared
# sources need no #ifdef. PUBLIC because the app's TUs call the same functions.
# C/C++ only, so a resource (.rc) compile never sees it.
target_compile_options(unisic-kit PUBLIC
    "$<$<COMPILE_LANGUAGE:C,CXX>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/src/platform/win/unisic_posix_compat.h>")

if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    set(UNISIC_KIT_FEATURES "HAVE_WIN32_HOTKEYS" PARENT_SCOPE)
endif()
