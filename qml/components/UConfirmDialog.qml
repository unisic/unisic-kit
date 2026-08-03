import QtQuick
import QtQuick.Controls
import Unisic.Kit

// In-app themed confirmation dialog — replaces QtQuick.Dialogs' MessageDialog,
// which opens a separate Qt-styled window that clashes with the design system.
// Parent it to Overlay.overlay so it centers over the whole window and dims it.
Popup {
    id: root

    property string title: ""
    property string text: ""
    property string confirmText: qsTr("OK")
    property string cancelText: qsTr("Cancel")
    // Destructive actions get the danger colour on the confirm button.
    property bool destructive: false
    // Info-only dialogs (e.g. settings help) hide the cancel button.
    property bool showCancel: true

    signal accepted()

    parent: Overlay.overlay
    anchors.centerIn: parent
    // Centred, so the WINDOW is its anchor - the containment rule is the one
    // every flyout follows, see UFlyout.qml.
    margins: UFlyout.margin
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    // Its own gutter is WIDER than UFlyout.margin on purpose - a dialog that
    // hugs the window edges reads as a panel. Stricter than the rule, so the
    // rule has nothing left to do horizontally.
    width: Math.min(440, parent ? parent.width - 2 * Theme.spacingXL : 440)
    padding: Theme.spacingXL

    // Land the keyboard on a button so the dialog is answerable without a
    // mouse. On a DESTRUCTIVE dialog that button is CANCEL: Return is the
    // habitual "make this go away" key, and "Discard annotations?" /
    // "Delete 12 history entries?" must never be answered by reflex. The safe
    // choice is focused, the destructive one is one Tab away, and Escape
    // cancels either way (closePolicy). Non-destructive dialogs (and info-only
    // ones with no cancel button at all) keep the confirm button focused.
    onOpened: (root.destructive && root.showCancel ? cancelButton : confirmButton)
                  .forceActiveFocus(Qt.PopupFocusReason)

    Overlay.modal: Rectangle { color: Theme.modalScrim }

    background: Rectangle {
        radius: Theme.radiusL
        color: Theme.surface
        border.width: 1
        border.color: Theme.divider
    }

    // Scroller + column: a long message in a short window scrolls instead of
    // pushing the buttons out of the dialog (UFlyout rule 3). With room it is
    // inert - contentHeight equals the height and it cannot be flicked.
    contentItem: Flickable {
        id: bodyFlick
        implicitHeight: UFlyout.fitHeight(root.parent, bodyCol.implicitHeight
                                          + root.topPadding + root.bottomPadding)
                        - root.topPadding - root.bottomPadding
        contentWidth: width
        contentHeight: bodyCol.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        MiddleScroll { flickable: bodyFlick }
        WheelBoost { flickable: bodyFlick }

        Column {
            id: bodyCol
            width: bodyFlick.width
            spacing: Theme.spacingM

            // On the contentItem, not on the Popup: the Accessible attached type
            // only binds to an Item, and a Popup is not one.
            Accessible.role: Accessible.Dialog
            Accessible.name: root.title
            Accessible.description: root.text

            Text {
                width: parent.width
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: Theme.fontL
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: root.text
                color: Theme.textSecondary
                font.pixelSize: Theme.fontM
                wrapMode: Text.WordWrap
            }
            Item { width: 1; height: Theme.spacingS }
            Row {
                anchors.right: parent.right
                spacing: Theme.spacingS
                UButton {
                    id: cancelButton
                    visible: root.showCancel
                    text: root.cancelText
                    variant: "ghost"
                    compact: true
                    onClicked: root.close()
                }
                UButton {
                    id: confirmButton
                    text: root.confirmText
                    variant: root.destructive ? "danger" : "filled"
                    compact: true
                    onClicked: { root.close(); root.accepted() }
                }
            }
        }
    }
}
