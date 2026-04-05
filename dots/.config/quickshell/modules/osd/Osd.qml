// OSD - on-screen display for volume and brightness changes.
// Appears as a small centered pill, auto-hides after 1.5 seconds.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../services"

PanelWindow {
    id: root

    anchors { bottom: true; left: true; right: true }
    height: 60
    color:  "transparent"
    exclusiveZone: 0

    property real  osdValue:  0.0    // 0.0 - 1.0
    property string osdIcon:  "󰕾"
    property string osdLabel: I18n.t("osd.volume")
    property bool   visible_: false

    Timer {
        id:      hideTimer
        interval: 1500
        onTriggered: root.visible_ = false
    }

    // Called externally to show the OSD (e.g. from a keybind helper or media keys)
    function showVolume(value) {
        osdValue  = value / 100
        osdIcon   = value <= 0 ? "󰸈" : value < 50 ? "󰖀" : "󰕾"
        osdLabel  = value <= 0 ? I18n.t("osd.muted") : I18n.t("osd.volume")
        visible_  = true
        hideTimer.restart()
    }

    function showBrightness(value) {
        osdValue  = value / 100
        osdIcon   = "󰃟"
        osdLabel  = I18n.t("osd.brightness")
        visible_  = true
        hideTimer.restart()
    }

    // Pill display
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     80
        width:   300
        height:  52
        radius:  26
        color:   Colors.panel
        border.color: Colors.surface1
        border.width: Config.theme.borderWidth

        opacity: root.visible_ ? 1.0 : 0.0
        scale:   root.visible_ ? 1.0 : 0.9
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text:           root.osdIcon
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                color:          Colors.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            // Progress bar
            Rectangle {
                width:  160
                height: 6
                radius: 3
                color:  Colors.surface1
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width:  Math.max(parent.radius, root.osdValue * parent.width)
                    height: parent.height
                    radius: parent.radius
                    color:  Colors.accent
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }

            Text {
                text:           Math.round(root.osdValue * 100) + "%"
                font.family:    Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color:          Colors.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Watch for volume changes (poll wpctl every 200ms when active)
    Timer {
        interval: 200
        running:  true
        repeat:   true
        onTriggered: volCheck.running = true
    }

    property real _lastVol: -1
    Process {
        id: volCheck
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                const match = data.match(/Volume:\s+([\d.]+)/)
                if (match) {
                    const vol = Math.round(parseFloat(match[1]) * 100)
                    if (root._lastVol >= 0 && vol !== root._lastVol) root.showVolume(vol)
                    root._lastVol = vol
                }
            }
        }
    }
}
