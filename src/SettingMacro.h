#pragma once
#include <QSettings>
#include <QTimer>

// U_SETTING(type, name, setterName, key, defval) — extracted verbatim from
// Unisic's Settings.h so both Unisic and Unisic Studio declare their
// QSettings-backed Q_PROPERTYs the same way (the Settings class itself is NOT
// part of the kit; each app owns its own property list).
//
// Expands to:
//   * a getter reading `key` from the member `m_s`, defaulting to `defval`;
//   * an early-return setter that skips a no-op write, stores the value,
//     (re)starts the debounce member `m_syncTimer`, and emits name##Changed().
//
// The enclosing class MUST therefore provide, alongside a Q_OBJECT macro:
//   * QSettings m_s;                       // the backing store
//   * QTimer    m_syncTimer;               // single-shot debounce that sync()s m_s
//   * void name##Changed();                // a NOTIFY signal per use
//   * Q_PROPERTY(... NOTIFY name##Changed) // wiring each property to the pair
#define U_SETTING(type, name, setterName, key, defval)                                 \
    type name() const { return m_s.value(key, defval).value<type>(); }                 \
    void setterName(const type &v) {                                                   \
        if (name() == v) return;                                                       \
        m_s.setValue(key, v);                                                          \
        m_syncTimer.start();                                                            \
        emit name##Changed();                                                          \
    }
