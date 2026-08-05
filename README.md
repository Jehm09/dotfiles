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
- **This repo stores only the delta**: ~50 patches, 14 files of my own, and a
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
| 5 | Display manager | SDDM + `sddm-astronaut-theme` (hyprland_kath variant) |
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

## Login screen (SDDM + astronaut theme)

SDDM is the display manager for both desktops — it is what lets you pick the
Hyprland or the Plasma session at login. The look is
[Keyitdev/sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme),
`hyprland_kath` variant.

Installed and configured by `setup post` step 5, from
`packages/deps-greeter.conf`. Configuration is split three ways:

| File | What it sets |
|---|---|
| `/etc/sddm.conf.d/10-theme.conf` | selects `sddm-astronaut-theme` |
| `/etc/sddm.conf.d/20-virtualkbd.conf` | the Qt virtual keyboard the theme expects |
| `/etc/sddm.conf.d/30-wayland.conf` | Wayland greeter with the layer-shell integration |

Drop-ins rather than `/etc/sddm.conf`, so pacman never leaves a `.pacnew` to
merge by hand.

**The variant selection is fragile, by design of the theme.** Which variant is
active is stored in `metadata.desktop`, and the screen size inside
`Themes/hyprland_kath.conf` — both under `/usr/share` and owned by the package,
so every upgrade silently reverts them to the `astronaut` variant at 1920x1080.
`packages/hooks/enabled/sddm-astronaut-theme.hook` re-applies both edits after
each upgrade. Change the variant or the resolution in **both** the hook and step
5 of `post-install.sh`, or they will disagree.

To try another variant (`Themes/` in the theme directory lists them all):

```bash
sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/black_hole.conf|' \
    /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sddm-astronaut-theme
```

`--test-mode` draws the greeter in a window, so a change can be checked without
logging out.

**Previous greeter.** This used to be greetd + `sysc-greet-hyprland` running
under niri. greetd is left installed but disabled, so going back is
`sudo systemctl disable sddm && sudo systemctl enable greetd`. To remove it for
good: `paru -Rns greetd greetd-agreety sysc-greet sysc-greet-debug`.

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
    ├── deps-greeter.conf    SDDM + the astronaut login theme
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
Runs as your user after the first boot. The desktop choice is required and has
no default; every step follows from it. Interactive by default, or `--all`.

| # | Step | What it does |
|---|---|---|
| 1 | Multilib | Uncomments `[multilib]` in `pacman.conf`, then `pacman -Sy` |
| 2 | AUR helper | Installs paru (or yay) by cloning and `makepkg -si` |
| 3 | Desktop packages | hyprland → `deps-hyprland.conf` + `deps-quickshell.conf`; kde → `deps-kde.conf` |
| 3b | Plasma session | *(kde only)* KWallet PAM hook in the greetd stack, then `setup kde apply` |
| 3c | Quickshell | *(hyprland only)* `setup upstream deps` for the pinned build, then builds the Python venv from `requirements.txt` |
| 4 | Apps | Everything in `apps.conf`, AUR included, through paru/yay |
| 5 | Display manager | Installs `deps-greeter.conf`, selects the theme variant, writes `/etc/sddm.conf.d/` drop-ins, disables greetd and enables sddm |
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
│   ├── patches/       ~50 diffs             ├── hypr/
│   ├── files/         14 of mine   ──┐     ├── quickshell/ii/
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

The Hyprland and Quickshell configuration is based on
[dots-hyprland by end-4](https://github.com/end-4/dots-hyprland).
Several components have been removed, others added, and the rest adapted to fit
this setup — it is not a straight copy of the original.

