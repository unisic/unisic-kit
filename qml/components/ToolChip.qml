import QtQuick
import Unisic.Kit

// Tool selector chip for editor/overlay toolbars.
Rectangle {
    id: root
    property string icon: ""
    property string iconName: ""
    property string iconStyle: ""   // "", "custom" or "system" (editor tools)
    property string label: ""
    // TOGGLE or COMMAND, and this property is what tells them apart. A toggle
    // chip (a tool, a mode, bold/italic, fill on/off) binds `active` and its
    // pressed-in look IS a state; a command chip (Undo, Redo, Delete shape,
    // Save preset) never touches it and just does its thing. `var`, not `bool`,
    // exactly so "never set" stays distinguishable from "set to false": an
    // unset `active` is undefined, which is falsy for the colour bindings below
    // and is what keeps the commands out of AT-SPI's checkable/checked pair.
    // Undo and Redo used to announce as toggle buttons that were permanently
    // unchecked, which reads as "this can be switched on and is off".
    property var active
    // The hover tip's label already carries the tool name AND its shortcut
    // letter (ToolCatalog.labelWithShortcut), so it doubles as the spoken name.
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal clicked()

    function _activate() { if (root.enabled) root.clicked() }

    width: 40; height: 40
    radius: Theme.radiusM
    opacity: root.enabled ? 1 : 0.35
    color: active ? Theme.accent
         : mouse.containsMouse ? Theme.alpha(Theme.accent, 0.18)
         : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    scale: mouse.pressed ? 0.9 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

    UIcon {
        visible: root.iconName !== ""
        anchors.centerIn: parent
        name: root.iconName
        iconStyle: root.iconStyle
        color: root.active ? Theme.textOnAccent : Theme.textPrimary
        size: 18
    }
    Text {
        visible: root.iconName === "" && root.icon !== ""
        anchors.centerIn: parent
        text: root.icon
        font.pixelSize: 17
        color: root.active ? Theme.textOnAccent : Theme.textPrimary
    }

    UHoverTip {
        anchor: root
        text: root.label
        show: mouse.containsMouse
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._activate()
    }

    // UKeys keeps P/L/A/T/… bubbling from a focused chip up to the editor's and
    // the overlay's single-letter tool-shortcut handlers. A host opts a chip out
    // of the tab chain by setting `activeFocusOnTab: false` (the one spelling -
    // there is no separate `focusable` property): the capture overlay does that
    // everywhere, because it binds Space/Enter to "confirm the capture" and
    // holds an exclusive keyboard grab, so a focused chip there would swallow
    // them. The chip keeps its accessible identity either way, and AT-SPI's
    // Press action works without keyboard focus.
    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => UKeys.activate(e, root._activate)
    Keys.onReturnPressed: (e) => UKeys.activate(e, root._activate)
    Keys.onEnterPressed: (e) => UKeys.activate(e, root._activate)

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName !== "" ? accessibleName : label
    Accessible.description: accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    // Only a chip that actually toggles carries the pair; see `active` above.
    Accessible.checkable: root.active !== undefined
    Accessible.checked: root.active === true
    Accessible.onPressAction: root._activate()

    // inset 3: the toolbars pack these 40x40 chips at 4-5 px spacing, so the
    // ring is pulled well inside its own bounds and can never read as belonging
    // to the neighbour.
    UFocusRing { inset: 3 }
}
