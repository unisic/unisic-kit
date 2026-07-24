#pragma once
#include <QObject>
#include <QAbstractNativeEventFilter>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QHash>
#include <QPair>

// Global hotkeys on an X11 session via XGrabKey - the reliable native path on
// non-KDE X11 (GNOME/Xorg, Xfce, ...), where KGlobalAccel is absent and the
// GlobalShortcuts portal backend is flaky/hardwired. Mirrors the
// PortalGlobalShortcuts shape: emit activated(id) -> AppContext::dispatchHotkey.
// KDE-X11 is NOT routed here - KGlobalAccel already works over D-Bus there.
//
// Uses Qt's own X connection (QX11Application::display()), so the passive root
// grabs deliver KeyPress straight into Qt's xcb event pump where
// nativeEventFilter() catches them - no second display, no capture thread.
//
// This header stays free of any <X11/...> include on purpose: Xlib's macros
// (None/Bool/KeyPress/...) would leak into every TU that includes it (AppContext).
class X11Hotkeys : public QObject, public QAbstractNativeEventFilter
{
    Q_OBJECT
public:
    struct Shortcut {
        QString id;        // stable action id, e.g. "capture-region"
        QString portable;  // Qt portable string, may hold comma-separated alternates
    };

    explicit X11Hotkeys(QObject *parent = nullptr);
    ~X11Hotkeys() override;

    // True when qApp runs on the xcb platform and an X display is reachable.
    static bool isAvailable();

    // (Re)grab the whole set - ungrabs the previous grabs first. Returns the ids
    // whose key another client already owns (XGrabKey BadAccess), so the UI can
    // surface a conflict toast, same as the KGlobalAccel path.
    QStringList bind(const QVector<Shortcut> &shortcuts);

signals:
    void activated(const QString &id);

protected:
    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

private:
    void ungrabAll();
    unsigned int resolveNumLockMask();

    void *m_dpy = nullptr;      // Display* (Qt's connection, not owned)
    unsigned long m_root = 0;   // Window
    unsigned int m_numLockMask = 0;
    bool m_filterInstalled = false;
    // (keycode << 8 | cleanModMask) -> action id. cleanModMask keeps only the
    // four real modifiers, so lock keys (Caps/Num) never spoil a match.
    QHash<quint32, QString> m_map;
    // (keycode, base modMask) grabbed, for ungrab across the lock variants.
    QVector<QPair<int, unsigned int>> m_grabbed;
};
