import QtQuick
import QtQuick.Effects
import Unisic.Kit

// iOS-style toggle.
Rectangle {
    id: root
    property bool checked: false
    // A switch carries no label of its own - the row around it does. USettingRow
    // pushes its label in here automatically; a hand-built row sets it.
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal toggled(bool checked)

    // Single activation path for pointer, keyboard and assistive tech. Emit
    // only - see the MouseArea note below.
    function _toggle() { if (root.enabled) root.toggled(!root.checked) }

    width: 50; height: 30
    radius: height / 2
    color: checked ? Theme.accent : Theme.surfaceHi
    border.width: 1
    border.color: checked ? Theme.accent : Theme.divider
    Behavior on color { ColorAnimation { duration: Theme.animMed } }

    Rectangle {
        width: 24; height: 24
        radius: 12
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.thumbTop }
            GradientStop { position: 1.0; color: Theme.thumbBottom }
        }
        Behavior on x { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
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
        anchors.fill: parent
        // A few pixels of slop around a 50x30 pill. Every row that holds one is
        // at least 40 px tall and the switch is alone at its right end, so the
        // margin lands on the row's own padding and can reach nothing else -
        // the same trick the Settings help badge uses. Clicks that graze the
        // edge (and the last pixels of a still-settling scroll) land on the
        // switch instead of on the row behind it.
        anchors.margins: -5
        cursorShape: Qt.PointingHandCursor
        // Emit only — writing `checked` here would destroy the consumer's
        // declarative binding (e.g. checked: model.enabled) on first interaction;
        // the handler updates the source and the binding flows back.
        onClicked: root._toggle()
    }

    activeFocusOnTab: enabled
    Keys.onSpacePressed: (e) => UKeys.activate(e, root._toggle)
    Keys.onReturnPressed: (e) => UKeys.activate(e, root._toggle)
    Keys.onEnterPressed: (e) => UKeys.activate(e, root._toggle)

    // CheckBox, NOT Switch. QAccessible::Switch (0x87) only exists from Qt 6.11
    // on; the shipped channels run older Qt (the AppImage/tarball pin 6.8.3, the
    // native packages follow their distro, and the declared floor is 6.5), where
    // `Accessible.Switch` resolves to undefined - the role assignment is dropped
    // with a warning and the control ends up with NO role at all. A local 6.11
    // dev build cannot see that, and neither can ctest.
    //
    // CheckBox + checkable/checked is the same fallback Qt itself used: Qt Quick
    // Controls' own Switch only moved to the new role in 6.11 ("The new
    // accessibility role Switch is used by the Switch type in Qt Quick
    // Controls." - What's New in Qt 6.11). Orca reads it as a two-state control
    // either way. Revisit only when the floor is 6.11+.
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onToggleAction: root._toggle()
    // Orca sends Press to plain switches too; route it to the same code path.
    Accessible.onPressAction: root._toggle()

    // inset 0: the pill is only 30 px tall and the thumb fills 24 of them, so an
    // inset ring would cut across the thumb. On the edge it just thickens the
    // existing 1 px border into an accent outline.
    UFocusRing { inset: 0 }
}
