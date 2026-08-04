import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.ItemDelegate {
    id: item

    Layout.fillWidth: true

    property alias iconItem: iconItem.children

    highlighted: activeFocus

    Accessible.name: `${text}`

    onHoveredChanged: if (hovered) {
        if (ListView.view) {
            ListView.view.currentIndex = index;
        }
        forceActiveFocus();
    }

    contentItem: RowLayout {
        id: row

        spacing: Kirigami.Units.smallSpacing

        Item {
            id: iconItem

            Layout.preferredWidth: 1.6 * Kirigami.Units.iconSizes.small
            Layout.preferredHeight: 1.6 * Kirigami.Units.iconSizes.small
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.minimumHeight: Layout.preferredHeight
            Layout.maximumHeight: Layout.preferredHeight
        }

        ColumnLayout {
            id: column
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents.Label {
                id: label
                Layout.fillWidth: true
                text: item.text
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
