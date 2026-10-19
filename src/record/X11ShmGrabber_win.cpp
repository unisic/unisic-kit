// Windows build of X11ShmGrabber: there is no X server, so start() refuses and
// the recorder takes its existing "backend failed to start" path. Kept as a
// class (not compiled out) because GifRecorder and ScrollCaptureController
// name it unconditionally.
#include "X11ShmGrabber.h"

X11ShmGrabber::X11ShmGrabber(QObject *parent) : IScreenGrabber(parent) {}

X11ShmGrabber::~X11ShmGrabber() = default;

bool X11ShmGrabber::start(const QRect &, int, bool)
{
    return false;
}

void X11ShmGrabber::stop() {}

QString X11ShmGrabber::pixelFormat() const
{
    return QStringLiteral("bgra");
}

bool X11ShmGrabber::latestFrame(QByteArray &, quint64 *, qint64 *)
{
    return false;
}

QVector<CursorSample> X11ShmGrabber::takeCursorSamples()
{
    return {};
}

void X11ShmGrabber::captureLoop() {}
