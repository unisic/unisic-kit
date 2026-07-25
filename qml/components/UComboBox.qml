import QtQuick
import QtQuick.Controls as C
import Unisic.Kit

// Dropdown whose list is a Popup anchored to the field: it renders on the
// window overlay (above every card/Flickable, never clipped by clip:true) and
// is contained by UFlyout's rule, which is where the whole story lives.
Rectangle {
    id: root

    // The window's overlay: what every flyout is measured against. One lookup
    // for the click-away catcher and for UFlyout.
    readonly property Item _overlay: C.Overlay.overlay

    property var model: []            // array of strings
    property int currentIndex: 0
    // Long lists (fonts): a filter field pinned at the top of the popup.
    property bool searchable: false
    // Render each entry in its own family (font pickers).
    property bool fontPreview: false
    readonly property string currentText: model && model.length > currentIndex && currentIndex >= 0
                                          ? String(model[currentIndex]) : ""
    // The visible value IS the name by default; the row label around it (or a
    // caller) supplies what the value is FOR. USettingRow pushes it in here.
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal activated(int index)
    // Live-preview hooks. `highlighted` fires for the entry under the pointer
    // WITHOUT committing it, so a consumer can show what picking it would do;
    // `listOpen` says the user is mid-choice, which is when such a preview is
    // wanted and when a plain hover of the field is not.
    signal highlighted(int index)
    readonly property alias listOpen: popup.opened

    property string _filter: ""
    // Entries carry their SOURCE index so filtering never breaks activation.
    readonly property var _entries: {
        var out = []
        for (var i = 0; model && i < model.length; ++i) {
            var s = String(model[i])
            if (_filter === "" || s.toLowerCase().indexOf(_filter) >= 0)
                out.push({ text: s, idx: i })
        }
        return out
    }

    function _toggleList() {
        if (!root.enabled)
            return
        popup.opened ? popup.close() : popup.open()
    }
    // Arrow keys step the selection on the CLOSED field (the desktop
    // convention) without opening the list. Emit only, like every other path
    // here - the consumer owns currentIndex.
    function _step(delta) {
        if (!root.enabled || !root.model || root.model.length === 0)
            return
        var next = Math.max(0, Math.min(root.model.length - 1, root.currentIndex + delta))
        if (next !== root.currentIndex)
            root.activated(next)
    }

    implicitWidth: 220
    implicitHeight: 40
    radius: Theme.radiusM
    color: mouse.containsMouse ? Theme.tertiary : Theme.surfaceHi
    border.width: 1
    border.color: popup.opened ? Theme.accent : Theme.divider
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

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
        text: root.currentText
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

    // An unmodified Space/Return/Enter opens the list; Up/Down step the value in
    // place. The arrows carry the same UKeys rule as the activation keys.
    function _keyActivate(e) {
        if (!UKeys.claim(e))
            return
        // While the list is up these only run if the popup did NOT take focus
        // (it normally does, and then popup._listKey owns the keys): commit the
        // highlighted row, or just close when nothing is highlighted.
        if (popup._armed) {
            if (!popup._commit())
                popup._dismiss()
            return
        }
        root._toggleList()
    }
    function _keyStep(e, delta) {
        if (!UKeys.claim(e))
            return
        // Closed: step the value in place. Open: walk the list instead of
        // closing it - an arrow that dismissed the popup left keyboard users
        // with no way to pick anything at all.
        if (popup._armed)
            popup._move(delta)
        else
            root._step(delta)
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => root._keyActivate(e)
    Keys.onReturnPressed: (e) => root._keyActivate(e)
    Keys.onEnterPressed: (e) => root._keyActivate(e)
    Keys.onDownPressed: (e) => root._keyStep(e, 1)
    Keys.onUpPressed: (e) => root._keyStep(e, -1)

    Accessible.role: Accessible.ComboBox
    // A bare Item exposes no AT-SPI value interface, so the CURRENT VALUE has
    // to travel in the name or a screen reader announces only the label.
    Accessible.name: root.accessibleName !== ""
                     ? root.accessibleName + ": " + root.currentText
                     : root.currentText
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onPressAction: root._toggleList()

    UFocusRing { }

    C.Popup {
        id: popup
        // Anchored to the FIELD, contained by UFlyout's rule: see UFlyout.qml
        // for why the parent is the field and not the overlay, why `margins`
        // is what keeps this inside the window, and why the size is capped.
        parent: root
        margins: UFlyout.margin
        // Fonts get a wider popup than the compact closed field.
        width: UFlyout.fitWidth(root._overlay, Math.max(root.width, root.searchable ? 240 : 0))
        readonly property int searchH: root.searchable ? 40 : 0
        readonly property int rowH: 34

        // --- containment: UFlyout's rule, and these lines go together -------
        // The side the list is on. Chosen when it opens, then held: see
        // UFlyout.qml (4) for why re-choosing per height change is what made an
        // open list jump across its own field while the user typed in it.
        property bool flyUp: false
        // What the list WANTS, counted from the model rather than read off
        // list.contentHeight: a ListView measures itself one frame late, so at
        // the instant the popup opens (or right after a filter change) that
        // number is the PREVIOUS list's. The rows are a fixed rowH with no
        // spacing, so the arithmetic is exact and it is available now.
        readonly property real flyWant: Math.min(root._entries.length * popup.rowH
                                                 + 12 + popup.searchH, 340)
        // The one reactive reading of the fit - window size, anchor position,
        // wanted height. Gated on `visible` so a closed list costs nothing.
        readonly property var flyFit: popup.visible
                                      ? UFlyout.rooms(root, root._overlay, popup.flyWant)
                                      : null
        onFlyFitChanged: popup.flyUp = UFlyout.sideNow(popup.flyUp, popup.flyFit, popup.opened)
        // Capped to the room on that side, so a list that cannot fit scrolls
        // instead of covering the field it belongs to.
        height: UFlyout.fitHeight(root._overlay, popup.flyWant,
                                  UFlyout.roomOn(popup.flyFit, popup.flyUp))
        y: UFlyout.offsetY(popup, root, popup.flyUp)
        z: outsideCatcher.z + 1
        padding: 6
        focus: true
        closePolicy: C.Popup.CloseOnEscape

        // --- keyboard navigation of the OPEN list ---
        // The popup takes focus when it opens (focus: true), so the field's own
        // Keys handlers stop running the moment the list is up - these do the
        // walking. Rows are ListView delegates, so they can be neither tab stops
        // nor focus holders: the ones outside the viewport do not exist yet, and
        // the focused one would be destroyed by a scroll. A highlight index is
        // the only thing that survives both.
        // It counts positions in root._entries (the FILTERED list), never model
        // indices; committing maps back through .idx. -1 = untouched, which is
        // also what keeps the list looking exactly as it did for pointer users
        // until a key is actually pressed.
        property int kbIndex: -1
        // "The list is up and nothing has been picked yet." NOT popup.opened:
        // that one only turns true once the enter transition has finished (a
        // key pressed in those first ~150 ms would be dropped) and it is still
        // true for the whole exit transition, which would let a Return the
        // search field already committed on be handled a second time here.
        // aboutToShow/aboutToHide bracket the choice exactly.
        property bool _armed: false
        onAboutToHide: _armed = false
        function _move(delta) {
            var n = root._entries.length
            if (n === 0) {
                kbIndex = -1
                return
            }
            var from = kbIndex
            if (from < 0) {
                // First arrow starts at the current selection, so the walk
                // begins where the user already is.
                from = -1
                for (var i = 0; i < n; ++i) {
                    if (root._entries[i].idx === root.currentIndex) {
                        from = i
                        break
                    }
                }
                if (from < 0) {
                    // A filter can hide the selected entry; then the first
                    // arrow lands on an END of the list instead of skipping a
                    // row past a selection that is not on screen.
                    _moveTo(delta > 0 ? 0 : n - 1)
                    return
                }
            }
            _moveTo(from + delta)
        }
        function _moveTo(i) {
            var n = root._entries.length
            if (n === 0) {
                kbIndex = -1
                return
            }
            kbIndex = Math.max(0, Math.min(n - 1, i))
            list.positionViewAtIndex(kbIndex, ListView.Contain)
            // Same live-preview hook the pointer fires on hover - a keyboard
            // walk must show the consumer exactly what a pointer walk does.
            root.highlighted(root._entries[kbIndex].idx)
        }
        // The ONE keyboard commit path. Same signal the mouse path emits, so
        // the two can never drift: emit only, the consumer owns currentIndex.
        function _commitAt(i) {
            if (!_armed || i < 0 || i >= root._entries.length)
                return false
            var idx = root._entries[i].idx
            popup.close()
            root.activated(idx)
            // Hand focus back to the field: closing a popup otherwise drops the
            // user out of the tab order entirely.
            root.forceActiveFocus(Qt.OtherFocusReason)
            return true
        }
        function _commit() { return _commitAt(kbIndex) }
        function _dismiss() {
            popup.close()
            root.forceActiveFocus(Qt.OtherFocusReason)
        }
        // One handler for the whole open list, attached to the item that holds
        // the focus (and that the search field's own keys bubble through).
        function _listKey(e) {
            // Re-entrant tail of a key the search field already committed on -
            // the choice is over, so there is nothing left to do with it.
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
            case Qt.Key_End:      popup._moveTo(root._entries.length - 1); break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (!popup._commit())
                    popup._dismiss()
                break
            case Qt.Key_Escape:
                // Close WITHOUT committing; the field keeps its value.
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
            root._filter = ""
            searchField.text = ""
            kbIndex = -1
            _armed = true
            popup.flyUp = UFlyout.sideAtOpen(root, root._overlay, popup.flyWant)
        }
        onOpened: if (root.searchable) searchField.forceFocus()

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
            // arrive here - and the search field's leftovers bubble up to it.
            focus: true
            Keys.onPressed: (e) => popup._listKey(e)

            UTextField {
                id: searchField
                visible: root.searchable
                width: parent.width
                implicitHeight: 34
                placeholder: qsTr("Search…")
                // A new filter renumbers _entries, so the old highlight position
                // would point at a different row.
                onEdited: (t) => { root._filter = t.toLowerCase(); popup.kbIndex = -1 }
                // Enter picks the row the arrows walked to, else the first
                // (best) match.
                onAccepted: {
                    if (!popup._commit())
                        popup._commitAt(0)
                }
            }

            ListView {
                id: list
                width: parent.width
                // Never negative: a capped popup in a very short window can
                // leave less than the search field's own height.
                height: Math.max(0, popup.height - 12 - popup.searchH)
                clip: true
                model: root._entries
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
                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        elide: Text.ElideRight
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontM
                        font.family: root.fontPreview ? modelData.text : Qt.application.font.family
                    }
                    UIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.idx === root.currentIndex
                        name: "checkmark"
                        size: 15
                        color: Theme.accent
                    }
                    MouseArea {
                        id: dMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) root.highlighted(modelData.idx)
                        // Emit only - writing currentIndex here would destroy the
                        // consumer's binding; the handler updates the source.
                        onClicked: dRow._pick()
                    }

                    function _pick() {
                        popup.close()
                        root.activated(modelData.idx)
                    }

                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.text
                    Accessible.selectable: true
                    Accessible.selected: modelData.idx === root.currentIndex
                    // The keyboard highlight is a virtual focus: the row cannot
                    // hold the real one (it is a recycled delegate), but the
                    // state change still posts the event a screen reader needs
                    // to announce the row the arrows just landed on.
                    Accessible.focused: dRow._kbHi
                    Accessible.onPressAction: dRow._pick()
                }
            }
        }
    }
}
