pragma Singleton
import QtQuick

// THE authoritative keyboard-activation rule for the whole design system - kit
// components and app-side controls alike route every key handler through here,
// so the rule can never drift between them. This is the only copy of the
// explanation; everything else just calls it.
//
// Why a rule is needed at all: Qt dispatches the DEDICATED attached handlers
// (Keys.onSpacePressed / onReturnPressed / onEnterPressed / onUpPressed / …)
// BEFORE Keys.onPressed, REGARDLESS of the modifiers held, and auto-accepts
// them. So a focused control silently swallows the window's own chords - the
// editor's Ctrl+Enter (quick copy-and-close) died the moment anything had
// focus. Clearing `accepted` inside the handler puts the event back on the
// normal path: this item's Keys.onPressed still runs and the event keeps
// bubbling to every ancestor key scope.
//
// KeypadModifier is masked out of the test because Qt sets it on the numpad's
// own Enter and its arrows/Home/End (NumLock off), which must still act.
//
// Use the dedicated handlers, one per key - never a blanket Keys.onPressed with
// an unconditional accept, which would eat the editor's and the overlay's
// single-letter tool shortcuts, Escape and Ctrl+Z along with everything else:
//
//     activeFocusOnTab: enabled
//     Keys.onSpacePressed:  (e) => UKeys.activate(e, root._activate)
//     Keys.onReturnPressed: (e) => UKeys.activate(e, root._activate)
//     Keys.onEnterPressed:  (e) => UKeys.activate(e, root._activate)
//
// `_activate` is the control's ONE activation path - the same function the
// MouseArea and Accessible.onPressAction call, so pointer, keyboard and
// assistive tech can never drift apart. When there is more to do than call it,
// keep a named function and open it with the guard:
//
//     function _keyStep(e, delta) {
//         if (!UKeys.claim(e))
//             return
//         ...
//     }
//     Keys.onDownPressed: (e) => root._keyStep(e, -1)
//
// A plain Keys.onPressed arrives UNaccepted, so there a declined chord needs no
// write at all - just test and fall through, and it keeps bubbling:
//
//     Keys.onPressed: (e) => {
//         if (!UKeys.unmodified(e))
//             return
//         ...
//     }
QtObject {
    id: keys

    // Pure test, no side effect: is this the bare key, with no chord on it?
    // For a Keys.onPressed handler, which arrives unaccepted.
    function unmodified(event) {
        return (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier
    }

    // The guard for a DEDICATED handler, which arrives pre-accepted: true when
    // the handler owns the key; otherwise the event is handed back to the
    // bubbling path and the caller must do nothing with it.
    function claim(event) {
        if (keys.unmodified(event))
            return true
        event.accepted = false
        return false
    }

    // The common case: claim the key, then run the control's activation path.
    function activate(event, action) {
        if (keys.claim(event))
            action()
    }
}
