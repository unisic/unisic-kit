import QtQuick
import QtQuick.Window

// THE keyboard-focus-follows-the-view rule for a Flickable: when Tab (or any
// other focus move) lands on a control the view has scrolled past, the view
// scrolls to it. Declare as a child of the Flickable, the third member of the
// same family as MiddleScroll and WheelBoost:
//
//     Flickable { id: fl; …; FocusScroll { flickable: fl } }
//
// It has to exist because a Flickable is not a Qt Quick Controls ScrollView and
// nothing in Qt scrolls a plain Flickable to its focused child - Tab happily
// moves focus off screen. Measured offscreen on Settings at 1060x700 before
// this component existed: the Capture pane's viewport is 528 px against 1715 px
// of content, and 22 of 60 Tab stops - every card past the seventh, and "Apply
// shortcuts" on the Hotkeys pane - sat below the fold with contentY still 0.
// The controls had focus, drew their ring and answered Space, entirely unseen.
//
// Three rules keep it from becoming a nuisance, and each one is load-bearing:
//
//  - It moves the view ONLY when the focused item is entirely OUT of sight.
//    Not "not fully visible": a click is a focus change too, and a control the
//    user just clicked is by definition on screen, so revealing a partially
//    visible item would scroll the page under the pointer that clicked it -
//    the one layout rule this project treats as load-bearing. An item with any
//    pixel inside the viewport is therefore left where it is (its focus ring
//    may be clipped; the alternative moves the page under the pointer), while
//    a Tab that lands past the fold - the case this exists for - reveals.
//  - It follows only focus INSIDE this Flickable. `activeFocusItem` is a
//    window-wide notion - the sidebar, the header buttons and a second pane all
//    write it - so the ancestor walk in reveal() is what makes this pane's
//    share of it this component's business and nothing else.
//  - The glide is short (a Tab held down arrives every ~30 ms; anything longer
//    would visibly lag behind the ring) and is abandoned the moment the user
//    drags or flicks, so a scroll gesture always wins over an old glide.
Item {
    id: root

    required property Flickable flickable
    // Breathing room left around the revealed item, in px.
    property int margin: 12
    // Glide duration in ms. 0 scrolls in one frame.
    property int duration: 120

    // Never painted, never hit-tested, no size: it lives inside the moving
    // contentItem like its two siblings and must not add to what that contains.
    visible: false
    width: 0
    height: 0

    // Window-wide focus. reveal() decides whether it is ours.
    readonly property Item windowFocus: root.Window.activeFocusItem
    onWindowFocusChanged: root.reveal(root.windowFocus)

    // When the last reveal ran, so a key repeat can be told from a fresh move.
    property real _lastReveal: 0

    function reveal(item) {
        const f = root.flickable
        if (!f || !item || !f.visible)
            return
        // Only our own content: walk up to the contentItem every child of a
        // Flickable is parented into.
        let p = item
        while (p && p !== f.contentItem)
            p = p.parent
        if (!p)
            return

        const at = item.mapToItem(f.contentItem, 0, 0)
        // Any pixel of it already on screen means the user can see (and could
        // have clicked) it - leave the view alone. Only a control that is
        // completely past an edge is worth moving the page for.
        if (root._onScreen(f.contentY, f.height, at.y, item.height)
                && root._onScreen(f.contentX, f.width, at.x, item.width))
            return
        const y = root._axis(f.contentY, f.height, f.contentHeight, at.y, item.height)
        const x = root._axis(f.contentX, f.width, f.contentWidth, at.x, item.width)
        if (y === f.contentY && x === f.contentX)
            return
        // A flick still decaying would keep scrolling out from under the glide.
        f.cancelFlick()
        // A held Tab repeats ~30 times a second; easing every one of those
        // would leave the view a row behind the ring for as long as the key is
        // down (measured: sampled 20 ms after each press, every stop past the
        // seventh was still off screen, arriving only after the key was let
        // go). So a move that lands inside the previous one's glide is applied
        // at once, and only the first move after a pause is eased.
        const now = Date.now()
        const chasing = now - root._lastReveal < root.duration * 2
        root._lastReveal = now
        root._go(glideY, "contentY", f.contentY, y, chasing)
        root._go(glideX, "contentX", f.contentX, x, chasing)
    }

    // Does [pos, pos+len] overlap the viewport on this axis at all? No margin
    // here on purpose: the margin is breathing room for a reveal, not a reason
    // to start one.
    function _onScreen(at, viewLen, pos, len) {
        return pos + len > at && pos < at + viewLen
    }

    // Where one axis has to end up for [pos, pos+len] to sit inside the
    // viewport with `margin` to spare. Returns `at` unchanged when it already
    // does - that is the "never fight the user's own scrolling" rule.
    function _axis(at, viewLen, contentLen, pos, len) {
        if (contentLen <= viewLen)
            return at
        const near = pos - root.margin
        const far = pos + len + root.margin
        let want = at
        if (far > at + viewLen)
            want = far - viewLen
        // Tested second on purpose: an item TALLER than the viewport then ends
        // up showing its start rather than its end, which is where the label,
        // the caption and the ring are.
        if (near < want)
            want = near
        return Math.max(0, Math.min(want, contentLen - viewLen))
    }

    function _go(anim, prop, from, to, immediate) {
        anim.stop()
        if (from === to)
            return
        if (immediate || root.duration <= 0) {
            root.flickable[prop] = to
            return
        }
        anim.from = from
        anim.to = to
        anim.start()
    }

    NumberAnimation {
        id: glideY
        target: root.flickable
        property: "contentY"
        duration: root.duration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: glideX
        target: root.flickable
        property: "contentX"
        duration: root.duration
        easing.type: Easing.OutCubic
    }

    Connections {
        target: root.flickable
        // The user took the view over; where we were gliding to is now stale.
        function onDragStarted() { glideY.stop(); glideX.stop() }
        function onFlickStarted() { glideY.stop(); glideX.stop() }
    }
}
