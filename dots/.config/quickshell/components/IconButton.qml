// IconButton - clickable icon with hover highlight and press animation.

import QtQuick
import "../services"

Rectangle {
    id: root

    property string iconName: ""
    property real   iconSize: 16
    property color  iconColor: Colors.subtext0
    property color  hoverColor: Colors.accentSubtle
    signal clicked()

    implicitWidth:  32
    implicitHeight: 32
    radius:         height / 2
    color:          hoverArea.containsMouse ? hoverColor : "transparent"

    Behavior on color { ColorAnimation { duration: 100 } }

    scale: hoverArea.pressed ? 0.9 : 1.0
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutBack } }

    Text {
        anchors.centerIn: parent
        text:             root.iconName
        font.family:      "JetBrainsMono Nerd Font"
        font.pixelSize:   root.iconSize
        color:            hoverArea.containsMouse ? Colors.accent : root.iconColor
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    MouseArea {
        id:           hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    root.clicked()
    }
}
