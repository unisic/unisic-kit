import QtQuick

// THE accessible-name bridge for label-plus-control rows - the one place that
// knows how a row's caption becomes the spoken name of the mute control next to
// it. This is the only copy; every row that needs it drops one in.
//
// A switch, a combo box, a slider and a bare text field say nothing about
// themselves: the only thing that names them is the row's own label, and
// assistive tech would otherwise announce "on" (or, worse for a field, its
// PLACEHOLDER - the example instead of the caption). Pushing the label in from
// here keeps the ~120 call sites free of the repetition.
//
// Drop it into any row - it is a plain QtObject, so it never joins a layout:
//
//     UNameBridge {
//         id: nameBridge
//         targets: [slot, footerSlot]   // the Items holding the controls
//         name: labelText.text
//         description: subText.text
//     }
//     ...
//     Item { id: slot; onChildrenChanged: nameBridge.refresh() }
//
// WHAT THE CAPTION NAMES
//
// A row caption is ONE identity, so it can only be one control's name:
//
//   - a row with exactly one control (the ~110 ordinary ones) hands the caption
//     over as that control's `accessibleName`, and the sub line as its
//     description;
//   - a row whose slots hold SEVERAL controls hands it to none of them. Naming
//     both the combo box and the Refresh button beside it "Application audio
//     only" is worse than naming neither: an AT element list then shows two
//     identical entries and nothing says which one picks the app. Controls that
//     share a slot already name themselves (`UButton.text`,
//     `UIconButton.tooltip`, `ColorDot.dotColor`, a combo's current value) -
//     what they lack is which ROW they belong to, so the caption is pushed down
//     into `accessibleDescription` instead. The three "Preview" buttons on the
//     sound page become Preview/"Capture sound", Preview/"Recording sound",
//     Preview/"Recording start sound". A description is additive - AT reads it
//     after the name - so repeating it down a row costs nothing, while
//     repeating a NAME is what destroys it.
//   - either way a name set at the call site always wins and is never taken
//     back: that is how a control that does need naming inside a shared slot
//     gets one.
//
// HOW FAR IT LOOKS
//
// Each target is searched ONE WRAPPER DEEP: a control sitting straight in the
// slot, and a control inside the single Row/Loader/Repeater a call site puts
// there, are both found. It deliberately stops there, and never descends into a
// control (a combo box carries its own search field, which is not the row's to
// rename). Anything deeper belongs to a component that packs its own controls -
// the hotkey rows' `UShortcutList` footer is the live case - and naming its guts
// after the row would also make the one-or-several count above depend on how
// many chips that list happens to hold right now. A control nested deeper than
// one wrapper names itself at the call site.
//
// The `onChildrenChanged` hook is required on every target: it is what picks up
// controls that arrive later AND what prunes the ones that go away. It cannot
// be the whole story though - a Loader that loads, or a Repeater that
// re-models, INSIDE a wrapper changes the WRAPPER's children and not the slot's
// - so the bridge hooks the wrappers it looks through to the same refresh
// itself. Nothing else is needed: name and description are installed as
// BINDINGS, so a qsTr() caption or a runtime-swapped hint stays live without
// anyone re-running anything.
QtObject {
    id: bridge

    // Items holding the controls to name (searched one wrapper deep).
    property var targets: []
    // The row's caption, and the sub/hint line under it.
    property string name: ""
    property string description: ""

    // One record per control we handled: { c, mode, ownName, ownDesc }. `mode`
    // is the rule applied above (1 = the caption is this control's name, 2 = the
    // caption is context for a shared slot), and the two flags are what keeps an
    // explicit call-site name or description from ever being overwritten or
    // taken back. Rebuilt from the live children on every refresh, which is what
    // prunes the records whose control was destroyed - a Repeater re-model used
    // to leave a stale wrapper here forever and keep re-bridging dead objects.
    property var _named: []
    // The wrappers we looked through, each hooked to re-run us (see refresh).
    property var _hooked: []

    function refresh() {
        var found = []
        var wrappers = []
        for (var t = 0; t < bridge.targets.length; ++t)
            if (bridge.targets[t])
                bridge._collect(bridge.targets[t], found, wrappers, 0)

        // The target's own `onChildrenChanged` cannot see a Loader that loads
        // later or a Repeater that re-models INSIDE a wrapper: in both cases the
        // wrapper's children change and the slot's do not. So every wrapper we
        // look through gets hooked to the same refresh, and drops its hook when
        // it leaves the row (destroyed ones take theirs with them).
        var h
        for (h = 0; h < bridge._hooked.length; ++h)
            if (bridge._hooked[h] && wrappers.indexOf(bridge._hooked[h]) < 0)
                bridge._hooked[h].childrenChanged.disconnect(bridge.refresh)
        for (h = 0; h < wrappers.length; ++h)
            if (bridge._hooked.indexOf(wrappers[h]) < 0)
                wrappers[h].childrenChanged.connect(bridge.refresh)
        bridge._hooked = wrappers

        // One control in the row -> the caption IS its name; several -> the
        // caption is context for all of them. See the header.
        var mode = (found.length === 1) ? 1 : 2
        var kept = []
        for (var i = 0; i < found.length; ++i) {
            var rec = bridge._record(found[i])
            if (!rec)
                rec = { c: found[i], mode: 0, ownName: false, ownDesc: false }
            if (rec.mode !== mode)
                bridge._install(rec, mode)
            kept.push(rec)
        }
        bridge._named = kept
    }

    // One wrapper deep, stopping at every control: `accessibleName` is the kit's
    // marker for "this item owns an accessible identity", so an item that has it
    // is a leaf here and an item that does not is a layout wrapper to look
    // through. Depth is capped rather than left open for the reason in the
    // header (a composite's internals are not this row's controls).
    function _collect(host, out, wrappers, depth) {
        var kids = host.children
        for (var i = 0; i < kids.length; ++i) {
            var c = kids[i]
            if (!c)
                continue
            if (c.accessibleName !== undefined)
                out.push(c)
            else if (depth < 1) {
                wrappers.push(c)
                bridge._collect(c, out, wrappers, depth + 1)
            }
        }
    }

    function _record(c) {
        for (var i = 0; i < bridge._named.length; ++i)
            if (bridge._named[i].c === c)
                return bridge._named[i]
        return null
    }

    function _install(rec, mode) {
        var c = rec.c
        if (mode === 1) {
            // Only ever fill an empty name, and only ever replace one of ours.
            if (rec.ownName || c.accessibleName === "") {
                c.accessibleName = Qt.binding(function() { return bridge.name })
                rec.ownName = true
            }
        } else if (rec.ownName) {
            // Demoted - a second control joined the slot. Drop our binding so
            // the control speaks for itself again instead of leaving the row's
            // caption sitting on both of them.
            c.accessibleName = ""
            rec.ownName = false
        }
        // Same ownership rule for the description. A control with a description
        // of its own (UValueCombo falls back to its tooltip) keeps it; set
        // `accessibleDescription` at the call site to say which row it is in.
        if (c.accessibleDescription !== undefined
                && (rec.ownDesc || c.accessibleDescription === "")) {
            c.accessibleDescription = (mode === 1)
                    ? Qt.binding(bridge._describe(c))
                    : Qt.binding(function() { return bridge.name })
            rec.ownDesc = true
        }
        rec.mode = mode
    }

    // Description fallback for the one named control: with the caption speaking
    // as the name, a field's placeholder would otherwise be lost to assistive
    // tech rather than just demoted - so a row with no sub line hands the
    // example over as the description instead.
    function _describe(c) {
        return function() {
            return bridge.description !== "" ? bridge.description
                 : (c.placeholder !== undefined ? c.placeholder : "")
        }
    }

    // Belt and braces: targets whose children were all parented before this
    // object existed never fired their hook at us.
    Component.onCompleted: bridge.refresh()
}
