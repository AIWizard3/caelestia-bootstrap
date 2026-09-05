#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------
# Config / Flags
# -----------------------------
DRY_RUN=false
INSTALL_SDDM=true
INSTALL_WALLPAPERS=true
INSTALL_EXTRAS=true

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --no-sddm) INSTALL_SDDM=false ;;
    --no-wallpapers) INSTALL_WALLPAPERS=false ;;
    --no-extras) INSTALL_EXTRAS=false ;;
  esac
done

# -----------------------------
# Logging
# -----------------------------
HOME="${HOME:-$(eval echo ~$(id -un) 2>/dev/null)}"
[[ -z "$HOME" ]] && { echo "❌ Could not determine HOME"; exit 1; }

LOG_FILE="$HOME/caelestia-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -----------------------------
# Error handler
# -----------------------------
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

error_handler() {
  echo
  echo "❌ ERROR"
  echo "Command : $3"
  echo "Line    : $2"
  echo "Code    : $1"
  echo "Log     : $LOG_FILE"
  exit "$1"
}

# -----------------------------
# Helpers
# -----------------------------
step() { echo -e "\n==> $1"; }

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

require() {
  command -v "$1" &>/dev/null || {
    echo "❌ Missing required command: $1"
    exit 1
  }
}

AUR_HELPER=""

ensure_aur_helper() {
  if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
    return
  fi

  if command -v paru &>/dev/null; then
    AUR_HELPER="paru"
    return
  fi

  step "No AUR helper found — building yay from source"

  run sudo pacman -S --needed --noconfirm base-devel

  YAY_TMP_DIR=$(mktemp -d)
  run git clone https://aur.archlinux.org/yay-bin.git "$YAY_TMP_DIR"
  run "cd $YAY_TMP_DIR && makepkg -si --noconfirm"

  AUR_HELPER="yay"
  require "$AUR_HELPER"
}

# -----------------------------
# Safety checks
# -----------------------------
[[ $EUID -eq 0 ]] && {
  echo "❌ Do NOT run as root"
  exit 1
}

require pacman
require git
require sudo

# systemd check
if ! pidof systemd &>/dev/null; then
  echo "⚠️ systemd not detected (SDDM will be skipped)"
  INSTALL_SDDM=false
fi

# network check
ping -c 1 github.com &>/dev/null || {
  echo "❌ No internet connection"
  exit 1
}

# -----------------------------
# System update
# -----------------------------
step "Updating system"
run sudo pacman -Syu --noconfirm

# -----------------------------
# Packages
# -----------------------------
step "Installing packages"
run sudo pacman -S --needed --noconfirm \
  hyprland \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  hyprpicker \
  wl-clipboard \
  cliphist \
  inotify-tools \
  app2unit \
  wireplumber \
  trash-cli \
  foot \
  fish \
  fastfetch \
  starship \
  btop \
  jq \
  eza \
  adw-gtk-theme \
  papirus-icon-theme \
  qt5ct-kde \
  qt6ct-kde \
  ttf-jetbrains-mono-nerd \
  git

require Hyprland
require fish

# -----------------------------
# SDDM (optional)
# -----------------------------
if $INSTALL_SDDM; then
  step "Installing SDDM"

  run sudo pacman -S --needed --noconfirm \
    sddm qt5-graphicaleffects qt5-svg qt5-quickcontrols2

  run sudo systemctl enable sddm

  echo "⚠️ Disabling other display managers"
  run sudo systemctl disable gdm lightdm ly 2>/dev/null || true

  # Theme install
  step "Installing Astronaut theme"

  TMP_DIR=$(mktemp -d)
  git clone https://github.com/Keyitdev/sddm-astronaut-theme.git "$TMP_DIR"

  ASTRONAUT_DIR="/usr/share/sddm/themes/astronaut"

  run sudo rm -rf "$ASTRONAUT_DIR"
  run sudo mv "$TMP_DIR" "$ASTRONAUT_DIR"

  [[ -f "$ASTRONAUT_DIR/theme.conf" ]] || {
    echo "❌ Theme install failed"
    exit 1
  }

  # Config
  step "Configuring SDDM"

  if [[ -f /etc/sddm.conf ]]; then
    run sudo cp /etc/sddm.conf "/etc/sddm.conf.bak.$(date +%s)"
  fi

  run sudo tee /etc/sddm.conf > /dev/null <<EOF
[Theme]
Current=astronaut

[General]
Numlock=on
EOF
fi

# -----------------------------
# Hyprland session
# -----------------------------
step "Ensuring Hyprland session"

SESSION_FILE="/usr/share/wayland-sessions/hyprland.desktop"

if [[ ! -f "$SESSION_FILE" ]]; then
  run sudo tee "$SESSION_FILE" > /dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=Dynamic Wayland Compositor
Exec=Hyprland
Type=Application
EOF
fi

# -----------------------------
# Caelestia dots
# -----------------------------
step "Installing Caelestia"

# The old install.fish script is deprecated. Caelestia is now installed via
# its AUR-packaged CLI, which reads manifest.toml from the dots repo to
# install packages and symlink configs — see caelestia-dots/caelestia's README.
ensure_aur_helper

run "$AUR_HELPER" -S --needed --noconfirm caelestia-cli
require caelestia

DOTS_DIR="$HOME/.local/share/caelestia"
export CAELESTIA_DOTS="$DOTS_DIR"

mkdir -p "$(dirname "$DOTS_DIR")"

if [[ ! -d "$DOTS_DIR" ]]; then
  run git clone https://github.com/caelestia-dots/caelestia.git "$DOTS_DIR"
fi

echo "ℹ️  'caelestia install' may prompt to confirm backing up an existing"
echo "   config directory, and to pick optional components (spotify,"
echo "   vscodium, zed, discord, nvim). Discord and a browser are already"
echo "   installed above, so those two can be skipped unless you also want"
echo "   Caelestia's own theming applied to them."

run caelestia install

# -----------------------------
# Auto-select Hyprland at the SDDM login screen
# -----------------------------
if $INSTALL_SDDM; then
  step "Defaulting login screen to Hyprland"

  CURRENT_USER="$(id -un)"

  # AccountsService is what SDDM reads to pre-select a session, so the very
  # first login (not just subsequent ones) goes straight to Hyprland with no
  # session picker involved — just type the password and hit enter.
  run sudo mkdir -p /var/lib/AccountsService/users
  run sudo tee "/var/lib/AccountsService/users/$CURRENT_USER" > /dev/null <<EOF
[User]
Session=hyprland
XSession=hyprland
EOF

  # Some display managers fall back to ~/.dmrc instead — set it too, cheap insurance.
  if ! $DRY_RUN; then
    cat > "$HOME/.dmrc" <<EOF
[Desktop]
Session=hyprland
EOF
  fi
fi

# -----------------------------
# Ensure the Caelestia shell autostarts on login
# -----------------------------
step "Verifying Caelestia shell autostart"

# 'caelestia install' normally wires this up already via an exec-once in the
# caelestia hyprland config. This is just a safety net in case that line is
# ever missing — it adds the autostart to hypr-user.conf, the sanctioned spot
# for user customizations that caelestia updates won't overwrite.
if ! $DRY_RUN; then
  if ! grep -rq "caelestia shell" "$HOME/.config/hypr" 2>/dev/null \
    && ! grep -rq "caelestia shell" "$DOTS_DIR" 2>/dev/null; then
    echo "⚠️ Caelestia shell autostart not found — adding fallback"

    CAELESTIA_USER_CONF="$HOME/.config/caelestia/hypr-user.conf"
    mkdir -p "$(dirname "$CAELESTIA_USER_CONF")"

    grep -Fxq "exec-once = caelestia shell -d" "$CAELESTIA_USER_CONF" 2>/dev/null \
      || echo "exec-once = caelestia shell -d" >> "$CAELESTIA_USER_CONF"
  fi
fi

# -----------------------------
# Wallpapers (optional)
# -----------------------------
if $INSTALL_WALLPAPERS; then
  step "Installing wallpapers"

  WALL_DIR="$HOME/pictures/wallpapers"
  mkdir -p "$WALL_DIR"

  if [[ ! -d "$WALL_DIR/wallpaper" ]]; then
    run git clone https://github.com/mylinuxforwork/wallpaper.git "$WALL_DIR/wallpaper"
  fi
fi

# -----------------------------
# Essentials: browser + Discord (optional)
# -----------------------------
if $INSTALL_EXTRAS; then
  step "Installing lightweight browser"

  # qutebrowser: keyboard-driven, minimal resource footprint, in the official repos
  run sudo pacman -S --needed --noconfirm qutebrowser

  step "Installing Discord"

  # Discord isn't in the official Arch repos, only the AUR.
  ensure_aur_helper
  run "$AUR_HELPER" -S --needed --noconfirm discord
fi

# -----------------------------
# Wayland fix (idempotent)
# -----------------------------
step "Applying Wayland fix"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
mkdir -p "$(dirname "$HYPR_CONF")"

LINE="exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"

grep -Fxq "$LINE" "$HYPR_CONF" || echo "$LINE" >> "$HYPR_CONF"

# -----------------------------
# Done
# -----------------------------
echo
echo "✅ Installation complete"
echo "➡️ Reboot → login → Hyprland"
echo "📄 Log: $LOG_FILE"
