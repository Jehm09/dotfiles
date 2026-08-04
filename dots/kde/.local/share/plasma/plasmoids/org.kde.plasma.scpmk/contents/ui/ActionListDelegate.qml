import QtQuick
import org.kde.kirigami as Kirigami

ListDelegate {
    id: item

    activeFocusOnTab: true

    iconItem: Kirigami.Icon {
        anchors.fill: parent
        source: item.icon.name
    }
}
