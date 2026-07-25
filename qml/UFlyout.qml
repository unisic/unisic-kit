pragma Singleton
import QtQuick

// THE containment rule for every flyout in the design system - the dropdowns
// (UComboBox, UValueCombo), the action menus (UMenuButton), the centred popups
// (UColorPopup, UConfirmDialog, UShortcutsHelp) and the hover tip all route
// their geometry through here, so "a flyout never hangs off the window" cannot
// drift between them. This is the only copy of the explanation; the components
// just call it.
//
// THE RULE, in two sentences. A flyout is CLAMPED inside the window on both
// axes with a `margin` gutter and it SHRINKS - scrolling its own content -
// rather than growing past a window edge OR over the control it belongs to. An
// anchored one opens BELOW that control and ABOVE it when there is no room
// below; the side is chosen once per opening and then HELD for as long as it
// stays usable, so a list can re-fit under a window resize without ever jumping
// across its own field while the user is working in it.
//
// WHO DOES WHAT - the split matters, because two of the five parts are Qt's and
// the other three are ours:
//
// 1. CLAMPING IS QT'S JOB. QQuickPopup.margins defaults to -1, which means "no
//    clamping at all" - that default was the whole bug. Set it (any value >= 0)
//    and QQuickPopupPositioner re-runs on the popup's own size changes, on the
//    anchor item's geometry, on EVERY ancestor's geometry (so a Flickable
//    scrolling under an open list drags the list along with it) and on the
//    window resizing, pulling the flyout back inside the window each time.
//    Arithmetic in onAboutToShow cannot do any of that: it runs ONCE, before
//    every one of those events.
//    Measured (offscreen probe, real components, Qt 6.11): a 130x340 list on a
//    bottom-right anchor of an 880x560 window painted at [790,554 b=894] with
//    the default margins - 40px past the right edge and 334px past the bottom -
//    and at [742,212 b=552] with margins:8. Resizing 1060x700 -> 880x560 with
//    the list open left it R+150 B+114 outside before, fits after. Scrolling the
//    host Flickable 250px under an open list left the list 124px ON TOP OF its
//    own field before; after, it travels with the anchor and the 6px gap is held
//    exactly - for as long as the side it is on still has room for it. When the
//    same event takes the room away, clamping is all Qt can do and it puts the
//    flyout back over its own field, which is what (3) and (4) are for.
//
// 2. TRACKING NEEDS THE POPUP PARENTED TO ITS ANCHOR ITEM, not to
//    Overlay.overlay - the anchor's ancestor chain is what Qt watches, and
//    `x`/`y` are then anchor-LOCAL, which is what keeps a flyout attached to a
//    field that moves. This costs nothing: a Popup's visual item is reparented
//    into the window overlay when it opens, whatever `parent` is, so it still
//    escapes every clip:true ancestor. Measured: a popup anchored to an item
//    inside a clip:true Flickable painted #00ff00 both 20px and 60px BELOW that
//    Flickable's clip rect. (A CENTRED popup keeps parent: Overlay.overlay - the
//    window IS its anchor.)
//
// 3. SHRINKING IS OURS, AND IT IS MEASURED AGAINST THE CHOSEN SIDE, NOT JUST
//    THE WINDOW. Qt only auto-resizes a popup that has no explicit size, so an
//    explicitly-sized list just hangs off the edge: measured, a 340-tall popup
//    in a 300-tall window painted at y=-48, i.e. 48px above the top, with
//    margins:8 set. fitHeight()/fitWidth() cap the wanted size to the window,
//    and fitHeight() takes a second cap - `room`, what is actually free on the
//    side the flyout sits on - because a clamp can only MOVE a flyout, never
//    shrink it. With the window cap alone Qt slid the list back inside the
//    window straight over the field that opened it, every time the window was
//    the smaller of the two constraints. Measured (offscreen probe, real
//    UComboBox, Qt 6.11), 10 rows on a 40px field at y=300 of an 880x560
//    window, where 340 fits neither side: painted 340 tall at y=8, bottom 348,
//    COVERING all 40px of its own field; with the room cap it is 286 tall at
//    y=8, bottom 294, i.e. the 6px gap above its field held exactly, and its
//    own ListView scrolls the rest. Same shape of result for the two other ways
//    the room can shrink under an open list: resizing 880x560 -> 880x300 gave
//    340 tall clamped to y=8, cover 40 (the whole field) before, 206 tall at
//    y=86 and cover 0 after; scrolling a Flickable 300px so the field moved to
//    y=460 gave 340 tall clamped to y=352, cover 40, before, and 186 tall at
//    y=506 with the 6px gap after. A list that cannot show all its rows must
//    scroll, never overflow and never cover its anchor.
//
// 4. WHICH SIDE, AND WHEN IT MAY CHANGE, IS OURS. Qt has no flip for a plain
//    Popup - measured, it only ever moves and clamps, so a list on a bottom
//    anchor ends up covering its own field. Two functions, and the difference
//    between them is the whole point:
//      * sideAtOpen() CHOOSES: below when the flyout fits below (above for a
//        `preferAbove` flyout, whose trigger sits on the window's bottom edge),
//        the other side when it does not fit, the roomier side when neither
//        fits.
//      * sideNow() may only REVISE, and it holds the current side while that
//        side still offers `minRoom` (or everything the flyout wants, if that
//        is less). Only when the side it is on has stopped being usable AND the
//        other one is usable does it move, once. Re-choosing freely instead was
//        the bug: a searchable list changes height on every keystroke, so an
//        open dropdown jumped across its own field while the user typed in it.
//        Measured, a 60-entry searchable list open ABOVE a field at y=580,
//        typing four characters into its search box: the fourth (which filters
//        the list down to nothing) re-chose "below" and threw the whole popup
//        across the field - the bottom edge that had been pinned 6px above the
//        field ended up 58px below it (+104px), the top edge +138px. Holding
//        the side, that anchored edge does not move at all: 0px on every one of
//        the four keystrokes, side still above, never a pixel of overlap with
//        the field. What still moves is the far edge, because the list genuinely
//        got shorter; an above-placed flyout keeps the edge that touches its
//        control (see offsetY).
//        The one exception is the enter transition - until `opened` turns true
//        the content is still settling and nobody can have interacted yet, so
//        sideNow() is allowed to choose freely there (pass settled=false), which
//        is what makes a list that measures its rows one frame late land on the
//        right side.
//
// 5. WATCHING THE FIT IS OURS TOO, AND IT IS A BINDING, NOT A SIGNAL. rooms()
//    adds up `y` along the anchor's parent chain instead of calling mapToItem():
//    the walk READS QML properties, so a BINDING that calls it depends on the
//    overlay's size, on the anchor's height and on the position of every item
//    between them - and re-evaluates when a window resize, a Flickable
//    scrolling under the flyout or a layout change moves any of them.
//    mapToItem() reads the same numbers through C++ transforms, where a binding
//    captures nothing; that is why the old code could only re-fit on the popup's
//    OWN height change, and why a resized window or a scrolled anchor left the
//    list sitting on top of its own field (the resize and the scroll numbers in
//    (3) are exactly those two events). Components gate the binding on
//    `visible`, so a closed flyout re-evaluates nothing.
//
// The lines an anchored flyout needs, and they go together:
//
//     property bool flyUp: false
//     readonly property real flyWant: <the height the content wants>
//     readonly property var  flyFit: visible ? UFlyout.rooms(anchor, overlay, flyWant) : null
//     onFlyFitChanged: flyUp = UFlyout.sideNow(flyUp, flyFit, opened, preferAbove)
//     height: UFlyout.fitHeight(overlay, flyWant, UFlyout.roomOn(flyFit, flyUp))
//     y: UFlyout.offsetY(popup, anchor, flyUp)
//     onAboutToShow: flyUp = UFlyout.sideAtOpen(anchor, overlay, flyWant, preferAbove)
//
// Plain overlay Items that are not Popups (UHoverTip) get no positioner at all,
// so they clamp through clampX()/clampY() in their own bindings instead.
QtObject {
    id: flyout

    // Gutter kept between a flyout and the window edge. Also the amount by
    // which a flyout is allowed to shrink into.
    readonly property int margin: 8
    // Gap between an anchor control and the flyout it opens.
    readonly property int gap: 6
    // "Still usable", for the hold rule in sideNow(): two 34px rows plus a
    // popup's 6px padding at each end. Less than this and the flyout has
    // stopped being a list worth staying on that side for.
    readonly property int minRoom: 80

    function _ok(overlay) { return !!overlay && overlay.width > 0 && overlay.height > 0 }

    // --- the shrink rule -------------------------------------------------
    // Largest size a flyout may ask for. Callers pass what they WANT (content
    // height, a design cap) and bind to the result, so the value follows the
    // window: `height: UFlyout.fitHeight(overlay, wanted, room)`.
    // `room` is optional and is what is free on the side the flyout is on -
    // pass UFlyout.roomOn(fit, side) for an anchored flyout, and nothing at all
    // for a centred one, which has no side and no anchor to cover.
    function fitHeight(overlay, wanted, room) {
        var h = wanted
        if (flyout._ok(overlay))
            h = Math.min(h, overlay.height - 2 * flyout.margin)
        if (room !== undefined && room !== null)
            h = Math.min(h, room)
        return Math.max(0, h)
    }
    function fitWidth(overlay, wanted) {
        if (!flyout._ok(overlay))
            return wanted
        return Math.max(0, Math.min(wanted, overlay.width - 2 * flyout.margin))
    }

    // --- the clamp rule, for non-Popup overlay items ---------------------
    // Popups get this from Qt (see 1). A plain Item on the overlay has to do it
    // in its own x/y binding.
    function clampX(overlay, x, w) {
        if (!flyout._ok(overlay))
            return x
        return Math.max(flyout.margin, Math.min(x, overlay.width - w - flyout.margin))
    }
    function clampY(overlay, y, h) {
        if (!flyout._ok(overlay))
            return y
        return Math.max(flyout.margin, Math.min(y, overlay.height - h - flyout.margin))
    }

    // --- reading the fit, as a binding (see 5) ---------------------------
    // Sum of `y` up the parent chain. Every step is a QML property read, so a
    // binding that calls this depends on the whole chain; mapToItem() would
    // return the same number and capture nothing. The one thing the sum does
    // NOT carry that a transform would is an ancestor `scale` or `rotation` -
    // no flyout anchor in the design system has one (the pressed-scale on the
    // controls themselves is on the anchor, which does not move its own y), and
    // a scaled ancestor would need a real transform walk here.
    function _absY(item) {
        var y = 0
        for (var p = item; p; p = p.parent)
            y += p.y
        return y
    }
    // { above, below, want }: the room free on each side of `anchor` inside
    // `overlay` (gap and margin already taken off), plus the height the flyout
    // wants, so the side rule below needs nothing else. null when there is no
    // window to measure against yet - every consumer treats that as "leave it
    // exactly as it is".
    function rooms(anchor, overlay, wanted) {
        if (!anchor || !flyout._ok(overlay))
            return null
        const top = flyout._absY(anchor) - flyout._absY(overlay)
        return {
            "above": top - flyout.gap - flyout.margin,
            "below": overlay.height - flyout.margin - (top + anchor.height + flyout.gap),
            "want": wanted
        }
    }
    // The room on the side the flyout is currently on; undefined (= no cap) when
    // there is nothing to measure yet.
    function roomOn(fit, above) {
        if (!fit)
            return undefined
        return above === true ? fit.above : fit.below
    }

    // --- the side rule (see 4) -------------------------------------------
    function _choose(fit, preferAbove) {
        const fitsBelow = fit.want <= fit.below
        const fitsAbove = fit.want <= fit.above
        if (fitsBelow && fitsAbove) return preferAbove === true
        if (fitsBelow)              return false
        if (fitsAbove)              return true
        return fit.above > fit.below
    }
    // Picked once, when the flyout opens.
    function sideAtOpen(anchor, overlay, wanted, preferAbove) {
        const fit = flyout.rooms(anchor, overlay, wanted)
        if (!fit)
            return preferAbove === true
        return flyout._choose(fit, preferAbove)
    }
    // The only thing that may change it afterwards. `settled` is the popup's
    // `opened`: false while the enter transition is still running (the content
    // is settling, nobody has interacted yet, so the side is still free), true
    // once the flyout is up, where the side is HELD until it stops being usable.
    function sideNow(above, fit, settled, preferAbove) {
        if (!fit)
            return above === true
        if (settled !== true)
            return flyout._choose(fit, preferAbove)
        const need = Math.min(fit.want, flyout.minRoom)
        const here = above === true ? fit.above : fit.below
        const there = above === true ? fit.below : fit.above
        if (here >= need)
            return above === true                 // still usable: stay put
        if (there >= need && there > here)
            return above !== true                 // gone: move, once
        return above === true                     // neither side fits: stay, capped
    }

    // --- the anchor-local position ---------------------------------------
    // Below the anchor, or above it with its BOTTOM edge on the anchor: a
    // flyout that shrinks while open keeps the edge that touches its control.
    function offsetY(popup, anchor, above) {
        if (!popup || !anchor)
            return 0
        return above === true ? -popup.height - flyout.gap
                              : anchor.height + flyout.gap
    }
}
