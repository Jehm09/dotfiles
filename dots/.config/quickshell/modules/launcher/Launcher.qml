// Launcher - full-screen overlay with tabbed search.
// Tabs: Apps | Clipboard | Emoji | Calculator | Web Search
// Toggle via IPC: qs ipc call toggleLauncher
// Dismiss: Escape or click outside.

import QtQuick
import Quickshell
import "./tabs"
import "../../components"
import "../../services"

PanelWindow {
    id: launcher

    property bool isOpen: false

    // Expose a flat surface that covers the screen (but let IPC control visibility)
    anchors { top: true; bottom: true; left: true; right: true }
    color:  "transparent"
    exclusiveZone: -1       // don't push other windows

    visible: isOpen

    // Scrim / background blur
    Rectangle {
        anchors.fill: parent
        color:        Colors.scrim

        opacity:      launcher.isOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked:    launcher.isOpen = false
        }
    }

    // Main panel - centered, fixed width from config
    Rectangle {
        id:      panel
        anchors.centerIn: parent
        width:   Config.launcher.width
        height:  Math.min(600, implicitHeight)
        radius:  Config.theme.borderRadius
        color:   Colors.panel
        border.color: Colors.surface1
        border.width: Config.theme.borderWidth

        scale:   launcher.isOpen ? 1.0 : 0.95
        opacity: launcher.isOpen ? 1.0 : 0.0
        Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 12

            // Search input
            SearchInput {
                id:          searchInput
                width:       parent.width
                placeholder: I18n.t("launcher.placeholder")
                focus:       launcher.isOpen

                onTextChanged: text => { tabContent.query = text }
                onAccepted:    tabContent.currentTab === 4 && webSearchTab.doSearch()
            }

            // Tab bar
            Row {
                spacing: 4

                Repeater {
                    model: [
                        I18n.t("launcher.tabs.apps"),
                        I18n.t("launcher.tabs.clipboard"),
                        I18n.t("launcher.tabs.emoji"),
                        I18n.t("launcher.tabs.calculator"),
                        I18n.t("launcher.tabs.websearch")
                    ]

                    delegate: Rectangle {
                        required property string modelData
                        required property int    index

                        readonly property bool active: tabContent.currentTab === index

                        width:  implicitWidth + 20
                        height: 28
                        radius: 14
                        color:  active ? Colors.accent : Colors.surface0

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text:       modelData
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize - 1
                            color:      active ? Colors.base : Colors.subtext0
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    tabContent.currentTab = index
                        }
                    }
                }
            }

            // Tab content area
            Item {
                id:     tabContent
                width:  parent.width
                height: 380

                property int    currentTab: 0
                property string query:      ""

                AppsTab      { anchors.fill: parent; visible: tabContent.currentTab === 0; query: tabContent.query }
                ClipboardTab { anchors.fill: parent; visible: tabContent.currentTab === 1; query: tabContent.query }
                EmojiTab     { anchors.fill: parent; visible: tabContent.currentTab === 2; query: tabContent.query }
                CalculatorTab{ anchors.fill: parent; visible: tabContent.currentTab === 3; query: tabContent.query }
                WebSearchTab {
                    id:          webSearchTab
                    anchors.fill: parent
                    visible:     tabContent.currentTab === 4
                    query:       tabContent.query
                }
            }
        }

        // Keyboard handling
        Keys.onEscapePressed: {
            if (searchInput.text.length > 0) {
                searchInput.text = ""
            } else {
                launcher.isOpen = false
            }
        }

        Keys.onTabPressed: {
            tabContent.currentTab = (tabContent.currentTab + 1) % 5
        }
    }

    // Reset state when closed
    onIsOpenChanged: {
        if (!isOpen) {
            searchInput.text        = ""
            tabContent.query        = ""
            tabContent.currentTab   = 0
        } else {
            searchInput.focus = true
        }
    }
}
