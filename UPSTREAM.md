# Upstream provenance

`unisic-kit` was extracted from the [Unisic](https://github.com/unisic/unisic)
project as a shared foundation library ("kit") for Unisic and Unisic Studio.

- **Source repository:** github.com/unisic/unisic
- **Source commit:** `c2c2ab825a51476011df27d335d7a6331e33f949`
- **Extraction date:** 2026-07-16

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

## Local modifications

The bootstrap copied the files above verbatim. The following adaptations were
then applied on top to make the kit a self-contained standalone library — when
syncing a file from upstream, re-apply its note below.

### Adapted copies

| File | What changed / why |
| --- | --- |
| `src/ConfigPath.h` | Rewritten from the hardcoded Unisic path (dev-build/legacy/sounds helpers) into a parameterized `UnisicKit` namespace: `setConfigName()` names the config once at startup, `filePath()`/`configDir()` derive from it. Defaults to `"unisic"`, so the historical path is unchanged. |
| `src/theme/ThemeController.h` | `UnisicConfig::filePath()` → `UnisicKit::filePath()` to match the reworked `ConfigPath.h`. Only line changed. |
| `qml/Theme.qml`, `qml/components/*.qml` (20 files) | `import Unisic` → `import Unisic.Kit` (the kit's QML module URI). |
| `qml/components/USwitch.qml`, `qml/components/VideoPreview.qml` | Genericized illustrative comments that named the app facade (`App.settings.x`, `App.capVideoPlayback`); no functional/binding change — both components were already self-contained via their own properties/signals. |

### Extracted (NOT verbatim copies — lifted out of larger upstream files)

| File | Extracted from | What / why |
| --- | --- | --- |
| `src/SettingMacro.h` | `unisic:src/Settings.h` | Just the `U_SETTING` macro block (getter / early-return setter / debounce-timer start / NOTIFY emit), byte-identical, plus include guard and the `<QSettings>`/`<QTimer>` includes the macro operates on. The `Settings` class itself is NOT copied. |
| `src/media/FfmpegUtil.h`, `src/media/FfmpegUtil.cpp` | `unisic:src/record/GifRecorder.cpp` | The ffmpeg encoder probe (thread-safe magic-static cache + `encoderUsable`/`hardwareEncoderAvailable`), the GIF palettegen/paletteuse filter builders, and the non-blocking `stopProcess()` QProcess escalation. Lifted into a free-function `FfmpegUtil` namespace (no `GifRecorder` members); `stopProcess` broadens its disconnect from `p→this` to all of `p`'s connections since there is no owning object. No recording logic copied. |

### Feature additions (kit-side, ahead of upstream)

Additive, default-off changes authored in the kit for Unisic Studio M2
(PipeWire cursor-metadata capture). Existing upstream call sites compile and
behave identically when the new options are not requested — when syncing these
files from upstream, re-apply the additions on top rather than reverting them.

| File | What was added |
| --- | --- |
| `src/capture/ScreenCastSession.h/.cpp` | `enum class CursorMode { Hidden=1, Embedded=2, Metadata=4 }`; a `start(CursorMode, …)` overload (the existing `start(bool includeCursor, …)` now delegates: `true`→Embedded, `false`→Hidden); `AvailableCursorModes` portal negotiation (Metadata requested only when advertised, else falls back to Embedded — cached like the `version` probe, successes only); `effectiveCursorMode()` getter the consumer reads after `ready()`. The blocking `screenCastPortalVersion()` was refactored to share one `screenCastPortalProperty()` Properties.Get helper with the new cursor-modes probe. |
| `src/record/PipeWireGrabber.h/.cpp` | `start(…, bool wantCursorMeta=false)`; announces `SPA_PARAM_Meta` (Header + Cursor, RANGE-sized bitmap) in the Format handler; parses `spa_meta_header` pts + `spa_meta_cursor` in `on_process`; `cursorShapeChanged(int,QImage,QPoint)` signal (once per new shape, bitmap→QImage cache owned by the PipeWire thread); `CursorSample` struct + `takeCursorSamples()` drain (mutex-guarded, bounded ring, drop-oldest); `latestFrame()` gained an optional `qint64 *ptsNs` out-param stamped from the same CLOCK_MONOTONIC pts source as the samples. Also cast the `SPA_FRACTION(cappedFps, …)` args to `uint32_t` to clear a pre-existing `-Wnarrowing` warning. All new code is under the existing `HAVE_PIPEWIRE` CMake gate. |

### Authored for the kit (no upstream origin)

- `CMakeLists.txt` — static `unisic-kit` library + `Unisic.Kit` QML module.
  Modelled on Unisic's `CMakeLists.txt` (optional-PipeWire guard, `qmlmod/`
  output dir, symbolic-icon resource prefix) but reduced to the kit's sources.

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
