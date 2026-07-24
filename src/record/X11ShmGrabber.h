#pragma once
#include "IScreenGrabber.h"
#include <QRect>
#include <QMutex>
#include <QByteArray>
#include <QVector>
#include <QImage>
#include <atomic>
#include <thread>

// Frame source for an X11 session: grabs a fixed root-window rect via the MIT-SHM
// extension (XShmGetImage) on a private capture thread and keeps the most recent
// frame, mirroring PipeWireGrabber's contract so GifRecorder's downstream
// (sampler, crop, overlays, ffmpeg) is unchanged. The Wayland portal/PipeWire
// path is untouched; this is only chosen at runtime when qApp is on the xcb QPA.
//
// XShmGetImage from the root does NOT include the hardware cursor, so cursor
// capture (wantCursorMeta) polls XFixesGetCursorImage each grab and feeds the
// same CursorSample / cursorShapeChanged path the recorder already draws.
class X11ShmGrabber : public IScreenGrabber
{
    Q_OBJECT
public:
    explicit X11ShmGrabber(QObject *parent = nullptr);
    ~X11ShmGrabber() override;

    // rootRect: the region to grab in ROOT-window (physical) pixels - a monitor
    // rect for full-screen, a region rect for region recording. maxFps caps the
    // grab loop. wantCursorMeta enables the XFixes cursor sampling/shape path.
    bool start(const QRect &rootRect, int maxFps, bool wantCursorMeta = false);
    void stop() override;

    // Always "bgra": X11 TrueColor visuals are little-endian BGRA (ZPixmap,
    // 32bpp) - the same native order the PipeWire path keeps, fed straight to
    // ffmpeg -pix_fmt with no swizzle.
    QString pixelFormat() const override;

    bool latestFrame(QByteArray &out, quint64 *seq = nullptr, qint64 *ptsNs = nullptr) override;
    QVector<CursorSample> takeCursorSamples() override;

private:
    void captureLoop();   // runs on m_thread

    QRect m_rect;
    int m_maxFps = 15;
    bool m_wantCursorMeta = false;
    std::thread m_thread;
    std::atomic<bool> m_running{false};

    QMutex m_mutex;
    QByteArray m_latest;   // front buffer: replaced by assignment only
    QByteArray m_pool[3];  // rotating back buffers: capture thread only
    quint64 m_seq = 0;     // guarded by m_mutex
    qint64 m_ptsNs = 0;    // pts of m_latest (CLOCK_MONOTONIC ns), guarded by m_mutex
    std::atomic<bool> m_haveFrame{false};
    // Pixel format resolved from the first XImage (0=bgr0 1=bgra 2=rgb0 3=rgba),
    // written on the capture thread before formatReady, read by pixelFormat().
    std::atomic<int> m_fmt{0};
    int m_poolIdx = 0;

    QVector<CursorSample> m_cursorSamples;   // guarded by m_mutex
    unsigned long m_lastCursorSerial = 0;    // capture thread only: last shape emitted
    double m_lastCursorX = 0.0;              // capture thread only: last on-screen position,
    double m_lastCursorY = 0.0;              //   held into off-screen samples so smoothing holds
    bool m_formatEmitted = false;            // capture thread only
};
