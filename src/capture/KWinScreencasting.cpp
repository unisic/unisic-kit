/*
    Adapted from KDE Spectacle's src/Platforms/screencasting.cpp:
    SPDX-FileCopyrightText: 2020 Aleix Pol Gonzalez <aleixpol@kde.org>
    SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
*/

#include "KWinScreencasting.h"
#include "qwayland-zkde-screencast-unstable-v1.h"

#include <QDebug>
#include <QGuiApplication>
#include <QPointer>
#include <QRect>
#include <QScreen>
#include <QtWaylandClient/QWaylandClientExtensionTemplate>
#include <qpa/qplatformnativeinterface.h>

class KWinScreencastStreamPrivate : public QtWayland::zkde_screencast_stream_unstable_v1
{
public:
    explicit KWinScreencastStreamPrivate(KWinScreencastStream *q)
        : q(q)
    {
    }
    ~KWinScreencastStreamPrivate() override
    {
        if (isInitialized()) {
            close();
        }
    }

    void zkde_screencast_stream_unstable_v1_created(uint32_t node) override
    {
        m_nodeId = node;
        Q_EMIT q->created(node);
    }

    void zkde_screencast_stream_unstable_v1_closed() override
    {
        Q_EMIT q->closed();
    }

    void zkde_screencast_stream_unstable_v1_failed(const QString &error) override
    {
        Q_EMIT q->failed(error);
    }

    quint32 m_nodeId = 0;
    QPointer<KWinScreencastStream> q;
};

KWinScreencastStream::KWinScreencastStream(QObject *parent)
    : QObject(parent)
    , d(new KWinScreencastStreamPrivate(this))
{
}

KWinScreencastStream::~KWinScreencastStream() = default;

quint32 KWinScreencastStream::nodeId() const
{
    return d->m_nodeId;
}

class KWinScreencastingPrivate : public QWaylandClientExtensionTemplate<KWinScreencastingPrivate>,
                                 public QtWayland::zkde_screencast_unstable_v1
{
public:
    KWinScreencastingPrivate()
        : QWaylandClientExtensionTemplate<KWinScreencastingPrivate>(5)
    {
        initialize();
        // Not initialized = not KWin, or the caller's desktop file lacks
        // X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1. Either way the
        // consumer falls back to the portal; only log in the KWin case where
        // the fix is actionable.
        if (!isInitialized() && qgetenv("XDG_CURRENT_DESKTOP").contains("KDE")) {
            qInfo() << "KWinScreencasting: zkde_screencast_unstable_v1 not granted -"
                       " desktop file needs X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1;"
                       " falling back to the portal";
        }
    }

    ~KWinScreencastingPrivate() override
    {
        if (isInitialized()) {
            destroy();
        }
    }
};

KWinScreencasting::KWinScreencasting(QObject *parent)
    : QObject(parent)
    , d(new KWinScreencastingPrivate)
{
}

KWinScreencasting::~KWinScreencasting() = default;

bool KWinScreencasting::isAvailable() const
{
    return d->isInitialized();
}

bool KWinScreencasting::regionStreamsSupported() const
{
    return d->isInitialized()
           && d->QWaylandClientExtension::version() >= ZKDE_SCREENCAST_UNSTABLE_V1_STREAM_REGION_SINCE_VERSION;
}

KWinScreencastStream *KWinScreencasting::createOutputStream(QScreen *screen, CursorMode mode)
{
    if (!d->isInitialized())
        return nullptr;
    auto *native = QGuiApplication::platformNativeInterface();
    wl_output *output =
        native ? static_cast<wl_output *>(native->nativeResourceForScreen("output", screen)) : nullptr;
    if (!output)
        return nullptr;

    auto *stream = new KWinScreencastStream(this);
    stream->setObjectName(screen->name());
    stream->d->init(d->stream_output(output, uint32_t(mode)));
    return stream;
}

KWinScreencastStream *KWinScreencasting::createRegionStream(const QRect &region, qreal scaling, CursorMode mode)
{
    if (!regionStreamsSupported())
        return nullptr;
    auto *stream = new KWinScreencastStream(this);
    stream->setObjectName(QStringLiteral("region-%1,%2 %3x%4")
                              .arg(region.x()).arg(region.y()).arg(region.width()).arg(region.height()));
    stream->d->init(d->stream_region(region.x(), region.y(), region.width(), region.height(),
                                     wl_fixed_from_double(scaling), uint32_t(mode)));
    return stream;
}

KWinScreencastStream *KWinScreencasting::createWindowStream(const QString &uuid, CursorMode mode)
{
    if (!d->isInitialized())
        return nullptr;
    auto *stream = new KWinScreencastStream(this);
    stream->d->init(d->stream_window(uuid, uint32_t(mode)));
    return stream;
}
