// AudioPanel - master volume slider with icon and percentage readout.

import QtQuick
import Quickshell.Io
import "../../../components"
import "../../../services"

Column {
    id: root

    spacing: 8

    property real volumeValue: 0.5

    // Refresh volume from wpctl on show
    function refresh() { volumeQuery.running = true }

    Process {
        id: volumeQuery
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const match = data.match(/Volume:\s+([\d.]+)/)
                if (match) root.volumeValue = parseFloat(match[1])
            }
        }
    }

    Row {
        width: parent.width
        spacing: 8

        Text {
            text:           root.volumeValue <= 0 ? "󰸈" : root.volumeValue < 0.5 ? "󰖀" : "󰕾"
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            color:          Colors.subtext0
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text:           I18n.t("controlcenter.volume")
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color:          Colors.text
            anchors.verticalCenter: parent.verticalCenter
        }

        Item { Layout.fillWidth: true; width: 1 }

        Text {
            text:           Math.round(root.volumeValue * 100) + "%"
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color:          Colors.subtext0
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Slider {
        width:  parent.width
        value:  root.volumeValue
        onMoved: val => {
            root.volumeValue = val
            Process {
                command: ["wpctl", "set-volume", "-l", "1.5",
                          "@DEFAULT_AUDIO_SINK@", (Math.round(val * 100)) + "%"]
                running: true
            }
        }
    }
}
