#include "X11ShmGrabber.h"

#include <QDebug>
#include <chrono>
#include <cstring>
#include <ctime>

#include <sys/ipc.h>
#include <sys/shm.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/Xfixes.h>

namespace {

enum PixFmt { FmtBgr0 = 0, FmtBgra = 1, FmtRgb0 = 2, FmtRgba = 3 };

qint64 monoNs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

// Our private Display makes only our own Xlib calls, so a benign handler here
// swallows an async error (e.g. a transient BadMatch) instead of the default
// handler calling exit() and taking the whole app down. Qt's xcb platform uses
// the xcb error path, not this Xlib global, so it is unaffected.
int ignoreX11Error(Display *, XErrorEvent *)
{
    return 0;
}

// XShmAttach fails asynchronously (the server can reject the segment: a separate
// IPC namespace in a container/sandbox, SHM limits, a remote/proxied X server).
// This handler flags it so we can fall back to plain XGetImage instead of
// spinning forever on an XShmGetImage that always returns False. Capture-thread
// only, swapped in just around the attach.
bool g_shmAttachError = false;
int shmAttachErrorHandler(Display *, XErrorEvent *)
{
    g_shmAttachError = true;
    return 0;
}

// Native byte order of an XImage -> ffmpeg rawvideo pix_fmt code. The standard
// Linux X11 TrueColor visual is LSBFirst with red_mask 0xFF0000 / blue 0xFF,
// which is B,G,R,(X) in memory. Depth 32 has a real alpha byte, depth 24 a pad.
int resolvePixFmt(const XImage *img)
{
    const bool alpha = (img->depth == 32);
    if (img->byte_order == LSBFirst) {
        if (img->blue_mask == 0xFFul)
            return alpha ? FmtBgra : FmtBgr0;
        if (img->red_mask == 0xFFul)
            return alpha ? FmtRgba : FmtRgb0;
    }
    // Anything exotic (MSBFirst / unusual masks): fall back to bgr0. The encoder
    // only reads RGB for yuv420p / GIF palettes, so a wrong alpha never shows;
    // a genuinely swapped R/B would, but no mainstream Linux X server does this.
    return FmtBgr0;
}

} // namespace

X11ShmGrabber::X11ShmGrabber(QObject *parent) : IScreenGrabber(parent) {}

X11ShmGrabber::~X11ShmGrabber()
{
    stop();
}

bool X11ShmGrabber::start(const QRect &rootRect, int maxFps, bool wantCursorMeta)
{
    if (m_running.load())
        return false;
    m_rect = rootRect;
    m_maxFps = qBound(1, maxFps, 60);
    m_wantCursorMeta = wantCursorMeta;
    m_haveFrame.store(false, std::memory_order_release);
    m_seq = 0;
    m_formatEmitted = false;
    m_lastCursorSerial = 0;
    m_running.store(true, std::memory_order_release);
    m_thread = std::thread([this] { captureLoop(); });
    return true;
}

void X11ShmGrabber::stop()
{
    m_running.store(false, std::memory_order_release);
    if (m_thread.joinable())
        m_thread.join();
}

QString X11ShmGrabber::pixelFormat() const
{
    switch (m_fmt.load(std::memory_order_relaxed)) {
    case FmtBgra: return QStringLiteral("bgra");
    case FmtRgb0: return QStringLiteral("rgb0");
    case FmtRgba: return QStringLiteral("rgba");
    case FmtBgr0:
    default:      return QStringLiteral("bgr0");
    }
}

bool X11ShmGrabber::latestFrame(QByteArray &out, quint64 *seq, qint64 *ptsNs)
{
    if (!m_haveFrame.load(std::memory_order_acquire))
        return false;
    QMutexLocker lock(&m_mutex);
    out = m_latest; // cheap shared ref: front buffer is only replaced, never mutated
    if (seq)
        *seq = m_seq;
    if (ptsNs)
        *ptsNs = m_ptsNs;
    return true;
}

QVector<CursorSample> X11ShmGrabber::takeCursorSamples()
{
    QMutexLocker lock(&m_mutex);
    QVector<CursorSample> out;
    out.swap(m_cursorSamples);
    return out;
}

void X11ShmGrabber::captureLoop()
{
    Display *dpy = XOpenDisplay(nullptr);
    if (!dpy) {
        emit streamError(tr("Could not open the X11 display for recording"));
        return;
    }
    XSetErrorHandler(ignoreX11Error);

    const int screen = DefaultScreen(dpy);
    const Window root = RootWindow(dpy, screen);
    Visual *vis = DefaultVisual(dpy, screen);
    const int depth = DefaultDepth(dpy, screen);

    // Clamp strictly inside the root so XShmGetImage can never raise BadMatch.
    const QRect rootBounds(0, 0, DisplayWidth(dpy, screen), DisplayHeight(dpy, screen));
    const QRect rect = m_rect.intersected(rootBounds);
    if (rect.width() < 2 || rect.height() < 2) {
        emit streamError(tr("Recording area is outside the screen"));
        XCloseDisplay(dpy);
        return;
    }
    const int w = rect.width();
    const int h = rect.height();

    bool useShm = XShmQueryExtension(dpy);
    XShmSegmentInfo shminfo;
    std::memset(&shminfo, 0, sizeof(shminfo));
    XImage *shmImg = nullptr;
    if (useShm) {
        shmImg = XShmCreateImage(dpy, vis, depth, ZPixmap, nullptr, &shminfo, w, h);
        if (!shmImg) {
            useShm = false;
        } else {
            shminfo.shmid = shmget(IPC_PRIVATE,
                                   size_t(shmImg->bytes_per_line) * shmImg->height,
                                   IPC_CREAT | 0600);
            if (shminfo.shmid < 0) {
                XDestroyImage(shmImg);
                shmImg = nullptr;
                useShm = false;
            } else {
                shminfo.shmaddr = shmImg->data = static_cast<char *>(shmat(shminfo.shmid, nullptr, 0));
                shminfo.readOnly = False;
                if (shmImg->data == reinterpret_cast<char *>(-1)) {
                    shmctl(shminfo.shmid, IPC_RMID, nullptr);
                    XDestroyImage(shmImg);
                    shmImg = nullptr;
                    useShm = false;
                } else {
                    g_shmAttachError = false;
                    XSetErrorHandler(shmAttachErrorHandler);
                    XShmAttach(dpy, &shminfo);
                    XSync(dpy, False); // force the async attach error to arrive now
                    XSetErrorHandler(ignoreX11Error);
                    if (g_shmAttachError) {
                        // Server rejected the segment: tear it down and fall back
                        // to plain XGetImage instead of a stream of empty grabs.
                        shmdt(shminfo.shmaddr);
                        shmctl(shminfo.shmid, IPC_RMID, nullptr);
                        shmImg->data = nullptr;
                        XDestroyImage(shmImg);
                        shmImg = nullptr;
                        useShm = false;
                    } else {
                        // Mark for destruction now: the segment stays alive until
                        // the last detach, so it is reclaimed even on a hard crash.
                        shmctl(shminfo.shmid, IPC_RMID, nullptr);
                    }
                }
            }
        }
    }

    int xfixesEvent = 0, xfixesError = 0;
    const bool haveXFixes = m_wantCursorMeta
                            && XFixesQueryExtension(dpy, &xfixesEvent, &xfixesError);

    const qint64 intervalNs = 1000000000LL / m_maxFps;
    bool reportedBadBpp = false;

    while (m_running.load(std::memory_order_acquire)) {
        const qint64 t0 = monoNs();
        XImage *img = nullptr;
        if (useShm) {
            if (XShmGetImage(dpy, root, shmImg, rect.x(), rect.y(), AllPlanes))
                img = shmImg;
        } else {
            img = XGetImage(dpy, root, rect.x(), rect.y(), w, h, AllPlanes, ZPixmap);
        }

        if (img) {
            if (img->bits_per_pixel != 32) {
                if (!reportedBadBpp) {
                    reportedBadBpp = true;
                    emit streamError(tr("Unsupported X11 pixel depth for recording"));
                }
                if (!useShm)
                    XDestroyImage(img);
                break;
            }
            if (!m_formatEmitted) {
                m_fmt.store(resolvePixFmt(img), std::memory_order_relaxed);
                m_formatEmitted = true;
                emit formatReady(QSize(w, h));
            }

            const int bpl = img->bytes_per_line;
            const qsizetype rowBytes = qsizetype(w) * 4;
            QByteArray &back = m_pool[m_poolIdx];
            m_poolIdx = (m_poolIdx + 1) % 3;
            back.resize(rowBytes * h);
            char *dst = back.data();
            const char *srcBase = img->data;
            for (int y = 0; y < h; ++y) {
                std::memcpy(dst, srcBase + qsizetype(y) * bpl, rowBytes);
                dst += rowBytes;
            }

            QVector<CursorSample> cursor;
            if (haveXFixes) {
                if (XFixesCursorImage *ci = XFixesGetCursorImage(dpy)) {
                    CursorSample s;
                    s.tMonoNs = t0;
                    s.visible = rect.contains(int(ci->x), int(ci->y));
                    if (s.visible) {
                        m_lastCursorX = double(ci->x) - rect.x();
                        m_lastCursorY = double(ci->y) - rect.y();
                    }
                    // Off-screen: hold the last on-screen position so the
                    // one-euro smoother is not fed a jump to another monitor.
                    s.x = m_lastCursorX;
                    s.y = m_lastCursorY;
                    s.shapeId = int(ci->cursor_serial);
                    cursor.append(s);
                    if (ci->cursor_serial != m_lastCursorSerial) {
                        m_lastCursorSerial = ci->cursor_serial;
                        QImage shape(int(ci->width), int(ci->height),
                                     QImage::Format_ARGB32_Premultiplied);
                        for (int y = 0; y < int(ci->height); ++y) {
                            auto *line = reinterpret_cast<QRgb *>(shape.scanLine(y));
                            const unsigned long *srcRow = ci->pixels + qsizetype(y) * ci->width;
                            for (int x = 0; x < int(ci->width); ++x)
                                line[x] = QRgb(srcRow[x] & 0xfffffffful); // XFixes: premultiplied ARGB
                        }
                        emit cursorShapeChanged(int(ci->cursor_serial), shape,
                                                QPoint(ci->xhot, ci->yhot));
                    }
                    XFree(ci);
                }
            }

            {
                QMutexLocker lock(&m_mutex);
                m_latest = back;
                ++m_seq;
                m_ptsNs = t0;
                // Bound the queue if the consumer stalls (one sample per frame,
                // normally drained every tick): drop new samples past the cap so
                // a wedged recorder can't grow this without limit.
                if (!cursor.isEmpty() && m_cursorSamples.size() < 4096)
                    m_cursorSamples += cursor;
            }
            m_haveFrame.store(true, std::memory_order_release);

            if (!useShm)
                XDestroyImage(img);
        }

        const qint64 sleepNs = intervalNs - (monoNs() - t0);
        if (sleepNs > 0)
            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepNs));
    }

    if (useShm && shmImg) {
        XShmDetach(dpy, &shminfo);
        // XDestroyImage would Xfree(data); data is the shmat() segment, not a
        // malloc'd buffer, so null it first (Xlib must not free it) and detach
        // the shared memory ourselves - otherwise free() on a non-heap pointer
        // corrupts the heap / aborts on every stop().
        shmImg->data = nullptr;
        XDestroyImage(shmImg);
        shmdt(shminfo.shmaddr);
    }
    XCloseDisplay(dpy);
}
