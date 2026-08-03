// Bound: the pill Repeater's delegate reaches the TextInput it draws inside by
// id, which a delegate may only do under this pragma.
pragma ComponentBehavior: Bound

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
    // A JS regular expression (source only, matched globally) for the template
    // variables this field understands. Every match is painted as a pill behind
    // the text it occupies, so "%file%" reads as one thing to click past rather
    // than six characters of punctuation. The field stays a plain TextInput and
    // `text` stays exactly the string that gets saved: only the painting knows
    // about this, so nothing downstream has to.
    property string tokenPattern: ""
    signal edited(string text)
    signal accepted()

    function forceFocus() { input.forceActiveFocus() }

    // Drops a variable in at the caret, replacing any selection, and leaves the
    // field focused with the caret where the user has to keep typing. A chip is
    // a typing shortcut, not a mode: `caretBack` is how many characters back
    // from the end the caret belongs, so inserting "$json:$" leaves it inside
    // the token where the path goes.
    //
    // A chip clicked while the caret is still parked inside the token the
    // PREVIOUS chip typed steps past that token first. Otherwise two clicks
    // nest one variable inside another - "$json:" + "$regex:" came out as
    // "$json:$regex:$$", which no extractor resolves, and every further click
    // piled another orphaned "$" on the end (user-reported). Only that exact
    // caret counts as parked: move it, or type in the token, and the chip goes
    // where the caret is, because then the position is the user's own choice.
    property int parkedCaret: -1   // where the last chip left the caret
    property int parkedEnd: -1     // end of the token it left it inside
    function insertToken(token, caretBack) {
        input.forceActiveFocus()
        if (input.selectionStart !== input.selectionEnd)
            input.remove(input.selectionStart, input.selectionEnd)
        if (root.parkedCaret >= 0 && input.cursorPosition === root.parkedCaret
            && root.parkedEnd <= input.text.length)
            input.cursorPosition = root.parkedEnd
        const at = input.cursorPosition
        input.insert(at, token)
        const back = caretBack || 0
        input.cursorPosition = at + token.length - back
        root.parkedCaret = back > 0 ? input.cursorPosition : -1
        root.parkedEnd = at + token.length
        // insert() is not typing, so textEdited never fires for it - without
        // this a caller that only listens to `edited` would miss the change.
        root.edited(input.text)
    }

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

    // The pills live OUTSIDE the TextInput, before it so they paint behind the
    // glyphs. Inside they were children of a clipping item, and a pill drawn
    // wider than its text lost exactly that padding to the clip: a flat cut
    // where the rounded end belonged, which read as the pill running out of the
    // field. This box is the input's rect grown by that padding, so the pill
    // keeps its shape and a token scrolled out of view still loses its half.
    Item {
        id: pillBox
        readonly property int padX: 3
        readonly property int padY: 1
        x: input.x - padX
        y: input.y - padY
        width: input.width + 2 * padX
        height: input.height + 2 * padY
        clip: true

        Repeater {
            model: input.tokenRanges
            Rectangle {
                required property var modelData
                required property int index
                // Each pill takes at most half the blank next to it, so two
                // never claim the same pixels. "$text$$text$" is two variables
                // with nothing between them, and pills grown by padX regardless
                // overlapped by twice that: their rounded borders crossed inside
                // the overlap and a row of tokens read as a scribble
                // (user-reported). A single space between two of them is the
                // same bug, 4 px wide.
                readonly property int padL: {
                    void input.tokenRev
                    return Math.min(pillBox.padX, Math.floor(input.tokenGap(index) / 2))
                }
                readonly property int padR: {
                    void input.tokenRev
                    return Math.min(pillBox.padX, Math.floor(input.tokenGap(index + 1) / 2))
                }
                readonly property rect box: {
                    void input.tokenRev // dependency only: positionToRectangle
                                        // is a function, so without this the
                                        // pills would stay put while the field
                                        // scrolls
                    const a = input.positionToRectangle(modelData[0])
                    const b = input.positionToRectangle(modelData[1])
                    return Qt.rect(a.x, a.y, b.x - a.x, a.height)
                }
                // pillBox already carries padX as its own offset, so the token's
                // left edge sits at box.x + padX in it.
                x: box.x + pillBox.padX - padL
                y: box.y
                width: box.width + padL + padR
                height: box.height + 2 * pillBox.padY
                radius: Theme.radiusS
                color: Theme.alpha(Theme.accent, 0.18)
                border.width: 1
                border.color: Theme.alpha(Theme.accent, 0.5)
            }
        }
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
        onTextEdited: {
            // Typing is the user taking the caret back, so the next chip goes
            // exactly where they put it.
            root.parkedCaret = -1
            root.edited(text)
        }
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

        // Every valid token in the text, as [start, end] character ranges.
        readonly property var tokenRanges: {
            const out = []
            if (root.tokenPattern === "")
                return out
            const re = new RegExp(root.tokenPattern, "g")
            for (let m = re.exec(text); m !== null; m = re.exec(text)) {
                // A pattern that can match nothing would spin here forever.
                if (m[0].length === 0) { re.lastIndex++; continue }
                out.push([m.index, m.index + m[0].length])
            }
            return out
        }
        // Pixels of blank before token `i`. Outside the list it is the field's
        // own inset, which is always wider than a pill's padding.
        function tokenGap(i) {
            const r = tokenRanges
            if (i <= 0 || i >= r.length)
                return 2 * pillBox.padX
            return positionToRectangle(r[i][0]).x - positionToRectangle(r[i - 1][1]).x
        }

        // Bumped by everything that can move a token's pixels. The text is the
        // obvious one; the horizontal scroll is the other, and a TextInput only
        // exposes it through the caret's rectangle.
        property int tokenRev: 0
        onTextChanged: tokenRev++
        onCursorRectangleChanged: tokenRev++
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
