# dotfiles

Personal dotfiles for Arch Linux, with a choice of two desktops: **Hyprland +
Quickshell** or **KDE Plasma 6**. Pick one at install time — every step follows
from that choice.

## Quick install

### 1. From the Arch live ISO

```bash
# As root
git clone <repo> dotfiles && cd dotfiles
./setup install
# Reboot when done
```

### 2. Post-install (first boot)

```bash
./setup post --hyprland     # Hyprland + Quickshell
./setup post --kde          # KDE Plasma
```

**The desktop is a required choice.** There is no default and no fallback: the
packages installed, the dotfiles linked and the session configured all follow
from it. Without `--hyprland` or `--kde` (or `d` in the menu) the script stops.

The interactive menu lets you pick the desktop and toggle each component:

| # | Component | Description |
|---|-----------|-------------|
| 1 | Multilib | Repository for Steam and 32-bit apps |
| 2 | AUR helper | paru or yay |
| 3 | Desktop packages | hyprland → `deps-hyprland.conf` + `deps-quickshell.conf`<br>kde → `deps-kde.conf`, then the `dots/kde/` profile and the KWallet PAM hook |
| 4 | Apps | `packages/apps.conf` (official + AUR) |
| 5 | Greeter | greetd + sysc-greet-hyprland + seatd |
| 6 | Pacman hooks | Hooks from `packages/hooks/enabled/` |
| 7 | Dotfiles | Symlinks for the chosen desktop |
| 8 | Fish shell | Set fish as the default shell |
| 9 | Hardware fixes | Logitech mouse blacklist + initramfs rebuild |

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
./setup post --kde --desktop-only   # just deps-kde.conf + the profile

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

## Command reference

```
./setup                  Interactive menu
./setup install          Install Arch from the live ISO  (root)
./setup post             Interactive post-install setup
./setup post --hyprland  Post-install with Hyprland as the desktop
./setup post --kde       Post-install with KDE Plasma as the desktop
./setup post --all --kde Post-install without prompting
./setup dotfiles hyprland|kde   Link ~/.config for that desktop
./setup kde apply|save|diff   KDE Plasma profile (copy-managed)
./setup kde theme        Apply the appearance stack (dots/kde/theme.sh)
./setup kde panel        Save the panel layout  (--restore to put it back)
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
    ├── requirements.txt     Python venv for the shell's helper scripts
    ├── modprobe/            Kernel module config installed to /etc/modprobe.d/
    └── hooks/
        ├── enabled/         Active pacman hooks
        └── disabled/        Inactive hooks
```

## Upstream shell (end-4/dots-hyprland)

The Hyprland and Quickshell code is **not** vendored here. Only our delta is —
about 52 patches, 14 own files and a removal list, roughly 2,000 lines. Upstream
is cloned to `$XDG_DATA_HOME/dotfiles/upstream` (outside git) and the working
tree is rebuilt there from `overlay/hyprland/`.

The clone carries two branches: `base`, the locked upstream commit, and `mine`,
`base` plus the overlay. Because `mine` descends from a real upstream commit,
updating is a genuine three-way merge — conflicts can only appear in files we
actually patched, and the ~600 files we don't touch update by themselves.

```bash
setup upstream status     # what is pinned, how far behind, anything unexported
setup upstream update     # fetch + merge; stops and lists conflicts if any
# resolve conflicts in the clone if it stopped
setup upstream export     # write the result back into overlay/
git add overlay && git commit
```

Nothing forces an update: if a merge looks bad, `git -C <clone> merge --abort`
leaves you on the commit in `upstream.lock`.

**Editing the shell.** `~/.config/quickshell/prism` and `~/.config/hypr` are
symlinks into the clone, so live edits land there, not in this repo. Run
`setup upstream export` before committing to pull them back into `overlay/`.

**Naming.** The overlay keeps upstream's `ii` naming throughout; the `prism` name
comes from the symlink, since Quickshell takes the config name from the directory
under `~/.config/quickshell` rather than from the link target. Renaming inside the
tree would cost ~180 renamed paths on every merge and buys nothing visible.

**What is not linked.** `UPSTREAM_LINK` in `cmd/lib/symlink.sh` is a whitelist:
`hypr`, `fuzzel`, `matugen`, `Kvantum`, `wlogout`, `kde-material-you-colors`, plus
quickshell and the portal file. Upstream also ships kitty, foot, fish, mpv,
`zshrc.d` and `starship.toml` — none are linked, so `dots/common/` stays in charge.

**quickshell's version.** Upstream pins one package and only one: quickshell
itself, by commit. `setup upstream deps` builds that PKGBUILD from the clone, so
the pin follows `upstream.lock`. Everything else (`hyprland`, `hypridle`, qt6…) is
unversioned upstream too, and comes from `packages/deps-*.conf` as usual.

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
`## AUR only` marker are injected into the archinstall config by `setup install`;
everything in the file is installed by `setup post`, which uses paru/yay and so
handles official repos and the AUR transparently.

### Desktop dependencies

Desktop deps are declared as plain packages so they update normally with
`paru -Syu`:

```bash
paru -S --needed - < packages/deps-hyprland.conf
paru -S --needed - < packages/deps-quickshell.conf
paru -S --needed - < packages/deps-kde.conf
```

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

The Hyprland and Quickshell configuration is based on
[dots-hyprland by end-4](https://github.com/end-4/dots-hyprland).
Several components have been removed, others added, and the rest adapted to fit
this setup — it is not a straight copy of the original.

