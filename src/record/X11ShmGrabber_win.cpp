// Windows build of X11ShmGrabber: the same frame-source contract, so the
// recorder and scroll capture downstream (sampler, crop, cursor overlay,
// ffmpeg) run unchanged. Frames come from DXGI Desktop Duplication: a full
// 2560x1440 copy measured 4-5 ms, against ~62 ms for a GDI BitBlt of the same
// area. GDI stays as the fallback for what duplication cannot serve: a rotated
// or non-BGRA output, an area spanning two monitors, a driver that refuses
// DuplicateOutput, and the time between losing a duplication and reopening it.
//
// Neither source contains the pointer, so cursor capture (wantCursorMeta)
// samples GetCursorInfo on every tick and renders each new HCURSOR once, as
// the X11 path does with XFixes.
//
// Coordinates: Qt 6 runs per-monitor DPI aware (v2), and the capture thread
// inherits that, so DXGI desktop coordinates, BitBlt and GetCursorInfo all
// speak physical pixels.
#include "X11ShmGrabber.h"

#include <QGuiApplication>
#include <QScreen>
#include <cstring>
#include <ctime>
#include <vector>

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace {

qint64 monoNs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

QRect virtualDesktop()
{
    return QRect(GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN),
                 GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_CYVIRTUALSCREEN));
}

// One BitBlt per grab into a DIB section that lives for the whole recording.
// CAPTUREBLT pulls in layered windows (menus, tooltips), as the screenshot
// path does.
class GdiSource
{
public:
    ~GdiSource() { close(); }

    bool open(const QRect &rect)
    {
        if (m_dib)
            return true;
        m_rect = rect;
        m_screen = GetDC(nullptr);
        m_mem = m_screen ? CreateCompatibleDC(m_screen) : nullptr;
        if (!m_mem) {
            close();
            return false;
        }
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
        bi.bmiHeader.biWidth = rect.width();
        bi.bmiHeader.biHeight = -rect.height(); // top-down, the row order of a frame
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        m_dib = CreateDIBSection(m_mem, &bi, DIB_RGB_COLORS, &m_bits, nullptr, 0);
        if (!m_dib) {
            close();
            return false;
        }
        m_old = SelectObject(m_mem, m_dib);
        return true;
    }

    // 32 bpp DIB rows are exactly width*4 bytes, so the whole frame is one copy.
    // Fails while the secure desktop (UAC, Ctrl+Alt+Del) is up.
    bool grab(char *dst)
    {
        if (!m_dib || !BitBlt(m_mem, 0, 0, m_rect.width(), m_rect.height(), m_screen,
                              m_rect.x(), m_rect.y(), SRCCOPY | CAPTUREBLT))
            return false;
        GdiFlush();
        std::memcpy(dst, m_bits, size_t(m_rect.width()) * m_rect.height() * 4);
        return true;
    }

    void close()
    {
        if (m_old)
            SelectObject(m_mem, m_old);
        if (m_dib)
            DeleteObject(m_dib);
        if (m_mem)
            DeleteDC(m_mem);
        if (m_screen)
            ReleaseDC(nullptr, m_screen);
        m_old = nullptr;
        m_dib = nullptr;
        m_mem = nullptr;
        m_screen = nullptr;
        m_bits = nullptr;
    }

private:
    QRect m_rect;
    HDC m_screen = nullptr;
    HDC m_mem = nullptr;
    HBITMAP m_dib = nullptr;
    HGDIOBJ m_old = nullptr;
    void *m_bits = nullptr;
};

class DxgiSource
{
public:
    enum Open { Opened, NotNow, Never };
    enum Grab { NewFrame, Unchanged, Lost };

    // Never: no single output holds the area in a form duplication serves, so
    // GDI takes the whole recording. NotNow: the output is there but refused
    // duplication (secure desktop, a mode change in flight); retry later.
    Open open(const QRect &rect)
    {
        close();
        ComPtr<IDXGIFactory1> factory;
        if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))))
            return Never;
        ComPtr<IDXGIAdapter1> adapter;
        for (UINT a = 0; factory->EnumAdapters1(a, &adapter) != DXGI_ERROR_NOT_FOUND; ++a) {
            ComPtr<IDXGIOutput> output;
            for (UINT o = 0; adapter->EnumOutputs(o, &output) != DXGI_ERROR_NOT_FOUND; ++o) {
                DXGI_OUTPUT_DESC od;
                if (FAILED(output->GetDesc(&od)) || !od.AttachedToDesktop)
                    continue;
                const RECT &d = od.DesktopCoordinates;
                const QRect outRect(int(d.left), int(d.top), int(d.right - d.left),
                                    int(d.bottom - d.top));
                if (!outRect.contains(rect))
                    continue;
                if (od.Rotation != DXGI_MODE_ROTATION_IDENTITY
                    && od.Rotation != DXGI_MODE_ROTATION_UNSPECIFIED)
                    return Never; // the duplicated image is unrotated; BitBlt is not
                return openOutput(adapter.Get(), output.Get(), rect, outRect.topLeft());
            }
        }
        return Never;
    }

    // Duplication hands out a frame only when the desktop presented; the very
    // first acquire is a pointer-only update with an all-black image (measured),
    // so frames without a present are skipped and the caller seeds from GDI.
    Grab grab(char *dst)
    {
        DXGI_OUTDUPL_FRAME_INFO fi;
        ComPtr<IDXGIResource> res;
        const HRESULT hr = m_dup->AcquireNextFrame(0, &fi, &res);
        if (hr == DXGI_ERROR_WAIT_TIMEOUT)
            return Unchanged;
        if (FAILED(hr))
            return Lost;
        Grab out = Unchanged;
        ComPtr<ID3D11Texture2D> tex;
        if (fi.LastPresentTime.QuadPart != 0 && SUCCEEDED(res.As(&tex))) {
            D3D11_BOX box;
            box.left = UINT(m_rect.x() - m_origin.x());
            box.top = UINT(m_rect.y() - m_origin.y());
            box.front = 0;
            box.right = box.left + UINT(m_rect.width());
            box.bottom = box.top + UINT(m_rect.height());
            box.back = 1;
            m_ctx->CopySubresourceRegion(m_staging.Get(), 0, 0, 0, 0, tex.Get(), 0, &box);
            D3D11_MAPPED_SUBRESOURCE map;
            if (FAILED(m_ctx->Map(m_staging.Get(), 0, D3D11_MAP_READ, 0, &map))) {
                m_dup->ReleaseFrame();
                return Lost;
            }
            const size_t rowBytes = size_t(m_rect.width()) * 4;
            const auto *src = static_cast<const char *>(map.pData);
            for (int y = 0; y < m_rect.height(); ++y)
                std::memcpy(dst + rowBytes * y, src + size_t(map.RowPitch) * y, rowBytes);
            m_ctx->Unmap(m_staging.Get(), 0);
            out = NewFrame;
        }
        m_dup->ReleaseFrame();
        return out;
    }

    bool isOpen() const { return bool(m_dup); }

    void close()
    {
        m_staging.Reset();
        m_dup.Reset();
        m_ctx.Reset();
        m_dev.Reset();
    }

private:
    Open openOutput(IDXGIAdapter1 *adapter, IDXGIOutput *output, const QRect &rect,
                    const QPoint &origin)
    {
        // The device must live on the output's own adapter, or DuplicateOutput
        // fails on hybrid-GPU laptops.
        if (FAILED(D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0, nullptr, 0,
                                     D3D11_SDK_VERSION, &m_dev, nullptr, &m_ctx)))
            return Never;
        ComPtr<IDXGIOutput1> output1;
        if (FAILED(output->QueryInterface(IID_PPV_ARGS(&output1)))) {
            close();
            return Never;
        }
        const HRESULT hr = output1->DuplicateOutput(m_dev.Get(), &m_dup);
        if (FAILED(hr)) {
            close();
            return (hr == E_ACCESSDENIED || hr == DXGI_ERROR_NOT_CURRENTLY_AVAILABLE
                    || hr == DXGI_ERROR_SESSION_DISCONNECTED)
                       ? NotNow
                       : Never;
        }
        DXGI_OUTDUPL_DESC dd;
        m_dup->GetDesc(&dd);
        if (dd.ModeDesc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
            close();
            return Never;
        }
        D3D11_TEXTURE2D_DESC td = {};
        td.Width = UINT(rect.width());
        td.Height = UINT(rect.height());
        td.MipLevels = 1;
        td.ArraySize = 1;
        td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        td.SampleDesc.Count = 1;
        td.Usage = D3D11_USAGE_STAGING;
        td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        if (FAILED(m_dev->CreateTexture2D(&td, nullptr, &m_staging))) {
            close();
            return Never;
        }
        m_rect = rect;
        m_origin = origin;
        return Opened;
    }

    QRect m_rect;
    QPoint m_origin;
    ComPtr<ID3D11Device> m_dev;
    ComPtr<ID3D11DeviceContext> m_ctx;
    ComPtr<IDXGIOutputDuplication> m_dup;
    ComPtr<ID3D11Texture2D> m_staging;
};

// Plain Sleep rounds up to the 15.6 ms system tick, which turns a 30 fps grab
// into an uneven 31/47 ms cadence; a high-resolution waitable timer does not.
class FrameTimer
{
public:
    FrameTimer()
        : m_timer(CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                         TIMER_ALL_ACCESS))
    {
    }
    ~FrameTimer()
    {
        if (m_timer)
            CloseHandle(m_timer);
    }
    void sleepNs(qint64 ns)
    {
        LARGE_INTEGER due;
        due.QuadPart = -(ns / 100); // relative, in 100 ns units
        if (m_timer && SetWaitableTimer(m_timer, &due, 0, nullptr, nullptr, FALSE)) {
            WaitForSingleObject(m_timer, INFINITE);
            return;
        }
        Sleep(DWORD(qMax<qint64>(1, ns / 1000000)));
    }

private:
    HANDLE m_timer;
};

// HCURSOR ids are USER handles, which carry 32 significant bits even in a
// 64-bit process; masked to stay a positive int, never 0 (= unknown).
unsigned long cursorId(HCURSOR c)
{
    const auto v = static_cast<unsigned long>(reinterpret_cast<quintptr>(c) & 0x7fffffffu);
    return v ? v : 1;
}

// QImage::fromHICON returns an empty or cropped image for the stock arrow,
// hand and resize cursors (measured), so the cursor is drawn twice, over black
// and over white: the difference is its coverage, the black render its
// premultiplied colour. That covers colour, alpha and monochrome cursors alike.
// A pixel that comes out lighter over black than over white inverts the screen
// (the text I-beam does); a recording cannot invert, so those become black
// with a white outline, which stays visible on any background.
QImage renderCursor(HCURSOR cursor, QPoint *hotspot)
{
    ICONINFO ii = {};
    if (!GetIconInfo(cursor, &ii))
        return {};
    BITMAP bm = {};
    int w = 0, h = 0;
    if (ii.hbmColor && GetObjectW(ii.hbmColor, sizeof(bm), &bm)) {
        w = bm.bmWidth;
        h = bm.bmHeight;
    } else if (ii.hbmMask && GetObjectW(ii.hbmMask, sizeof(bm), &bm)) {
        w = bm.bmWidth;
        h = bm.bmHeight / 2; // monochrome: the AND mask stacked over the XOR mask
    }
    *hotspot = QPoint(int(ii.xHotspot), int(ii.yHotspot));
    if (ii.hbmMask)
        DeleteObject(ii.hbmMask);
    if (ii.hbmColor)
        DeleteObject(ii.hbmColor);
    if (w <= 0 || h <= 0 || w > 256 || h > 256)
        return {};

    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    HDC dc = CreateCompatibleDC(nullptr);
    if (!dc)
        return {};
    void *bits[2] = {};
    HBITMAP dib[2] = {};
    bool drawn = true;
    for (int i = 0; i < 2 && drawn; ++i) {
        dib[i] = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits[i], nullptr, 0);
        if (!dib[i]) {
            drawn = false;
            break;
        }
        HGDIOBJ old = SelectObject(dc, dib[i]);
        PatBlt(dc, 0, 0, w, h, i ? WHITENESS : BLACKNESS);
        drawn = DrawIconEx(dc, 0, 0, cursor, w, h, 0, nullptr, DI_NORMAL);
        SelectObject(dc, old);
    }
    GdiFlush();

    QImage img;
    if (drawn) {
        img = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
        const auto *black = static_cast<const quint32 *>(bits[0]);
        const auto *white = static_cast<const quint32 *>(bits[1]);
        std::vector<bool> inverted(size_t(w) * h, false);
        for (int y = 0; y < h; ++y) {
            auto *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < w; ++x) {
                const quint32 b = black[y * w + x];
                const quint32 wh = white[y * w + x];
                const int br = int((b >> 16) & 0xff), bg = int((b >> 8) & 0xff), bb = int(b & 0xff);
                const int diff = (int((wh >> 16) & 0xff) - br + int((wh >> 8) & 0xff) - bg
                                  + int(wh & 0xff) - bb) / 3;
                if (diff < -64) {
                    inverted[size_t(y) * w + x] = true;
                    line[x] = qRgba(0, 0, 0, 255);
                    continue;
                }
                const int a = qBound(0, 255 - diff, 255);
                line[x] = qRgba(qMin(br, a), qMin(bg, a), qMin(bb, a), a);
            }
        }
        for (int y = 0; y < h; ++y) {
            auto *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < w; ++x) {
                if (qAlpha(line[x]) != 0)
                    continue;
                bool edge = false;
                for (int dy = -1; dy <= 1 && !edge; ++dy)
                    for (int dx = -1; dx <= 1 && !edge; ++dx) {
                        const int nx = x + dx, ny = y + dy;
                        edge = nx >= 0 && ny >= 0 && nx < w && ny < h
                               && inverted[size_t(ny) * w + nx];
                    }
                if (edge)
                    line[x] = qRgba(255, 255, 255, 255);
            }
        }
    }
    for (HBITMAP d : dib)
        if (d)
            DeleteObject(d);
    DeleteDC(dc);
    return img;
}

} // namespace

X11ShmGrabber::X11ShmGrabber(QObject *parent) : IScreenGrabber(parent) {}

X11ShmGrabber::~X11ShmGrabber()
{
    stop();
}

bool X11ShmGrabber::isAvailable()
{
    return QGuiApplication::platformName() == QLatin1String("windows");
}

// Qt keeps each screen's origin in native pixels and scales only its size.
QRect X11ShmGrabber::screenRect(const QScreen *screen)
{
    const qreal dpr = screen->devicePixelRatio() > 0 ? screen->devicePixelRatio() : 1.0;
    const QRect g = screen->geometry();
    return QRect(g.topLeft(), QSize(qRound(g.width() * dpr), qRound(g.height() * dpr)));
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

// Both sources hand out B,G,R,X in memory; the fourth byte is not alpha.
QString X11ShmGrabber::pixelFormat() const
{
    return QStringLiteral("bgr0");
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
    const QRect rect = m_rect.intersected(virtualDesktop());
    if (rect.width() < 2 || rect.height() < 2) {
        emit streamError(tr("Recording area is outside the screen"));
        return;
    }
    const int w = rect.width();
    const int h = rect.height();
    const qsizetype frameBytes = qsizetype(w) * h * 4;

    GdiSource gdi;
    DxgiSource dxgi;
    bool dxgiPossible = dxgi.open(rect) != DxgiSource::Never;
    qint64 dxgiRetryAtNs = 0;
    constexpr qint64 kDxgiRetryNs = 1000000000LL;
    if (!gdi.open(rect) && !dxgi.isOpen()) {
        emit streamError(tr("Could not capture the screen for recording"));
        return;
    }
    // Duplication starts with no image and a static desktop never presents, so
    // each time it (re)opens, one GDI grab supplies the current picture; every
    // change after that arrives as a duplication frame.
    bool seeded = false;

    FrameTimer timer;
    const qint64 intervalNs = 1000000000LL / m_maxFps;

    while (m_running.load(std::memory_order_acquire)) {
        const qint64 t0 = monoNs();

        if (!dxgi.isOpen() && dxgiPossible && t0 >= dxgiRetryAtNs) {
            dxgiPossible = dxgi.open(rect) != DxgiSource::Never;
            dxgiRetryAtNs = t0 + kDxgiRetryNs;
            seeded = false;
        }

        QByteArray &back = m_pool[m_poolIdx];
        back.resize(frameBytes);
        bool fresh = false;
        if (dxgi.isOpen()) {
            switch (dxgi.grab(back.data())) {
            case DxgiSource::NewFrame:
                fresh = true;
                gdi.close();
                break;
            case DxgiSource::Unchanged:
                break;
            case DxgiSource::Lost:
                dxgi.close();
                dxgiRetryAtNs = t0; // a mode switch is usually over by the next tick
                break;
            }
        }
        if (!fresh && (!dxgi.isOpen() || !seeded) && gdi.open(rect))
            fresh = gdi.grab(back.data());
        if (fresh)
            seeded = true;

        if (fresh) {
            m_poolIdx = (m_poolIdx + 1) % 3;
            if (!m_formatEmitted) {
                m_formatEmitted = true;
                emit formatReady(QSize(w, h));
            }
        }

        // The pointer moves without the desktop presenting, so it is sampled
        // every tick, not only on a new frame.
        QVector<CursorSample> cursor;
        CURSORINFO ci = {};
        ci.cbSize = sizeof(ci);
        if (m_wantCursorMeta && GetCursorInfo(&ci)) {
            const bool showing = (ci.flags & CURSOR_SHOWING) && ci.hCursor;
            const QPoint p(int(ci.ptScreenPos.x), int(ci.ptScreenPos.y));
            CursorSample s;
            s.tMonoNs = t0;
            s.visible = showing && rect.contains(p);
            if (rect.contains(p)) {
                m_lastCursorX = double(p.x() - rect.x());
                m_lastCursorY = double(p.y() - rect.y());
            }
            // Off-screen: hold the last on-screen position so the one-euro
            // smoother is not fed a jump to another monitor.
            s.x = m_lastCursorX;
            s.y = m_lastCursorY;
            const unsigned long id = showing ? cursorId(ci.hCursor) : 0;
            s.shapeId = int(id);
            cursor.append(s);
            if (id && id != m_lastCursorSerial) {
                m_lastCursorSerial = id;
                QPoint hot;
                const QImage shape = renderCursor(ci.hCursor, &hot);
                if (!shape.isNull())
                    emit cursorShapeChanged(int(id), shape, hot);
            }
        }

        if (fresh || !cursor.isEmpty()) {
            QMutexLocker lock(&m_mutex);
            if (fresh) {
                m_latest = back;
                ++m_seq;
                m_ptsNs = t0;
            }
            // Bound the queue if the consumer stalls (one sample per tick,
            // normally drained every recorder tick).
            if (!cursor.isEmpty() && m_cursorSamples.size() < 4096)
                m_cursorSamples += cursor;
        }
        if (fresh)
            m_haveFrame.store(true, std::memory_order_release);

        const qint64 sleepNs = intervalNs - (monoNs() - t0);
        if (sleepNs > 0)
            timer.sleepNs(sleepNs);
    }
}
