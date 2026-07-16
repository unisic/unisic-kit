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

## Usage

`unisic-kit` is not distributed as a prebuilt binary SDK. It is consumed as a
**git submodule** and built together with the consuming application from
source (Unisic and Unisic Studio both do this).

```sh
git submodule add <unisic-kit-repo-url> external/unisic-kit
```

CMake build files (so the consuming app can `add_subdirectory()` this kit and
link against it, and so the QML module registers as `Unisic.Kit`) are not
present yet — they arrive in a follow-up commit.

## Provenance

This repository was extracted from the Unisic project. See
[UPSTREAM.md](UPSTREAM.md) for the source commit, full file manifest, and
instructions for diffing/syncing against upstream.
