import QtQuick
import Unisic.Kit

Rectangle {
    id: root
    property string icon: ""
    property string iconName: ""
    property string label: ""
    property bool active: false
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal clicked()

    function _activate() { if (root.enabled) root.clicked() }

    width: parent ? parent.width : 200
    height: 38
    radius: Theme.radiusS
    color: active ? Theme.tertiary
         : mouse.containsMouse ? Theme.alpha(Theme.tertiary, 0.45)
         : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 11
        spacing: 10
        UIcon {
            visible: root.iconName !== ""
            name: root.iconName
            color: root.active ? Theme.textPrimary : Theme.textSecondary
            size: 17
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.iconName === "" && root.icon !== ""
            text: root.icon; font.pixelSize: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.label
            color: root.active ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: Theme.fontM
            font.weight: root.active ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
        }
    }

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

    // ListItem, not PageTab: there is no PageTabList container around these,
    // and ListItem carries the selected state a screen reader needs.
    Accessible.role: Accessible.ListItem
    Accessible.name: accessibleName !== "" ? accessibleName : label
    Accessible.description: accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.selectable: true
    Accessible.selected: root.active
    Accessible.onPressAction: root._activate()

    UFocusRing { inset: 1 }
}
