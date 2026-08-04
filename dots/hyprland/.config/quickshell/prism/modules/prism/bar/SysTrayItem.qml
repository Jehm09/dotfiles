pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool targetMenuOpen: false

    signal menuOpened(qsWindow: var)
    signal menuClosed()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: 20
    implicitHeight: 20
    function toggleMenu() {
        if (!item.hasMenu)
            return;
        if (menu.active && menu.item && typeof menu.item.close === "function")
            menu.item.close();
        else
            menu.open();
    }

    readonly property string identity: `${item.id ?? ""} ${item.title ?? ""} ${item.tooltipTitle ?? ""}`.toLowerCase()
    readonly property bool isSteam: identity.includes("steam")

    onPressed: (event) => {
        switch (event.button) {
        case Qt.LeftButton:
            if (root.isSteam) {
                // Steam ignores the SNI Activate call, so re-run the command; an
                // already-running Steam just shows its main window.
                Quickshell.execDetached(["sh", "-c", "steam || flatpak run com.valvesoftware.Steam"]);
            } else if (item.onlyMenu && item.hasMenu) {
                // Items that only offer a menu (don't implement Activate): show it.
                root.toggleMenu();
            } else {
                item.activate();
            }
            break;
        case Qt.RightButton:
            root.toggleMenu();
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            trayItemId: root.item.id
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    IconImage {
        id: trayIcon
        visible: !Config.options.tray.monochromeIcons
        source: root.item.icon
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
    }

    Loader {
        active: Config.options.tray.monochromeIcons
        anchors.fill: trayIcon
        sourceComponent: Item {
            Desaturate {
                id: desaturatedIcon
                visible: false // There's already color overlay
                anchors.fill: parent
                source: trayIcon
                desaturation: 0.8 // 1.0 means fully grayscale
            }
            ColorOverlay {
                anchors.fill: desaturatedIcon
                source: desaturatedIcon
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
            }
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
        // Leave room for the drop shadow so it isn't clipped by the popup surface.
        horizontalMargin: Appearance.sizes.elevationMargin
        verticalMargin: Appearance.sizes.elevationMargin

        // Match the right-click menu's look: colLayer0 background, border, rounding,
        // shadow and on-layer text, instead of the default dark tooltip.
        contentItem: Item {
            implicitWidth: tooltipBackground.implicitWidth
            implicitHeight: tooltipBackground.implicitHeight

            StyledRectangularShadow {
                target: tooltipBackground
            }
            Rectangle {
                id: tooltipBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                implicitWidth: tooltipLabel.implicitWidth + 24
                implicitHeight: tooltipLabel.implicitHeight + 14

                StyledText {
                    id: tooltipLabel
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 360)
                    text: tooltip.text
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }

}
