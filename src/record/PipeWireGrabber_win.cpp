// Windows build of PipeWireGrabber: there is no PipeWire, so start() refuses
// and the recorder takes its existing "backend failed to start" path. Kept as a
// class (not compiled out) because GifRecorder and ScrollCaptureController
// name it unconditionally.
#include "PipeWireGrabber.h"

PipeWireGrabber::PipeWireGrabber(QObject *parent) : IScreenGrabber(parent) {}

PipeWireGrabber::~PipeWireGrabber() = default;

bool PipeWireGrabber::start(int, uint, int, bool)
{
    return false;
}

void PipeWireGrabber::stop() {}

QString PipeWireGrabber::pixelFormat() const
{
    return QStringLiteral("bgra");
}

bool PipeWireGrabber::latestFrame(QByteArray &, quint64 *, qint64 *)
{
    return false;
}

QVector<CursorSample> PipeWireGrabber::takeCursorSamples()
{
    return {};
}

void PipeWireGrabber::onParamChanged(uint32_t, const void *) {}

void PipeWireGrabber::onProcess() {}
