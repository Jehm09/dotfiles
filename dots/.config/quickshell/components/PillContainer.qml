// PillContainer - reusable pill-shaped panel segment.
// Used for bar segments, buttons, and any rounded card element.

import QtQuick
import "../services"

Rectangle {
    id: root

    property bool elevated: false  // slightly lighter surface when elevated

    implicitHeight: 32
    implicitWidth:  childrenRect.width + paddingH * 2

    property real paddingH: 10
    property real paddingV: 6

    color:  elevated ? Colors.surface1 : Colors.panelVariant
    radius: height / 2

    layer.enabled: true
    layer.effect: null   // can be overridden with a blur effect if needed

    Behavior on color { ColorAnimation { duration: 150 } }
}
