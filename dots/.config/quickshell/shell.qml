//@ pragma Env QS_NO_RELOAD_POPUP=1

// Shell entry point.

import "services"
import "modules/bar"
import "modules/launcher"
import "modules/osd"
import "modules/settings"

import Quickshell

ShellRoot {
    id: root

    // Services (Config, Colors, Wallpaper, I18n, Visibilities) load as
    // singletons automatically when their module is imported above.

    // Bar — one instance per connected screen.
    Variants {
        model: Quickshell.screens
        delegate: BarWindow {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // Launcher — one instance (fullscreen overlay, screen-agnostic).
    LauncherWindow {}

    // OSD — one instance (bottom pill overlay).
    OsdWindow {}

    // Settings panel — toggle with: qs ipc call settings toggle
    SettingsWindow {}
}
