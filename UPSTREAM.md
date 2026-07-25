# Upstream provenance

`unisic-kit` was extracted from the [Unisic](https://github.com/unisic/unisic)
project as a shared foundation library ("kit") for Unisic and Unisic Studio.

- **Source repository:** github.com/unisic/unisic
- **Source commit (bootstrap):** `c2c2ab825a51476011df27d335d7a6331e33f949`
- **Extraction date:** 2026-07-16
- **Last full sync:** `45ff731` (2026-07-23) — the commit at which Unisic
  switched from local copies to consuming the kit as a git submodule. From that
  point on the kit IS the single source for the files below; the "diffing
  against upstream" workflow at the bottom only matters for history archaeology.

All files listed below were copied verbatim (byte-for-byte, no content
changes) from the source commit at extraction time. Any adaptation for
standalone build/use happens in later commits on top of this bootstrap.

## Manifest

| File in unisic-kit | Origin path in unisic |
| --- | --- |
| `LICENSE` | `LICENSE` |
| `src/capture/PortalRequest.h` | `src/capture/PortalRequest.h` |
| `src/capture/PortalRequest.cpp` | `src/capture/PortalRequest.cpp` |
| `src/capture/ScreenCastSession.h` | `src/capture/ScreenCastSession.h` |
| `src/capture/ScreenCastSession.cpp` | `src/capture/ScreenCastSession.cpp` |
| `src/record/PipeWireGrabber.h` | `src/record/PipeWireGrabber.h` |
| `src/record/PipeWireGrabber.cpp` | `src/record/PipeWireGrabber.cpp` |
| `src/theme/ThemeController.h` | `src/theme/ThemeController.h` |
| `src/theme/ThemeController.cpp` | `src/theme/ThemeController.cpp` |
| `src/theme/IconImageProvider.h` | `src/theme/IconImageProvider.h` |
| `src/theme/IconImageProvider.cpp` | `src/theme/IconImageProvider.cpp` |
| `src/ConfigPath.h` | `src/ConfigPath.h` |
| `qml/Theme.qml` | `qml/Theme.qml` |
| `qml/components/UButton.qml` | `qml/components/UButton.qml` |
| `qml/components/UCard.qml` | `qml/components/UCard.qml` |
| `qml/components/UIcon.qml` | `qml/components/UIcon.qml` |
| `qml/components/UIconButton.qml` | `qml/components/UIconButton.qml` |
| `qml/components/USplitIconButton.qml` | `qml/components/USplitIconButton.qml` |
| `qml/components/UComboBox.qml` | `qml/components/UComboBox.qml` |
| `qml/components/UValueCombo.qml` | `qml/components/UValueCombo.qml` |
| `qml/components/UMenuButton.qml` | `qml/components/UMenuButton.qml` |
| `qml/components/UConfirmDialog.qml` | `qml/components/UConfirmDialog.qml` |
| `qml/components/UColorPopup.qml` | `qml/components/UColorPopup.qml` |
| `qml/components/UHoverTip.qml` | `qml/components/UHoverTip.qml` |
| `qml/components/USwitch.qml` | `qml/components/USwitch.qml` |
| `qml/components/USlider.qml` | `qml/components/USlider.qml` |
| `qml/components/UTextField.qml` | `qml/components/UTextField.qml` |
| `qml/components/UFilterChip.qml` | `qml/components/UFilterChip.qml` |
| `qml/components/ColorDot.qml` | `qml/components/ColorDot.qml` |
| `qml/components/SidebarItem.qml` | `qml/components/SidebarItem.qml` |
| `qml/components/ToolChip.qml` | `qml/components/ToolChip.qml` |
| `qml/components/MiddleScroll.qml` | `qml/components/MiddleScroll.qml` |
| `qml/components/WheelBoost.qml` | `qml/components/WheelBoost.qml` |
| `qml/components/VideoPreview.qml` | `qml/components/VideoPreview.qml` |
| `resources/icons/sym/*.svg` (66 files) | `resources/icons/sym/*.svg` |

Added at the 45ff731 sync (origin paths in unisic):

| File in unisic-kit | Origin path in unisic |
| --- | --- |
| `src/theme/ThemeJson.h` | `src/theme/ThemeJson.h` (verbatim) |
| `qml/components/USettingRow.qml` | `qml/components/USettingRow.qml` (import swap only) |
| `qml/components/UShortcutRecorder.qml` | `qml/components/UShortcutRecorder.qml` (genericized, see below) |
| `qml/components/UShortcutList.qml` | `qml/components/UShortcutList.qml` (genericized, see below) |
| `qml/components/UShortcutsHelp.qml` | `qml/components/UShortcutsHelp.qml` (import swap only) |

Added with the X11 backends (origin paths in unisic):

| File in unisic-kit | Origin path in unisic |
| --- | --- |
| `src/hotkeys/ShortcutKeyMap.h` | `src/hotkeys/ShortcutKeyMap.h` (verbatim; MOVED, no copy left upstream) |
| `src/hotkeys/X11Hotkeys.h` | `src/hotkeys/X11Hotkeys.h` (verbatim; MOVED) |
| `src/hotkeys/X11Hotkeys.cpp` | `src/hotkeys/X11Hotkeys.cpp` (verbatim; MOVED) |

These are moves, not copies: unisic deleted its versions in the same change and
now includes them from the kit (`<hotkeys/ShortcutKeyMap.h>`,
`<hotkeys/X11Hotkeys.h>`), so there is nothing left to keep in sync. Unisic's
`ShortcutBinder` (which writes desktop custom-shortcut stores) stays app-side
and consumes `ShortcutKeyMap` from here.

## Local modifications

The bootstrap copied the files above verbatim. The following adaptations were
then applied on top to make the kit a self-contained standalone library — when
syncing a file from upstream, re-apply its note below.

### Adapted copies

| File | What changed / why |
| --- | --- |
| `src/ConfigPath.h` | Rewritten from the hardcoded Unisic path (dev-build/legacy/sounds helpers) into a parameterized `UnisicKit` namespace: `setConfigName()` names the config once at startup, `filePath()`/`configDir()` derive from it. Defaults to `"unisic"`, so the historical path is unchanged. 45ff731 sync adds `setConfigFilePath()` — a full-path override for apps whose historical file name does not follow the `<name>/<name>.conf` derivation (Unisic's dev build keeps `unisic-dev/unisic.conf`); `configDir()` follows the override's directory so `themes/` stays next to the config file. |
| `src/theme/ThemeController.h/.cpp` | Synced to 45ff731 (custom-theme JSON scan/hot-reload/seeding, `themesFolder()`, watcher). Adaptation re-applied: `UnisicConfig::filePath()` → `UnisicKit::filePath()`. The decorative seed themes (`:/resources/themes/*.json`) are looked up in the RUNTIME qrc — the consuming app ships them (Unisic does); with none present, seeding is a no-op. |
| `qml/Theme.qml`, `qml/components/*.qml` | `import Unisic` → `import Unisic.Kit` (the kit's QML module URI). Theme.qml synced to 45ff731: decorative palettes (Catppuccin ×2, Dracula, Nord, Gruvbox) moved OUT of `_defs` into the app-seeded JSON files resolved via `ThemeController.customDefs`; recording-overlay tokens (`recBadge*`, `countdown*`, `keystroke*`) added. |
| `qml/components/USwitch.qml`, `qml/components/VideoPreview.qml` | Genericized illustrative comments that named the app facade (`App.settings.x`, `App.capVideoPlayback`); no functional/binding change — both components were already self-contained via their own properties/signals. |
| `qml/components/UShortcutRecorder.qml` | Genericized off the app facade: `App.formatShortcut(key, mods, scanCode)` → `property var formatKey` (host-supplied function, same signature), `App.setShortcutRecording(bool)` → `signal captureStateChanged(bool)` (also emitted `false` from `Component.onDestruction`). Visuals/behaviour unchanged. |
| `qml/components/UShortcutList.qml` | Passes `formatKey` through to its embedded recorder and re-emits `captureStateChanged`. |
| `qml/components/ColorDot.qml`, `SidebarItem.qml`, `UHoverTip.qml`, `UIconButton.qml`, `UTextField.qml`, `resources/icons/sym/configure.svg` | Synced verbatim to 45ff731 (+ import swap where applicable). |

### Extracted (NOT verbatim copies — lifted out of larger upstream files)

| File | Extracted from | What / why |
| --- | --- | --- |
| `src/SettingMacro.h` | `unisic:src/Settings.h` | Just the `U_SETTING` macro block (getter / early-return setter / debounce-timer start / NOTIFY emit), byte-identical, plus include guard and the `<QSettings>`/`<QTimer>` includes the macro operates on. The `Settings` class itself is NOT copied. |
| `src/media/FfmpegUtil.h`, `src/media/FfmpegUtil.cpp` | `unisic:src/record/GifRecorder.cpp` | The ffmpeg encoder probe (thread-safe magic-static cache + `encoderUsable`/`hardwareEncoderAvailable`), the GIF palettegen/paletteuse filter builders, and the non-blocking `stopProcess()` QProcess escalation. Lifted into a free-function `FfmpegUtil` namespace (no `GifRecorder` members); `stopProcess` broadens its disconnect from `p→this` to all of `p`'s connections since there is no owning object. No recording logic copied. 45ff731 sync: `hardwareEncoderAvailable` gained the upstream `av1-nvenc` id, and `GifRecorder::hardwareEncoderWorks` (the does-it-actually-encode probe with its mutex-guarded cache) moved here as `FfmpegUtil::hardwareEncoderWorks` — unisic's `GifRecorder` now calls these instead of carrying copies. |

### Feature additions (kit-side, ahead of upstream)

Additive, default-off changes authored in the kit for Unisic Studio M2
(PipeWire cursor-metadata capture). Existing upstream call sites compile and
behave identically when the new options are not requested — when syncing these
files from upstream, re-apply the additions on top rather than reverting them.

Upstream unisic later absorbed this feature (with fixes of its own); at the
45ff731 sync both files were re-based on the upstream versions and the
kit-only surface re-applied on top, so the kit is now a strict superset:

| File | State after the 45ff731 sync |
| --- | --- |
| `src/capture/ScreenCastSession.h/.cpp` | Upstream internals + the kit API kept: `enum class CursorMode { Hidden, Embedded, Metadata }` (upstream renamed the enumerators `CursorHidden/…` — the kit keeps the scoped names Studio compiles against), both `start()` overloads, internal Metadata→Embedded fallback, `effectiveCursorMode()`. New from upstream: public static `availableCursorModes()` (success-only cache), which `selectSources` now also uses. |
| `src/record/PipeWireGrabber.h/.cpp` | Re-based on upstream 45ff731 (premultiplied-alpha cursor formats, atomic `m_format`, decode-bitmap-on-every-`bitmap_offset` fix for KWin's in-place id reuse — the per-id shape cache is GONE, consumers re-key by id; transitive `SPA_PARAM_Meta` include fix for AppImage CI; no `pw_stream_get_time_n`). Kit extras re-applied: `latestFrame(out, seq, qint64 *ptsNs)` out-param + `m_ptsNs` stamped from the same CLOCK_MONOTONIC chain as `CursorSample::tMonoNs` (pts now computed for every buffer, not only under `wantCursorMeta`), cursor-state reset in `start()` for instance reuse, `uint32_t` cast in `SPA_FRACTION` (-Wnarrowing). |

### Authored for the kit (no upstream origin)

- `CMakeLists.txt` — static `unisic-kit` library + `Unisic.Kit` QML module.
  Modelled on Unisic's `CMakeLists.txt` (optional-PipeWire guard, `qmlmod/`
  output dir, symbolic-icon resource prefix) but reduced to the kit's sources.
- `src/capture/KWinScreencasting.{h,cpp}` — client of KWin's
  `zkde_screencast_unstable_v1` protocol (adapted from KDE Spectacle's
  `screencasting.{h,cpp}`, LGPL-2.1/3.0, SPDX headers kept): the app names the
  capture source (output / global-logical region / window uuid) and receives a
  PipeWire node id on the default session daemon — no portal share dialog, no
  restore tokens. Optional `HAVE_KWIN_SCREENCAST` build (Qt6 WaylandClient +
  GuiPrivate + plasma-wayland-protocols); the consuming app's desktop file must
  carry `X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1` or
  `isAvailable()` stays false and consumers fall back to the portal.
  `PipeWireGrabber::start()` takes fd `-1` for this path (default-daemon
  connect instead of the portal's `OpenPipeWireRemote` fd).
- `src/record/IScreenGrabber.h` - the abstract frame-source base both grabbers
  implement (`pixelFormat`/`latestFrame`/`takeCursorSamples`/`stop` + the
  `formatReady`/`streamError`/`cursorShapeChanged` signals; `CursorSample` moved
  here out of `PipeWireGrabber.h`). `start()` is deliberately NOT on the base -
  its arguments are per-backend (portal fd + node id vs. a root rect). A
  consumer's encoder holds an `IScreenGrabber *` and never learns which backend
  it got. Always compiled, so the signal wiring exists even with every optional
  backend off.
- `src/record/X11ShmGrabber.{h,cpp}` - XShm frame capture on a producer thread
  with its own `XOpenDisplay` (Xlib is not thread-safe across Qt's connection),
  falling back to `XGetImage` when `XShmAttach` fails; publishes into a 3-slot
  rotating pool under the same `++seq` contract as `PipeWireGrabber`, and polls
  `XFixesGetCursorImage` for `CursorSample`s because a root-window grab does not
  contain the hardware cursor. Optional `HAVE_X11`.
- `qml/UKeys.qml` - the design system's ONE keyboard-activation rule
  (`activate`/`claim`/`unmodified`), extracted from the guard that used to be
  hand-copied into every focusable component. Consumers call it too: an app-side
  control that writes its own `Keys.onSpacePressed`/`onReturnPressed`/
  `onEnterPressed` must go through it, or a chord like Ctrl+Return dies on that
  control. See the README section and the file's own comment (the only copy of
  the explanation).
- `qml/UFlyout.qml` - the design system's ONE flyout-containment rule
  (`margin`/`gap`/`minRoom`, `fitWidth`/`fitHeight`, `clampX`/`clampY`,
  `rooms`/`roomOn`, `sideAtOpen`/`sideNow`, `offsetY`), extracted from the
  placement arithmetic that used to be hand-copied into
  `UComboBox`/`UValueCombo`/`UMenuButton` - where it ran ONCE in
  `onAboutToShow` and so could not survive a window resize, a growing list or a
  `Flickable` scrolling under an open popup. Part of the work is Qt's: the
  popups are parented to their ANCHOR (not to `Overlay.overlay`) and set
  `margins`, which is what makes `QQuickPopupPositioner` re-clamp them on every
  one of those events. The kit keeps what a clamp cannot do: capping a flyout to
  the room on the side it is on (a clamp can only move it, so an uncapped list
  gets slid over its own field), choosing that side once per opening and holding
  it while it stays usable (re-choosing on every height change made an open
  dropdown jump across its own field while the user typed in its search box),
  and re-reading the fit as a BINDING that walks the anchor's parent chain. See
  the README section and the file's own comment (the only copy of the
  explanation, with the measurements behind each part).
- `qml/components/UNameBridge.qml` - the design system's ONE accessible-name
  bridge: pushes a row's caption into the mute control(s) next to it, as
  bindings, pruning controls that go away. `USettingRow` carries one; hand-built
  label+control rows in a consuming app add their own instead of re-implementing
  it.
- `src/hotkeys/X11Hotkeys.{h,cpp}` - passive `XGrabKey` root grabs on Qt's own X
  connection, delivered through a `QAbstractNativeEventFilter` (no second
  display, no thread). Grabs each combo across the Caps/Num lock mask variants,
  reports `XGrabKey` `BadAccess` back as a conflict id list. The header stays
  free of any `<X11/...>` include so Xlib's macros (`None`, `Bool`, `KeyPress`)
  do not leak into consumers. Optional `HAVE_X11_HOTKEYS`.

## Diffing / syncing against upstream

To compare `unisic-kit` against the current state of a file in `unisic`:

```sh
diff /path/to/unisic/<origin-path> /path/to/unisic-kit/<kit-path>
```

To see what changed upstream since the extraction commit, in the `unisic`
checkout:

```sh
git log c2c2ab825a51476011df27d335d7a6331e33f949..HEAD -- <origin-path>
git diff c2c2ab825a51476011df27d335d7a6331e33f949..HEAD -- <origin-path>
```

To pull an upstream update into `unisic-kit` manually, copy the updated file
over its counterpart from the manifest above, re-apply any local adaptation
on top, and note the new upstream commit hash in this file.
