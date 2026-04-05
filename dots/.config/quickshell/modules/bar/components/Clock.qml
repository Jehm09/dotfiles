// Clock - shows current time in the bar center.
// Format is read from Config.bar.clockFormat.

import QtQuick
import Quickshell
import "../../../components"
import "../../../services"

PillContainer {
    id: root

    paddingH: 12

    Text {
        anchors.centerIn: parent
        text:       Qt.formatTime(new Date(), Config.bar.clockFormat)
        color:      Colors.text
        font.family: Config.theme.font
        font.pixelSize: Config.theme.fontSize
        font.weight: Font.Medium

        Timer {
            interval:  1000
            running:   true
            repeat:    true
            onTriggered: parent.text = Qt.formatTime(new Date(), Config.bar.clockFormat)
        }
    }
}
