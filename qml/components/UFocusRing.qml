import QtQuick
import Unisic.Kit

// The ONE keyboard-focus indicator for the whole design system: a 2 px accent
// outline around the host, drawn INSIDE its own bounds by default. It never
// reflows anything: a Row/Flow reads the host's width/height, and the ring is a
// plain non-layout child.
//
// THE INSET RULE. This is the only place it is stated - a call site that passes
// a negative inset points at this comment instead of re-arguing the case:
//
//   * inset >= 0 for every host that has neighbours: a strip, a grid, a
//     toolbar, a list, a row of swatches. The toolbars pack 40x40 chips at
//     4-5 px spacing, so a ring drawn outside one would sit over the chip next
//     door and read as belonging to it. The default 2 also keeps the ring clear
//     of the host's own 1 px border so both stay readable; 0 draws it right on
//     the edge, for a host whose bounds already are the visible shape.
//   * inset < 0 (an OUTSET ring) for exactly one shape of host: a standalone
//     text link, whose Item bounds hug the glyphs - an inset ring there would
//     strike through the very text it is pointing at. Standalone is part of the
//     rule, not a footnote: nothing packed within |inset| px, and nothing
//     clipping it, since clip:true on the host or on a Flickable above it just
//     cuts the ring off. Anything that is not a lone text link keeps inset >= 0.
//     This is a review rule and nothing checks it at runtime: the clipping-host
//     case did warn from Component.onCompleted, but the ring ships in every
//     build, so that console.warn fired at users on a release build for a
//     mistake only a developer can make - and can read here.
//
// It carries no input and no accessible identity of its own; the host owns
// both. Drop one into any focusable component:
//
//     UFocusRing { }                       // host is the QML parent
//     UFocusRing { hostRadius: 12 }        // explicit when the host is an Item
//     UFocusRing { inset: -3 }             // standalone text link, per the rule
//
Rectangle {
    id: ring

    // The focusable item the ring reports for. `var` (not Item) so the radius /
    // activeFocus lookups stay dynamic - hosts are Rectangles, Items and even
    // plain halves of a split control.
    property var host: parent
    // How far in from the host's edge; negative pushes the ring outside. Which
    // value a host may use is THE INSET RULE in the header above.
    property real inset: 2
    // Corner radius of the host. Auto-read from a Rectangle host; set it by
    // hand when the host is a bare Item (USlider) or when the visible shape is
    // smaller than the hit area.
    property real hostRadius: (host && host.radius !== undefined) ? host.radius : 0

    anchors.fill: parent
    anchors.margins: inset
    // Above the host's own content (icon/label), below any popup.
    z: 100
    // Faded, not toggled, and the same idiom as UHoverTip: `visible` follows
    // the animated opacity so the ring is a real scene-graph node only while it
    // is on screen, and the fade still runs both ways.
    opacity: (host && host.activeFocus === true) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    color: "transparent"
    border.width: Theme.focusRingWidth
    border.color: Theme.focusRing
    // Concentric with the host: shrinking the radius by the inset keeps the
    // corners parallel instead of pinching.
    radius: Math.max(0, hostRadius - inset)

    // Never intercepts a click and never shows up in the accessibility tree -
    // the ring is pure decoration for the control that owns it.
    enabled: false
    Accessible.ignored: true
}
