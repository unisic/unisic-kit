import QtQuick
import QtQuick.Effects
import Unisic.Kit

Item {
    id: root
    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    // A slider carries no label of its own - the row around it does.
    // USettingRow pushes its label in here; a hand-built row sets it.
    property string accessibleName: ""
    property string accessibleDescription: ""
    // Qt's accessibility value interface reads these exact property names off
    // the item, so a screen reader can announce "42, minimum 0, maximum 100"
    // instead of a bare number. Aliases of from/to - never set them directly.
    readonly property real minimumValue: from
    readonly property real maximumValue: to
    signal moved(real value)

    implicitWidth: 220
    implicitHeight: 30

    function _ratio() { return to > from ? (value - from) / (to - from) : 0 }
    function _setFromX(x) {
        var r = Math.max(0, Math.min(1, (x - 10) / (width - 20)))
        var v = from + r * (to - from)
        v = Math.round(v / stepSize) * stepSize
        v = Math.max(from, Math.min(to, v))
        // Emit only — assigning `value` would break the consumer's binding.
        if (v !== value) moved(v)
    }
    // Keyboard / assistive-tech stepping. `n` counts steps, not units, so
    // PageUp can be "ten steps" whatever stepSize is.
    function _step(n) {
        if (!root.enabled)
            return
        var v = Math.max(from, Math.min(to, value + n * stepSize))
        if (v !== value) moved(v)
    }
    function _jump(v) {
        if (!root.enabled)
            return
        v = Math.max(from, Math.min(to, v))
        if (v !== value) moved(v)
    }

    Rectangle {  // track
        anchors.verticalCenter: parent.verticalCenter
        x: 10; width: parent.width - 20; height: 5
        radius: 2.5
        color: Theme.surfaceHi
        Rectangle {
            width: parent.width * root._ratio()
            height: parent.height
            radius: 2.5
            color: Theme.accent
        }
    }

    Rectangle {  // thumb
        x: 10 + (parent.width - 20) * root._ratio() - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; radius: 10
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.thumbTop }
            GradientStop { position: 1.0; color: Theme.thumbBottom }
        }
        scale: drag.pressed ? 1.15 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.5
            shadowVerticalOffset: 2
            shadowOpacity: 0.6
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // Inside a vertical Flickable a diagonal drag would otherwise let the
        // Flickable steal the grab and drop the slider mid-drag.
        preventStealing: true
        onPressed: (m) => root._setFromX(m.x)
        onPositionChanged: (m) => { if (pressed) root._setFromX(m.x) }
    }

    // Arrows step, PageUp/PageDown jump ten steps, Home/End go to the ends.
    // The arrow handlers accept only their own key; the Keys.onPressed below
    // accepts ONLY when it matched one of its four keys, so everything else
    // (letters, Escape, Ctrl chords) still bubbles to the window's key scope.
    // All six carry the same UKeys rule as the kit's Space/Return activation.
    function _keyStep(e, n) {
        if (!UKeys.claim(e))
            return
        root._step(n)
    }

    activeFocusOnTab: enabled
    Keys.onLeftPressed: (e) => root._keyStep(e, -1)
    Keys.onDownPressed: (e) => root._keyStep(e, -1)
    Keys.onRightPressed: (e) => root._keyStep(e, 1)
    Keys.onUpPressed: (e) => root._keyStep(e, 1)
    Keys.onPressed: (e) => {
        // Unlike the dedicated handlers this one arrives UNaccepted, so a
        // modified Page/Home/End just falls through and keeps bubbling.
        if (!UKeys.unmodified(e))
            return
        if (e.key === Qt.Key_PageUp) { root._step(10); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { root._step(-10); e.accepted = true }
        else if (e.key === Qt.Key_Home) { root._jump(root.from); e.accepted = true }
        else if (e.key === Qt.Key_End) { root._jump(root.to); e.accepted = true }
    }

    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onIncreaseAction: root._step(1)
    Accessible.onDecreaseAction: root._step(-1)
    // Push a value-changed event so a screen reader speaks the new number
    // while the user holds an arrow key.
    onValueChanged: Accessible.valueChanged()

    // The root Item is a 30 px band around a 5 px track: ring the whole band as
    // a pill (an Item has no radius of its own to inherit).
    UFocusRing { inset: 0; hostRadius: root.height / 2 }
}
