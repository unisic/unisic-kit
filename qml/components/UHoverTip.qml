import QtQuick
import QtQuick.Controls as C
import QtQuick.Effects
import Unisic.Kit

// Hover tooltip rendered as a PLAIN visual Item on the window's overlay layer.
// It is deliberately NOT a Popup and carries no input handling: a Popup tooltip
// perturbed the scene's hover delivery, which flip-flopped the anchor's
// `containsMouse` and made the tip blink. A plain overlay item lets every mouse/
// hover event pass straight through to the anchor, so hover stays stable and the
// tip never flickers. Still on the overlay (never clipped by toolbars / the
// custom title bar); flips below the anchor near the window's top edge.
//
// The ONE tooltip in the app: every hover hint goes through here so they share
// the delay, the fade and the look. Qt Quick Controls' own ToolTip is the Basic
// style's grey box and matches nothing else in this UI.
Item {
    id: tip

    required property Item anchor
    property string text: ""
    property bool show: false
    // A tip that appears the instant the pointer crosses a button strobes while
    // you sweep along a toolbar; a short arming delay keeps it calm.
    property int delayMs: 320
    // Long hints wrap instead of running off the window.
    property int maxWidth: 320
    // A key chip after the text, for a control whose shortcut is worth
    // reading at a glance (the editor's tools) rather than inside "(P)".
    property string shortcut: ""
    // "auto": above the anchor, below it near the window's top edge. "right":
    // beside it, for a vertical rail whose neighbours sit above and below.
    property string placement: "auto"

    parent: C.Overlay.overlay
    enabled: false // purely visual — never intercepts the anchor's hover

    property bool _armed: false
    Timer {
        id: armTimer
        interval: tip.delayMs
        onTriggered: tip._armed = true
    }
    onShowChanged: {
        if (show) {
            armTimer.restart()
        } else {
            armTimer.stop()
            tip._armed = false
        }
    }

    readonly property bool _wanted: show && _armed && text !== ""
                                    && anchor !== null && parent !== null
    opacity: _wanted ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    width: bg.width
    height: bg.height

    // Anchor's top-left in overlay coordinates. `show` is a deliberate binding
    // dependency: mapToItem is NOT reactive to a scrolling ancestor, so an anchor
    // inside a GridView/Flickable (the History grid) would otherwise keep its
    // stale creation-time position and the tip would land far from the button.
    // Re-reading on every show fixes it — the anchor is static during a hover.
    readonly property point _a: (show && anchor && parent)
        ? anchor.mapToItem(parent, 0, 0) : Qt.point(0, 0)
    readonly property bool _above: _a.y > height + 10
    readonly property bool _right: placement === "right"

    // Centred on the anchor, then kept on screen. This is not a Popup, so it
    // gets no positioner and no `margins` - it clamps through the same UFlyout
    // rule by hand, in its own bindings (which re-run on every dependency, so
    // there is nothing stale to re-place).
    x: (!anchor || !parent) ? 0
        : UFlyout.clampX(parent, _right ? _a.x + anchor.width + 8
                                        : _a.x + (anchor.width - width) / 2, width)
    // Above the anchor, or below it when the top edge is too close - clamped
    // either way, so a tip on a control at the very bottom cannot hang out.
    y: (!anchor || !parent) ? 0
        : UFlyout.clampY(parent, _right ? _a.y + (anchor.height - height) / 2
                                 : _above ? _a.y - height - 8 : _a.y + anchor.height + 8,
                         height)
    // A few pixels of travel on the way in, from the direction it opens.
    transform: Translate {
        x: tip._wanted || !tip._right ? 0 : -4
        y: tip._wanted || tip._right ? 0 : (tip._above ? 4 : -4)
        Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: bg
        implicitWidth: tipRow.width + (tip.shortcut !== "" ? 15 : 20)
        implicitHeight: Math.max(tipLabel.implicitHeight + 12, tip.shortcut !== "" ? 26 : 0)
        radius: Theme.radiusS
        color: Theme.tooltipBg
        border.width: 1
        border.color: Theme.alpha(Theme.edgeLight, 0.18)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.7
            shadowVerticalOffset: 2
            shadowOpacity: 0.45
        }

        Row {
            id: tipRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                id: tipLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, tip.maxWidth)
                text: tip.text
                color: Theme.tooltipText
                font.pixelSize: Theme.fontS
                wrapMode: Text.WordWrap
                horizontalAlignment: lineCount > 1 ? Text.AlignLeft : Text.AlignHCenter
            }
            Rectangle {
                visible: tip.shortcut !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(20, keyText.implicitWidth + 10)
                height: 20
                radius: 4
                color: Theme.alpha(Theme.tooltipText, 0.10)
                border.width: 1
                border.color: Theme.alpha(Theme.tooltipText, 0.18)
                Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: tip.shortcut
                    color: Theme.tooltipText
                    font.family: "monospace"
                    font.pixelSize: 11
                }
            }
        }
    }
}
