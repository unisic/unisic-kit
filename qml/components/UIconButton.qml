import QtQuick
import Unisic.Kit

Rectangle {
    id: root
    property string icon: ""
    property string iconName: ""
    property string tooltip: ""
    // Tri-state: see the Accessible block below. Undefined is falsy, so every
    // `active ? … : …` binding in here reads it exactly as it read false.
    property var active
    property int iconSize: 18
    // Icon-only control: the tooltip is the ONLY user-visible label, so it is
    // also the default spoken name. `accessibleName` overrides it for the
    // handful of buttons that carry no tooltip at all.
    property string accessibleName: ""
    property string accessibleDescription: ""
    readonly property alias hovered: mouse.containsMouse
    signal clicked()

    readonly property string _accName: accessibleName !== "" ? accessibleName : tooltip

    function _activate() { if (root.enabled) root.clicked() }

    width: 38; height: 38
    radius: Theme.radiusM
    opacity: root.enabled ? 1 : 0.35
    color: active ? Theme.accent
         : mouse.containsMouse ? Theme.alpha(Theme.accent, 0.16)
         : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    scale: mouse.pressed && root.enabled ? 0.92 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

    UIcon {
        visible: root.iconName !== ""
        anchors.centerIn: parent
        name: root.iconName
        color: root.active ? Theme.textOnAccent : Theme.textPrimary
        size: root.iconSize
    }
    Text {
        visible: root.iconName === "" && root.icon !== ""
        anchors.centerIn: parent
        text: root.icon
        font.pixelSize: 17
        color: root.active ? Theme.textOnAccent : Theme.textPrimary
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._activate()
    }

    UHoverTip {
        anchor: root
        text: root.tooltip
        show: mouse.containsMouse
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => UKeys.activate(e, root._activate)
    Keys.onReturnPressed: (e) => UKeys.activate(e, root._activate)
    Keys.onEnterPressed: (e) => UKeys.activate(e, root._activate)

    Accessible.role: Accessible.Button
    Accessible.name: root._accName
    // Only what the caller adds on top: mirroring the tooltip here would make a
    // screen reader read the same sentence twice (it is already the name).
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    // `active` is this control's pressed-in/toggled look (tool selected, panel
    // open) - report it so the state is audible, not just visible. Tri-state,
    // same rule as ToolChip and ColorDot: unset means a plain command button,
    // and a command must not carry a checked state with no checkable to
    // explain it (the Settings gear and the title-bar buttons are commands).
    Accessible.checkable: root.active !== undefined
    Accessible.checked: root.active === true
    Accessible.onPressAction: root._activate()

    UFocusRing { }
}
