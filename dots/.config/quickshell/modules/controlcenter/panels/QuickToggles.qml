// QuickToggles - row of toggle buttons (Wi-Fi, Bluetooth, Mute, DnD).

import QtQuick
import Quickshell
import Quickshell.Io
import "../../../components"
import "../../../services"

Row {
    id: root

    spacing: 8

    property bool dndEnabled: false

    // Generic toggle pill button
    component TogglePill: Rectangle {
        required property string icon
        required property string label
        required property bool   active
        signal toggled()

        width:  72
        height: 64
        radius: Config.theme.borderRadius
        color:  active ? Colors.accentSubtle : Colors.surface0

        Behavior on color { ColorAnimation { duration: 150 } }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           icon
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                color:          active ? Colors.accent : Colors.subtext0
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           label
                font.family:    Config.theme.font
                font.pixelSize: 10
                color:          active ? Colors.accent : Colors.subtext0
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape:  Qt.PointingHandCursor
            onClicked:    parent.toggled()
        }
    }

    // Wi-Fi toggle
    TogglePill {
        id:     wifiToggle
        icon:   active ? "󰤨" : "󰤭"
        label:  I18n.t("controlcenter.wifi")
        active: true

        onToggled: {
            active = !active
            Process { command: ["nmcli", "radio", "wifi", active ? "on" : "off"]; running: true }
        }
    }

    // Bluetooth toggle
    TogglePill {
        id:     btToggle
        icon:   active ? "󰂯" : "󰂲"
        label:  I18n.t("controlcenter.bluetooth")
        active: false

        onToggled: {
            active = !active
            Process {
                command: ["bash", "-c", active ? "bluetoothctl power on" : "bluetoothctl power off"]
                running: true
            }
        }
    }

    // Mute toggle
    TogglePill {
        id:     muteToggle
        icon:   active ? "󰸈" : "󰕾"
        label:  I18n.t("controlcenter.mute")
        active: false

        onToggled: {
            active = !active
            Process { command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]; running: true }
        }
    }

    // Do Not Disturb
    TogglePill {
        icon:   root.dndEnabled ? "󰂛" : "󰂚"
        label:  I18n.t("controlcenter.doNotDisturb")
        active: root.dndEnabled

        onToggled: root.dndEnabled = !root.dndEnabled
    }
}
