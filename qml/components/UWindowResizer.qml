import QtQuick

// Edge and corner resize zones for a FRAMELESS window. A window without
// system decoration has no compositor-drawn border, so nothing answers the
// pointer at its edges: no resize cursor, no drag. This fills the window with
// eight thin MouseAreas (four edges, four corners) that show the right resize
// cursor and hand the drag to the compositor via startSystemResize - the same
// interactive resize a decorated window gets, on Wayland and X11 alike.
//
// Usage: last child of the window's content (so it sits above everything),
// `active` bound to the frameless state. The zones live only in the outer
// `border` px, so page content keeps its clicks; the top band overlaps the
// first pixels of a custom title bar on purpose - resize beats move there,
// exactly like a decorated window behaves.
Item {
    id: root
    anchors.fill: parent
    z: 1000

    property bool active: true
    property int border: 7
    property int cornerSize: 14

    // Resolved by the enclosing QML Window; resizing a maximized or
    // fullscreen window makes no sense and decorated windows resize
    // themselves.
    readonly property var _win: Window.window
    readonly property bool _on: active && _win !== null
                                && _win.visibility !== Window.Maximized
                                && _win.visibility !== Window.FullScreen

    component ResizeZone: MouseArea {
        property int edges
        visible: root._on
        acceptedButtons: Qt.LeftButton
        onPressed: root._win.startSystemResize(edges)
    }

    ResizeZone { // left
        edges: Qt.LeftEdge
        cursorShape: Qt.SizeHorCursor
        x: 0; y: root.cornerSize
        width: root.border; height: parent.height - 2 * root.cornerSize
    }
    ResizeZone { // right
        edges: Qt.RightEdge
        cursorShape: Qt.SizeHorCursor
        x: parent.width - root.border; y: root.cornerSize
        width: root.border; height: parent.height - 2 * root.cornerSize
    }
    ResizeZone { // top
        edges: Qt.TopEdge
        cursorShape: Qt.SizeVerCursor
        x: root.cornerSize; y: 0
        width: parent.width - 2 * root.cornerSize; height: root.border
    }
    ResizeZone { // bottom
        edges: Qt.BottomEdge
        cursorShape: Qt.SizeVerCursor
        x: root.cornerSize; y: parent.height - root.border
        width: parent.width - 2 * root.cornerSize; height: root.border
    }
    ResizeZone { // top-left
        edges: Qt.TopEdge | Qt.LeftEdge
        cursorShape: Qt.SizeFDiagCursor
        x: 0; y: 0
        width: root.cornerSize; height: root.cornerSize
    }
    ResizeZone { // top-right
        edges: Qt.TopEdge | Qt.RightEdge
        cursorShape: Qt.SizeBDiagCursor
        x: parent.width - root.cornerSize; y: 0
        width: root.cornerSize; height: root.cornerSize
    }
    ResizeZone { // bottom-left
        edges: Qt.BottomEdge | Qt.LeftEdge
        cursorShape: Qt.SizeBDiagCursor
        x: 0; y: parent.height - root.cornerSize
        width: root.cornerSize; height: root.cornerSize
    }
    ResizeZone { // bottom-right
        edges: Qt.BottomEdge | Qt.RightEdge
        cursorShape: Qt.SizeFDiagCursor
        x: parent.width - root.cornerSize; y: parent.height - root.cornerSize
        width: root.cornerSize; height: root.cornerSize
    }
}
