import QtQuick

// The kit's one wheel-scrolling rule for a Flickable, matched to Chromium so a
// notch moves the same distance on every surface of the app and about as far
// as in a web browser. Declare as a child of the Flickable, like MiddleScroll.
// Wheel-only (NoButton) and z:-1: clicks, hover and the middle-click autoscroll
// pass through untouched.
//
// What Chromium does on Linux, and what this copies:
//  - A notch is 120 px (MouseWheelEvent::kWheelDelta = 120 in
//    ui/events/event.cc, kWheelScrollAmount = 120 in
//    ui/events/x/events_x_utils.cc), a fixed distance with no multiplier for a
//    fast spin. A spin covers more ground only because each notch adds 120 px
//    to the target of the glide already running.
//  - Each notch glides with an ease-in-out cubic-bezier(0.42, 0, 0.58, 1) over
//    200 ms for one notch, shortening linearly to 100 ms for 480 px or more
//    still to go (kInverseDelta in cc/animation/scroll_offset_animation_curve.cc).
//  - A notch during a glide retargets it: new target = old target + 120, the
//    new segment starts from where the view is with its current speed, and is
//    never slower than 2.5x the time that speed needs for the rest.
// There are no per-site settings on purpose: a surface that scrolled faster or
// slower than its neighbors is exactly what this replaced.
//
// Touchpad pixelDelta is never eased and never rounded: it is already a
// continuous stream and stays 1:1. Content that fits leaves the wheel to
// whatever is behind (a menu's click-away catcher, an outer page). The glide
// yields contentX/Y to anyone else the moment they touch it (the middle-click
// autoscroll, a drag, positionViewAtIndex): if the view is not where the last
// tick left it, the glide stops instead of fighting over it.
MouseArea {
    id: area
    required property Flickable flickable

    // Inside the contentItem, explicitly. A plain Flickable puts its declared
    // children there by itself, but a ListView or GridView keeps them as
    // direct children of the view, behind the contentItem, where the view
    // takes the wheel first: every item view in the app silently ran on
    // Flickable's own wheel physics (72 px per notch, measured) with this
    // component attached and never called.
    parent: area.flickable.contentItem
    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.NoButton

    readonly property real _stepPx: 120

    // --- glide state ---
    // _writtenX/Y is the last position this component put the view at; any
    // other value means somebody else is scrolling now (see _hijacked).
    property real _fromX: 0
    property real _fromY: 0
    property real _targetX: 0
    property real _targetY: 0
    property real _writtenX: 0
    property real _writtenY: 0
    property real _startMs: 0
    property real _durMs: 0
    // First control point's y of the segment's bezier; 0 = plain ease-in-out,
    // larger keeps the speed a retargeted glide already had.
    property real _y1: 0

    function _clampY(v) {
        const f = area.flickable
        return Math.max(0, Math.min(f.contentHeight - f.height, v))
    }
    function _clampX(v) {
        const f = area.flickable
        return Math.max(0, Math.min(f.contentWidth - f.width, v))
    }
    function _apply(x, y) {
        const f = area.flickable
        if (f.contentHeight > f.height) {
            f.contentY = area._clampY(y)
            area._writtenY = f.contentY
        }
        if (f.contentWidth > f.width) {
            f.contentX = area._clampX(x)
            area._writtenX = f.contentX
        }
    }
    // Per axis, and only where there is something to scroll: an axis this
    // component never writes (content that fits) would otherwise report a
    // stale position forever.
    function _hijacked() {
        const f = area.flickable
        return (f.contentHeight > f.height && Math.abs(f.contentY - area._writtenY) > 1)
            || (f.contentWidth > f.width && Math.abs(f.contentX - area._writtenX) > 1)
    }

    // cubic-bezier(0.42, y1, 0.58, 1): one coordinate at parameter s.
    function _bz(p1, p2, s) {
        return ((1 - 3 * p2 + 3 * p1) * s + (3 * p2 - 6 * p1)) * s * s + 3 * p1 * s
    }
    function _bzd(p1, p2, s) {
        return (3 * (1 - 3 * p2 + 3 * p1) * s + 2 * (3 * p2 - 6 * p1)) * s + 3 * p1
    }
    // The curve's parameter at time fraction u (x is monotonic: bisection).
    function _param(u) {
        let lo = 0, hi = 1, s = u
        for (let i = 0; i < 24; ++i) {
            s = (lo + hi) / 2
            if (area._bz(0.42, 0.58, s) < u) lo = s
            else hi = s
        }
        return s
    }
    function _progress(u) {
        return area._bz(area._y1, 1, area._param(u))
    }
    // Signed scroll speed of the running segment, px/ms, along its main axis.
    function _velocity(u) {
        const s = area._param(u)
        const dx = area._bzd(0.42, 0.58, s)
        const slope = dx > 1e-6 ? area._bzd(area._y1, 1, s) / dx : 0
        return slope * area._major(area._targetX - area._fromX, area._targetY - area._fromY) / area._durMs
    }
    function _major(dx, dy) {
        return Math.abs(dx) > Math.abs(dy) ? dx : dy
    }
    // kInverseDelta: 12 frames at 60 Hz for 120 px, down to 6 for 480 px.
    function _durationFor(dist) {
        return Math.max(6, Math.min(12, 12 - (Math.abs(dist) - 120) / 60)) * 1000 / 60
    }

    function _glideBy(dx, dy) {
        const f = area.flickable
        const now = Date.now()
        let v = 0
        if (glide.running && !area._hijacked()) {
            const u = Math.min(1, (now - area._startMs) / area._durMs)
            v = area._velocity(u)
            area._targetX = area._clampX(area._targetX - dx)
            area._targetY = area._clampY(area._targetY - dy)
        } else {
            area._writtenX = f.contentX
            area._writtenY = f.contentY
            area._targetX = area._clampX(f.contentX - dx)
            area._targetY = area._clampY(f.contentY - dy)
        }
        area._fromX = f.contentX
        area._fromY = f.contentY
        const rest = area._major(area._targetX - area._fromX, area._targetY - area._fromY)
        if (Math.abs(rest) < 0.5) {
            glide.stop()
            area._apply(area._targetX, area._targetY)
            return
        }
        let dur = area._durationFor(rest)
        // Velocity bound: a fast glide does not slow down to cover a short rest.
        if (v * rest > 0)
            dur = Math.min(dur, rest / v * 2.5)
        area._durMs = Math.max(16, dur)
        // Keep the current speed: the first control point's slope is set so the
        // new segment starts at v (clamped like Chromium's ±1000).
        const slope = Math.max(-1000, Math.min(1000, v * area._durMs / rest))
        area._y1 = 0.42 * slope
        area._startMs = now
        // start() on a running Timer RESTARTS its countdown: a high-resolution
        // wheel sending eight events per detent would keep pushing the next
        // tick away and the view would sit still until the hand stopped.
        if (!glide.running)
            glide.start()
    }

    // A press freezes the view. The glide is short, but it is still motion, and
    // this project's one load-bearing layout rule is that nothing moves under
    // the pointer: a click that lands while the tail of a wheel step is still
    // running has its target slide out from under it between press and release,
    // and a MouseArea only emits `clicked` when the release is still inside it.
    // Small controls lose that race first - a 50x30 switch is gone after 15 px
    // of glide - which reads as "this switch cannot be toggled".
    //
    // A plain Item, NOT a MouseArea, and a PointHandler, NOT a TapHandler:
    // PointHandler is the one handler that only ever takes a PASSIVE grab, so
    // the press is observed and passed on untouched. TapHandler is not - even
    // with gesturePolicy: DragThreshold it swallowed the click outright, which
    // tests/WheelBoostTest.cpp caught (the switch became unclickable in a
    // different way). The catcher has to sit ABOVE the content: events are
    // offered per item, top-most first, so from behind - like the wheel area
    // itself, at z:-1 - it would never see a press that lands on a control.
    // Nothing is drawn and no hover is claimed, so it stays invisible to
    // everything else.
    Item {
        parent: area.parent
        anchors.fill: parent
        z: 1e6
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) glide.stop()
        }
    }

    Timer {
        id: glide
        interval: 16
        repeat: true
        onTriggered: {
            const f = area.flickable
            if (!f || area._hijacked()) {
                glide.stop()
                return
            }
            // Re-clamp every tick: a model that shrinks mid-glide (a filter
            // switch, a deleted entry) moves the end of the content under us,
            // and a target left beyond it would never be reached.
            area._targetX = area._clampX(area._targetX)
            area._targetY = area._clampY(area._targetY)
            // Time-based, not per-tick: a late tick lands where the curve says,
            // so the glide takes the same time under load.
            const u = (Date.now() - area._startMs) / area._durMs
            if (u >= 1) {
                area._apply(area._targetX, area._targetY)
                glide.stop()
                return
            }
            const p = area._progress(u)
            area._apply(area._fromX + (area._targetX - area._fromX) * p,
                        area._fromY + (area._targetY - area._fromY) * p)
        }
    }

    onWheel: (w) => {
        const f = area.flickable
        if (!f || (f.contentHeight <= f.height && f.contentWidth <= f.width)) {
            w.accepted = false
            return
        }
        // Touchpad: a continuous pixel stream, passed through untouched.
        if (w.pixelDelta.x !== 0 || w.pixelDelta.y !== 0) {
            glide.stop()
            area._apply(f.contentX - w.pixelDelta.x, f.contentY - w.pixelDelta.y)
        } else {
            // A high-resolution wheel sends several partial notches per detent
            // (8 events of 15): each adds its share of the 120 px.
            area._glideBy((w.angleDelta.x / 120) * area._stepPx, (w.angleDelta.y / 120) * area._stepPx)
        }
        w.accepted = true
    }
}
