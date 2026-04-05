// SearchInput - styled text input for the launcher search bar.

import QtQuick
import "../services"

FocusScope {
    id: root

    property alias text:        field.text
    property string placeholder: ""
    signal accepted()
    signal textChanged(string text)

    implicitHeight: 44
    implicitWidth:  400

    Rectangle {
        anchors.fill:  parent
        color:         Colors.surface0
        radius:        height / 2
        border.color:  field.activeFocus ? Colors.accent : Colors.surface1
        border.width:  Config.theme.borderWidth

        Behavior on border.color { ColorAnimation { duration: 150 } }

        // Search icon
        Text {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text:           ""
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color:          field.activeFocus ? Colors.accent : Colors.overlay1
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        TextInput {
            id:             field
            anchors {
                left:   parent.left; leftMargin:  40
                right:  parent.right; rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            color:          Colors.text
            selectionColor: Colors.accentSubtle
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize + 1
            clip:           true
            focus:          true

            onTextChanged:  root.textChanged(text)
            Keys.onReturnPressed: root.accepted()
            Keys.onEscapePressed: { text = ""; }
        }

        // Placeholder text
        Text {
            anchors {
                left:   field.left
                verticalCenter: parent.verticalCenter
            }
            text:           root.placeholder
            color:          Colors.overlay0
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize + 1
            visible:        field.text.length === 0
        }
    }
}
