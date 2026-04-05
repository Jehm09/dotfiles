// AppsTab - fuzzy app search using DesktopEntries.

import QtQuick
import Quickshell
import "../../../services"

Item {
    id: root

    property string query: ""

    // Simple fuzzy match: all chars of needle appear in order in haystack
    function fuzzyMatch(haystack, needle) {
        if (needle.length === 0) return true
        const h = haystack.toLowerCase()
        const n = needle.toLowerCase()
        let hi = 0
        for (let ni = 0; ni < n.length; ni++) {
            hi = h.indexOf(n[ni], hi)
            if (hi === -1) return false
            hi++
        }
        return true
    }

    ListView {
        id:           list
        anchors.fill: parent
        clip:         true
        spacing:      4

        model: DesktopEntries.applications.filter(app =>
            !app.noDisplay && fuzzyMatch(app.name + " " + (app.genericName ?? ""), root.query)
        ).slice(0, Config.launcher.maxResults)

        delegate: Rectangle {
            required property var modelData

            width:  list.width
            height: 52
            radius: Config.theme.borderRadius
            color:  hoverArea.containsMouse ? Colors.accentSubtle : Colors.surface0

            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 12

                // App icon
                Image {
                    width:        32
                    height:       32
                    source:       modelData.icon ? "image://icon/" + modelData.icon : ""
                    fillMode:     Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter

                    // Fallback text icon
                    Text {
                        anchors.centerIn: parent
                        visible:         parent.status !== Image.Ready
                        text:            "󰘔"
                        font.family:     "JetBrainsMono Nerd Font"
                        font.pixelSize:  22
                        color:           Colors.subtext0
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text:           modelData.name
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        color:          Colors.text
                    }

                    Text {
                        visible:        modelData.comment?.length > 0
                        text:           modelData.comment ?? ""
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize - 2
                        color:          Colors.subtext0
                    }
                }
            }

            MouseArea {
                id:           hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    modelData.launch()
                    launcher.isOpen = false
                }
            }
        }
    }
}
