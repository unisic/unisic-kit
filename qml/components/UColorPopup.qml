import QtQuick
import QtQuick.Controls
import Unisic.Kit

// In-scene HSV colour picker. QtQuick.Dialogs' ColorDialog is a separate
// top-level Window — under the region overlay's layer-shell surface (which
// holds an EXCLUSIVE keyboard grab) that window never receives input, so it
// froze the whole capture screen. A Popup renders inside the SAME window
// scene / wl_surface, so it works everywhere the overlay does.
Popup {
    id: root

    property bool showAlpha: false
    // Scrim darkness behind the picker. Kept LIGHT by default: the whole point
    // of the in-scene picker is comparing the colour against the image, which
    // a heavy dim (the old separate-window ColorDialog greyed everything)
    // made impossible.
    property real scrimOpacity: 0.25
    // Quick-pick chips (the theme palette by default).
    property var swatches: Theme.swatches

    // Emitted continuously as the user drags (live preview) and once more on
    // Done — consumers just assign it to their colour property.
    signal picked(color c)
    // The eyedropper button asks the host to start screen colour-picking; the
    // host samples a pixel and calls setColor(c) to resume with it.
    signal requestScreenPick()

    // Set h/s/v/a from an arbitrary colour (used by the hex field and the
    // screen eyedropper result).
    function setColor(c) {
        hue = c.hsvHue >= 0 ? c.hsvHue : hue
        sat = c.hsvSaturation
        val = c.hsvValue
        if (root.showAlpha)
            alpha = c.a
    }

    // HSV state in [0,1]; `col` is the composed result.
    property real hue: 0
    property real sat: 0
    property real val: 1
    property real alpha: 1
    readonly property color col: Qt.hsva(hue, sat, val, alpha)

    function openWith(c) {
        hue = c.hsvHue >= 0 ? c.hsvHue : 0
        sat = c.hsvSaturation
        val = c.hsvValue
        alpha = c.a
        open()
    }

    onColChanged: if (opened) root.picked(col)

    parent: Overlay.overlay
    anchors.centerIn: parent
    // Centred, so the WINDOW is its anchor - but the containment rule is the
    // same one every flyout follows, see UFlyout.qml: `margins` is what keeps
    // it inside, and the content below scrolls rather than spilling out of a
    // window too short to show it whole.
    margins: UFlyout.margin
    modal: true
    focus: true
    // Escape must close THIS, not cancel the capture session — a focused
    // Popup consumes the key before the overlay root's handler sees it.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Theme.spacingL

    // Percentages read better than 0..1 floats in a screen reader.
    function _pct(v) { return Math.round(v * 100) + "%" }

    Overlay.modal: Rectangle { color: Theme.alpha(Theme.mediaBase, root.scrimOpacity) }
    background: Rectangle {
        radius: Theme.radiusL
        color: Theme.surface
        border.width: 1
        border.color: Theme.divider
    }

    // Scroller + column. It only ever scrolls when the window is too short for
    // the whole picker (UFlyout rule 3): with room, contentHeight equals the
    // height and `interactive` is false, so nothing about the drag surfaces
    // below changes. Measured before this: at 480x300 the swatch row, the hex
    // field and the Done button hung 36-82px out of the popup's own background.
    contentItem: Flickable {
        id: pickerFlick
        // 240 is the picker's own width, as it always was: the hex field, the
        // hue and alpha bars and the SV square all size off it. The swatch row
        // may ask for more (a custom theme with more swatches), never for less
        // - deriving the width from that row alone shrank the picker by 50 px
        // and squeezed the hex field, and a short row could drive it negative.
        implicitWidth: Math.max(240, swatchRow.implicitWidth)
        implicitHeight: UFlyout.fitHeight(root.parent, pickerCol.implicitHeight
                                          + root.topPadding + root.bottomPadding)
                        - root.topPadding - root.bottomPadding
        contentWidth: width
        contentHeight: pickerCol.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        // The wheel reaches nothing else in here: the SV square, the hue bar and
        // the alpha bar are all drag surfaces, none of them takes a wheel.
        MiddleScroll { flickable: pickerFlick }
        WheelBoost { flickable: pickerFlick }

        Column {
            id: pickerCol
            spacing: Theme.spacingM
            width: pickerFlick.width

            // On the contentItem, not on the Popup: the Accessible attached type
            // only binds to an Item, and a Popup is not one.
            Accessible.role: Accessible.ColorChooser
            Accessible.name: qsTr("Colour picker")

            // ---- saturation / value square ----
            Item {
                id: svArea
                width: parent.width
                height: 150

                function _nudge(ds, dv) {
                    root.sat = Math.max(0, Math.min(1, root.sat + ds))
                    root.val = Math.max(0, Math.min(1, root.val + dv))
                }

                activeFocusOnTab: true
                Keys.onLeftPressed: (e) => { if (UKeys.claim(e)) svArea._nudge(-0.02, 0) }
                Keys.onRightPressed: (e) => { if (UKeys.claim(e)) svArea._nudge(0.02, 0) }
                Keys.onUpPressed: (e) => { if (UKeys.claim(e)) svArea._nudge(0, 0.02) }
                Keys.onDownPressed: (e) => { if (UKeys.claim(e)) svArea._nudge(0, -0.02) }

                // No 2D-field role exists; Canvas is the honest one, and the live
                // values travel in the name so arrow-key nudging is audible.
                Accessible.role: Accessible.Canvas
                Accessible.name: qsTr("Saturation and brightness")
                Accessible.description: qsTr("Saturation %1, brightness %2")
                                        .arg(root._pct(root.sat)).arg(root._pct(root.val))
                Accessible.focusable: svArea.activeFocusOnTab

                UFocusRing { inset: 0; hostRadius: Theme.radiusS }

                Rectangle { // pure hue base
                    anchors.fill: parent
                    radius: Theme.radiusS
                    color: Qt.hsva(root.hue, 1, 1, 1)
                }
                Rectangle { // white -> transparent (saturation, left to right)
                    anchors.fill: parent
                    radius: Theme.radiusS
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ffffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
                Rectangle { // transparent -> black (value, top to bottom)
                    anchors.fill: parent
                    radius: Theme.radiusS
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#ff000000" }
                    }
                }
                Rectangle { // marker
                    width: 14; height: 14; radius: 7
                    border.width: 2; border.color: Theme.mediaText
                    color: "transparent"
                    x: root.sat * parent.width - width / 2
                    y: (1 - root.val) * parent.height - height / 2
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 2; radius: 5
                        border.width: 1; border.color: Theme.alpha(Theme.mediaBase, 0.5); color: "transparent"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    // The scroller above only turns interactive in a window too
                    // short for the picker; there, a drag here must still paint the
                    // colour instead of scrolling it away.
                    preventStealing: true
                    onPressed: (m) => handle(m)
                    onPositionChanged: (m) => handle(m)
                    function handle(m) {
                        root.sat = Math.max(0, Math.min(1, m.x / width))
                        root.val = Math.max(0, Math.min(1, 1 - m.y / height))
                    }
                }
            }

            // ---- hue slider ----
            Item {
                id: hueArea
                width: parent.width
                height: 18

                function _nudge(d) { root.hue = Math.max(0, Math.min(1, root.hue + d)) }

                activeFocusOnTab: true
                Keys.onLeftPressed: (e) => { if (UKeys.claim(e)) hueArea._nudge(-0.01) }
                Keys.onDownPressed: (e) => { if (UKeys.claim(e)) hueArea._nudge(-0.01) }
                Keys.onRightPressed: (e) => { if (UKeys.claim(e)) hueArea._nudge(0.01) }
                Keys.onUpPressed: (e) => { if (UKeys.claim(e)) hueArea._nudge(0.01) }

                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Hue")
                Accessible.description: Math.round(root.hue * 360) + "°"
                Accessible.focusable: hueArea.activeFocusOnTab
                Accessible.onIncreaseAction: hueArea._nudge(0.01)
                Accessible.onDecreaseAction: hueArea._nudge(-0.01)

                UFocusRing { inset: 0; hostRadius: 9 }

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.000; color: "#ff0000" }
                        GradientStop { position: 0.167; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.500; color: "#00ffff" }
                        GradientStop { position: 0.667; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1.000; color: "#ff0000" }
                    }
                }
                Rectangle {
                    width: 6; height: parent.height + 4; radius: 3
                    y: -2
                    x: root.hue * parent.width - width / 2
                    color: "transparent"
                    border.width: 2; border.color: Theme.mediaText
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true   // same as the square above
                    onPressed: (m) => root.hue = Math.max(0, Math.min(1, m.x / width))
                    onPositionChanged: (m) => root.hue = Math.max(0, Math.min(1, m.x / width))
                }
            }

            // ---- alpha slider (fill colour only) ----
            Item {
                id: alphaArea
                visible: root.showAlpha
                width: parent.width
                height: 18

                function _nudge(d) { root.alpha = Math.max(0, Math.min(1, root.alpha + d)) }

                activeFocusOnTab: visible
                Keys.onLeftPressed: (e) => { if (UKeys.claim(e)) alphaArea._nudge(-0.02) }
                Keys.onDownPressed: (e) => { if (UKeys.claim(e)) alphaArea._nudge(-0.02) }
                Keys.onRightPressed: (e) => { if (UKeys.claim(e)) alphaArea._nudge(0.02) }
                Keys.onUpPressed: (e) => { if (UKeys.claim(e)) alphaArea._nudge(0.02) }

                Accessible.role: Accessible.Slider
                Accessible.name: qsTr("Opacity")
                Accessible.description: root._pct(root.alpha)
                Accessible.focusable: alphaArea.activeFocusOnTab
                Accessible.onIncreaseAction: alphaArea._nudge(0.02)
                Accessible.onDecreaseAction: alphaArea._nudge(-0.02)

                UFocusRing { inset: 0; hostRadius: 9 }

                Canvas { // checkerboard so transparency reads
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        const s = 6
                        for (let y = 0; y < height; y += s)
                            for (let x = 0; x < width; x += s) {
                                ctx.fillStyle = ((x / s + y / s) % 2 === 0) ? "#cccccc" : "#888888"
                                ctx.fillRect(x, y, s, s)
                            }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.hsva(root.hue, root.sat, root.val, 0) }
                        GradientStop { position: 1.0; color: Qt.hsva(root.hue, root.sat, root.val, 1) }
                    }
                }
                Rectangle {
                    width: 6; height: parent.height + 4; radius: 3
                    y: -2
                    x: root.alpha * parent.width - width / 2
                    color: "transparent"
                    border.width: 2; border.color: Theme.mediaText
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true   // same as the square above
                    onPressed: (m) => root.alpha = Math.max(0, Math.min(1, m.x / width))
                    onPositionChanged: (m) => root.alpha = Math.max(0, Math.min(1, m.x / width))
                }
            }

            // ---- quick swatches ----
            Row {
                id: swatchRow
                spacing: 6
                Repeater {
                    model: root.swatches
                    delegate: Rectangle {
                        id: swatch
                        required property var modelData
                        width: 22; height: 22; radius: Theme.radiusS
                        color: modelData
                        border.width: Qt.colorEqual(modelData, root.col) ? 2 : 1
                        border.color: Qt.colorEqual(modelData, root.col) ? Theme.accent : Theme.divider

                        function _pick() {
                            const c = swatch.color
                            root.hue = c.hsvHue >= 0 ? c.hsvHue : root.hue
                            root.sat = c.hsvSaturation
                            root.val = c.hsvValue
                            // keep current alpha
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: swatch._pick()
                        }

                        activeFocusOnTab: true
                        Keys.onSpacePressed: (e) => UKeys.activate(e, swatch._pick)
                        Keys.onReturnPressed: (e) => UKeys.activate(e, swatch._pick)
                        Keys.onEnterPressed: (e) => UKeys.activate(e, swatch._pick)

                        Accessible.role: Accessible.Button
                        // No name to inherit - the hex value is the only honest one.
                        Accessible.name: String(swatch.modelData)
                        Accessible.focusable: swatch.activeFocusOnTab
                        Accessible.checkable: true
                        Accessible.checked: Qt.colorEqual(swatch.modelData, root.col)
                        Accessible.onPressAction: swatch._pick()

                        UFocusRing { inset: 0; hostRadius: Theme.radiusS }
                    }
                }
            }

            // ---- eyedropper + editable hex ----
            Row {
                width: parent.width
                spacing: Theme.spacingS
                UIconButton {
                    iconName: "color-picker"; iconSize: 16
                    width: 34; height: 34
                    anchors.verticalCenter: parent.verticalCenter
                    tooltip: qsTr("Pick a colour from the screen")
                    onClicked: { root.close(); root.requestScreenPick() }
                }
                Rectangle {
                    width: 34; height: 34; radius: Theme.radiusS
                    color: root.col
                    border.width: 1; border.color: Theme.divider
                    anchors.verticalCenter: parent.verticalCenter
                }
                UTextField {
                    id: hexField
                    width: parent.width - 34 * 2 - Theme.spacingS * 2
                    anchors.verticalCenter: parent.verticalCenter
                    placeholder: root.showAlpha ? "#AARRGGBB" : "#RRGGBB"
                    // Reflect the live colour unless the user is editing the field.
                    text: hexField.inputActiveFocus ? text
                        : (root.showAlpha
                           ? "#" + root.col.toString().slice(1).toUpperCase()
                           : "#" + root.col.toString().slice(1, 7).toUpperCase())
                    function applyHex() {
                        let t = text.trim()
                        if (t.length > 0 && t[0] !== "#") t = "#" + t
                        // #RGB / #RRGGBB / #AARRGGBB only.
                        if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t)) {
                            const c = Qt.color(t)
                            if (c.a !== undefined) root.setColor(c)
                        }
                    }
                    onAccepted: applyHex()
                    onInputActiveFocusChanged: if (!hexField.inputActiveFocus) applyHex()
                }
            }

            // ---- done ----
            UButton {
                anchors.right: parent.right
                text: qsTr("Done")
                variant: "filled"
                compact: true
                onClicked: { root.picked(root.col); root.close() }
            }
        }
    }
}
