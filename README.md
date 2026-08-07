# dotfiles

Personal dotfiles for Arch Linux, with a choice of two desktops: **Hyprland +
Quickshell** or **KDE Plasma 6**. Pick one at install time — every step follows
from that choice.

## How the Hyprland side works — read this first

The Hyprland/Quickshell interface is **not mine and is not stored here**. It is
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland), pulled straight
from its author, and this repo carries only my changes on top of it.

That is a deliberate change of direction. This repo used to hold a full copy of
end-4's shell — some 780 files — which meant maintaining someone else's code:
their bugfixes never arrived, and anything that broke was mine to fix. Now:

- **end-4's version is the base.** It is cloned to
  `$XDG_DATA_HOME/dotfiles/upstream`, outside git, and updates come from him.
- **This repo stores only the delta**: ~51 patches, 13 files of my own, and a
  list of things I delete (the AI assistant, the `waffle` panel family, Google
  Cloud services, the translations). Around 2,000 lines instead of 80,000.
- **Updating is a real git three-way merge.** Conflicts can only happen in files
  I actually patched; the ~600 I don't touch update by themselves.

So when end-4 improves the bar, fixes the notification popup or rewrites a
widget, I get it by running one command — and I only look at whatever collides
with my own changes. See [Upstream shell](#upstream-shell-end-4dots-hyprland).

The KDE profile is unrelated to this and stays fully mine, copy-managed under
`dots/kde/`.

## Quick install

### 1. From the Arch live ISO

```bash
# As root
git clone <repo> dotfiles && cd dotfiles
./setup install
# Reboot when done
```

### 2. Post-install (first boot)

`setup install` is the only one-off: it runs archinstall from the live ISO and
never runs again. **Everything else is `setup post`, and it can be run whole, a
step at a time, or re-run whenever you like.**

```bash
./setup post --hyprland                  # pick steps in a menu
./setup post --all --hyprland            # everything, no prompts
./setup post --only greeter --hyprland   # just the login screen
./setup post --skip apps,hwfix --kde     # everything but those two
```

Step names for `--only` / `--skip`: `multilib`, `aur`, `desktop`, `apps`,
`greeter`, `hooks`, `dotfiles`, `shell`, `hwfix`. An unknown name is an error
listing the valid ones, not a silent no-op.

Without `--all`, `--only` or `--skip` it asks: desktop, then AUR helper, then
login screen, then a checklist of the steps.

```
┌──────── Post-install — hyprland, sddm ─────────────────────┐
│  Space toggles · Tab to the buttons · Enter confirms       │
│  Listed in the order they run; each assumes the ones above.│
│                                                            │
│   [*] multilib  1. base     [multilib] repo — Steam, 32-bit│
│   [ ] aur       2. base     paru/yay — steps below use it  │
│   [*] desktop   3. desktop  graphical stack — Hyprland/KDE │
│   [*] apps      4. apps     browsers, editors, games       │
│   [*] greeter   5. login    SDDM, or greetd + sysc-greet   │
│   [*] hooks     6. system   pacman hooks from hooks/enabled│
│   [*] dotfiles  7. config   ~/.config — kitty, fish, …     │
│   [*] shell     8. config   fish as the login shell        │
│   [*] hwfix     9. hardware Logitech mouse fix + initramfs │
│                                                            │
│              <Ok>              <Cancel>                    │
└────────────────────────────────────────────────────────────┘
```

The numbering is the dependency order: each step assumes the ones above it are
done. Unchecking one is fine — it just means you have that handled some other
way.

**The AUR step adapts.** With a helper already installed it starts unchecked
(nothing to do) and that helper is what the package steps use. With none, it is
forced on, you pick `yay` (default), `paru` or `both`, and unticking it is
refused while any package step is still selected — otherwise steps 3 and below
would fail one at a time. `--aur-helper=` sets it non-interactively.

whiptail ships with `libnewt`, already present on any Arch system, and is themed
dark through `NEWT_COLORS` in `cmd/lib/utils.sh`. When it is missing or stdin is
a pipe, every menu falls back to a plain prompt, so nothing can wedge an
automated run.

**The desktop is a required choice.** There is no default and no fallback: the
packages installed, the dotfiles linked and the session configured all follow
from it. Without `--hyprland` or `--kde` the menu asks, and a non-interactive run
without either stops.

| Step | What it does |
|---|---|
| `multilib` | Enables `[multilib]` for Steam and 32-bit apps |
| `aur` | Installs yay, paru or both — steps 3+ install through it |
| `desktop` | hyprland → `deps-hyprland.conf` + `deps-quickshell.conf`<br>kde → `deps-kde.conf`, plus the `dots/kde/` profile and the KWallet PAM hook |
| `apps` | `packages/apps.conf` (official + AUR) |
| `greeter` | SDDM + `sddm-astronaut-theme`, or greetd + sysc-greet |
| `hooks` | Hooks from `packages/hooks/enabled/` |
| `dotfiles` | Symlinks for the chosen desktop |
| `shell` | Sets fish as the login shell |
| `hwfix` | Logitech mouse blacklist + initramfs rebuild |

### Dotfiles only

```bash
./setup dotfiles hyprland              # dots/common + dots/hyprland
./setup dotfiles kde                   # dots/common  (then: ./setup kde apply)
./setup dotfiles kde --dry-run         # preview changes without applying them
./setup dotfiles hyprland --unlink     # remove symlinks and restore backups
```

#### Profiles

| Profile | Contents | Managed by |
|---|---|---|
| `dots/common/` | kitty, fish, yazi, mpv, fastfetch, starship, fontconfig, darklyrc, browser/editor flags | symlink |
| `dots/hyprland/` | our own additions only: `settings/`, the systemd target, `auto-Hypr.fish` | symlink |
| `overlay/hyprland/` | our delta on top of end-4's shell — hypr, quickshell, fuzzel, matugen, Kvantum, wlogout | rebuilt by `setup upstream`, then symlinked |
| `dots/kde/` | the whole Plasma setup | **copy** (`setup kde`), never symlink |

`common` is linked by both desktops; `hyprland` and `kde` are mutually exclusive.
KDE is copy-managed because KConfig rewrites its files at runtime and would turn a
symlink into a regular file — see the KDE section below.

The Hyprland/Quickshell code itself is **not** in this repo; see
[Upstream shell](#upstream-shell-end-4dots-hyprland) below.

#### Merged directories

Three directories under `~/.config` are kept as **real directories** with their
contents symlinked file by file, rather than being symlinked whole:

| Directory | Why |
|---|---|
| `systemd/user` | holds runtime `*.target.wants/` for enabled user services |
| `xdg-desktop-portal` | Hyprland owns `hyprland-portals.conf`, KDE owns `kde-portals.conf`; a directory symlink would make `setup kde apply` write the KDE file inside `dots/hyprland/` |
| `fish` | split across profiles — `config.fish`, `functions/`, `conf.d/`, `completions/` in `common`, `auto-Hypr.fish` in `hyprland`. As a plain entry the second profile would hide the first |

### KDE Plasma profile

Plasma is managed separately from the rest of the dotfiles, and by **copy rather
than symlink**: KConfig rewrites its `*rc` files on every settings change and
again on logout, using a write-temp-then-rename pattern that turns a symlink into
a regular file. Which files are managed is declared in `dots/kde/files.list`.

```bash
./setup post --kde                  # full post-install with Plasma as the desktop
./setup post --only desktop,dotfiles --kde   # just the packages + profile

./setup kde apply      # repo -> ~   (backs up whatever it replaces)
./setup kde save       # ~ -> repo   (run this after tweaking System Settings)
./setup kde diff       # show what differs, change nothing
./setup kde theme      # apply the appearance stack from dots/kde/theme.sh
./setup kde apply --dry-run
```

The panel is built by hand, then captured as a whole file:

```bash
./setup kde panel             # live -> repo  (run after changing the panel)
./setup kde panel --restore   # repo -> live  (stops plasmashell, then restarts)
```

It is kept out of `apply`/`save` because plasmashell owns
`plasma-org.kde.plasma.desktop-appletsrc` and rewrites it from memory on exit, so
a restore only sticks with plasmashell stopped. The file also carries every panel
widget's configuration — including Panel Colorizer's ~55 kB `globalSettings` JSON —
which is why it is copied whole rather than rebuilt by a script. `[ScreenMapping]`
and `lastScreen=` inside it are machine-specific; see
[dots/kde/VENDORED.md](dots/kde/VENDORED.md).

### Reproducing this setup on another machine

```bash
./setup post --kde      # packages, dotfiles (common), profile, KWallet PAM hook
./setup kde theme       # select the global theme, decoration, colours, cursor, icons
./setup kde panel --restore
```

`setup post --kde` already runs `setup kde apply` (config, scripts, shortcuts,
themes, icons — ~6200 files); the two steps above are the ones it does not.

Theme assets are vendored under `dots/kde/.local/share/`; see
[dots/kde/VENDORED.md](dots/kde/VENDORED.md) for provenance, the local
modifications, and what was deliberately left out.

Absolute home paths are stored as a `@HOME@` placeholder and substituted both
ways, so the profile is portable across machines and users.

Plasma and Hyprland can stay installed side by side — the greeter offers both
sessions. `~/.config/kdeglobals` and `~/.config/dolphinrc` belong to this profile
and are deliberately skipped by the symlink manager.

## Login screen

Two options, mutually exclusive — `/etc/systemd/system/display-manager.service`
is a single symlink, so only one can be enabled:

| | `setup greeter sddm` | `setup greeter greetd` |
|---|---|---|
| What | Graphical Qt login | Console greeter |
| Theme | [sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme), `hyprland_kath` | none |
| Runs under | weston (kiosk shell) | Cagebreak |
| Packages | `deps-greeter-sddm.conf` | `deps-greeter-greetd.conf` |
| Needs seatd | no — uses logind | yes |
| Good when | you want a themed login and switch sessions often | the GPU makes SDDM's weston greeter misbehave, or you want something lighter |

`setup post` installs and configures whichever you pick — `--greeter=sddm`
(default) or `--greeter=greetd`, or choose it in the menu. Switching later is one
command; both leave the other installed.

```bash
setup greeter status    # which is active, and what would break
setup greeter sddm      # switch to SDDM
setup greeter greetd    # switch to greetd + sysc-greet
setup greeter apply     # re-apply the active one's config
setup greeter test      # preview the SDDM theme in a window; Super+Q to close
```

Both switches add the GRUB console entry first (`setup grub rescue`), so a
greeter that fails to start cannot lock you out. If it does: pick
**Arch Linux (console / TTY)** at the boot menu, log in on the TTY, and run
`setup greeter greetd` (or `sddm`).

### SDDM: three ways it looks broken when it is not

All three were hit in practice, and all three are handled by
`setup greeter sddm`. They are worth knowing because the journal reports
`Greeter session started successfully` in every one of them.

**It draws on every screen.** SDDM instantiates the theme on every QScreen the
compositor exposes — core behaviour, not the theme — so the login form can land
on a monitor that is off. **Displays are left untouched by default**, which is
what makes this repo installable anywhere. To pin it on a given machine:

```bash
GREETER_OUTPUT=DP-5 setup greeter apply
```

Connector names are the ones the kernel reports (`DP-5`, `HDMI-A-2`, `eDP-1`) —
the same ones Hyprland uses in `monitors.lua`. With weston this writes
`/etc/sddm/weston.ini` and is reliable; with kwin it writes
`kwinoutputconfig.json` under the greeter's home, whose format is versioned, so
it is best-effort — if kwin rejects it every screen simply stays on.

**The setting sticks.** `setup greeter apply` writes whatever it was given to
`local.conf` at the repo root, which `cmd/lib/utils.sh` sources before anything
reads it — so a later plain `setup greeter apply` keeps the pin instead of
quietly undoing it. Passing the variable again overrides and re-saves; passing
it empty (`GREETER_OUTPUT= setup greeter apply`) removes the pin and the
compositor's output config with it.

`local.conf` is **gitignored**: it describes one machine, and committing it is
exactly what would stop the repo installing cleanly on the next one. See
[local.conf.example](local.conf.example) for every setting it takes.

The theme's `ScreenWidth`/`ScreenHeight` are deliberately left empty:
`Main.qml` does `height: config.ScreenHeight || Screen.height`, so setting them
pins one resolution on *every* screen, rendering the primary's size onto a
secondary of a different size.

**seatd fights logind over the input devices.** greetd needs seatd; SDDM uses
logind. Both enabled gives `Backend 'seatd' failed to open seat` and
`Could not take device: Device already taken`, and the greeter never accepts
typing. Each `setup greeter` target enables or disables seatd to match.

**The pointer is invisible under weston.** Nothing draws it. weston does not
implement `wp_cursor_shape_manager_v1` (0 references in its binaries; Qt 6 has
72), neither of its shells sets a default pointer image, and SDDM never exports
`XCURSOR_THEME` — it only has its own `CursorTheme` key, which the compositor
never sees. `WESTON_DISABLE_ATOMIC=1` does not help: that only fixes the NVIDIA
cursor plane, and the problem is upstream of it.

Fixed by running the greeter under **kwin_wayland**, which does implement
cursor-shape-v1. That is the default; `GREETER_COMPOSITOR=weston` switches back.

| | kwin (default) | weston |
|---|---|---|
| Cursor | yes | **none, ever** |
| Output pinning | best-effort | reliable |

And one that makes it genuinely crash, worth stating as a rule: **never set**
`GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell`. weston's
kiosk-shell does not implement wlr-layer-shell, Qt then fails to load its platform
plugin, and the greeter aborts on every boot. That advice only applies when the
SDDM compositor is `kwin_wayland` or a wlroots one.

`setup greeter status` checks for all four.

### What `setup post` cannot get right on a fresh machine

The weston output config comes from `~/.config/hypr/monitors.lua`, which does not
exist yet: it is written once you set the display layout in the session, and it
is in `local.ignore` so it never ships with the repo. Step 5 therefore leaves
every output enabled — correct on a single monitor, wrong on a multi-head box.
Set up the displays, then re-run `setup greeter apply`. Both the script and
`setup post` say so when the file is missing.

### Configuration files

| File | What it sets |
|---|---|
| `/etc/sddm.conf.d/10-theme.conf` | theme, cursor theme and size |
| `/etc/sddm.conf.d/20-virtualkbd.conf` | the Qt virtual keyboard the theme expects |
| `/etc/sddm.conf.d/30-wayland.conf` | Wayland greeter, and the weston command |
| `/etc/sddm/weston.ini` | which outputs that compositor enables |
| `/etc/greetd/config.toml` | the greetd session command |

Drop-ins rather than `/etc/sddm.conf`, so pacman never leaves a `.pacnew` to
merge by hand.

**The theme variant is fragile, by design of the theme.** Which variant is active
lives in `metadata.desktop` and the screen size in `Themes/hyprland_kath.conf` —
both under `/usr/share`, owned by the package, so every upgrade reverts them to
the `astronaut` variant at 1920x1080.
`packages/hooks/enabled/sddm-astronaut-theme.hook` re-applies both edits after
each upgrade. Change the variant or the resolution in **both** the hook and
`cmd/lib/greeter.sh`, or they will disagree. The other variants are listed in the
theme's `Themes/` directory.

## Boot menu rescue entry

```bash
setup grub rescue    # add it
setup grub status    # show what is installed
setup grub remove    # delete it
```

Adds **Arch Linux (console / TTY)** to the GRUB menu — the same entry as the
normal one plus `systemd.unit=multi-user.target`, and without `quiet` and
`loglevel=3` so failures are visible. It boots the full system minus the
graphical session, which is the way back in when a greeter or compositor breaks.

It is written to `/boot/grub/custom.cfg`, not `/etc/grub.d/40_custom`, because
Arch's `41_custom` already makes `grub.cfg` source that file at boot. So the entry
needs no `grub-mkconfig` run to appear, and survives every future one —
`grub-mkconfig` only rewrites `grub.cfg` and never touches `custom.cfg`.

The entry is cloned from the real `Arch Linux` entry rather than written from
scratch, which keeps the root UUID, the ESP search line, the kernel and initrd
paths and any microcode images correct on any machine, with nothing hardcoded to
drift.

## Command reference

```
./setup                  Menu: post → tools → install
./setup install          Install Arch from the live ISO  (root)
./setup post             Interactive post-install setup
./setup post --hyprland  Post-install with Hyprland as the desktop
./setup post --kde       Post-install with KDE Plasma as the desktop
./setup post --all --kde Post-install without prompting
./setup post --only greeter --hyprland   Just one step
./setup post --skip apps,hwfix --kde     All but those
./setup dotfiles hyprland|kde   Link ~/.config for that desktop
./setup kde apply|save|diff   KDE Plasma profile (copy-managed)
./setup kde theme        Apply the appearance stack (dots/kde/theme.sh)
./setup kde panel        Save the panel layout  (--restore to put it back)
./setup greeter status   Which login screen is active, and what would break
./setup greeter sddm|greetd   Switch the login screen
./setup greeter apply    Re-apply the active greeter's config
./setup grub rescue      Add the console entry to the boot menu
./setup upstream status  Pinned upstream commit, drift, unexported edits
./setup upstream sync    Rebuild the upstream tree from overlay/hyprland/
./setup upstream update  Merge new upstream changes into our overlay
./setup upstream export  Save the result back into overlay/hyprland/
./setup upstream deps    Build quickshell at the commit upstream pins
./setup --help           Show help
```

## Structure

```
dotfiles/
├── setup                    Main entry point
├── cmd/
│   ├── lib/
│   │   ├── utils.sh         Shared functions (colors, sudo keepalive, etc.)
│   │   ├── symlink.sh       Dotfiles symlink manager
│   │   ├── upstream.sh      end-4/dots-hyprland overlay manager
│   │   ├── greeter.sh       Login screen — SDDM or greetd
│   │   ├── grub.sh          Boot menu console entry
│   │   └── kde.sh           KDE Plasma profile manager (apply / save / diff)
│   └── arch/
│       ├── install.sh       Arch installer via archinstall
│       ├── post-install.sh  Post-install setup
│       └── archinstall/
│           ├── user_configuration.json   archinstall config (kernel, locale, mirrors...)
│           └── user_credentials.json     Encrypted credentials (argon2id)
├── dots/
│   ├── common/.config/      Desktop-agnostic app configs — symlinked, both desktops
│   ├── hyprland/.config/    Our own Hyprland-side additions only (settings/, systemd/, fish/)
│   └── kde/                 KDE Plasma profile — copied to ~, mirrors $HOME
│       ├── files.list       Which files the profile manages
│       ├── .config/         kwinrc, kglobalshortcutsrc, kde/scripts/, ...
│       └── .local/share/applications/   Shortcut .desktop files (X-KDE-Shortcuts)
├── overlay/hyprland/        Our delta on top of end-4/dots-hyprland
│   ├── upstream.lock        The upstream commit the overlay applies to
│   ├── remove.list          Upstream paths we delete (AI, waffle, gCloud, translations)
│   ├── local.ignore         Per-machine paths, never exported
│   ├── files/               Files that are entirely ours
│   └── patches/             Edits on top of upstream files
└── packages/
    ├── apps.conf            User apps — official repos + an AUR-only section
    ├── deps-hyprland.conf   Hyprland WM + Wayland session tools
    ├── deps-quickshell.conf Quickshell runtime + widget backends
    ├── deps-kde.conf        KDE Plasma desktop + Krohnkite tiling
    ├── deps-greeter-sddm.conf    SDDM + the astronaut login theme
    ├── deps-greeter-greetd.conf  greetd + sysc-greet (Cagebreak)
    ├── requirements.txt     Python venv for the shell's helper scripts
    ├── modprobe/            Kernel module config installed to /etc/modprobe.d/
    └── hooks/
        ├── enabled/         Active pacman hooks
        └── disabled/        Inactive hooks
```

## What each script does

`setup` is a thin dispatcher: it resolves `REPO_ROOT`, sources
`cmd/lib/utils.sh` and hands off. All the work is in `cmd/`.

### `cmd/lib/utils.sh`
Sourced by everything else. Colour helpers (`info` / `success` / `warn` /
`error` / `step`), `parse_packages` (strips comments from a `.conf`),
`multilib_enable`, `sudo_keepalive` / `sudo_stop_keepalive`, and `prevent_root`.

Also the menu helpers: `has_menu`, `menu_checklist`, `menu_radiolist`,
`menu_confirm`, plus the `NEWT_COLORS` dark theme. They wrap whiptail, which
ships in `libnewt` and works on a bare TTY — where `setup post` runs after the
very first boot. `has_menu` is false when whiptail is missing or stdin is not a
terminal, and every caller falls back to a plain prompt, so no menu can wedge an
automated run.

whiptail's stock palette is the old Red Hat installer look — light grey on blue,
glaring next to a dark terminal. The theme sets the window background to black
and leaves the root pane empty (`root=,`) so it inherits your terminal's own
background instead of painting over it.

### `cmd/arch/install.sh` — `setup install`
Runs as root from the live ISO. Logs everything to `arch-install.log`.

1. **Validate** — refuses to start unless both archinstall JSONs and `apps.conf` exist.
2. **Inject packages** — awk reads `apps.conf` and stops at the `# AUR only`
   marker; a Python heredoc merges those names into `user_configuration.json`,
   deduplicated. Packages below the marker are skipped because archinstall
   installs with pacman and cannot build from the AUR.
3. **archinstall** — runs it with the merged config and the credentials file.

The live ISO is deliberately not updated first: that desyncs it from the mirror
snapshot archinstall then installs from.

### `cmd/arch/post-install.sh` — `setup post`
Runs as your user after the first boot, and **is the only thing you ever need to
re-run** — `setup install` is one-off, everything else lives here. Steps are
named and independently selectable with `--only` / `--skip`; without either you
get a whiptail checklist. The desktop choice is required and has no default.

| # | Step | What it does |
|---|---|---|
| 1 | Multilib | Uncomments `[multilib]` in `pacman.conf`, then `pacman -Sy` |
| 2 | AUR helper | Installs paru (or yay) by cloning and `makepkg -si` |
| 3 | Desktop packages | hyprland → `deps-hyprland.conf` + `deps-quickshell.conf`; kde → `deps-kde.conf` |
| 3b | Plasma session | *(kde only)* KWallet PAM hook in the display manager's stack, then `setup kde apply` |
| 3c | Quickshell | *(hyprland only)* `setup upstream deps` for the pinned build, then builds the Python venv from `requirements.txt` |
| 4 | Apps | Everything in `apps.conf`, AUR included, through paru/yay |
| 5 | Login screen | Hands over to `cmd/lib/greeter.sh`: installs the packages, writes the config, adds the GRUB console entry, switches `display-manager.service` |
| 6 | Pacman hooks | Copies `packages/hooks/enabled/*.hook` to `/etc/pacman.d/hooks` (currently empty; move one out of `disabled/` to activate it) |
| 7 | Dotfiles | Calls `symlink.sh` for the chosen desktop |
| 8 | Shell | `chsh` to fish |
| 9 | Hardware fixes | Logitech module blacklist to `/etc/modprobe.d/`, rebuilds initramfs |

sudo is asked for once, after the flags are parsed, and kept alive for the rest
of the run — so `--help` and the desktop validation never prompt.

### `cmd/lib/symlink.sh` — `setup dotfiles <hyprland|kde>`
Builds `~/.config` out of two sources.

1. **Pick the profiles** — `hyprland` → `dots/common` + `dots/hyprland`;
   `kde` → `dots/common` only.
2. **Sync upstream if missing** — for hyprland, runs `setup upstream sync` when
   there is no clone yet.
3. **Repair leftovers** — any `MERGE_DIRS` entry (or `~/.config/quickshell`) that
   is a stale directory symlink gets turned back into a real directory. `mkdir -p`
   succeeds silently on a symlink-to-directory, so without this every file below
   would be written *into* the repo.
4. **Link the repo entries** — one symlink per entry, skipping `KDE_OWNED`
   (`kdeglobals`, `dolphinrc`: KConfig rewrites them) and the `MERGE_DIRS` tops.
5. **Link the merge directories** — `systemd/user`, `xdg-desktop-portal` and
   `fish` stay real directories, linked file by file.
6. **Link the upstream entries** — only what is in `UPSTREAM_LINK`, plus
   `quickshell/ii` and the portal file.

Anything real it replaces is moved to `~/.config/backup/<name>.<timestamp>`.
`--dry-run` prints the plan; `--unlink` removes the links and restores the most
recent backup of each.

### `cmd/lib/greeter.sh` — `setup greeter <sub>`
The login screen, both variants. `sddm` and `greetd` each install their package
list, write their config, ensure the GRUB console entry exists and flip
`display-manager.service`; `apply` re-runs the config of whichever is active,
`status` reports what would break. Everything SDDM needs beyond the packages —
theme variant, `weston.ini` generated from `monitors.lua`, cursor, seatd — lives
here rather than in `post-install.sh`, so the same code serves a later re-run.

### `cmd/lib/grub.sh` — `setup grub <sub>`
Clones the real `Arch Linux` entry from `grub.cfg` into `/boot/grub/custom.cfg`
with `systemd.unit=multi-user.target` added and `quiet`/`loglevel` removed.
Cloning rather than templating keeps every machine-specific value correct;
`custom.cfg` rather than `40_custom` means no `grub-mkconfig` run is needed and
future ones cannot wipe it.

### `cmd/lib/upstream.sh` — `setup upstream <sub>`
Manages end-4's code as an overlay. Detailed in the section below; in short:
`sync` (clone + rebuild), `apply` (rebuild only), `update` (fetch + merge),
`export` (clone → `overlay/`), `deps` (pinned quickshell), `status`.

### `cmd/lib/kde.sh` — `setup kde <apply|save|diff|theme|panel>`
The Plasma profile, managed by copy because KConfig would clobber symlinks.
`files.list` declares what is managed, `render()` swaps absolute home paths for a
`@HOME@` placeholder in both directions, and `_is_text` (`grep -Iq .`) keeps
binaries out of the substitution. The panel is handled separately because
plasmashell rewrites its file from memory on exit.

## Upstream shell (end-4/dots-hyprland)

### Where the code lives

```
THIS REPO (what I version)              THE CLONE (35 MB, outside git)
dotfiles/                               ~/.local/share/dotfiles/upstream/
├── overlay/hyprland/                   ├── setup, sdata, dots-extra…  (end-4's)
│   ├── upstream.lock  the commit       └── dots/.config/
│   ├── patches/       ~51 diffs             ├── hypr/
│   ├── files/         13 of mine   ──┐     ├── quickshell/ii/
│   ├── remove.list    219 deletions  │     ├── fuzzel/ matugen/ Kvantum/ …
│   └── local.ignore   per-machine    │     └── kitty/ foot/ fish/  ← never linked
├── dots/common/                       │
└── dots/kde/                          │  branches: base = end-4 untouched
                                       │            mine = base + my overlay
     setup upstream sync  ─────────────┘
```

`~/.config/hypr` and `~/.config/quickshell/ii` are symlinks into that clone, so
editing the config is the same as it always was — the files just live elsewhere.

### The four kinds of change

`setup upstream export` classifies everything mechanically, with no judgement
calls:

| What I did | Where it goes |
|---|---|
| Edited a file of end-4's | `patches/<path>.patch` |
| Added a file of my own | `files/<path>` (permissions kept) |
| Deleted a file of end-4's | a line in `remove.list` |
| A file the machine generates | matched by `local.ignore`, never exported |

Patches rather than whole copies, because a stored copy would silently swallow
every upstream fix to that file. As a patch, git merges it for real.

### Which command do I want?

| I want to… | Run |
|---|---|
| Know where I stand | `setup upstream status` |
| Save changes I just made to the shell | `setup upstream export` |
| Pull end-4's newer code | `setup upstream update`, then `export` |
| Set this up on a new machine | `setup upstream sync` |
| Rebuild after hand-editing a patch | `setup upstream apply` |
| Match the quickshell runtime to the pin | `setup upstream deps` |

The one to remember is **`export`**: it is what writes the clone back into
`overlay/`, whether the changes are mine or came from a merge with end-4.
`update` only adds the step of fetching his code first. `status` tells you if
you have forgotten either.

### Editing the shell

```bash
nvim ~/.config/quickshell/ii/modules/ii/bar/Bar.qml   # or wherever
setup upstream export                                 # clone -> overlay/
git add overlay && git commit
```

Never edit the `.patch` files: `export` regenerates all of them from the clone,
so the clone is the source of truth and hand edits would be lost. If you forget
to export, `setup upstream status` says so.

### Pulling end-4's changes

```bash
setup upstream update     # fetch + three-way merge; stops if anything conflicts
# resolve the conflicts in the clone, then:
setup upstream export
git add overlay && git commit
setup upstream deps       # only if update reported the pin moved
```

Nothing forces an update through. If a merge looks bad,
`git -C ~/.local/share/dotfiles/upstream merge --abort` puts you back on the
commit in `upstream.lock` and everything keeps working.

### `update` and `deps` are separate — and why

They are two different commands and neither runs the other:

| | `setup upstream update` | `setup upstream deps` |
|---|---|---|
| Changes | config files in the clone | the installed quickshell package |
| Needs root | no | yes (sudo) |
| Takes | seconds | minutes (compiles Qt) |
| Safe to abort | yes, always | builds first, swaps at the very end |

They are split because most updates only move QML around, and forcing a Qt
rebuild every time would be painful. But they *are* related: end-4 pins the
quickshell runtime to a specific commit, and pulling new code can move that pin.
So both `update` and `status` check it and tell you when `deps` has to run again:

```
WARNING: Upstream now pins quickshell at 3f9a1c22, which is not the build you have.
WARNING: Run 'setup upstream deps' to rebuild the runtime to match.
```

`deps` is idempotent — if the installed package already matches the pin it exits
without building anything.

### Why quickshell is pinned at all

The AUR's `quickshell-git` tracks upstream master, so every `yay -Syu` rebuilds
it against whatever landed that day, and quickshell breaks QML APIs often enough
that this is the usual way the shell dies. end-4 pins a known-good commit, so
`quickshell-git` is deliberately **absent** from `deps-quickshell.conf` and
`setup upstream deps` builds the pinned PKGBUILD from the clone instead. That
build also installs a pacman hook that re-checks quickshell after every
`qt6-base` / `qt6-wayland` upgrade.

It is the only pinned package in the whole setup. `hyprland`, `hypridle`,
`hyprlock`, the qt6 stack and everything else are unversioned upstream too and
come from `packages/deps-*.conf` as normal packages.

### Details worth knowing

**Naming.** The overlay keeps end-4's `ii` naming everywhere, and so does
`~/.config/quickshell/ii` — the shell is his work, and renaming it only ever cost
merge noise.

**What is never linked.** `UPSTREAM_LINK` in `cmd/lib/symlink.sh` is a whitelist:
`hypr`, `fuzzel`, `matugen`, `Kvantum`, `wlogout`, `kde-material-you-colors`, plus
quickshell and the portal file. end-4 also ships kitty, foot, fish, mpv,
`zshrc.d` and `starship.toml` — none of them are linked, so `dots/common/` stays
in charge of those.

**Per-machine files.** `monitors.lua` and `workspaces.lua` are generated from
`dots/hyprland/.config/settings/quickshell/config.json` by the display scripts.
They are listed in `local.ignore`, kept untracked inside the clone, and survive
rebuilds — they describe this machine's monitors and must not travel in the repo.

**The Python venv.** Colour extraction, thumbnails and region detection shell out
to `~/.local/state/quickshell/.venv`, built by `setup post` from
`packages/requirements.txt`. If a colour script starts failing after an update,
compare that file against `sdata/uv/requirements.in` in the clone.

## Adding an app config

Drop its folder into the profile it belongs to and re-run `setup dotfiles`. Use
`common/` unless the config only makes sense under one desktop:

```bash
mkdir -p dots/common/.config/nvim
# copy or create your config files in dots/common/.config/nvim/
./setup dotfiles hyprland     # or: ./setup dotfiles kde
```

If the same directory name exists in both `common` and `hyprland`, add it to
`MERGE_DIRS` in [cmd/lib/symlink.sh](cmd/lib/symlink.sh) — otherwise the second
profile's symlink replaces the first's and one of the two configs disappears.

## Adding packages

Everything the user installs lives in `packages/apps.conf`. Packages above the
`# AUR only` marker are injected into the archinstall config by `setup install`;
everything in the file is installed by `setup post`, which uses paru/yay and so
handles official repos and the AUR transparently.

### Desktop dependencies

Desktop deps are declared as plain packages so they update normally with
`paru -Syu`. `setup post` installs them through `parse_packages()`
([cmd/lib/utils.sh](cmd/lib/utils.sh)); to do it by hand, strip the comments
first — `paru -S -` reads stdin verbatim and would try to install them:

```bash
for f in deps-hyprland deps-quickshell deps-greeter; do
    paru -S --needed $(awk '!/^[[:space:]]*#/ && NF {print $1}' "packages/$f.conf")
done
```

In fish, use `(...)` instead of `$(...)`.

**One exception: quickshell.** The AUR's `quickshell-git` tracks upstream master,
so every `-Syu` rebuilds it against whatever landed that day — and quickshell
breaks QML APIs often enough that this is how the shell usually dies. It is
therefore deliberately absent from `deps-quickshell.conf`; `setup upstream deps`
builds the commit end-4 pins instead, and that pin moves only when you run
`setup upstream update`. It also installs a pacman hook that re-checks quickshell
after every `qt6-base` / `qt6-wayland` upgrade.

The Python venv the shell's colour, thumbnail and region scripts depend on is
built by `setup post` from `packages/requirements.txt` into
`~/.local/state/quickshell/.venv`.

## Credits

The Hyprland and Quickshell interface is
**[dots-hyprland by end-4](https://github.com/end-4/dots-hyprland)** — his work,
his design, pulled straight from his repository and used as the base. It is not
a fork and it is not vendored here: the code is cloned from upstream at install
time, and updates come from him.

What this repository adds is a thin layer on top: about 51 patches, 13 files of
my own, and a list of parts I remove (the AI assistant, the `waffle` panel
family, Google Cloud services, upstream's translations). Roughly 2,000 lines
against his 80,000. Every file not in that layer is his, unmodified.

Credit for how the shell looks and works belongs to end-4. If you want it, get
it from [his repository](https://github.com/end-4/dots-hyprland) — and consider
[sponsoring him](https://github.com/sponsors/end-4).

The rest — the Arch installer, the package lists, the symlink and overlay
managers, the KDE profile — is mine.

