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
    // Icon above a short label, for a narrow icon rail. Off by default: the
    // wide sidebar row stays exactly as it was for every existing caller.
    property bool stacked: false
    signal clicked()

    function _activate() { if (root.enabled) root.clicked() }

    width: parent ? parent.width : 200
    height: stacked ? 56 : 38
    radius: stacked ? Theme.radiusM : Theme.radiusS
    color: active ? (stacked ? Theme.secondary : Theme.tertiary)
         : mouse.containsMouse ? Theme.alpha(Theme.tertiary, 0.45)
         : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Row {
        visible: !root.stacked
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

    Column {
        visible: root.stacked
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.spacingXS
        spacing: 4
        UIcon {
            name: root.iconName
            color: root.active ? Theme.accent : Theme.textSecondary
            size: 20
            anchors.horizontalCenter: parent.horizontalCenter
        }
        // German and Italian labels run past the tile at full size, so the
        // text shrinks to fit before it elides.
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: root.active ? Theme.textPrimary : Theme.textSecondary
            font.pixelSize: 11
            font.weight: root.active ? Font.DemiBold : Font.Medium
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 9
            elide: Text.ElideRight
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
