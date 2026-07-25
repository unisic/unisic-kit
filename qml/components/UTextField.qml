import QtQuick
import Unisic.Kit

Rectangle {
    id: root
    property alias text: input.text
    property alias placeholder: placeholderText.text
    // Optional leading icon (e.g. "magnify" for search fields); shifts the
    // input right when set, no-op when empty so existing fields keep their
    // layout.
    property string iconName: ""
    property alias readOnly: input.readOnly
    property alias echoMode: input.echoMode
    property alias validator: input.validator
    // The root Rectangle is not a FocusScope, so its own activeFocus stays
    // false; expose the inner TextInput's focus so callers can tell if the
    // user is editing (e.g. UColorPopup's hex-field guard/blur-commit).
    readonly property alias inputActiveFocus: input.activeFocus
    // Spoken name. Defaults to the placeholder - which is the only visible
    // labelling most fields have - and is overridden by the row label where
    // there is one (USettingRow pushes it in).
    property string accessibleName: ""
    property string accessibleDescription: ""
    signal edited(string text)
    signal accepted()

    function forceFocus() { input.forceActiveFocus() }

    implicitWidth: 260
    implicitHeight: 40
    radius: Theme.radiusM
    color: Theme.surfaceHi
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.accent : Theme.divider
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    UIcon {
        visible: root.iconName !== ""
        name: root.iconName
        size: 15
        color: Theme.textTertiary
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: root.iconName !== "" ? 34 : 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.textPrimary
        font.pixelSize: Theme.fontM
        clip: true
        selectionColor: Theme.tertiary
        onTextEdited: root.edited(text)
        onAccepted: root.accepted()

        // QML TextInput defaults to activeFocusOnTab FALSE, so until now every
        // field in the app could only be reached with the mouse.
        activeFocusOnTab: root.enabled && !input.readOnly

        // The accessible identity lives on the TextInput, not on the root
        // Rectangle: the TextInput is what actually takes focus, and it already
        // provides the text/caret interfaces a screen reader reads. The root's
        // 2 px accent border (above) is this control's focus ring.
        Accessible.role: Accessible.EditableText
        Accessible.name: root.accessibleName !== "" ? root.accessibleName
                                                    : placeholderText.text
        Accessible.description: root.accessibleDescription
        Accessible.focusable: input.activeFocusOnTab
        Accessible.editable: !input.readOnly
        Accessible.readOnly: input.readOnly
        Accessible.passwordEdit: input.echoMode !== TextInput.Normal
    }
    Text {
        id: placeholderText
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        color: Theme.textTertiary
        font.pixelSize: Theme.fontM
        visible: input.text.length === 0 && !input.activeFocus
        elide: Text.ElideRight
    }
}
