# unisic-kit

`unisic-kit` is the shared foundation of [Unisic](https://github.com/unisic/unisic)
and Unisic Studio. It bundles the C++ and QML pieces that both applications
need in common, so they don't drift apart:

- **C++ static library**
  - Portal `ScreenCastSession` (XDG Desktop Portal ScreenCast setup)
  - `PortalRequest` (portal D-Bus request/response handling)
  - `PipeWireGrabber` (PipeWire frame capture)
  - `ThemeController` (light/dark theme + accent color state)
  - `IconImageProvider` (QML image provider for symbolic icons)
  - `ConfigPath` (XDG-aware config path resolution)

- **`Unisic.Kit` QML module**
  - `Theme` singleton (colors, spacing, typography tokens)
  - The `U*` component design system (`UButton`, `UCard`, `UIcon`,
    `UIconButton`, `USplitIconButton`, `UComboBox`, `UValueCombo`,
    `UMenuButton`, `UConfirmDialog`, `UColorPopup`, `UHoverTip`, `USwitch`,
    `USlider`, `UTextField`, `UFilterChip`, and supporting components like
    `ColorDot`, `SidebarItem`, `ToolChip`, `MiddleScroll`, `WheelBoost`,
    `VideoPreview`)
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

## Provenance

This repository was extracted from the Unisic project. See
[UPSTREAM.md](UPSTREAM.md) for the source commit, full file manifest, and
instructions for diffing/syncing against upstream.
