# caelestia-bootstrap

Opinionated Arch Linux bootstrap for Hyprland using [Caelestia dots](https://github.com/caelestia-dots/caelestia).

## Assumptions

This script assumes:

- A working Arch Linux install
- A normal user with sudo access
- Internet connectivity
- GPU drivers already installed (mesa / NVIDIA / AMD)
- You are **NOT** running from the Arch ISO

If you don't know what these mean, do not run the script.

## ▶️ Installation

Clone the repository:

```
git clone https://github.com/AIWizard3/caelestia-bootstrap.git
```

```
cd caelestia-bootstrap
```

Make the script executable:

```
chmod +x caelestia-bootstrap.sh
```

Run it as a normal user:

```
./caelestia-bootstrap.sh
```

You will be prompted for your sudo password when required.

## What it installs

- **Hyprland** and its portals, plus a set of core CLI/quality-of-life packages (fish, foot, btop, starship, fastfetch, etc.)
- **SDDM** with the Astronaut login theme, set to auto-select the Hyprland session so logging in goes straight to your desktop — no session picker
- **Caelestia dots**, installed via the official `caelestia-cli` (AUR) and `caelestia install`, which reads the project's `manifest.toml` to install packages and symlink configs
- A lightweight browser (**qutebrowser**) and **Discord**, installed via an AUR helper (uses `yay`/`paru` if present, otherwise builds `yay` from source)
- Desktop wallpapers from [mylinuxforwork/wallpaper](https://github.com/mylinuxforwork/wallpaper)
- A small Wayland environment-variable fix appended to your Hyprland config

Everything is written to be idempotent — re-running the script won't duplicate config lines or re-clone existing repos.

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print every command instead of running it |
| `--no-sddm` | Skip installing/configuring SDDM |
| `--no-wallpapers` | Skip cloning the wallpaper pack |
| `--no-extras` | Skip installing the browser and Discord |

Example:

```
./caelestia-bootstrap.sh --no-wallpapers --dry-run
```

## Heads-up: one interactive step

`caelestia install` itself may prompt you to:

- confirm backing up an existing config directory, and
- choose optional Caelestia components (Spotify, VSCodium, Zed, Discord, Neovim)

A couple of things worth knowing before you answer those prompts:

- Caelestia's own "discord" component installs **`equibop-bin`** (a modded Discord client), not vanilla Discord. This script already installs the real `discord` package separately, so saying yes here gets you both.
- Caelestia's **Firefox** component is enabled by default, so you'll end up with Firefox alongside `qutebrowser` unless you deselect it.

## Logs

Every run is logged to `~/caelestia-install.log` (via `tee`), so you can review or share it if something goes wrong.

## Safety checks

The script will refuse to run if:

- you run it as root
- `pacman`, `git`, or `sudo` are missing
- there's no internet connection

If systemd isn't detected, SDDM installation is skipped automatically.
