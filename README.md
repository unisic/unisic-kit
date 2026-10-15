# unisic-kit

`unisic-kit` is the shared foundation of [Unisic](https://github.com/unisic/unisic)
and Unisic Studio. It bundles the C++ and QML pieces that both applications
need in common, so they don't drift apart:

- **C++ static library**
  - Portal `ScreenCastSession` (XDG Desktop Portal ScreenCast setup)
  - `KWinScreencasting` (KWin-native zkde_screencast client - record a named
    output/region/window with no portal dialog; always built, and at RUNTIME
    `isAvailable()` additionally wants the
    `X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1` desktop-file grant)
  - `PortalRequest` (portal D-Bus request/response handling)
  - `IScreenGrabber` (the backend-agnostic frame-source contract both grabbers
    implement, so a consumer's encoder holds one pointer either way)
  - `PipeWireGrabber` (PipeWire frame capture - portal fd or default daemon)
  - `X11ShmGrabber` (XShm frame capture straight off the X server, the frame
    source on an X11 session where there is no working ScreenCast portal;
    always built, needs libX11 + libXext + libXfixes)
  - `X11Hotkeys` (XGrabKey global hotkeys for X11 sessions without KGlobalAccel
    or a usable GlobalShortcuts portal; always built, needs libX11 + libxcb) and
  - `ShortcutKeyMap` (header-only Qt-portable → X-keysym/GTK-accelerator
    vocabulary, shared by the grabs above and by desktop custom-shortcut stores)
  - `ThemeController` (light/dark theme + accent color state)
  - `IconImageProvider` (QML image provider for symbolic icons)
  - `ConfigPath` (XDG-aware config path resolution)

- **`Unisic.Kit` QML module**
  - `Theme` singleton (colors, spacing, typography tokens)
  - `UKeys` singleton (the one keyboard-activation rule - see below),
    `UFlyout` singleton (the one flyout-containment rule - see below) and
    `UNameBridge` (the one accessible-name bridge for label+control rows)
  - The `U*` component design system (`UButton`, `UCard`, `UIcon`,
    `UIconButton`, `USplitIconButton`, `UComboBox`, `UValueCombo`,
    `UMenuButton`, `UConfirmDialog`, `UColorPopup`, `UHoverTip`, `USwitch`,
    `USlider`, `USettingRow`, `UTextField`, `UFilterChip`, the hotkey editors
    `UShortcutRecorder`/`UShortcutList`/`UShortcutsHelp` (host app supplies
    `formatKey` and reacts to `captureStateChanged` - see the files' doc
    comments), and supporting components like `ColorDot`, `SidebarItem`,
    `ToolChip`, `MiddleScroll`, `WheelBoost`, `VideoPreview`)
  - Symbolic icon set (`resources/icons/sym/`)

## License

GPLv3 - see [LICENSE](LICENSE).

## Building

Requires **C++20**, **Qt 6.5+**, and **CMake** (Ninja recommended).

**Every dependency below is required.** The kit has no optional ones: a missing
package stops the configure with a `FATAL_ERROR` naming it on Fedora, Debian,
Arch and openSUSE, rather than dropping a backend and letting a consuming
application ship a build that cannot do what its interface offers. The `HAVE_*`
names still identify their code paths, they simply cannot be off - a successful
configure exports all four to the consumer as `UNISIC_KIT_FEATURES`.

Build dependencies (Fedora package names; use your distro's equivalents):

- `qt6-qtbase-devel` - Core, Gui, DBus, and the Qt6 GUI **private** headers
  (`qt6-qtbase-private-devel`) for the per-screen `wl_output`
- `qt6-qtdeclarative-devel` - Quick, Qml, the QML module tooling
- `qt6-qtsvg-devel` - SVG image format plugin (renders the bundled symbolic icons)
- `qt6-qtwayland-devel` + `plasma-wayland-protocols-devel` (>= 1.7) -
  `KWinScreencasting` (`HAVE_KWIN_SCREENCAST`): KWin-native capture with no
  portal share dialog
- `pipewire-devel` - `PipeWireGrabber` (`HAVE_PIPEWIRE`): screen-frame capture
  on a Wayland session
- `libX11-devel libXext-devel libXfixes-devel` - `X11ShmGrabber` (`HAVE_X11`):
  recording on an X11 session
- `libX11-devel libxcb-devel` - `X11Hotkeys` (`HAVE_X11_HOTKEYS`): global
  hotkeys on an X11 session. Deliberately a separate probe from the one above,
  so a missing package is named exactly; both are mandatory.

Debian 13 (trixie) is the one distro that needs a detour: it installs the Qt6
GUI private headers but ships no `Qt6GuiPrivateConfig.cmake` at all, so the
`GuiPrivate` component probe fails on a system that has everything the code
needs. The build then locates `qpa/qplatformnativeinterface.h` directly and
prints which of the two routes it took.

Every backend is additive at RUNTIME. The Wayland paths (portal + PipeWire,
KGlobalAccel/portal hotkeys) are untouched by the X11 ones, which are selected
only when `QGuiApplication::platformName() == "xcb"`.

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
module - do not register them imperatively.

### Keyboard activation (`UKeys`)

Every focusable control - in the kit **and in the consuming app** - routes its
key handlers through the `UKeys` singleton, so the rule cannot drift between
them. Qt dispatches `Keys.onSpacePressed` / `onReturnPressed` / `onEnterPressed`
/ `onUpPressed` … *before* `Keys.onPressed`, regardless of the modifiers held,
and auto-accepts them, so an unguarded control silently swallows the window's
own chords (an editor's Ctrl+Enter dies the moment anything has focus).
`UKeys` declines those and lets them keep bubbling, while masking out
`KeypadModifier` so the numpad's own Enter still activates.

```qml
import Unisic.Kit

activeFocusOnTab: enabled
Keys.onSpacePressed:  (e) => UKeys.activate(e, root._activate)
Keys.onReturnPressed: (e) => UKeys.activate(e, root._activate)
Keys.onEnterPressed:  (e) => UKeys.activate(e, root._activate)
```

`_activate` is the control's single activation path - the same function the
`MouseArea` and `Accessible.onPressAction` call. Two lower-level entry points
cover the rest: `UKeys.claim(e)` is the same guard when a handler has more to do
than call one function (`if (!UKeys.claim(e)) return`), and `UKeys.unmodified(e)`
is the pure test for a plain `Keys.onPressed`, which arrives unaccepted and so
needs no write to decline. The full explanation lives in `qml/UKeys.qml`; do not
copy the modifier expression anywhere else.

### Row labels (`UNameBridge`)

A switch, a combo box, a slider and a bare text field are mute: the only thing
that names them is the caption of the row they sit in. `UNameBridge` pushes that
caption into them, so call sites do not repeat themselves. It is a plain
`QtObject`, so it never joins a layout:

```qml
UNameBridge {
    id: nameBridge
    targets: [slot, footerSlot]   // the Items holding the controls
    name: labelText.text
    description: subText.text
}
...
Item { id: slot; onChildrenChanged: nameBridge.refresh() }
```

A caption is one identity, so it can only be one control's name. A row holding
exactly **one** control hands the caption over as that control's
`accessibleName` (and the sub line as its description). A row whose slots hold
**several** gives it to none of them - naming both a combo box and the Refresh
button beside it "Application audio only" is worse than naming neither - so
those keep the names they give themselves (`UButton.text`,
`UIconButton.tooltip`, `ColorDot.dotColor`, a combo's current value) and the
caption is pushed into their `accessibleDescription` instead, which is what
tells three identical "Preview" buttons apart. A name set explicitly at the call
site always wins and is never taken back.

Each target is searched one wrapper deep, so a control inside the `Row`,
`Loader` or `Repeater` a call site puts in the slot is found too; deeper than
that belongs to a component that packs its own controls, and is left alone.

The `onChildrenChanged` hook is required on every target - it picks up controls
that arrive later and prunes the ones that go away; the bridge hooks the
wrappers it looks through the same way, so a `Loader` that loads or a `Repeater`
that re-models *inside* one still reaches it. Nothing else is:
`name`/`description` are installed as bindings, so a `qsTr()` caption or a
runtime-swapped hint stays live. `USettingRow` already carries one - hand-built
rows add their own.

### Flyout containment (`UFlyout`)

Every flyout - the dropdown lists, the action menus, the centred popups and the
hover tip - routes its geometry through the `UFlyout` singleton, so "a flyout
never hangs off the window" cannot drift between them. A flyout is clamped
inside the window on both axes with an 8px gutter and it shrinks - scrolling its
own content - rather than growing past a window edge or over the control it
belongs to. An anchored one opens below that control and above it when there is
no room below; the side is chosen once per opening and then held for as long as
it stays usable, so a list re-fits under a window resize without ever jumping
across its own field while the user is working in it.

Part of that is Qt's, and the split is what matters:

```qml
C.Popup {
    id: popup
    parent: root                                  // the ANCHOR, not the overlay
    margins: UFlyout.margin                       // Qt clamps, on every change
    property bool flyUp: false                    // the side, chosen at open
    readonly property real flyWant: Math.min(entries.length * rowH + 58, 340)
    readonly property var  flyFit: visible ? UFlyout.rooms(root, root._overlay, flyWant)
                                           : null
    onFlyFitChanged: flyUp = UFlyout.sideNow(flyUp, flyFit, opened)
    height: UFlyout.fitHeight(root._overlay, flyWant, UFlyout.roomOn(flyFit, flyUp))
    y: UFlyout.offsetY(popup, root, flyUp)
    onAboutToShow: flyUp = UFlyout.sideAtOpen(root, root._overlay, flyWant)
}
```

`QQuickPopup.margins` defaults to `-1`, which means *no clamping at all*; set it
and Qt's positioner re-runs on the popup's own size changes, on the anchor's
geometry, on every ancestor's geometry (a `Flickable` scrolling under an open
list drags the list along with it) and on the window resizing. That is why the
popup is parented to the anchor item and not to `Overlay.overlay` - and it costs
nothing, because a popup's visual item is reparented into the window overlay
when it opens whatever `parent` is, so it still escapes every `clip: true`
ancestor.

What is left for the kit is the three things Qt's clamp cannot do, because a
clamp can only *move* a popup: the height cap (Qt only auto-resizes a popup with
no explicit size, and the cap is against the room on the chosen side, not just
the window, or a list on a low anchor is slid back inside straight over its own
field), the above/below choice (a plain `Popup` has no flip), and re-reading the
fit. That last one is a binding, not a signal: `UFlyout.rooms()` adds up `y`
along the anchor's parent chain, so calling it from a binding captures a
dependency on the window size, the anchor and every item in between - which
`mapToItem()` cannot do. `sideNow()` is then the only thing allowed to change
the side while the flyout is up, and it holds the current side until that side
stops being usable. Plain overlay `Item`s that are not popups get no positioner
at all, so they clamp through `UFlyout.clampX()`/`clampY()` in their own
bindings. The full explanation, with the measurements behind each part, lives in
`qml/UFlyout.qml`; do not copy the arithmetic anywhere else.

### Wheel scrolling (`WheelBoost`)

`MiddleScroll` and `WheelBoost` are declared as children of the `Flickable` they
drive, and both stay out of everything else's way (wheel-only / middle-only,
`z: -1`):

```qml
Flickable {
    id: fl
    MiddleScroll { flickable: fl }
    WheelBoost { flickable: fl }
}
```

`WheelBoost` gives a mouse wheel a fixed `stepPx` per notch (220 by default),
ramps that up to `maxBoost` (3) while the notches keep arriving within
`boostWindowMs` (300) of each other, caps any one notch at 90% of the viewport,
and eases each step in over `settleMs` (110) so a boosted notch reads as motion
rather than a jump. Touchpads are untouched by all of it: their `pixelDelta`
stays 1:1 and unsmoothed. `settleMs: 0` restores the plain instant step and
`maxBoost: 1` the plain fixed one. An easing step yields the view the moment
anything else moves it, so the middle-click autoscroll beside it, a drag, or a
`positionViewAtIndex` always wins.

The default step suits a column of short rows. A view of **tall** rows should
raise it at the call site rather than change the default - one whole tile per
notch reads as crawling on a big window. Unisic's History grid asks for a row
and a half, and for a third of the viewport once about four and a half rows fit:

```qml
WheelBoost {
    flickable: grid
    stepPx: Math.max(Math.round(grid.cellHeight * 1.5), Math.round(grid.height / 3))
}
```

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
PipeWire thread - connect it queued/auto). `latestFrame()` takes an optional
`qint64 *ptsNs` out-param stamped from the same `CLOCK_MONOTONIC` clock as the
samples, so frames and cursor motion map onto one timeline. Runs on the
`pipewire-devel` path (`HAVE_PIPEWIRE`), which every build has.

## Provenance

This repository was extracted from the Unisic project. See
[UPSTREAM.md](UPSTREAM.md) for the source commit, full file manifest, and
instructions for diffing/syncing against upstream.
