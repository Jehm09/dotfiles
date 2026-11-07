import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Paquetes por actualizar (repos + AUR) o reinicio pendiente. Click: Settings → Update.
MouseArea {
    id: root
    readonly property int count: SystemUpdates.count
    readonly property bool strong: count > Config.options.updates.stronglyAdviseUpdateThreshold
    readonly property color colContent: strong ? Appearance.colors.colError : Appearance.colors.colOnLayer0

    visible: count > 0 || SystemUpdates.rebootNeeded || SystemUpdates.running
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    // Sin aceptar el evento, el MouseArea del lado derecho de la barra abre el sidebar.
    onPressed: event => {
        QsLaunch.openSettings("UpdateConfig");
        event.accepted = true;
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2
        opacity: root.containsMouse ? 0.7 : 1

        MaterialSymbol {
            text: SystemUpdates.running ? "downloading" : root.count > 0 ? "system_update_alt" : "restart_alt"
            iconSize: Appearance.font.pixelSize.larger
            color: root.colContent
        }
        StyledText {
            visible: root.count > 0
            text: root.count
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colContent
        }
    }

    PopupToolTip {
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
        text: [
            SystemUpdates.running ? Translation.tr("System update running") : "",
            root.count > 0 ? Translation.tr("%1 update(s): %2 from the repos, %3 from the AUR")
                .arg(root.count).arg(SystemUpdates.repoPackages.length).arg(SystemUpdates.aurPackages.length) : "",
            SystemUpdates.rebootNeeded ? Translation.tr("Reboot to finish the last update") : "",
            SystemUpdates.news.length > 0 ? Translation.tr("Unread Arch news") : ""
        ].filter(line => line).join("\n")
    }
}
