import QtQuick

// Faster, deterministic wheel scrolling for a Flickable: each mouse-wheel
// notch moves a fixed pixel step (Flickable's built-in wheel physics needed
// far too many notches on long pages), while touchpads keep their precise
// 1:1 pixelDelta feel. Declare as a child of the Flickable, like
// MiddleScroll. Wheel-only (NoButton) and z:-1 — clicks, hover and the
// middle-click autoscroll pass through untouched.
//
// Three things shape the feel; the defaults are tuned for a page of short
// rows (a column of setting cards), which is what most call sites are.
//
//  - stepPx is the plain, unhurried step of a single deliberate notch. A view
//    whose rows are TALL should raise it: 220 px is one whole tile in the
//    History grid, and one row per notch reads as crawling on a maximized
//    window, where a row is a sixth of the viewport. Derive it from the row
//    height and the viewport there, do not raise this default.
//  - notches that keep coming within boostWindowMs of each other build a
//    multiplier up to maxBoost, so a long spin covers ground while a single
//    notch stays exactly stepPx. The boosted step is capped at 90% of the
//    viewport, so no notch can ever jump clean over content nobody saw.
//    maxBoost: 1 turns the ramp off.
//  - settleMs eases each wheel step in over that many milliseconds instead of
//    teleporting; a boosted step is most of a screen and needs the motion to
//    stay readable. 0 restores the old instant jump.
//
// Touchpad pixelDelta is never boosted, never eased and never rounded: it is
// already a continuous stream and stays 1:1. The easing also yields contentX/Y
// to anyone else the moment they touch it (the middle-click autoscroll, a
// drag, positionViewAtIndex): if the view is not where the last tick left it,
// the glide stops instead of fighting over it.
MouseArea {
    id: area
    required property Flickable flickable
    // Pixels scrolled per mouse-wheel notch.
    property real stepPx: 220
    // Ceiling of the fast-spin multiplier. 1 = every notch is stepPx.
    property real maxBoost: 3
    // A notch this soon after the previous one counts as part of a spin.
    property int boostWindowMs: 300
    // How much of the multiplier one full notch adds.
    property real boostPerNotch: 0.5
    // Glide duration of a wheel step, in ms. 0 = jump there in one frame.
    property int settleMs: 110

    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.NoButton

    // --- glide state ---
    // _writtenX/Y is the last position this component put the view at; any
    // other value means somebody else is scrolling now (see _hijacked).
    property real _boost: 1
    property real _lastNotchMs: 0
    property real _targetX: 0
    property real _targetY: 0
    property real _writtenX: 0
    property real _writtenY: 0

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
            f.contentY = y
            area._writtenY = f.contentY
        }
        if (f.contentWidth > f.width) {
            f.contentX = x
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
    function _scrollBy(dx, dy, smooth) {
        const f = area.flickable
        if (!smooth || area.settleMs <= 0) {
            glide.stop()
            area._apply(area._clampX(f.contentX - dx), area._clampY(f.contentY - dy))
            return
        }
        // A fresh glide starts from where the view actually is; a glide already
        // running accumulates, so notches arriving faster than it settles do
        // not each lose the distance the previous one had left to cover.
        if (!glide.running || area._hijacked()) {
            area._targetX = f.contentX
            area._targetY = f.contentY
            area._writtenX = f.contentX
            area._writtenY = f.contentY
        }
        area._targetX = area._clampX(area._targetX - dx)
        area._targetY = area._clampY(area._targetY - dy)
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
            const restX = f.contentWidth > f.width ? area._targetX - f.contentX : 0
            const restY = f.contentHeight > f.height ? area._targetY - f.contentY : 0
            if (Math.abs(restX) < 0.5 && Math.abs(restY) < 0.5) {
                area._apply(area._targetX, area._targetY)
                glide.stop()
                return
            }
            // Exponential ease-out: k is the fraction of what is left to cover
            // this frame, sized so ~95% of the step has landed after settleMs.
            const k = 1 - Math.pow(0.05, glide.interval / Math.max(glide.interval, area.settleMs))
            area._apply(f.contentX + restX * k, f.contentY + restY * k)
        }
    }

    onWheel: (w) => {
        const f = area.flickable
        if (!f) {
            w.accepted = false
            return
        }
        // Touchpad: a continuous pixel stream, passed through untouched.
        if (w.pixelDelta.x !== 0 || w.pixelDelta.y !== 0) {
            area._boost = 1
            area._scrollBy(w.pixelDelta.x, w.pixelDelta.y, false)
            w.accepted = true
            return
        }
        const now = Date.now()
        // High-resolution wheels send several partial notches per detent, so
        // the ramp counts angle, not events: a detent is worth one bump
        // whether it arrives as 1 event of 120 or 8 events of 15.
        const notches = Math.max(Math.abs(w.angleDelta.x), Math.abs(w.angleDelta.y)) / 120
        area._boost = (now - area._lastNotchMs) > area.boostWindowMs
                    ? 1
                    : Math.min(area.maxBoost, area._boost + area.boostPerNotch * notches)
        area._lastNotchMs = now
        const step = area.stepPx * area._boost
        area._scrollBy((w.angleDelta.x / 120) * Math.min(step, f.width * 0.9),
                       (w.angleDelta.y / 120) * Math.min(step, f.height * 0.9), true)
        w.accepted = true
    }
}
