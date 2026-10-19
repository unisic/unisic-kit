// Windows build of X11Hotkeys: the same class and contract, backed by
// RegisterHotKey instead of XGrabKey. The header is shared with Linux, so the
// X11-named members are reused: m_dpy holds the HWND of a message-only window
// that receives WM_HOTKEY, m_map maps a hotkey id to an action id, and
// m_grabbed lists the registered ids.
//
// A message-only window, not a thread hotkey (RegisterHotKey(nullptr, ...)):
// thread messages carry no HWND, so a native modal loop (window move/resize,
// a system menu) drops them. A window message is dispatched by every loop.
#include "X11Hotkeys.h"
#include "ShortcutKeyMap.h"

#include <QDebug>
#include <QGuiApplication>
#include <QMetaObject>
#include <QOperatingSystemVersion>
#include <QSettings>

#include <windows.h>

namespace {

const wchar_t kSinkClass[] = L"UnisicHotkeySink";

// Windows 11 hands a bare Print Screen to the Snipping Tool ("Use the Print
// screen key to open screen capture", on by default since 22H2). Its
// RegisterHotKey still succeeds, but WM_HOTKEY never arrives. The value is
// absent until the user flips the switch once, so absent means the default.
bool snippingToolOwnsPrint()
{
    const QSettings kb(QStringLiteral("HKEY_CURRENT_USER\\Control Panel\\Keyboard"),
                       QSettings::NativeFormat);
    const QVariant on = kb.value(QStringLiteral("PrintScreenKeyForSnippingEnabled"));
    if (on.isValid())
        return on.toInt() != 0;
    return QOperatingSystemVersion::current() >= QOperatingSystemVersion::Windows11_22H2;
}

// Application hotkey ids live in 0x0000..0xBFFF; 0 is avoided so a zeroed
// wParam never matches.
constexpr int kFirstHotkeyId = 1;

LRESULT CALLBACK sinkProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_HOTKEY) {
        // nativeEventFilter is public on the base class, which is how this free
        // function reaches the protected override without widening the header.
        auto *filter = reinterpret_cast<QAbstractNativeEventFilter *>(
            GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (filter) {
            MSG m{};
            m.hwnd = hwnd;
            m.message = msg;
            m.wParam = wp;
            m.lParam = lp;
            qintptr result = 0;
            filter->nativeEventFilter(QByteArrayLiteral("windows_generic_MSG"), &m, &result);
        }
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

HWND createSink()
{
    const HINSTANCE inst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = sinkProc;
    wc.hInstance = inst;
    wc.lpszClassName = kSinkClass;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return nullptr;
    return CreateWindowExW(0, kSinkClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, inst,
                           nullptr);
}

UINT modsFor(const QStringList &mods)
{
    UINT m = 0;
    for (const QString &mod : mods) {
        if (mod == QLatin1String("Super"))      m |= MOD_WIN;
        else if (mod == QLatin1String("Ctrl"))  m |= MOD_CONTROL;
        else if (mod == QLatin1String("Alt"))   m |= MOD_ALT;
        else if (mod == QLatin1String("Shift")) m |= MOD_SHIFT;
    }
    return m;
}

// A punctuation key by the character it types on the active layout, so "/" is
// the key that types "/" here and not the US position. Falls back to the US
// OEM code when the character needs a modifier on this layout (VkKeyScan's
// high byte), since a hotkey cannot carry that hidden modifier.
UINT punctuationVk(wchar_t ch, UINT usFallback)
{
    const SHORT scan = VkKeyScanW(ch);
    if (scan != -1 && (scan & 0xff00) == 0)
        return UINT(scan & 0xff);
    return usFallback;
}

// X-keysym base name (ShortcutKeyMap::Chord::key) to a virtual-key code; 0 for
// anything Windows cannot register.
UINT vkFor(const QString &key)
{
    if (key.size() == 1) {
        const QChar c = key.at(0);
        if (c >= QLatin1Char('a') && c <= QLatin1Char('z'))
            return UINT('A' + (c.unicode() - 'a'));
        if (c >= QLatin1Char('0') && c <= QLatin1Char('9'))
            return UINT(c.unicode());
    }
    if (key.size() >= 2 && key.at(0) == QLatin1Char('F')) {
        bool num = false;
        const int n = key.mid(1).toInt(&num);
        if (num)
            return (n >= 1 && n <= 24) ? UINT(VK_F1 + n - 1) : 0;
    }
    static const struct { const char *name; UINT vk; } named[] = {
        {"Print", VK_SNAPSHOT}, {"Return", VK_RETURN}, {"space", VK_SPACE},
        {"Escape", VK_ESCAPE}, {"Tab", VK_TAB}, {"BackSpace", VK_BACK},
        {"Delete", VK_DELETE}, {"Insert", VK_INSERT}, {"Home", VK_HOME},
        {"End", VK_END}, {"Prior", VK_PRIOR}, {"Next", VK_NEXT},
        {"Left", VK_LEFT}, {"Right", VK_RIGHT}, {"Up", VK_UP}, {"Down", VK_DOWN},
        {"Menu", VK_APPS},
    };
    for (const auto &n : named)
        if (key == QLatin1String(n.name))
            return n.vk;
    static const struct { const char *name; wchar_t ch; UINT us; } punct[] = {
        {"slash", L'/', VK_OEM_2}, {"backslash", L'\\', VK_OEM_5},
        {"comma", L',', VK_OEM_COMMA}, {"period", L'.', VK_OEM_PERIOD},
        {"semicolon", L';', VK_OEM_1}, {"apostrophe", L'\'', VK_OEM_7},
        {"bracketleft", L'[', VK_OEM_4}, {"bracketright", L']', VK_OEM_6},
        {"minus", L'-', VK_OEM_MINUS}, {"equal", L'=', VK_OEM_PLUS},
        {"grave", L'`', VK_OEM_3},
    };
    for (const auto &p : punct)
        if (key == QLatin1String(p.name))
            return punctuationVk(p.ch, p.us);
    return 0;
}

} // namespace

X11Hotkeys::X11Hotkeys(QObject *parent) : QObject(parent)
{
    HWND sink = createSink();
    if (!sink) {
        qWarning() << "hotkeys: could not create the WM_HOTKEY window, error" << GetLastError();
        return;
    }
    SetWindowLongPtrW(sink, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(static_cast<QAbstractNativeEventFilter *>(this)));
    m_dpy = sink;
}

X11Hotkeys::~X11Hotkeys()
{
    ungrabAll();
    if (HWND sink = static_cast<HWND>(m_dpy)) {
        SetWindowLongPtrW(sink, GWLP_USERDATA, 0);
        DestroyWindow(sink);
    }
}

bool X11Hotkeys::isAvailable()
{
    return QGuiApplication::platformName() == QLatin1String("windows");
}

// No lock-key masking on Windows: RegisterHotKey already ignores Caps/Num Lock.
unsigned int X11Hotkeys::resolveNumLockMask()
{
    return 0;
}

QStringList X11Hotkeys::bind(const QVector<Shortcut> &shortcuts)
{
    HWND sink = static_cast<HWND>(m_dpy);
    if (!sink)
        return {};

    ungrabAll();
    int nextId = kFirstHotkeyId;
    QStringList conflicts;
    for (const Shortcut &s : shortcuts) {
        const QList<ShortcutKeyMap::Chord> chords = ShortcutKeyMap::parseAll(s.portable);
        bool anyOk = false;
        bool anyConflict = false;
        for (const ShortcutKeyMap::Chord &c : chords) {
            if (!c.ok || c.key.isEmpty())
                continue; // modifier-only: RegisterHotKey needs a base key
            const UINT vk = vkFor(c.key);
            if (vk == 0)
                continue;
            const UINT mods = modsFor(c.mods);
            const int id = nextId++;
            const QString chord = (c.mods + QStringList{c.key}).join(QLatin1Char('+'));
            // MOD_NOREPEAT: holding the key fires once, like a passive X grab.
            if (RegisterHotKey(sink, id, mods | MOD_NOREPEAT, vk)) {
                m_map.insert(quint32(id), s.id);
                m_grabbed.append({id, mods});
                // Kept registered all the same: it starts working the moment
                // the user turns the Windows switch off, with no rebind.
                if (mods == 0 && vk == VK_SNAPSHOT && snippingToolOwnsPrint()) {
                    qWarning().noquote() << "hotkeys:" << chord << "for" << s.id
                                         << "goes to the Snipping Tool (Windows Settings > Accessibility"
                                            " > Keyboard > Use the Print screen key to open screen capture)";
                    anyConflict = true;
                } else {
                    anyOk = true;
                }
            } else {
                const DWORD err = GetLastError();
                qWarning().noquote() << "hotkeys: RegisterHotKey failed for" << s.id
                                     << chord << "error" << err;
                anyConflict = true;
            }
        }
        if (anyConflict && !anyOk)
            conflicts << s.id;
    }
    return conflicts;
}

void X11Hotkeys::ungrabAll()
{
    if (HWND sink = static_cast<HWND>(m_dpy)) {
        for (const auto &g : m_grabbed)
            UnregisterHotKey(sink, g.first);
    }
    m_grabbed.clear();
    m_map.clear();
}

bool X11Hotkeys::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *)
{
    if (eventType != QByteArrayLiteral("windows_generic_MSG") || m_map.isEmpty())
        return false;
    const MSG *msg = static_cast<const MSG *>(message);
    if (msg->message != WM_HOTKEY)
        return false;
    const auto it = m_map.constFind(quint32(msg->wParam));
    if (it == m_map.constEnd())
        return false;
    // Queued, so the action never runs inside the window procedure (and so a
    // native modal loop that dispatched the message returns first).
    const QString id = it.value();
    QMetaObject::invokeMethod(this, [this, id] { emit activated(id); }, Qt::QueuedConnection);
    return false;
}
