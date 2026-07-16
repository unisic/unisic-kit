#pragma once
#include <QString>
#include <QSet>

class QProcess;

// ffmpeg helpers extracted from Unisic's GifRecorder so Unisic and Unisic
// Studio share one probe/escalation/filter path. Semantics are unchanged from
// the originals; only the signatures were lifted out of GifRecorder (no
// recorder members are referenced).
namespace FfmpegUtil {

// Thread-safe magic-static cache of the video encoders the ffmpeg in PATH
// advertises. An EMPTY set means the probe itself failed (no ffmpeg) — callers
// treat that as "assume usable" so the real "ffmpeg could not be started" path
// reports the problem. The first caller runs the probe; concurrent callers
// block until it finishes, which makes an off-thread warm-up safe.
const QSet<QString> &encoders();

// Whether `name` is an encoder this ffmpeg can use — true also when the probe
// failed (empty set), so a preferred encoder is kept rather than rejected.
bool encoderUsable(const QString &name);

// Whether a hardware H.264 encoder is usable now: "vaapi" needs h264_vaapi AND
// a render node at /dev/dri/renderD128; "nvenc" needs h264_nvenc.
bool hardwareEncoderAvailable(const QString &id);

// GIF two-pass palette filter strings. quality: 0 = fast/small, 1 = balanced,
// 2 = best. gifPaletteGenFilter feeds pass 1 (palettegen), gifPaletteUseFilter
// feeds pass 2 (paletteuse); the dither choice scales with quality.
QString gifPaletteGenFilter(int quality);
QString gifPaletteUseFilter(int quality);

// Non-blocking graceful teardown of a QProcess. Disconnects it, then (if still
// running) closeWriteChannel() -> terminate() -> SIGKILL after 1 s. The process
// reaps itself (finished -> deleteLater), so this never blocks the caller. The
// passed pointer is nulled.
void stopProcess(QProcess *&process);

} // namespace FfmpegUtil
