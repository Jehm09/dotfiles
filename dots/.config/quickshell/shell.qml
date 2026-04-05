//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded

// Shell entry point.
// Instantiates all top-level modules: bar, launcher, control center,
// notifications, and OSD. All monitors get a Bar.
// The launcher and control center are singletons shared across monitors.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "./modules/bar"
import "./modules/launcher"
import "./modules/controlcenter"
import "./modules/notifications"
import "./modules/osd"
import "./services"

ShellRoot {
    // Watch config + i18n files for live reloading
    settings.watchFiles: true

    // ---------------------------------------------------------------
    // Shared state
    // ---------------------------------------------------------------
    property bool controlCenterOpen: false
    property bool launcherOpen:      false

    // IPC function exposed to Hyprland keybinds and external callers.
    // Keybind: hyprctl dispatch exec -- qs ipc call toggleLauncher
    function toggleLauncher()      { launcherOpen      = !launcherOpen }
    function toggleControlCenter() { controlCenterOpen = !controlCenterOpen }

    // ---------------------------------------------------------------
    // Bar - one per connected monitor
    // ---------------------------------------------------------------
    Variants {
        model: Quickshell.screens

        Bar {
            required property ShellScreen modelData
            screen: modelData

            isOpen_controlCenter: controlCenterOpen
            isOpen_launcher:      launcherOpen

            onControlCenterToggled: controlCenterOpen = !controlCenterOpen
            onLauncherToggled:      launcherOpen      = !launcherOpen
        }
    }

    // ---------------------------------------------------------------
    // Launcher overlay (fullscreen, all monitors share one instance)
    // ---------------------------------------------------------------
    Launcher {
        id:      launcher_
        isOpen:  launcherOpen
        onIsOpenChanged: launcherOpen = isOpen
    }

    // ---------------------------------------------------------------
    // Control center slide-in panel
    // ---------------------------------------------------------------
    ControlCenter {
        id:      cc_
        isOpen:  controlCenterOpen
        onIsOpenChanged: controlCenterOpen = isOpen
    }

    // ---------------------------------------------------------------
    // Toast notifications
    // ---------------------------------------------------------------
    NotificationPopup {}

    // ---------------------------------------------------------------
    // OSD (volume / brightness)
    // ---------------------------------------------------------------
    Osd { id: osd_ }
}
