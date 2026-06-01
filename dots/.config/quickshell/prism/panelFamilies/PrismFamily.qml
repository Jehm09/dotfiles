import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.prism.background
import qs.modules.prism.bar
import qs.modules.prism.cheatsheet
import qs.modules.prism.dock
import qs.modules.prism.lock
import qs.modules.prism.mediaControls
import qs.modules.prism.notificationPopup
import qs.modules.prism.onScreenDisplay
import qs.modules.prism.onScreenKeyboard
import qs.modules.prism.overview
import qs.modules.prism.polkit
import qs.modules.prism.regionSelector
import qs.modules.prism.screenCorners
import qs.modules.prism.sessionScreen
import qs.modules.prism.sidebarRight
import qs.modules.prism.overlay
import qs.modules.prism.verticalBar
import qs.modules.prism.wallpaperSelector

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
}
