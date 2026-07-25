import QtQuick
import Unisic.Kit

Rectangle {
    id: root

    property string shortcut: ""
    property string placeholder: qsTr("Click to record")
    property bool recording: false
    // Ghost-button look for the "+ Add shortcut" affordance in UShortcutList:
    // accent text, hugging width, no filled background until recording.
    property bool addStyle: false

    // Host-app hooks (the kit has no app facade): formatKey converts a captured
    // key event into the portable shortcut string — function(key, modifiers,
    // nativeScanCode) -> string, empty string = "not a bindable key, keep
    // recording". Without it the recorder captures nothing.
    // captureStateChanged(true/false) brackets the recording so the app can
    // suspend its global hotkeys meanwhile; false is also emitted from
    // Component.onDestruction so a torn-down recorder can never leave them off.
    property var formatKey: null
    // Spoken name; defaults to the bound keys, or to the placeholder while the
    // field is empty.
    property string accessibleName: ""
    property string accessibleDescription: ""

    signal recorded(string shortcut)
    signal captureStateChanged(bool active)

    implicitWidth: addStyle ? label.implicitWidth + 28 : 220
    implicitHeight: addStyle ? 32 : 40
    radius: Theme.radiusM
    color: recording ? Theme.alpha(Theme.accent, 0.16)
         : addStyle ? (hoverArea.containsMouse ? Theme.alpha(Theme.accent, 0.10) : "transparent")
         : Theme.surfaceHi
    border.width: activeFocus || recording ? 2 : 1
    border.color: recording ? Theme.accent
                : (activeFocus ? Theme.accent
                : (addStyle ? Theme.alpha(Theme.accent, 0.55) : Theme.divider))
    activeFocusOnTab: true

    function beginRecording() {
        recording = true
        forceActiveFocus()
        captureStateChanged(true)
    }

    function endRecording() {
        if (!recording)
            return
        recording = false
        captureStateChanged(false)
    }

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    Text {
        id: label
        anchors.fill: parent
        anchors.leftMargin: root.addStyle ? 0 : 14
        anchors.rightMargin: root.addStyle ? 0 : 14
        horizontalAlignment: root.addStyle ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        text: root.recording ? qsTr("Press shortcut...")
                            : (root.shortcut.length > 0 ? root.shortcut : root.placeholder)
        color: root.recording ? Theme.accent
             : root.addStyle ? Theme.accent
             : (root.shortcut.length > 0 ? Theme.textPrimary : Theme.textTertiary)
        font.pixelSize: root.addStyle ? Theme.fontS + 1 : Theme.fontM
        elide: Text.ElideRight
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.beginRecording()
    }

    // ONE handler for both states, deliberately. Dedicated
    // Keys.onSpacePressed/onReturnPressed/onEnterPressed handlers cannot do
    // this job: Qt dispatches them BEFORE Keys.onPressed, regardless of the
    // modifiers held, and auto-accepts - so while the field was recording they
    // stole exactly the keys the user was trying to BIND (Meta+Space,
    // Ctrl+Return, a bare Space), formatKey never ran and the field sat on
    // "Press shortcut..." forever.
    Keys.onPressed: (event) => {
        if (!root.recording) {
            // Idle: an unmodified Space/Return/Enter starts recording (the
            // keyboard equivalent of clicking the field) - the kit's usual
            // activation rule, spelled out here because this handler owns both
            // states. Everything else keeps bubbling, so a Tab-focused recorder
            // never eats the window's own shortcuts.
            if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return
                 || event.key === Qt.Key_Enter) && UKeys.unmodified(event)) {
                root.beginRecording()
                event.accepted = true
            }
            return
        }
        // Recording: EVERY key is ours, Space/Return/Enter included.
        event.accepted = true
        if (event.key === Qt.Key_Escape) {
            root.endRecording()
            return
        }
        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            root.recorded("")
            root.endRecording()
            return
        }

        // nativeScanCode lets the host's formatKey check the PHYSICAL key
        // (layout-independent) — see Unisic's ShortcutFormat.h.
        const value = root.formatKey
                    ? root.formatKey(event.key, event.modifiers, event.nativeScanCode) : ""
        if (value.length > 0) {
            root.recorded(value)
            root.endRecording()
        }
    }

    Accessible.role: Accessible.HotkeyField
    Accessible.name: root.accessibleName !== "" ? root.accessibleName
                   : (root.shortcut.length > 0 ? root.shortcut : root.placeholder)
    Accessible.description: root.accessibleDescription
    Accessible.focusable: root.activeFocusOnTab
    Accessible.onPressAction: root.beginRecording()

    onActiveFocusChanged: {
        if (!activeFocus)
            endRecording()
    }

    Component.onDestruction: captureStateChanged(false)
}
