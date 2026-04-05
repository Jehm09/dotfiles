pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

// SettingsPanel — scrollable content for the settings drawer.
//
// All changes write through to Config immediately (Config's debounce
// coalesces rapid edits before flushing to disk).
//
Item {
    id: root

    // -----------------------------------------------------------------------
    // Inline reusable primitives — no external component library required.
    // -----------------------------------------------------------------------

    // Section card wrapping a group of rows.
    component SectionCard: Rectangle {
        id: card

        default property alias content: col.data
        required property string title

        Layout.fillWidth: true
        implicitHeight: cardHeader.height + col.implicitHeight + 12
        radius: 12
        color: Colors.surfaceContainer

        // Section title bar
        Rectangle {
            id: cardHeader
            width: parent.width
            height: 38
            radius: parent.radius
            color: Colors.surfaceContainerHigh

            // Square off bottom corners of the header
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.radius
                color: parent.color
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                text: card.title
                color: Colors.primary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
        }

        ColumnLayout {
            id: col
            anchors.top: cardHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.bottomMargin: 8
            anchors.margins: 4
            spacing: 2
        }
    }

    // Label + switch row.
    component SwitchRow: Rectangle {
        id: sr

        required property string label
        property bool checked: false
        signal toggled(bool value)

        Layout.fillWidth: true
        height: 44
        radius: 8
        color: "transparent"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: sr.label
            color: Colors.onSurface
            font.pixelSize: 14
        }

        // Pill toggle
        Rectangle {
            id: pill
            width: 48
            height: 26
            radius: 13
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: sr.checked ? Colors.primary : Colors.surfaceVariant

            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                id: thumb
                width: 20
                height: 20
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                x: sr.checked ? parent.width - width - 3 : 3
                color: sr.checked ? Colors.onPrimary : Colors.outline

                Behavior on x     { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation  { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sr.toggled(!sr.checked)
            }
        }
    }

    // Label + integer spinbox row.
    component NumberRow: Rectangle {
        id: nr

        required property string label
        property int value: 0
        property int from: 0
        property int to: 9999
        property int stepSize: 1
        property string suffix: ""
        signal valueModified(int value)

        Layout.fillWidth: true
        height: 44
        color: "transparent"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: nr.label
            color: Colors.onSurface
            font.pixelSize: 14
        }

        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // Minus button
            Rectangle {
                width: 28; height: 28; radius: 6
                color: Colors.surfaceContainerHigh
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Colors.onSurface
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const next = Math.max(nr.from, nr.value - nr.stepSize)
                        if (next !== nr.value) nr.valueModified(next)
                    }
                }
            }

            // Value display
            Rectangle {
                implicitWidth: valueText.implicitWidth + 16
                height: 28; radius: 6
                color: Colors.surfaceContainerLowest
                Text {
                    id: valueText
                    anchors.centerIn: parent
                    text: nr.value + (nr.suffix ? " " + nr.suffix : "")
                    color: Colors.onSurface
                    font.pixelSize: 13
                    font.monospacedDigits: true
                }
            }

            // Plus button
            Rectangle {
                width: 28; height: 28; radius: 6
                color: Colors.surfaceContainerHigh
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Colors.onSurface
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const next = Math.min(nr.to, nr.value + nr.stepSize)
                        if (next !== nr.value) nr.valueModified(next)
                    }
                }
            }
        }
    }

    // Label + single-line text input row.
    component TextRow: Rectangle {
        id: tr

        required property string label
        property string value: ""
        property string placeholder: ""
        signal committed(string value)

        Layout.fillWidth: true
        height: 44
        color: "transparent"

        Text {
            id: trLabel
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: tr.label
            color: Colors.onSurface
            font.pixelSize: 14
        }

        Rectangle {
            anchors.left: trLabel.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            radius: 6
            color: Colors.surfaceContainerLowest
            border.color: textInput.activeFocus ? Colors.primary : "transparent"
            border.width: 1.5

            Behavior on border.color { ColorAnimation { duration: 120 } }

            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.margins: 8
                text: tr.value
                color: Colors.onSurface
                font.pixelSize: 13
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                Keys.onReturnPressed: tr.committed(text)
                Keys.onTabPressed:    tr.committed(text)
                onActiveFocusChanged: if (!activeFocus) tr.committed(text)
            }

            // Placeholder
            Text {
                anchors.fill: parent
                anchors.margins: 8
                text: tr.placeholder
                color: Colors.onSurfaceVariant
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                visible: textInput.text.length === 0 && !textInput.activeFocus
            }
        }
    }

    // -----------------------------------------------------------------------
    // Panel layout
    // -----------------------------------------------------------------------

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentCol.implicitHeight + 24
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: Colors.outline
                opacity: parent.active ? 0.8 : 0.3
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }

        ColumnLayout {
            id: contentCol
            width: flickable.width
            spacing: 10

            // Top padding
            Item { height: 8 }

            // ── Appearance ──────────────────────────────────────────────
            SectionCard {
                title: I18n.s("settings.appearance.title").toUpperCase()

                SwitchRow {
                    label: I18n.s("settings.appearance.darkMode")
                    checked: Config.ready ? Config.appearance.dark : true
                    onToggled: value => { Config.appearance.dark = value }
                }

                TextRow {
                    label: I18n.s("settings.appearance.wallpaper")
                    value: Config.ready ? Config.appearance.wallpaper : ""
                    placeholder: I18n.s("settings.appearance.wallpaperPlaceholder")
                    onCommitted: path => { if (path) Wallpaper.set(path) }
                }

                TextRow {
                    label: I18n.s("settings.appearance.profilePicture")
                    value: Config.ready ? Config.profile.picture : ""
                    placeholder: I18n.s("settings.appearance.profilePicturePlaceholder")
                    onCommitted: path => { Config.profile.picture = path }
                }
            }

            // ── Bar ─────────────────────────────────────────────────────
            SectionCard {
                title: I18n.s("settings.bar.title").toUpperCase()

                NumberRow {
                    label: I18n.s("settings.bar.height")
                    value: Config.ready ? Config.bar.height : 36
                    from: 24; to: 72; stepSize: 2; suffix: "px"
                    onValueModified: v => { Config.bar.height = v }
                }

                SwitchRow {
                    label: I18n.s("settings.bar.showWorkspaces")
                    checked: Config.ready ? Config.bar.workspaces.show : true
                    onToggled: v => { Config.bar.workspaces.show = v }
                }

                NumberRow {
                    label: I18n.s("settings.bar.workspacesCount")
                    value: Config.ready ? Config.bar.workspaces.count : 10
                    from: 1; to: 20; stepSize: 1
                    onValueModified: v => { Config.bar.workspaces.count = v }
                }

                SwitchRow {
                    label: I18n.s("settings.bar.showClock")
                    checked: Config.ready ? Config.bar.clock.show : true
                    onToggled: v => { Config.bar.clock.show = v }
                }

                TextRow {
                    label: I18n.s("settings.bar.clockFormat")
                    value: Config.ready ? Config.bar.clock.format : "HH:mm"
                    placeholder: "HH:mm"
                    onCommitted: v => { if (v) Config.bar.clock.format = v }
                }

                SwitchRow {
                    label: I18n.s("settings.bar.showSystray")
                    checked: Config.ready ? Config.bar.systray.show : true
                    onToggled: v => { Config.bar.systray.show = v }
                }

                SwitchRow {
                    label: I18n.s("settings.bar.showBattery")
                    checked: Config.ready ? Config.bar.battery.show : true
                    onToggled: v => { Config.bar.battery.show = v }
                }
            }

            // ── Launcher ────────────────────────────────────────────────
            SectionCard {
                title: I18n.s("settings.launcher.title").toUpperCase()

                NumberRow {
                    label: I18n.s("settings.launcher.width")
                    value: Config.ready ? Config.launcher.width : 680
                    from: 320; to: 1200; stepSize: 20; suffix: "px"
                    onValueModified: v => { Config.launcher.width = v }
                }
            }

            // ── OSD ─────────────────────────────────────────────────────
            SectionCard {
                title: I18n.s("settings.osd.title").toUpperCase()

                NumberRow {
                    label: I18n.s("settings.osd.timeout")
                    value: Config.ready ? Config.osd.timeout : 2000
                    from: 500; to: 10000; stepSize: 250; suffix: "ms"
                    onValueModified: v => { Config.osd.timeout = v }
                }
            }

            // Bottom padding
            Item { height: 16 }
        }
    }
}
