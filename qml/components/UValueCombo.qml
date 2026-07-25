import QtQuick
import QtQuick.Controls as C
import Unisic.Kit

// Numeric dropdown: a preset list plus a free-entry "Custom" field at the
// bottom. A typed value applies immediately but is NEVER added to the preset
// list. Same popup pattern as UComboBox - anchored to the field and contained
// by UFlyout's rule (which is where the whole story lives), so it escapes
// Flickable clipping AND can never hang off the window. Optional `tooltip`
// shows on hover (used for hints like "0 = keep open" that used to bloat the
// row label).
Rectangle {
    id: root

    // The window's overlay: what every flyout is measured against. One lookup
    // for the click-away catcher and for UFlyout.
    readonly property Item _overlay: C.Overlay.overlay
    property var values: []           // preset numbers, ascending
    property int value: 0
    property int from: 0
    property int to: 100
    property string suffix: ""
    property string tooltip: ""
    // What the number means. USettingRow pushes its row label in here; the
    // value itself is appended to the spoken name below.
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal changed(int value)
    // Same live-preview hooks as UComboBox: the entry under the pointer, and
    // whether the list is open (i.e. the user is choosing).
    signal highlighted(int value)
    readonly property alias listOpen: popup.opened

    implicitWidth: 130
    implicitHeight: 40
    radius: Theme.radiusM
    color: mouse.containsMouse ? Theme.tertiary : Theme.surfaceHi
    border.width: 1
    border.color: popup.opened ? Theme.accent : Theme.divider
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    function _apply(v) {
        v = Math.max(from, Math.min(to, Math.round(v)))
        // Emit only - assigning `value` would break the consumer's binding.
        if (v !== value) root.changed(v)
    }

    function _toggleList() {
        if (!root.enabled)
            return
        popup.opened ? popup.close() : popup.open()
    }
    // Arrow keys / the AT increase-decrease actions walk the PRESET list (the
    // same choices the popup offers); with no presets they nudge by one.
    function _step(delta) {
        if (!root.enabled)
            return
        var vs = root.values
        if (!vs || vs.length === 0) {
            root._apply(root.value + delta)
            return
        }
        // Nearest preset, then move `delta` places along the list.
        var best = 0
        for (var i = 1; i < vs.length; ++i) {
            if (Math.abs(Number(vs[i]) - root.value) < Math.abs(Number(vs[best]) - root.value))
                best = i
        }
        if (Number(vs[best]) !== root.value)
            best += (delta > 0 ? (Number(vs[best]) > root.value ? 0 : 1)
                               : (Number(vs[best]) < root.value ? 0 : -1))
        else
            best += delta
        best = Math.max(0, Math.min(vs.length - 1, best))
        root._apply(Number(vs[best]))
    }

    Item {
        id: outsideCatcher
        parent: root._overlay
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        visible: popup.opened && parent !== null
        z: 999

        MouseArea {
            anchors.fill: parent
            onClicked: popup.close()
            onWheel: (w) => { popup.close(); w.accepted = false }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: chevron.left
        text: root.value + root.suffix
        color: Theme.textPrimary
        font.pixelSize: Theme.fontM
        elide: Text.ElideRight
    }
    UIcon {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron-down"
        size: 16
        color: Theme.textSecondary
        rotation: popup.opened ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._toggleList()
    }

    UHoverTip {
        anchor: root
        text: root.tooltip
        show: mouse.containsMouse && !popup.opened
    }

    // An unmodified Space/Return/Enter opens the list, Up/Down step the value.
    // The arrows carry the same UKeys rule as the activation keys.
    function _keyActivate(e) {
        if (!UKeys.claim(e))
            return
        // Only reachable if the popup did NOT take focus while up (it
        // normally does, and then popup._listKey owns the keys).
        if (popup._armed) {
            if (!popup._commit())
                popup._dismiss()
            return
        }
        root._toggleList()
    }
    // Closed, the arrows are a spinner: Up RAISES the value, so it walks the
    // ascending preset list backwards-on-screen. Open, they are list keys: Down
    // moves DOWN the visible rows (i.e. to the larger preset). Each is the
    // convention of the thing actually on screen.
    function _keyStep(e, delta) {
        if (!UKeys.claim(e))
            return
        if (popup._armed)
            popup._move(-delta)
        else
            root._step(delta)
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => root._keyActivate(e)
    Keys.onReturnPressed: (e) => root._keyActivate(e)
    Keys.onEnterPressed: (e) => root._keyActivate(e)
    Keys.onUpPressed: (e) => root._keyStep(e, 1)
    Keys.onDownPressed: (e) => root._keyStep(e, -1)

    Accessible.role: Accessible.ComboBox
    // Same reason as UComboBox: no value interface on a bare Item, so the
    // number travels in the name.
    Accessible.name: root.accessibleName !== ""
                     ? root.accessibleName + ": " + root.value + root.suffix
                     : root.value + root.suffix
    Accessible.description: root.accessibleDescription !== "" ? root.accessibleDescription
                                                              : root.tooltip
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onPressAction: root._toggleList()
    Accessible.onIncreaseAction: root._step(1)
    Accessible.onDecreaseAction: root._step(-1)

    UFocusRing { }

    C.Popup {
        id: popup
        // Anchored to the FIELD, contained by UFlyout's rule: see UFlyout.qml
        // for why the parent is the field and not the overlay, why `margins`
        // is what keeps this inside the window, and why the height is capped.
        parent: root
        margins: UFlyout.margin
        width: UFlyout.fitWidth(root._overlay, Math.max(root.width, 130))
        readonly property int rowH: 34
        // Divider + the custom field + the Column's spacing around them.
        readonly property int customH: 46

        // --- containment: UFlyout's rule, and these lines go together -------
        // Same rig as UComboBox, for the same reasons: the side is chosen when
        // the list opens and then held (UFlyout.qml (4)), the wanted height is
        // counted from the model rather than read off the ListView one frame
        // late, and the height is capped to the room on the chosen side so a
        // list that cannot fit scrolls instead of covering its own field.
        property bool flyUp: false
        readonly property real flyWant: Math.min((root.values ? root.values.length : 0) * popup.rowH
                                                 + 12 + popup.customH, 340)
        readonly property var flyFit: popup.visible
                                      ? UFlyout.rooms(root, root._overlay, popup.flyWant)
                                      : null
        onFlyFitChanged: popup.flyUp = UFlyout.sideNow(popup.flyUp, popup.flyFit, popup.opened)
        height: UFlyout.fitHeight(root._overlay, popup.flyWant,
                                  UFlyout.roomOn(popup.flyFit, popup.flyUp))
        y: UFlyout.offsetY(popup, root, popup.flyUp)
        z: outsideCatcher.z + 1
        padding: 6
        focus: true
        closePolicy: C.Popup.CloseOnEscape

        // --- keyboard navigation of the OPEN list ---
        // Same rig as UComboBox, and for the same reason: the popup takes focus
        // when it opens, so the field's own Keys handlers stop running, and the
        // rows are ListView delegates that can be neither tab stops nor focus
        // holders. `kbIndex` is a row of root.values; -1 = untouched, so the
        // list looks exactly as it did for pointer users until a key is pressed.
        property int kbIndex: -1
        // "The list is up and nothing has been picked yet." NOT popup.opened:
        // that one only turns true once the enter transition has finished (a
        // key pressed in those first ~150 ms would be dropped) and it is still
        // true for the whole exit transition. aboutToShow/aboutToHide bracket
        // the choice exactly.
        property bool _armed: false
        onAboutToHide: _armed = false
        function _move(delta) {
            var n = root.values ? root.values.length : 0
            if (n === 0) {
                kbIndex = -1
                return
            }
            var from = kbIndex
            if (from < 0) {
                // First arrow starts at the preset currently in effect (or the
                // nearest one), so the walk begins where the user already is.
                from = 0
                for (var i = 1; i < n; ++i) {
                    if (Math.abs(Number(root.values[i]) - root.value)
                            < Math.abs(Number(root.values[from]) - root.value))
                        from = i
                }
            }
            _moveTo(from + delta)
        }
        function _moveTo(i) {
            var n = root.values ? root.values.length : 0
            if (n === 0) {
                kbIndex = -1
                return
            }
            kbIndex = Math.max(0, Math.min(n - 1, i))
            list.positionViewAtIndex(kbIndex, ListView.Contain)
            // Same live-preview hook the pointer fires on hover - a keyboard
            // walk must show the consumer exactly what a pointer walk does.
            root.highlighted(Number(root.values[kbIndex]))
        }
        // The ONE keyboard commit path, through the same _apply()/changed()
        // the mouse rows use.
        function _commit() {
            var n = root.values ? root.values.length : 0
            if (!_armed || kbIndex < 0 || kbIndex >= n)
                return false
            var v = Number(root.values[kbIndex])
            popup.close()
            root._apply(v)
            // Hand focus back to the field: closing a popup otherwise drops the
            // user out of the tab order entirely.
            root.forceActiveFocus(Qt.OtherFocusReason)
            return true
        }
        function _dismiss() {
            popup.close()
            root.forceActiveFocus(Qt.OtherFocusReason)
        }
        function _listKey(e) {
            // Re-entrant tail of a key the custom field already applied - the
            // choice is over, so there is nothing left to do with it.
            if (!popup._armed) {
                e.accepted = true
                return
            }
            // Keys.onPressed arrives unaccepted, so a declined chord just falls
            // through and keeps bubbling.
            if (!UKeys.unmodified(e))
                return
            switch (e.key) {
            case Qt.Key_Down:     popup._move(1); break
            case Qt.Key_Up:       popup._move(-1); break
            case Qt.Key_PageDown: popup._moveTo((kbIndex < 0 ? 0 : kbIndex) + 10); break
            case Qt.Key_PageUp:   popup._moveTo((kbIndex < 0 ? 0 : kbIndex) - 10); break
            case Qt.Key_Home:     popup._moveTo(0); break
            case Qt.Key_End:      popup._moveTo((root.values ? root.values.length : 0) - 1); break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (!popup._commit())
                    popup._dismiss()
                break
            case Qt.Key_Escape:
                // Close WITHOUT applying; the field keeps its value.
                popup._dismiss()
                break
            default:
                e.accepted = false
                return
            }
            e.accepted = true
        }

        // Below the field, flipping above when out of room (UFlyout rule 4);
        // every later re-fit is the flyFit binding's, and everything about
        // staying inside the window is Qt's, via `margins` above.
        onAboutToShow: {
            customField.text = ""
            kbIndex = -1
            _armed = true
            popup.flyUp = UFlyout.sideAtOpen(root, root._overlay, popup.flyWant)
        }

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }

        background: Rectangle {
            radius: Theme.radiusM
            color: Theme.surfaceHi
            border.width: 1
            border.color: Theme.divider
        }

        contentItem: Column {
            spacing: 6
            // This is the item the popup's focus lands on, so the list keys
            // arrive here - and the custom field's leftovers bubble up to it.
            focus: true
            Keys.onPressed: (e) => popup._listKey(e)

            ListView {
                id: list
                width: parent.width
                // Never negative: a capped popup in a very short window can
                // leave less than the custom field's own height.
                height: Math.max(0, popup.height - 12 - popup.customH)
                clip: true
                model: root.values
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: dRow
                    width: ListView.view.width
                    // The popup's own arithmetic counts rows at this height.
                    height: popup.rowH
                    radius: Theme.radiusS
                    // Same fill for the pointer and the keyboard - one highlight
                    // look for the list, whichever is driving it.
                    readonly property bool _kbHi: popup.kbIndex === index
                    color: dMouse.containsMouse || dRow._kbHi
                           ? Theme.tertiary : "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData + root.suffix
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontM
                    }
                    UIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Number(modelData) === root.value
                        name: "checkmark"
                        size: 15
                        color: Theme.accent
                    }
                    MouseArea {
                        id: dMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) root.highlighted(Number(modelData))
                        onClicked: dRow._pick()
                    }

                    function _pick() {
                        popup.close()
                        root._apply(Number(modelData))
                    }

                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData + root.suffix
                    Accessible.selectable: true
                    Accessible.selected: Number(modelData) === root.value
                    // The keyboard highlight is a virtual focus: the row cannot
                    // hold the real one (it is a recycled delegate), but the
                    // state change still posts the event a screen reader needs
                    // to announce the row the arrows just landed on.
                    Accessible.focused: dRow._kbHi
                    Accessible.onPressAction: dRow._pick()
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.divider }

            UTextField {
                id: customField
                width: parent.width
                implicitHeight: 34
                placeholder: qsTr("Custom…")
                validator: IntValidator { bottom: root.from; top: root.to }
                onAccepted: {
                    var v = parseInt(text)
                    if (!isNaN(v)) {
                        popup.close()
                        root._apply(v)
                        // Same as the list's own commit: the field this was
                        // typed into dies with the popup, so hand focus back
                        // instead of dropping the user out of the tab order.
                        root.forceActiveFocus(Qt.OtherFocusReason)
                    }
                }
            }
        }
    }
}
