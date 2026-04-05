// EmojiTab - browse and copy emojis. Filtered by name search.

import QtQuick
import Quickshell.Io
import "../../../services"

Item {
    id: root

    property string query: ""

    // Curated emoji set with names for searching
    readonly property var emojis: [
        {e:"😀",n:"grinning face"},{e:"😂",n:"face with tears of joy"},{e:"🥲",n:"smiling face with tear"},
        {e:"😍",n:"smiling face with heart-eyes"},{e:"🤔",n:"thinking face"},{e:"😎",n:"smiling face with sunglasses"},
        {e:"😭",n:"loudly crying face"},{e:"🥹",n:"face holding back tears"},{e:"😤",n:"face with steam"},
        {e:"🤯",n:"exploding head"},{e:"🥳",n:"partying face"},{e:"😴",n:"sleeping face"},
        {e:"👍",n:"thumbs up"},{e:"👎",n:"thumbs down"},{e:"👏",n:"clapping hands"},
        {e:"🙌",n:"raising hands"},{e:"🤝",n:"handshake"},{e:"✌️",n:"victory hand"},
        {e:"❤️",n:"red heart"},{e:"🧡",n:"orange heart"},{e:"💛",n:"yellow heart"},
        {e:"💚",n:"green heart"},{e:"💙",n:"blue heart"},{e:"💜",n:"purple heart"},
        {e:"🔥",n:"fire"},{e:"⭐",n:"star"},{e:"✨",n:"sparkles"},
        {e:"🎉",n:"party popper"},{e:"🎊",n:"confetti ball"},{e:"🎁",n:"gift"},
        {e:"🚀",n:"rocket"},{e:"🌈",n:"rainbow"},{e:"⚡",n:"lightning"},
        {e:"🐱",n:"cat face"},{e:"🐶",n:"dog face"},{e:"🦊",n:"fox"},
        {e:"🌸",n:"cherry blossom"},{e:"🍕",n:"pizza"},{e:"☕",n:"coffee"},
        {e:"💻",n:"laptop computer"},{e:"📱",n:"mobile phone"},{e:"🎮",n:"video game"},
        {e:"📝",n:"memo"},{e:"🔑",n:"key"},{e:"🏠",n:"house"},
        {e:"💡",n:"light bulb"},{e:"🔧",n:"wrench"},{e:"📦",n:"package"}
    ]

    readonly property var filtered: emojis.filter(item =>
        root.query.length === 0 || item.n.includes(root.query.toLowerCase())
    )

    GridView {
        anchors.fill: parent
        clip:         true
        cellWidth:    52
        cellHeight:   52

        model: root.filtered

        delegate: Rectangle {
            required property var modelData

            width:  48
            height: 48
            radius: 8
            color:  hoverArea.containsMouse ? Colors.accentSubtle : "transparent"

            Behavior on color { ColorAnimation { duration: 80 } }

            Text {
                anchors.centerIn: parent
                text:           modelData.e
                font.pixelSize: 24
            }

            MouseArea {
                id:           hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    Process {
                        command: ["bash", "-c", `echo -n ${JSON.stringify(modelData.e)} | wl-copy`]
                        running: true
                    }
                    launcher.isOpen = false
                }
            }
        }
    }
}
