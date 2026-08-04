# Vendored theme assets

## Scratchy (current global theme)

- **Upstream**: KDE Store <https://store.kde.org/p/1898344>
- **License**: GPL 3+
- Vendored whole: **130 files, 2.5 MB, no symlinks**

A Plasma 6 global theme is four separate packages, and all four are needed:

| Part | Path |
|---|---|
| look-and-feel | `.local/share/plasma/look-and-feel/Scratchy/` |
| aurorae decoration | `.local/share/aurorae/themes/Scratchy/` |
| Plasma style | `.local/share/plasma/desktoptheme/Scratchy/` |
| colour scheme | `.local/share/color-schemes/Scratchy.colors` |

Applying it is `setup kde theme`, not a file copy: selecting a global theme writes
keys across `kwinrc`, `kdeglobals`, `plasmarc` and `kcminputrc`. Note that it
**resets the cursor theme**, which is why `theme.sh` sets the cursor last.

Scratchy applies cleanly on Plasma 6.7, verified on this machine. That is worth
stating because third-party global themes are the riskiest thing to install on
Plasma 6 — see KDE's own warning:
<https://itsfoss.com/news/kde-plasma-global-theme-fiasco/>. An earlier attempt with
`vinceliuice/WhiteSur-kde` was abandoned for exactly that reason (its issue #124,
"Global theme causes complete desktop failure on Plasma 6", is still open).

## YAMIS icons

- **Upstream**: <https://www.opendesktop.org/p/2303161> (same item as
  <https://store.kde.org/p/2303161/>), by *dirn*
- **License**: GPL 3
- **20 MB: 3960 files plus 2070 symlinks**

Vendored whole, at `.local/share/icons/YAMIS/`. This needed two fixes in
`cmd/lib/kde.sh` first, because an icon theme is mostly symlinks:

- `expand_entries` matched `-type f` only, which silently skipped all 2070 links.
  It now matches `\( -type f -o -type l \)`.
- The copy loop rendered every entry through `sed`, which would have
  **dereferenced** each link into a full copy of its target — bloating the tree and
  destroying the theme's structure. Symlinks are now detected before the regular
  file path and recreated with `ln -sfn`, with `@HOME@` substitution applied to
  the link target in case it is absolute.

## Cursor

**Bibata-Modern-Classic**, size 24, from the packaged `bibata-cursor-theme`.
Not vendored — it is a normal repo package.

It was already declared in `packages/deps-hyprland.conf`, but that file is not
installed on a KDE-only machine, so it is declared in `deps-kde.conf` too;
otherwise a fresh install ends up with no cursor theme. `theme.sh` sets it **last**,
because applying a global theme resets the cursor.


## Panel layout

Saved as a whole file at `dots/kde/panel/plasma-org.kde.plasma.desktop-appletsrc`
(64 kB, 30 applets), managed by `setup kde panel` / `setup kde panel --restore`
rather than by `files.list`. Reasons it is handled separately:

- plasmashell owns the file and rewrites it from memory on exit, so a restore only
  survives with plasmashell stopped — which the `panel` mode does for you.
- It carries every panel widget's configuration, including Panel Colorizer's
  ~55 kB `globalSettings` JSON blob. That is why the file is copied wholesale
  instead of being reconstructed by a script.

Two keys inside it are machine-specific and will not transfer cleanly to a
different monitor setup: `[ScreenMapping]` / `screenMapping=` and the per-panel
`lastScreen=`. Plasma regenerates both, but the panel may first appear on the
wrong screen. Also expect `panelWidgets=` (Colorizer's widget-discovery cache) to
differ after a restart — it is a cache, not configuration.

## Plasmoids

Both are vendored rather than packaged, so `setup kde apply` installs them and
`packages/deps-kde.conf` lists them under "INSTALLED OUTSIDE PACMAN".

**Thermal Monitor** — KDE Store <https://store.kde.org/p/998915>, MIT, by Oliver
Beard, upstream <https://invent.kde.org/olib/thermalmonitor>. At
`.local/share/plasma/plasmoids/org.kde.olib.thermalmonitor/` (128 kB, 16 files).
Vendored at **0.2.8** because AUR `plasma6-applets-thermal-monitor` is 0.2.7-2 and
was flagged out-of-date on 2026-07-20 — the packaged version is older than this one.

**Krohnkite** — tiling script, at `.local/share/kwin/scripts/krohnkite/` (532 kB,
10 files). **PATCHED**: `contents/ui/popup.qml` had its `show()` emptied out.
Krohnkite draws an on-screen display on every action — including a direction arrow —
centred on the window area, i.e. exactly where the pointer lands after a
Super+arrow. Setting `notificationDuration=0` in `kwinrc [Script-krohnkite]` is not
enough: the original `show()` set `visible = true` *before* starting `hideTimer`, so
with a 0 ms interval the popup still painted for at least one frame.

Unrelated pre-existing issue on Plasma 6.7, present before that patch: Krohnkite
logs `Qt.createQmlObject(): Missing parent object` from `script.js:1627`, where it
tries to build a `Timer` with an undefined `scriptRoot`. Tiling still works.

**SCP menu (scpmk)** — power menu, KDE Store. At
`.local/share/plasma/plasmoids/org.kde.plasma.scpmk/` (100 kB, 14 files).
**PATCHED**: upstream imports `org.kde.plasma.private.quicklaunch`, which no longer
exists in Plasma 6.7 (the quicklaunch applet became a compiled plugin with its QML
embedded), so the widget refused to load with *module … is not installed*. That
import was only used for its `openUrl()`, so it is replaced with the `executable`
engine of `Plasma5Support` — already imported by the widget — running
`kioclient exec`. The patch is marked `PATCHED (dotfiles)` in `contents/ui/main.qml`.

Its configurable surface is tiny: `General/icon`, `General/showCmd1..3` and
`Apps/appList`. The button grid, fonts and spacing are hardcoded in the QML, so
changing those means extending the patch.

## Considered and not installed

**A "minimised windows only" applet.** Plasma 6's task manager has no such filter —
no `showOnlyMinimized` option exists anywhere in the applet, verified against the
compiled plugin. The closest third-party option is
<https://github.com/LoneDev6/kde-minimized-previews-only> (targets 6.7, user-local,
no system files), but it renders *live previews* rather than icons and also shows
previews for virtual desktops holding a single window. Not installed.
