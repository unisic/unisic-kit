import QtQuick
import Unisic.Kit

Rectangle {
    id: root
    property color dotColor: "#FF4757"
    // Tri-state, same rule as ToolChip: left unset (undefined) this dot is a
    // plain button - the picker-opening dots in the props bar are that - and
    // bound to a bool it is a two-state swatch. Announcing every dot as a
    // checkable toggle made the picker openers claim a checked state that
    // mirrored an unrelated switch. Undefined is falsy, so the visuals below
    // read it exactly as they read false.
    property var active
    // The hover state is owned by the internal MouseArea, whose id is not
    // reachable from a caller — expose it so a host can drive a hover tip.
    readonly property alias hovered: mouse.containsMouse
    // A dot has no text at all, so a screen reader would announce a wall of
    // nameless buttons. Hosts (ToolPropsBar's swatches, fill, outline, presets)
    // name theirs; the hex value is the fallback so it is never empty.
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal clicked()

    function _activate() { if (root.enabled) root.clicked() }

    width: 26; height: 26
    radius: 13
    color: dotColor
    // Hover feedback is BORDER COLOUR ONLY. The dot used to scale to 1.12 on
    // hover, which moved a control under the pointer; the selected state still
    // grows it, because that is a state change and not a hover response.
    border.width: active ? 3 : 1
    border.color: active ? Theme.accent
                : mouse.containsMouse ? Theme.alpha(Theme.textPrimary, 0.65)
                : Theme.alpha(Theme.textPrimary, 0.25)
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    scale: active ? 1.12 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._activate()
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => UKeys.activate(e, root._activate)
    Keys.onReturnPressed: (e) => UKeys.activate(e, root._activate)
    Keys.onEnterPressed: (e) => UKeys.activate(e, root._activate)

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName !== "" ? accessibleName : String(root.dotColor)
    Accessible.description: accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.checkable: root.active !== undefined
    Accessible.checked: root.active === true
    Accessible.onPressAction: root._activate()

    // The dot is filled edge to edge, so the ring goes OUTSIDE its fill but
    // still inside the item's own bounds: a negative inset would grow nothing
    // (the item keeps its 26x26) yet would overlap a neighbouring swatch, so it
    // sits at the edge instead.
    UFocusRing { inset: 0; hostRadius: root.radius }
}
