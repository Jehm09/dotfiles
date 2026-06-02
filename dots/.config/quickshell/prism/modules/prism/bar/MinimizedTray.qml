pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Shows minimized windows (parked in the hidden special workspace) as clickable
// icons in the bar, next to the system tray. Click to restore the window.
Item {
    id: root
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight
    visible: MinimizedWindows.minimized.length > 0

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        spacing: 15

        Repeater {
            model: ScriptModel {
                objectProp: "address"
                values: MinimizedWindows.minimized
            }

            delegate: MouseArea {
                id: entry
                required property var modelData

                Layout.fillHeight: true
                implicitWidth: 20
                implicitHeight: 20
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onPressed: event => {
                    MinimizedWindows.restore(entry.modelData);
                    event.accepted = true;
                }

                IconImage {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    opacity: entry.containsMouse ? 0.7 : 1
                    source: Quickshell.iconPath(AppSearch.guessIcon(entry.modelData.appId), "image-missing")
                }
            }
        }
    }
}
