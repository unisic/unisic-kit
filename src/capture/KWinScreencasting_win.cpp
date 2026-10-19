// Windows build of KWinScreencasting: there is no KWin, so isAvailable() is
// false and every caller already falls back on that answer. The create*
// functions return nullptr, which callers only reach after isAvailable().
#include "KWinScreencasting.h"

class KWinScreencastStreamPrivate
{
public:
    quint32 m_nodeId = 0;
};

class KWinScreencastingPrivate
{
};

KWinScreencastStream::KWinScreencastStream(QObject *parent)
    : QObject(parent)
    , d(new KWinScreencastStreamPrivate)
{
}

KWinScreencastStream::~KWinScreencastStream() = default;

quint32 KWinScreencastStream::nodeId() const
{
    return d->m_nodeId;
}

KWinScreencasting::KWinScreencasting(QObject *parent)
    : QObject(parent)
    , d(new KWinScreencastingPrivate)
{
}

KWinScreencasting::~KWinScreencasting() = default;

bool KWinScreencasting::isAvailable() const
{
    return false;
}

KWinScreencastStream *KWinScreencasting::createOutputStream(QScreen *, CursorMode)
{
    return nullptr;
}

KWinScreencastStream *KWinScreencasting::createRegionStream(const QRect &, qreal, CursorMode)
{
    return nullptr;
}

bool KWinScreencasting::regionStreamsSupported() const
{
    return false;
}

KWinScreencastStream *KWinScreencasting::createWindowStream(const QString &, CursorMode)
{
    return nullptr;
}
