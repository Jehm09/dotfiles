import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    // Per-monitor: used only as fallback when no app is focused
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    readonly property var workspaceId: root.monitorData?.activeWorkspace?.id

    // Globally active window — same on every monitor's bar
    readonly property Toplevel activeToplevel: ToplevelManager.activeToplevel
    readonly property bool hasActive: root.activeToplevel !== null
                                   && root.activeToplevel?.activated === true

    readonly property string displayClass: root.hasActive
        ? root.activeToplevel.appId
        : Translation.tr("Desktop")

    readonly property string displayTitle: root.hasActive
        ? root.activeToplevel.title
        : `${Translation.tr("Workspace")} ${root.workspaceId ?? 1}`

    implicitWidth: colLayout.implicitWidth

    ColumnLayout {
        id: colLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: -4

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.displayClass
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: root.displayTitle
        }
    }
}
