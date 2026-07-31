import QtQuick
import QtQuick.Controls as C
import Unisic.Kit

// A UButton-shaped action menu: the trigger is a tonal pill; its list is a
// Popup anchored to that trigger and rendered on the window overlay (never
// clipped by the bar), preferring to open ABOVE the trigger since the action
// bar sits on the window's bottom edge. Containment is UFlyout's rule, which is
// where the whole story lives - including why a long menu SCROLLS here instead
// of growing past the window. Unlike UComboBox it tracks no selection - each
// row fires its own `trigger` callback. `actions` items: { label, iconName,
// enabled, hint, separatorBefore, trigger:function }.
Rectangle {
    id: root

    // The window's overlay: what every flyout is measured against. One lookup
    // for the click-away catcher and for UFlyout.
    readonly property Item _overlay: C.Overlay.overlay

    property string text: ""
    property string iconName: ""
    property string tooltip: ""
    // Keeps menus usable in dense action rows without creating a separate,
    // subtly different icon-menu control.
    property bool iconOnly: false
    property var actions: []
    // Read-only for the caller: the menu is on the window overlay, so a trigger
    // that lives in a hover-revealed strip has no other way to know it must
    // stay up while its own menu is open.
    readonly property bool menuOpen: popup.opened
    // Spoken name. Falls back to the visible text, or to the tooltip when the
    // trigger is icon-only and has no visible text at all.
    property string accessibleName: ""
    property string accessibleDescription: ""

    readonly property string _accName: accessibleName !== "" ? accessibleName
                                     : (!iconOnly && text !== "" ? text : tooltip)

    // The ONE open path. `fromKeyboard` decides whether the menu also takes the
    // keyboard: a pointer user gets the menu exactly as it always looked (no
    // row highlighted, same as the dropdowns' kbIndex: -1), a keyboard user
    // lands on the first action and can walk from there without pressing Tab.
    function _openMenu(fromKeyboard) {
        if (!root.enabled)
            return
        popup._kb = fromKeyboard === true
        popup.open()
    }
    // Pointer and AT-SPI Press.
    function _toggleMenu() {
        if (!root.enabled)
            return
        popup.opened ? popup.close() : root._openMenu(false)
    }

    // The popup used to be pinned at 220px with the label growing right and the
    // hint growing left, so long (esp. localized) strings collided and clipped.
    // Measure the widest label+hint row and size the popup to fit (clamped to
    // the overlay); the row layout below also elides the label as a backstop.
    TextMetrics { id: _tmLabel; font.pixelSize: Theme.fontM; font.weight: Font.DemiBold }
    TextMetrics { id: _tmHint;  font.pixelSize: Theme.fontS }
    function measureContentWidth() {
        var w = 220
        for (var i = 0; i < actions.length; ++i) {
            var a = actions[i]
            _tmLabel.text = a.label || ""
            var lw = _tmLabel.width
            var hw = 0
            if (a.hint) { _tmHint.text = a.hint; hw = _tmHint.width + 24 }
            var iconw = (a.iconName !== undefined && a.iconName !== "") ? 27 : 0
            // 10 left pad + icon + label + hint(+gap) + 10 right pad + 12 popup padding
            w = Math.max(w, 10 + iconw + lw + hw + 10 + 12)
        }
        return Math.ceil(w)
    }

    readonly property bool _hovered: mouse.containsMouse && !mouse.pressed
    implicitWidth: iconOnly ? 38 : rowC.implicitWidth + 34
    implicitHeight: 42
    radius: height / 2
    color: (popup.opened || _hovered) ? Qt.lighter(Theme.tertiary, 1.12) : Theme.tertiary
    border.width: 1
    border.color: popup.opened ? Theme.accent : Theme.divider
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    scale: mouse.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

    Row {
        id: rowC
        anchors.centerIn: parent
        spacing: 7
        UIcon {
            visible: root.iconName !== ""
            name: root.iconName; size: 18; color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: !root.iconOnly && root.text !== ""
            text: root.text; font.pixelSize: Theme.fontM; font.weight: Font.DemiBold
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
        UIcon {
            visible: !root.iconOnly
            name: "chevron-down"; size: 14; color: Theme.textSecondary
            rotation: popup.opened ? 180 : 0
            anchors.verticalCenter: parent.verticalCenter
            Behavior on rotation { NumberAnimation { duration: Theme.animFast } }
        }
    }

    // Click-away catcher (same idiom as UComboBox).
    Item {
        id: catcher
        parent: root._overlay
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        visible: popup.opened && parent !== null
        z: 999
        MouseArea { anchors.fill: parent; onClicked: popup.close(); onWheel: (w) => { popup.close(); w.accepted = false } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._toggleMenu()
    }

    UHoverTip {
        anchor: root
        text: root.tooltip
        show: mouse.containsMouse && root.tooltip !== ""
    }

    // An unmodified Space/Return/Enter toggles the menu and Down opens it; both
    // hand it the keyboard, so the walk starts on the first action instead of
    // needing a Tab first. The arrow carries the same UKeys rule as the
    // activation keys.
    function _keyOpen(e, toggle) {
        if (!UKeys.claim(e))
            return
        if (!popup.opened)
            root._openMenu(true)
        else if (toggle)
            popup._dismiss()
        else
            popup._focusFirst()   // already open by pointer: take the keyboard
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => root._keyOpen(e, true)
    Keys.onReturnPressed: (e) => root._keyOpen(e, true)
    Keys.onEnterPressed: (e) => root._keyOpen(e, true)
    Keys.onDownPressed: (e) => root._keyOpen(e, false)

    Accessible.role: Accessible.ButtonMenu
    Accessible.name: root._accName
    Accessible.description: root.accessibleDescription !== "" ? root.accessibleDescription
                            : (root._accName === root.tooltip ? "" : root.tooltip)
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onPressAction: root._toggleMenu()

    UFocusRing { }

    C.Popup {
        id: popup
        // Anchored to the TRIGGER, contained by UFlyout's rule: see UFlyout.qml
        // for why the parent is the trigger and not the overlay, why `margins`
        // is what keeps this inside the window, and why the size is capped.
        parent: root
        margins: UFlyout.margin
        // Recomputed on open (onAboutToShow) so newly-bound actions are measured.
        // (Not named contentWidth - that shadows QQuickPopup's final property.)
        property real measuredWidth: 220
        width: UFlyout.fitWidth(root._overlay, Math.max(root.width, measuredWidth))

        // --- containment: UFlyout's rule, and these lines go together -------
        // The side the menu is on: preferring ABOVE (the action bar sits on the
        // window's bottom edge), chosen when it opens and then held - see
        // UFlyout.qml (4). Capped to the room on that side, so a long menu can
        // never be taller than what is free above its own trigger; menuFlick
        // below scrolls whatever the cap cut off.
        property bool flyUp: true
        readonly property real flyWant: col.implicitHeight + 12
        readonly property var flyFit: popup.visible
                                      ? UFlyout.rooms(root, root._overlay, popup.flyWant)
                                      : null
        onFlyFitChanged: popup.flyUp = UFlyout.sideNow(popup.flyUp, popup.flyFit,
                                                       popup.opened, true)
        height: UFlyout.fitHeight(root._overlay, popup.flyWant,
                                  UFlyout.roomOn(popup.flyFit, popup.flyUp))
        y: UFlyout.offsetY(popup, root, popup.flyUp)
        z: catcher.z + 1
        padding: 6
        focus: true
        closePolicy: C.Popup.CloseOnEscape

        // The bar is at the window's bottom edge, so prefer opening above
        // (UFlyout rule 4); every later re-fit is the flyFit binding's, and
        // everything about staying inside the window is Qt's, via `margins`.
        onAboutToShow: {
            measuredWidth = root.measureContentWidth()
            popup.flyUp = UFlyout.sideAtOpen(root, root._overlay, popup.flyWant, true)
        }

        // --- keyboard navigation of the OPEN menu ---
        // Unlike the dropdowns' virtual highlight, the rows here are ordinary
        // Repeater items - all of them exist and none is recycled - so they can
        // hold the REAL focus, and the focus ring is the highlight. What that
        // still needs is an entry point (a menu opened from the keyboard puts
        // the first action under it, so no Tab is needed), a walk that cannot
        // leave the menu, and Escape. Without the entry point the popup's focus
        // sat on its contentItem and the menu was inert: measured in an offscreen
        // probe, Down opened the menu and then Down/Down/Up/Up/Down moved
        // nothing and Return activated nothing, while the same keys walked and
        // committed in both dropdowns. Tab did work, which is exactly the
        // inconsistency - the two other flyouts need no Tab.
        // "Opened by a key": the pointer path leaves the menu untouched, the
        // keyboard path focuses the first action.
        property bool _kb: false
        onOpened: if (popup._kb) popup._focusFirst()
        onAboutToHide: popup._kb = false

        // The focusable action rows, in visual order. Built by walking the
        // Column rather than nextItemInFocusChain(): the chain runs straight
        // out of the popup at either end, and a menu walk must stay in the
        // menu. Disabled rows drop out of the tab chain, so they are skipped
        // here for free.
        function _rows() {
            var out = []
            for (var i = 0; i < col.children.length; ++i) {
                var wrap = col.children[i]
                if (!wrap || !wrap.children)
                    continue
                for (var j = 0; j < wrap.children.length; ++j) {
                    var it = wrap.children[j]
                    if (it && it.activeFocusOnTab === true && it.visible === true)
                        out.push(it)
                }
            }
            return out
        }
        // Move `delta` rows from `from` (null = enter the menu from outside),
        // wrapping at both ends the way a menu does.
        function _walk(from, delta) {
            const rows = popup._rows()
            if (rows.length === 0)
                return
            const i = rows.indexOf(from)
            const next = i < 0 ? (delta > 0 ? 0 : rows.length - 1)
                               : (i + delta + rows.length) % rows.length
            rows[next].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
            popup._reveal(rows[next])
        }
        function _focusFirst() { popup._walk(null, 1) }
        // Close and hand the keyboard back to the trigger: closing a popup
        // otherwise drops the user out of the tab order entirely.
        function _dismiss() {
            popup.close()
            root.forceActiveFocus(Qt.OtherFocusReason)
        }

        // A Flickable does not scroll itself to follow the focus - so a
        // keyboard walk into the part the cap cut off has to bring the row into
        // view itself.
        function _reveal(item) {
            if (!item || menuFlick.contentHeight <= menuFlick.height)
                return
            let p = item
            while (p && p !== col)
                p = p.parent
            if (p !== col)
                return   // focus left the menu entirely
            const top = item.mapToItem(col, 0, 0).y
            const bottom = top + item.height
            if (top < menuFlick.contentY)
                menuFlick.contentY = top
            else if (bottom > menuFlick.contentY + menuFlick.height)
                menuFlick.contentY = bottom - menuFlick.height
        }

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }

        background: Rectangle {
            radius: Theme.radiusM
            color: Theme.surfaceHi
            border.width: 1
            border.color: Theme.divider
        }

        // The rows live in a Flickable so a capped menu scrolls instead of
        // overflowing (UFlyout rule 3). With room for every row it never
        // moves - contentHeight then equals its height.
        contentItem: Flickable {
            id: menuFlick
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            // Where the popup's focus lands, so these keys run for a menu the
            // POINTER opened (nothing is focused then): the first arrow walks
            // into the rows, and Escape closes from anywhere in the menu.
            focus: true
            Keys.onDownPressed: (e) => { if (UKeys.claim(e)) popup._walk(null, 1) }
            Keys.onUpPressed: (e) => { if (UKeys.claim(e)) popup._walk(null, -1) }
            Keys.onEscapePressed: (e) => { if (UKeys.claim(e)) popup._dismiss() }
            // Inert unless it actually has something to scroll, so a menu that
            // fits keeps taking the wheel exactly as it did before it had a
            // scroller: the event falls through to the click-away catcher,
            // which closes the menu.
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: menuFlick.width
                spacing: 2
                Repeater {
                    model: root.actions
                    delegate: Column {
                        width: col.width
                        spacing: 2
                        Rectangle {
                            visible: modelData.separatorBefore === true
                            x: 6; width: parent.width - 12; height: 1; color: Theme.divider
                        }
                        Rectangle {
                            id: mRow
                            width: parent.width; height: 36; radius: Theme.radiusS
                            readonly property bool _on: modelData.enabled !== false
                            opacity: _on ? 1 : 0.4
                            color: rMouse.containsMouse && _on ? Theme.tertiary : "transparent"

                            // The ONE activation path - pointer, keyboard and
                            // AT-SPI Press all come through here. The keyboard
                            // one also hands focus back to the trigger, since
                            // the row it was standing on is about to close;
                            // a pointer click leaves focus alone, so clicking
                            // an action cannot make a focus ring appear on a
                            // trigger nobody was on.
                            function _fire() {
                                if (!mRow._on)
                                    return
                                const byKey = mRow.activeFocus
                                popup.close()
                                if (byKey)
                                    root.forceActiveFocus(Qt.OtherFocusReason)
                                modelData.trigger()
                            }
                            // Rows hold the real focus INSIDE the open popup, so
                            // the menu is walkable without a pointer; Up/Down
                            // walk the rows (wrapping, never out of the menu) and
                            // Escape closes, all under the same UKeys rule as the
                            // activation keys. A capped menu scrolls, so the row
                            // the walk lands on is also brought into view.
                            function _keyWalk(e, forward) {
                                if (!UKeys.claim(e))
                                    return
                                popup._walk(mRow, forward ? 1 : -1)
                            }
                            activeFocusOnTab: mRow._on
                            Keys.onSpacePressed: (e) => UKeys.activate(e, mRow._fire)
                            Keys.onReturnPressed: (e) => UKeys.activate(e, mRow._fire)
                            Keys.onEnterPressed: (e) => UKeys.activate(e, mRow._fire)
                            Keys.onDownPressed: (e) => mRow._keyWalk(e, true)
                            Keys.onUpPressed: (e) => mRow._keyWalk(e, false)
                            Keys.onEscapePressed: (e) => UKeys.activate(e, popup._dismiss)

                            Accessible.role: Accessible.MenuItem
                            Accessible.name: modelData.label || ""
                            Accessible.description: modelData.hint || ""
                            Accessible.focusable: mRow.activeFocusOnTab
                            Accessible.onPressAction: mRow._fire()

                            UFocusRing { inset: 1 }
                            // Anchored icon / label / hint: the hint owns the right
                            // edge, the label fills the gap and elides - so a long
                            // label or hint can never overlap or clip the other.
                            UIcon {
                                id: rowIcon
                                visible: modelData.iconName !== undefined && modelData.iconName !== ""
                                name: modelData.iconName || ""; size: 17; color: Theme.textPrimary
                                anchors.left: parent.left; anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: rowHint
                                visible: !!modelData.hint
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.hint || ""; color: Theme.textTertiary
                                font.pixelSize: Theme.fontS
                            }
                            Text {
                                text: modelData.label; color: Theme.textPrimary
                                font.pixelSize: Theme.fontM
                                elide: Text.ElideRight
                                anchors.left: rowIcon.visible ? rowIcon.right : parent.left
                                anchors.leftMargin: 10
                                anchors.right: rowHint.visible ? rowHint.left : parent.right
                                anchors.rightMargin: rowHint.visible ? 12 : 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            MouseArea {
                                id: rMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: mRow._on ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: mRow._fire()
                            }
                        }
                    }
                }
            }
        }
    }
}
