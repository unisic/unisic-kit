/*
    Client of KWin's zkde_screencast_unstable_v1 Wayland protocol — the
    KDE-native screen-recording path (what Spectacle uses). Unlike the portal,
    the APP names the capture source itself: no system share dialog, no restore
    tokens. KWin authorizes by the installed .desktop file of the caller:
    X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1 — without it the
    global never binds and isAvailable() stays false (callers then fall back
    to the portal, mirroring the KWinScreenShot2 -> Portal screenshot pattern).

    Adapted from KDE Spectacle's src/Platforms/screencasting.{h,cpp}:
    SPDX-FileCopyrightText: 2020 Aleix Pol Gonzalez <aleixpol@kde.org>
    SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
*/

#pragma once

#include <QObject>
#include <QScopedPointer>

class QScreen;
class QRect;
class QSize;

class KWinScreencastingPrivate;
class KWinScreencastStreamPrivate;

// One requested stream. The compositor answers asynchronously: created(nodeId)
// hands the PipeWire node to consume (connect PipeWireGrabber to the DEFAULT
// PipeWire daemon — there is no portal fd on this path), failed(error) reports
// refusal, closed() fires when the compositor ends the cast (output unplugged,
// window closed). Deleting the object closes the stream.
class KWinScreencastStream : public QObject
{
    Q_OBJECT
public:
    explicit KWinScreencastStream(QObject *parent);
    ~KWinScreencastStream() override;

    quint32 nodeId() const;

Q_SIGNALS:
    void created(quint32 nodeId);
    void failed(const QString &error);
    void closed();

private:
    friend class KWinScreencasting;
    QScopedPointer<KWinScreencastStreamPrivate> d;
};

class KWinScreencasting : public QObject
{
    Q_OBJECT
public:
    explicit KWinScreencasting(QObject *parent = nullptr);
    ~KWinScreencasting() override;

    // Same wire values as the portal's cursor_mode (and KWin's protocol enum).
    enum CursorMode {
        Hidden = 1,
        Embedded = 2,
        Metadata = 4,
    };
    Q_ENUM(CursorMode)

    // False when not on KWin OR the desktop file did not declare the
    // interface — treat exactly like a KWinScreenShot2 auth failure and use
    // the portal instead.
    bool isAvailable() const;

    // Whole output. The stream is the output's pixel size, DPR-native.
    KWinScreencastStream *createOutputStream(QScreen *screen, CursorMode mode);

    // Exact region, GLOBAL logical coordinates (compositor workspace space).
    // The compositor crops server-side — the stream is just the region, no
    // app-side ffmpeg crop. `scaling` is the output scale factor to render at
    // (pass the target screen's devicePixelRatio for pixel-perfect capture).
    // Needs protocol v3+ — check regionStreamsSupported() first.
    KWinScreencastStream *createRegionStream(const QRect &region, qreal scaling, CursorMode mode);
    bool regionStreamsSupported() const;

    // A single window, by KWin's window uuid (org.kde.KWin queryWindowInfo /
    // plasma window management report it).
    KWinScreencastStream *createWindowStream(const QString &uuid, CursorMode mode);

private:
    QScopedPointer<KWinScreencastingPrivate> d;
};
