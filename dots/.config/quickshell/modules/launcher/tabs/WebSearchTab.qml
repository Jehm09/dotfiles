// WebSearchTab - press Enter to search the web with the current query.

import QtQuick
import Quickshell.Io
import "../../../services"

Item {
    id: root

    property string query: ""

    function doSearch() {
        if (query.trim().length === 0) return
        const encoded = encodeURIComponent(query)
        Process {
            command: ["xdg-open", "https://www.google.com/search?q=" + encoded]
            running: true
        }
        launcher.isOpen = false
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 12

        // Search preview card
        Rectangle {
            width:  parent.width
            height: 64
            radius: Config.theme.borderRadius
            color:  hoverArea.containsMouse ? Colors.accentSubtle : Colors.surface0
            visible: root.query.length > 0

            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 12

                Text {
                    text:           "󰖟"
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                    color:          Colors.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text:           I18n.t("launcher.tabs.websearch")
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize - 1
                        color:          Colors.subtext0
                    }

                    Text {
                        text:           root.query
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        color:          Colors.text
                    }
                }
            }

            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text:           "↵"
                font.pixelSize: 18
                color:          Colors.subtext0
            }

            MouseArea {
                id:           hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:    root.doSearch()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.query.length === 0
            text:    I18n.t("launcher.websearchHint")
            color:   Colors.overlay0
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize
        }
    }

    // Also trigger on Enter from the search field (forwarded from Launcher)
    Keys.onReturnPressed: doSearch()
}
