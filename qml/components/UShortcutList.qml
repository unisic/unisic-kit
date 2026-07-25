import QtQuick
import Unisic.Kit

// Multi-binding hotkey editor: one removable chip per bound key (left to
// right, primary first) plus a ghost "+ Add shortcut" button that records an
// alternative in place. The value is the comma-joined portable string
// ("Meta+Shift+S, Print") — exactly what the settings store,
// GlobalHotkeys::keysFor parses (each chord becomes an ALTERNATE key of the
// same KGlobalAccel action) and portableFromKeys round-trips. QKeySequence
// carries at most 4 chords in one string, hence the cap.
Item {
    id: root

    property string shortcuts: ""
    readonly property var list: shortcuts.length > 0 ? shortcuts.split(", ") : []
    readonly property int maxBindings: 4

    // Passed through to the embedded UShortcutRecorder — see its doc comment.
    property var formatKey: null

    // The caption of the row this list edits, e.g. "Full screen". Declaring the
    // kit's `accessibleName` marker is also what makes UNameBridge stop HERE
    // (one wrapper deep, see its header) and hand the row's caption over, so a
    // call site inside a captioned row gets this for free.
    //
    // It is spent as the DESCRIPTION of every control in the list, never as a
    // name: a hotkey row holds one recorder plus a remove button per binding,
    // which is the bridge's shared-slot case - each of those already says what
    // it does ("+ Add shortcut", "Remove this binding") and what it lacks is
    // WHICH action it belongs to. Measured before this existed: seven identical
    // "+ Add shortcut" buttons with empty descriptions, and nothing anywhere in
    // the accessible tree tying one to "Full screen" and the next to "Region".
    // Fixed as description rather than name deliberately - deriving it from the
    // one-or-several count would flip these between name and description as the
    // user adds and removes bindings.
    property string accessibleName: ""

    signal changed(string shortcuts)
    signal captureStateChanged(bool active)

    implicitWidth: flow.implicitWidth
    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: parent.width
        spacing: 6

        Repeater {
            model: root.list
            delegate: Rectangle {
                id: keyChip
                required property string modelData
                required property int index
                width: chipText.implicitWidth + 12 + 24
                height: 32
                radius: Theme.radiusM
                color: Theme.surfaceHi
                border.width: 1
                border.color: Theme.divider

                // Not focusable: the chip itself does nothing, its remove
                // button does. It only needs to be READ, so the bound keys are
                // announced instead of a bare "remove" button in empty space.
                Accessible.role: Accessible.ListItem
                Accessible.name: keyChip.modelData
                Accessible.description: root.accessibleName
                Text {
                    id: chipText
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontS + 1
                }
                UIconButton {
                    iconName: "close"; iconSize: 10
                    width: 20; height: 20
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    tooltip: qsTr("Remove this binding")
                    accessibleDescription: root.accessibleName
                    onClicked: {
                        const next = root.list.slice()
                        next.splice(index, 1)
                        root.changed(next.join(", "))
                    }
                }
            }
        }

        UShortcutRecorder {
            visible: root.list.length < root.maxBindings
            addStyle: true
            width: recording ? 150 : implicitWidth
            placeholder: root.list.length === 0 ? qsTr("+ Add shortcut")
                                                : qsTr("+ Add alternative")
            accessibleDescription: root.accessibleName
            shortcut: ""
            formatKey: root.formatKey
            onCaptureStateChanged: (active) => root.captureStateChanged(active)
            onRecorded: (t) => {
                if (t.length === 0 || root.list.indexOf(t) >= 0)
                    return
                root.changed(root.list.concat([t]).join(", "))
            }
        }
    }
}
