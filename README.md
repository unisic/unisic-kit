# unisic-kit

`unisic-kit` is the shared foundation of [Unisic](https://github.com/unisic/unisic)
and Unisic Studio. It bundles the C++ and QML pieces that both applications
need in common, so they don't drift apart:

- **C++ static library**
  - Portal `ScreenCastSession` (XDG Desktop Portal ScreenCast setup)
  - `KWinScreencasting` (KWin-native zkde_screencast client — record a named
    output/region/window with no portal dialog; optional, needs the
    `X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1` desktop-file grant)
  - `PortalRequest` (portal D-Bus request/response handling)
  - `IScreenGrabber` (the backend-agnostic frame-source contract both grabbers
    implement, so a consumer's encoder holds one pointer either way)
  - `PipeWireGrabber` (PipeWire frame capture — portal fd or default daemon)
  - `X11ShmGrabber` (XShm frame capture straight off the X server, the frame
    source on an X11 session where there is no working ScreenCast portal;
    optional, needs libX11 + libXext + libXfixes)
  - `X11Hotkeys` (XGrabKey global hotkeys for X11 sessions without KGlobalAccel
    or a usable GlobalShortcuts portal; optional, needs libX11 + libxcb) and
  - `ShortcutKeyMap` (header-only Qt-portable → X-keysym/GTK-accelerator
    vocabulary, shared by the grabs above and by desktop custom-shortcut stores)
  - `ThemeController` (light/dark theme + accent color state)
  - `IconImageProvider` (QML image provider for symbolic icons)
  - `ConfigPath` (XDG-aware config path resolution)

- **`Unisic.Kit` QML module**
  - `Theme` singleton (colors, spacing, typography tokens)
  - The `U*` component design system (`UButton`, `UCard`, `UIcon`,
    `UIconButton`, `USplitIconButton`, `UComboBox`, `UValueCombo`,
    `UMenuButton`, `UConfirmDialog`, `UColorPopup`, `UHoverTip`, `USwitch`,
    `USlider`, `USettingRow`, `UTextField`, `UFilterChip`, the hotkey editors
    `UShortcutRecorder`/`UShortcutList`/`UShortcutsHelp` (host app supplies
    `formatKey` and reacts to `captureStateChanged` — see the files' doc
    comments), and supporting components like `ColorDot`, `SidebarItem`,
    `ToolChip`, `MiddleScroll`, `WheelBoost`, `VideoPreview`)
  - Symbolic icon set (`resources/icons/sym/`)

## License

GPLv3 — see [LICENSE](LICENSE).

## Building

Requires **C++20**, **Qt 6.5+**, and **CMake** (Ninja recommended).

Build dependencies (Fedora package names; use your distro's equivalents):

- `qt6-qtbase-devel` — Core, Gui, DBus
- `qt6-qtdeclarative-devel` — Quick, Qml, the QML module tooling
- `qt6-qtsvg-devel` — SVG image format plugin (renders the bundled symbolic icons)
- `pipewire-devel` *(optional)* — enables `PipeWireGrabber` screen-frame capture.
  Without it the kit still builds; only `PipeWireGrabber` is dropped and a
  warning is printed at configure time.
- `libX11-devel libXext-devel libXfixes-devel` *(optional)* - enables
  `X11ShmGrabber` (`HAVE_X11`): recording on an X11 session.
- `libX11-devel libxcb-devel` *(optional)* - enables `X11Hotkeys`
  (`HAVE_X11_HOTKEYS`): global hotkeys on an X11 session. Deliberately a
  separate gate from the one above; either can be built without the other.

Every optional gate is additive. The Wayland paths (portal + PipeWire,
KGlobalAccel/portal hotkeys) are untouched by the X11 ones, which are selected
at runtime only when `QGuiApplication::platformName() == "xcb"`.

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

This produces the static library `libunisic-kit.a` and the `Unisic.Kit` QML
module (under `build/qmlmod/Unisic/Kit/`).

## Usage

`unisic-kit` is not distributed as a prebuilt binary SDK. It is consumed as a
**git submodule** and built together with the consuming application from
source (Unisic and Unisic Studio both do this).

```sh
git submodule add <unisic-kit-repo-url> external/unisic-kit
```

Then in the consuming app's `CMakeLists.txt`:

```cmake
add_subdirectory(external/unisic-kit)
target_link_libraries(myapp PRIVATE unisic-kit unisic-kitplugin)
```

C++ headers are exported under `src/`, so consumers include
`<capture/ScreenCastSession.h>`, `<theme/ThemeController.h>`,
`<media/FfmpegUtil.h>`, etc. The QML side imports `import Unisic.Kit`.

The consuming app names its config file once at startup (defaults to `unisic`)
and wires the icon image provider onto its QML engine:

```cpp
UnisicKit::setConfigName("unisic-studio"); // ~/.config/unisic-studio/unisic-studio.conf
engine.addImageProvider("icon", new IconImageProvider(nullptr));
```

`ThemeController` and `Theme` register declaratively into the `Unisic.Kit`
module — do not register them imperatively.

### Cursor-metadata capture

The capture stack can record the pointer *out of band* instead of burning it
into the frames, so a post-production consumer (Unisic Studio) can track and
re-render it. It is fully opt-in and default-off. Start the portal session with
`ScreenCastSession::start(ScreenCastSession::CursorMode::Metadata, …)`; the kit
only requests metadata when the portal advertises it in `AvailableCursorModes`,
otherwise it transparently falls back to `Embedded`, so read
`effectiveCursorMode()` after `ready()` to learn what was negotiated. When it is
`Metadata`, pass `wantCursorMeta=true` to `PipeWireGrabber::start(fd, node, fps,
true)`. The grabber then attaches `SPA_META_Header` + `SPA_META_Cursor` to the
buffers and, per frame, appends a `CursorSample` (`tMonoNs`, stream-pixel `x/y`,
`visible`, `shapeId`) to an internal bounded buffer you drain with
`takeCursorSamples()`; each distinct cursor bitmap is emitted once as
`cursorShapeChanged(int id, QImage image, QPoint hotspot)` (emitted off the
PipeWire thread — connect it queued/auto). `latestFrame()` takes an optional
`qint64 *ptsNs` out-param stamped from the same `CLOCK_MONOTONIC` clock as the
samples, so frames and cursor motion map onto one timeline. Requires the
optional `pipewire-devel` build (`HAVE_PIPEWIRE`).

## Provenance

This repository was extracted from the Unisic project. See
[UPSTREAM.md](UPSTREAM.md) for the source commit, full file manifest, and
instructions for diffing/syncing against upstream.
