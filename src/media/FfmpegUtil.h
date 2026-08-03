#pragma once
#include <QString>
#include <QSet>

class QImage;
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

// Whether a hardware encoder is LISTED as usable now: "vaapi" needs h264_vaapi
// AND a render node at /dev/dri/renderD128; "nvenc" needs h264_nvenc;
// "av1-nvenc" (RTX 40+) needs av1_nvenc — the only hardware encoder a WebM can
// carry here.
bool hardwareEncoderAvailable(const QString &id);

// Does the encoder actually ENCODE, not just appear in -encoders? Measured
// necessity, not caution: ffmpeg may list vp9_vaapi/h264_vaapi and the render
// node may exist, yet the encode fails outright — the listing describes the
// ffmpeg build, the hardware behind it may not implement the codec. Encodes a
// tiny synthetic clip to /dev/null (~0.5 s), cached per encoder per process;
// thread-safe (the probe runs outside the cache lock, a concurrent duplicate
// probe is harmless).
bool hardwareEncoderWorks(const QString &id);

// GIF two-pass palette filter strings. quality: 0 = fast/small, 1 = balanced,
// 2 = best. gifPaletteGenFilter feeds pass 1 (palettegen), gifPaletteUseFilter
// feeds pass 2 (paletteuse); the dither choice scales with quality.
QString gifPaletteGenFilter(int quality);
QString gifPaletteUseFilter(int quality);

// Encodes ONE image into the bytes of a still GIF. Qt cannot do this itself:
// the bundled gif plugin reads and never writes (QImageWriter::
// supportedImageFormats() lists no gif), so the still path goes through the
// same ffmpeg the recorder already requires.
//
// Both palette passes live in one filter graph here, which would be wrong for
// a recording (palettegen buffers every frame until EOF - gigabytes) and is
// right for a single frame: that one frame IS the whole buffer.
//
// `quality` is the 1-100 image-quality setting: it picks the palette size and
// the dither, low meaning few colours and a cheap ordered dither.
// Transparency survives as GIF's one bit of it.
//
// BLOCKING, and deliberately so - it stands in for QImage::save() and runs
// where that ran. Cost: ~0.5 s and ~2x the frame in RAM for 3840x2160
// (measured), the same order as the PNG encode it replaces. Empty on failure
// (no ffmpeg, a timeout at 20 s, a non-zero exit); callers fall back to PNG.
QByteArray encodeStillGif(const QImage &image, int quality);

// Non-blocking graceful teardown of a QProcess. Disconnects it, then (if still
// running) closeWriteChannel() -> terminate() -> SIGKILL after 1 s. The process
// reaps itself (finished -> deleteLater), so this never blocks the caller. The
// passed pointer is nulled.
void stopProcess(QProcess *&process);

} // namespace FfmpegUtil
