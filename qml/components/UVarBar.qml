// Bound: the chip Repeater's delegate reads the bar it belongs to by id, which
// a delegate may only do under this pragma.
pragma ComponentBehavior: Bound

import QtQuick
import Unisic.Kit

// A floating row of template-variable chips for whichever field has focus.
//
// Parent it ABOVE the form (a card, a pane), never inside it. A row that joins
// the layout when it appears pushes everything below it down, so the form jumps
// under the cursor that just clicked into the field - and with one bar per form
// instead of one per field, six token-bearing fields cost one row, not six.
//
// `vars` is whatever the C++ side that performs the substitutions hands out
// (UploadManager::templateHelp, FilenameTemplate::help): the same shape from
// both, so this draws either without knowing which.
Rectangle {
    id: bar
    // The focused field. Anything with `height` and `insertToken(token, back)`,
    // which is UTextField and any wrapper that forwards to one. `var` and not
    // `Item`: the wrappers are plain Items to the type system, so a typed
    // property would make every insertToken call an unqualified-access warning.
    property var field: null
    // [{ token, label, description, caretBack }], usually `field`'s own list.
    property var vars: []
    // The scrolling area the bar must stay inside. Optional: without one the
    // bar is clamped to its parent instead, which is right when the form does
    // not scroll.
    property Flickable viewport: null

    visible: !!field && vars.length > 0
    // Above the form it covers. Not enough on its own if the parent has later
    // siblings - keep the bar last in its parent, or raise the parent too.
    z: 2
    height: chips.implicitHeight + 2 * Theme.spacingS
    radius: Theme.radiusM
    color: Theme.surface
    border.width: 1
    border.color: Theme.divider

    // Flush with the field it belongs to, edge to edge. Sized to the viewport
    // instead it ran wider than the field on both sides and read as a panel of
    // its own rather than as that field's variables (user-reported).
    x: {
        if (bar.viewport)
            void bar.viewport.contentX
        return bar.field && bar.parent ? bar.parent.mapFromItem(bar.field, 0, 0).x : 0
    }
    width: bar.field ? bar.field.width : (bar.parent ? bar.parent.width : 0)

    y: {
        // Read for their dependencies only: mapFromItem is a function call, so
        // without these the bar would stay where the field used to be as the
        // form scrolls under it.
        if (bar.viewport)
            void bar.viewport.contentY
        void bar.height
        if (!bar.field || !bar.parent)
            return 0
        const below = bar.parent.mapFromItem(bar.field, 0, bar.field.height).y + Theme.spacingXS
        const top = bar.viewport ? bar.parent.mapFromItem(bar.viewport, 0, 0).y : 0
        const room = bar.viewport ? bar.viewport.height : bar.parent.height
        // Clamped, so a field scrolled to the very bottom still gets its chips
        // on screen instead of just off the fold.
        return Math.max(top, Math.min(below, top + room - bar.height))
    }

    // The bar sits over the form, so a click that lands between chips must stop
    // there rather than reaching whatever it covers.
    MouseArea { anchors.fill: parent }

    Flow {
        id: chips
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingXS
        Repeater {
            model: bar.vars
            delegate: UFilterChip {
                required property var modelData
                text: modelData.label
                accessibleDescription: modelData.description
                // Never a Tab stop: the bar exists only while a field has
                // focus, so a stop here is one that disappears as it is
                // reached. The tokens stay reachable in text - every field
                // offering chips also names its variables in its own caption or
                // hint.
                activeFocusOnTab: false
                onClicked: bar.field.insertToken(modelData.token, modelData.caretBack)
            }
        }
    }
}
