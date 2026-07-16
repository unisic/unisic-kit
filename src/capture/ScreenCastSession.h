#pragma once
#include <QObject>
#include <QRect>

// Drives one org.freedesktop.portal.ScreenCast session:
// CreateSession -> SelectSources(monitor) -> Start -> OpenPipeWireRemote.
// Emits ready(fd, nodeId, streamSize) when frames can be consumed,
// or failed(error). Close by deleting the object (closes the session).
class ScreenCastSession : public QObject
{
    Q_OBJECT
public:
    explicit ScreenCastSession(QObject *parent = nullptr);
    ~ScreenCastSession() override;

    // Portal ScreenCast `cursor_mode` (a bitmask in the wire protocol, but only
    // one mode is ever requested): Hidden burns nothing, Embedded composites the
    // cursor into the frames, Metadata delivers it out-of-band per PipeWire
    // buffer (spa_meta_cursor) so the consumer can track/re-render it. Values
    // match the portal bits (HIDDEN=1, EMBEDDED=2, METADATA=4).
    enum class CursorMode { Hidden = 1, Embedded = 2, Metadata = 4 };

    // sourceTypes: bitmask MONITOR=1, WINDOW=2, VIRTUAL=4 (the portal shows a
    // matching picker). Default MONITOR for screen/region capture.
    void start(bool includeCursor, uint sourceTypes = 1, const QString &restoreToken = {});

    // Explicit-mode overload. Metadata is only requested when the portal
    // advertises it in AvailableCursorModes; otherwise it silently falls back to
    // Embedded (so an older portal still starts). Read effectiveCursorMode()
    // after ready() to learn which mode was actually negotiated. The bool
    // overload above is just start(includeCursor ? Embedded : Hidden).
    void start(CursorMode cursorMode, uint sourceTypes = 1, const QString &restoreToken = {});

    // The cursor_mode actually negotiated with the portal — valid once ready()
    // (or failed()) has fired. Consumers that requested Metadata should read
    // this and only wire up PipeWireGrabber's cursor path when it is Metadata.
    CursorMode effectiveCursorMode() const { return m_effectiveCursorMode; }

signals:
    // streamPos: the stream's logical position in the compositor workspace, or
    // (INT_MIN, INT_MIN) when the portal did not report one — (0,0) alone is
    // ambiguous, it is also a legit primary-monitor origin.
    void ready(int pipewireFd, uint nodeId, const QSize &streamSize, const QPoint &streamPos);
    void failed(const QString &error);
    void restoreTokenChanged(const QString &token);
    // The user stopped sharing from the system UI (portal Session Closed).
    void sessionClosed();

private:
    void createSession(CursorMode cursorMode);
    void selectSources(CursorMode cursorMode);
    void startCast();
    void openRemote(uint nodeId, const QSize &size, const QPoint &pos);

    QString m_sessionHandle;
    QString m_restoreToken;
    uint m_sourceTypes = 1;
    bool m_restoreTokensSupported = false;
    CursorMode m_effectiveCursorMode = CursorMode::Hidden;
};
