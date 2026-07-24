#include "X11Hotkeys.h"
#include "ShortcutKeyMap.h"

#include <QGuiApplication>
#include <QDebug>
// QNativeInterface::QX11Application (display()) is declared in the platform
// header, not pulled by <QGuiApplication> alone.
#if __has_include(<QtGui/qguiapplication_platform.h>)
#include <QtGui/qguiapplication_platform.h>
#endif

#include <xcb/xcb.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>

namespace {

// The four real modifiers Unisic binds; lock keys (Caps/Num/Scroll) are masked
// out so a hotkey still fires with NumLock on. Same bit values in Xlib and xcb.
constexpr unsigned int kAllMods = ShiftMask | ControlMask | Mod1Mask | Mod4Mask;

// XGrabKey reports "combo already owned by another client" asynchronously as a
// BadAccess. A benign handler records it (checked after an XSync) instead of the
// default Xlib handler calling exit(). Only our own Xlib calls hit this handler;
// Qt's xcb platform uses the xcb error path and is unaffected. All access is on
// the GUI thread (bind runs there), so a plain static flag is safe.
bool g_grabBadAccess = false;
int grabErrorHandler(Display *, XErrorEvent *e)
{
    if (e->error_code == BadAccess)
        g_grabBadAccess = true;
    return 0;
}

unsigned int modMaskFor(const QStringList &mods)
{
    unsigned int m = 0;
    for (const QString &mod : mods) {
        if (mod == QLatin1String("Super"))      m |= Mod4Mask;
        else if (mod == QLatin1String("Ctrl"))  m |= ControlMask;
        else if (mod == QLatin1String("Alt"))   m |= Mod1Mask;
        else if (mod == QLatin1String("Shift")) m |= ShiftMask;
    }
    return m;
}

} // namespace

X11Hotkeys::X11Hotkeys(QObject *parent) : QObject(parent)
{
    if (auto *x11 = qApp->nativeInterface<QNativeInterface::QX11Application>()) {
        m_dpy = x11->display();
        if (m_dpy)
            m_root = DefaultRootWindow(static_cast<Display *>(m_dpy));
    }
}

X11Hotkeys::~X11Hotkeys()
{
    ungrabAll();
    if (m_filterInstalled)
        qApp->removeNativeEventFilter(this);
}

bool X11Hotkeys::isAvailable()
{
    if (QGuiApplication::platformName() != QLatin1String("xcb"))
        return false;
    auto *x11 = qApp->nativeInterface<QNativeInterface::QX11Application>();
    return x11 && x11->display();
}

unsigned int X11Hotkeys::resolveNumLockMask()
{
    Display *dpy = static_cast<Display *>(m_dpy);
    if (!dpy)
        return Mod2Mask;
    const KeyCode numlock = XKeysymToKeycode(dpy, XK_Num_Lock);
    if (!numlock)
        return Mod2Mask;
    XModifierKeymap *mm = XGetModifierMapping(dpy);
    if (!mm)
        return Mod2Mask;
    unsigned int mask = Mod2Mask;
    for (int i = 0; i < 8; ++i)
        for (int j = 0; j < mm->max_keypermod; ++j)
            if (mm->modifiermap[i * mm->max_keypermod + j] == numlock)
                mask = (1u << i);
    XFreeModifiermap(mm);
    return mask;
}

QStringList X11Hotkeys::bind(const QVector<Shortcut> &shortcuts)
{
    Display *dpy = static_cast<Display *>(m_dpy);
    if (!dpy)
        return {};

    ungrabAll();
    if (!m_filterInstalled) {
        qApp->installNativeEventFilter(this);
        m_filterInstalled = true;
    }
    m_numLockMask = resolveNumLockMask();
    // Grab each combo with every on/off state of the ignorable locks (Caps + Num)
    // so the key fires regardless of their state.
    const unsigned int ignore[4] = {0, LockMask, m_numLockMask, LockMask | m_numLockMask};

    QStringList conflicts;
    XSync(dpy, False);
    for (const Shortcut &s : shortcuts) {
        const QList<ShortcutKeyMap::Chord> chords = ShortcutKeyMap::parseAll(s.portable);
        bool anyOk = false;
        bool anyConflict = false;
        for (const ShortcutKeyMap::Chord &c : chords) {
            if (!c.ok || c.key.isEmpty())
                continue; // modifier-only: XGrabKey needs a base key
            const KeySym ks = XStringToKeysym(c.key.toUtf8().constData());
            if (ks == NoSymbol)
                continue;
            const KeyCode kc = XKeysymToKeycode(dpy, ks);
            if (kc == 0)
                continue;
            const unsigned int mods = modMaskFor(c.mods);
            m_map.insert((quint32(kc) << 8) | (mods & kAllMods), s.id);

            g_grabBadAccess = false;
            XErrorHandler prev = XSetErrorHandler(grabErrorHandler);
            for (unsigned int ig : ignore)
                XGrabKey(dpy, kc, mods | ig, m_root, False, GrabModeAsync, GrabModeAsync);
            XSync(dpy, False); // force the async BadAccess (if any) to arrive now
            XSetErrorHandler(prev);
            m_grabbed.append({int(kc), mods});
            if (g_grabBadAccess)
                anyConflict = true;
            else
                anyOk = true;
        }
        if (anyConflict && !anyOk)
            conflicts << s.id;
    }
    return conflicts;
}

void X11Hotkeys::ungrabAll()
{
    Display *dpy = static_cast<Display *>(m_dpy);
    if (dpy && !m_grabbed.isEmpty()) {
        const unsigned int ignore[4] = {0, LockMask, m_numLockMask, LockMask | m_numLockMask};
        for (const auto &g : m_grabbed)
            for (unsigned int ig : ignore)
                XUngrabKey(dpy, g.first, g.second | ig, m_root);
        XSync(dpy, False);
    }
    m_grabbed.clear();
    m_map.clear();
}

bool X11Hotkeys::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *)
{
    if (eventType != QByteArrayLiteral("xcb_generic_event_t") || m_map.isEmpty())
        return false;
    auto *ev = static_cast<xcb_generic_event_t *>(message);
    if ((ev->response_type & ~0x80) != XCB_KEY_PRESS)
        return false;
    auto *ke = reinterpret_cast<xcb_key_press_event_t *>(ev);
    const quint32 key = (quint32(ke->detail) << 8) | (ke->state & kAllMods);
    const auto it = m_map.constFind(key);
    if (it == m_map.constEnd())
        return false;
    emit activated(it.value());
    return false; // let Qt keep processing; a root grab has no focused Qt window
}
