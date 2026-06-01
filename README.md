# dotfiles

Personal dotfiles for Arch Linux with Hyprland.

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
./setup post
```

Shows an interactive menu to select what to install:

| # | Component | Description |
|---|-----------|-------------|
| 1 | Multilib | Repository for Steam and 32-bit apps |
| 2 | AUR helper | paru or yay |
| 3 | AUR packages | Packages from `packages/aur.conf` |
| 4 | Greeter | greetd + sysc-greet-hyprland + seatd |
| 5 | Pacman hooks | Hooks from `packages/hooks/enabled/` |
| 6 | Dotfiles | Symlinks from `dots/.config/` → `~/.config/` |
| 7 | Fish shell | Set fish as the default shell |

### Dotfiles only

```bash
./setup dotfiles
./setup dotfiles --dry-run   # preview changes without applying them
./setup dotfiles --unlink    # remove symlinks and restore backups
```

## Command reference
a
```
./setup                  Interactive menu
./setup install          Install Arch from the live ISO  (root)
./setup post             Interactive post-install setup
./setup post --all       Post-install without prompting
./setup dotfiles         Link ~/.config
./setup --help           Show help
```

## Structure

```
dotfiles/
├── setup                    Main entry point
├── cmd/
│   ├── lib/
│   │   ├── utils.sh         Shared functions (colors, sudo keepalive, etc.)
│   │   └── symlink.sh       Dotfiles symlink manager
│   └── arch/
│       ├── install.sh       Arch installer via archinstall
│       ├── post-install.sh  Post-install setup
│       └── archinstall/
│           ├── user_configuration.json   archinstall config (kernel, locale, mirrors...)
│           └── user_credentials.json     Encrypted credentials (argon2id)
├── dots/
│   └── .config/             App configs — symlinked to ~/.config/
└── packages/
    ├── apps.conf            Pacman packages (injected into archinstall)
    ├── aur.conf             AUR packages (installed during post)
    ├── dependencies.conf    UI fonts/symbols needed before launching Hyprland
    ├── hyprland.conf        Hyprland WM + Wayland session tools
    ├── quickshell.conf      Quickshell runtime + widget backends
    └── hooks/
        ├── enabled/         Active pacman hooks
        └── disabled/        Inactive hooks
```

## Adding an app config

Drop its folder into `dots/.config/` and run `./setup dotfiles`:

```bash
mkdir -p dots/.config/nvim
# copy or create your config files in dots/.config/nvim/
./setup dotfiles
```

## Adding packages

- **Pacman** (installed during `setup install`): add to `packages/apps.conf`
- **AUR** (installed during `setup post`): add to `packages/aur.conf`

### Hyprland / Quickshell dependencies

The desktop (Hyprland + Quickshell) deps are declared as plain packages so they
update normally with `yay -Syu` — no pinned `makepkg` builds:

```bash
paru -S --needed - < packages/hyprland.conf
paru -S --needed - < packages/quickshell.conf
```

## Credits

The Hyprland and Quickshell configuration is based on
[dots-hyprland by end-4](https://github.com/end-4/dots-hyprland).
Several components have been removed, others added, and the rest adapted to fit
this setup — it is not a straight copy of the original.

