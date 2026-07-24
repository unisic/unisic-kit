#pragma once
#include <QObject>
#include <QSize>
#include <QString>
#include <QByteArray>
#include <QVector>
#include <QImage>
#include <QPoint>

// One captured cursor position, in the grabber's own frame pixel space and
// clock. Plain value struct - travels out via takeCursorSamples(), never a
// signal, so it needs no Q_DECLARE_METATYPE. `tMonoNs` shares the
// CLOCK_MONOTONIC domain with latestFrame()'s ptsNs, so a consumer can map
// cursor motion and video frames onto one timeline. `shapeId` identifies the
// bitmap worn at this sample (0 = unknown); pair it with cursorShapeChanged().
struct CursorSample {
    qint64 tMonoNs = 0;   // CLOCK_MONOTONIC ns (== latestFrame() ptsNs domain)
    double x = 0.0;       // frame pixels
    double y = 0.0;       // frame pixels
    bool visible = true;
    int shapeId = 0;      // shape id; 0 = no/unknown shape this sample
};

// The frame-source contract GifRecorder consumes, backend-agnostic. Two
// concrete backends implement it: PipeWireGrabber (Wayland portal / KWin
// ScreenCast stream) and X11ShmGrabber (XShmGetImage on an X11 session). The
// recorder samples latestFrame() at a fixed FPS (sample-and-hold gives GIF a
// constant rate), reads pixelFormat() to pick the ffmpeg -pix_fmt, and drains
// cursor metadata for the pointer/halo/ripples overlay.
//
// start() is deliberately NOT part of this interface: each backend needs a
// different handle (a PipeWire fd+nodeId vs an X11 root rect), so the recorder
// calls it on the concrete type right after construction, then treats the
// grabber only through this base.
class IScreenGrabber : public QObject
{
    Q_OBJECT
public:
    explicit IScreenGrabber(QObject *parent = nullptr) : QObject(parent) {}
    ~IScreenGrabber() override = default;

    virtual void stop() = 0;

    // ffmpeg rawvideo pix_fmt for the negotiated byte order (valid after
    // formatReady): frames are kept in native order, not swizzled.
    virtual QString pixelFormat() const = 0;

    // Hands out the latest frame (tightly packed in pixelFormat() and the
    // negotiated size) as a cheap implicitly-shared reference. Returns false if
    // none arrived yet. `seq` increments once per new frame - lets the sampler
    // skip re-cropping an unchanged frame. `ptsNs` (optional) is the frame's
    // CLOCK_MONOTONIC presentation time, the clock CursorSample::tMonoNs uses.
    virtual bool latestFrame(QByteArray &out, quint64 *seq = nullptr,
                             qint64 *ptsNs = nullptr) = 0;

    // Drains all cursor samples captured since the last call (empty when the
    // backend was started without cursor metadata). Call from the recorder thread.
    virtual QVector<CursorSample> takeCursorSamples() = 0;

signals:
    void formatReady(const QSize &size);
    void streamError(const QString &message);
    // A cursor shape (identified by `id`) was seen for the first time: `image`
    // is a deep-copied RGBA bitmap, `hotspot` its click point. May be emitted
    // from a capture thread - connect QUEUED (or Auto).
    void cursorShapeChanged(int id, const QImage &image, const QPoint &hotspot);
};
