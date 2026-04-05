// Slider - styled horizontal slider for volume and brightness controls.

import QtQuick
import "../services"

Item {
    id: root

    property real  value:    0.5       // 0.0 to 1.0
    property real  minimum:  0.0
    property real  maximum:  1.0
    property bool  enabled:  true
    signal moved(real value)

    implicitHeight: 20
    implicitWidth:  200

    // Track background
    Rectangle {
        id:           track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height:       4
        radius:       2
        color:        Colors.surface1

        // Filled portion
        Rectangle {
            width:  Math.max(parent.radius, (root.value - root.minimum) / (root.maximum - root.minimum) * track.width)
            height: parent.height
            radius: parent.radius
            color:  Colors.accent
            Behavior on width { NumberAnimation { duration: 80 } }
        }
    }

    // Thumb
    Rectangle {
        id:     thumb
        width:  16
        height: 16
        radius: 8
        color:  Colors.text
        x:      (root.value - root.minimum) / (root.maximum - root.minimum) * (track.width - width)
        anchors.verticalCenter: parent.verticalCenter
        Behavior on x { NumberAnimation { duration: 80 } }

        scale: dragArea.containsMouse ? 1.2 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id:           dragArea
        anchors.fill: parent
        hoverEnabled: true
        enabled:      root.enabled

        function updateValue(mouseX) {
            const clamped = Math.max(0, Math.min(mouseX, track.width))
            const ratio   = clamped / track.width
            root.value    = root.minimum + ratio * (root.maximum - root.minimum)
            root.moved(root.value)
        }

        onPressed:      updateValue(mouseX)
        onPositionChanged: if (pressed) updateValue(mouseX)
    }
}
