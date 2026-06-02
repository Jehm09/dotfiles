pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Minimize-to-bar support for Hyprland.
 *
 * Hyprland has no native minimize: when an app (e.g. a game under XWayland/Proton)
 * requests to be minimized it only emits a `minimize>>ADDRESS,STATE` socket2 event.
 * We react to that event (or a manual shortcut) by parking the window in a hidden
 * special workspace.
 *
 * The list of minimized windows is DERIVED from live Hyprland state (windows that
 * are currently on the hidden workspace), so it self-heals across a shell
 * reload/crash-restart instead of leaving windows stuck and hidden with no icon.
 */
Singleton {
    id: root

    // Hidden special workspace where minimized windows are parked.
    readonly property string minimizedWorkspace: "special:minimized"

    // Each entry: { address: "0x...", appId, title }
    readonly property var minimized: HyprlandData.windowList
        .filter(w => w.workspace?.name === root.minimizedWorkspace)
        .map(w => ({
            address: w.address,
            appId: w.class ?? "",
            title: w.title ?? ""
        }))

    function isMinimized(address) {
        const fullAddr = address.startsWith("0x") ? address : ("0x" + address);
        return root.minimized.some(entry => entry.address === fullAddr);
    }

    function minimize(address) {
        const fullAddr = address.startsWith("0x") ? address : ("0x" + address);
        const win = HyprlandData.windowByAddress[fullAddr];
        if (!win)
            return; // Unknown window, nothing to do
        if (win.workspace?.name === root.minimizedWorkspace)
            return; // Already hidden

        // This Hyprland config interprets dispatch args as Lua (hl.dsp.*), so we
        // use that form instead of native dispatcher strings. follow=false → silent.
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${root.minimizedWorkspace}", follow = false, window = "address:${fullAddr}" })`);
    }

    function restore(entry) {
        if (!entry)
            return;
        // Bring the window to the workspace the user is currently on, then focus it.
        const target = HyprlandData.activeWorkspace?.name ?? HyprlandData.activeWorkspace?.id;
        if (target !== undefined && target !== null)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${target}", follow = false, window = "address:${entry.address}" })`);
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${entry.address}" })`);
    }

    function minimizeFocused() {
        const addr = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        if (addr)
            root.minimize(addr);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "minimize")
                return;
            // Payload: ADDRESS,STATE  (ADDRESS has no 0x prefix, STATE is 0/1)
            const parts = event.data.split(",");
            const fullAddr = "0x" + parts[0];
            if (parts[1] === "1") {
                root.minimize(fullAddr);
            } else if (root.isMinimized(fullAddr)) {
                root.restore(root.minimized.find(e => e.address === fullAddr));
            }
        }
    }

    // Manual minimize shortcut (bound in hypr keybinds as quickshell:minimizeFocused)
    GlobalShortcut {
        name: "minimizeFocused"
        description: "Minimize the focused window to the bar"
        onPressed: root.minimizeFocused()
    }
}
