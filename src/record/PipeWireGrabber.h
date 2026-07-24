#pragma once
#include "IScreenGrabber.h"
#include <QObject>
#include <QSize>
#include <QString>
#include <QMutex>
#include <QByteArray>
#include <QVector>
#include <QImage>
#include <QPoint>
#include <QHash>
#include <atomic>

struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_stream;

// Consumes a portal ScreenCast PipeWire stream (SHM buffers, BGRx/BGRA)
// on PipeWire's own thread and keeps the most recent frame; the recorder
// samples it at a fixed FPS (sample-and-hold gives GIF a constant rate).
//
// Cursor-metadata capture (opt in with start(..., wantCursorMeta=true), and
// only meaningful after ScreenCastSession negotiated CursorMetadata — in any
// other cursor mode no cursor meta is attached to the buffers).
class PipeWireGrabber : public IScreenGrabber
{
    Q_OBJECT
public:
    explicit PipeWireGrabber(QObject *parent = nullptr);
    ~PipeWireGrabber() override;

    // wantCursorMeta requests SPA_META_Header + SPA_META_Cursor on the buffers
    // and enables the cursor sampling / shape path. Defaulted off: existing
    // callers are byte-for-byte unaffected.
    // pipewireFd: the portal's OpenPipeWireRemote fd (ownership taken), or -1
    // to connect to the user's DEFAULT PipeWire daemon — the KWin-native
    // (zkde_screencast) path, where the compositor hands out only a node id.
    bool start(int pipewireFd, uint nodeId, int maxFps, bool wantCursorMeta = false);
    void stop() override;

    // ffmpeg rawvideo pix_fmt for the negotiated byte order (valid after
    // formatReady): frames are kept in native order, not swizzled to BGRA.
    QString pixelFormat() const override;

    // Hands out the latest frame (tightly packed in pixelFormat() and the
    // negotiated size) as a cheap implicitly-shared reference. Returns false if
    // none arrived yet.
    // `seq` (same mutex, so atomic with the frame) increments once per new
    // stream frame — compositor streams are damage-driven, so on a static
    // screen it lets the sampler skip re-cropping an unchanged frame.
    // `ptsNs` (optional) is the frame's presentation time in CLOCK_MONOTONIC ns,
    // the same clock stamped on CursorSample::tMonoNs, so both map to one clock.
    bool latestFrame(QByteArray &out, quint64 *seq = nullptr, qint64 *ptsNs = nullptr) override;

    // Drains all cursor samples captured since the last call (empty when
    // wantCursorMeta was false). Call from the GUI/recorder thread.
    QVector<CursorSample> takeCursorSamples() override;

    // formatReady / streamError / cursorShapeChanged are inherited from
    // IScreenGrabber and emitted from the PipeWire thread (connect QUEUED).

public: // called from PipeWire C callbacks
    void onParamChanged(uint32_t id, const void *param);
    void onProcess();

private:

    pw_thread_loop *m_loop = nullptr;
    pw_context *m_context = nullptr;
    pw_core *m_core = nullptr;
    pw_stream *m_stream = nullptr;
    void *m_listener = nullptr;

    QMutex m_mutex;
    QByteArray m_latest;   // front buffer: replaced by assignment only, never written in place
    QByteArray m_pool[3];  // rotating back buffers: PipeWire thread only
    quint64 m_seq = 0;     // frame sequence, guarded by m_mutex
    qint64 m_ptsNs = 0;    // pts of m_latest (CLOCK_MONOTONIC ns), guarded by m_mutex
    std::atomic<bool> m_haveFrame{false};
    QSize m_size;
    // Written on the PipeWire thread (onParamChanged), read on the GUI thread
    // (pixelFormat() during beginEncoding and per-frame compositing) — atomic
    // so a mid-stream renegotiation is not a data race.
    std::atomic<uint32_t> m_format{0};

    // Cursor-metadata path. m_cursorSamples is drained by takeCursorSamples();
    // the rest below is PipeWire-thread-only state.
    bool m_wantCursorMeta = false;
    QVector<CursorSample> m_cursorSamples;   // guarded by m_mutex
    bool m_cursorOverflowWarned = false;     // guarded by m_mutex
    double m_lastCursorX = 0.0;              // PipeWire thread only: last visible position,
    double m_lastCursorY = 0.0;              //   carried into hidden samples so interpolation holds
};
