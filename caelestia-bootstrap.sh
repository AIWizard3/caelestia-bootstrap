#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------
# Config / Flags
# -----------------------------
DRY_RUN=false
INSTALL_SDDM=true
INSTALL_WALLPAPERS=true
INSTALL_EXTRAS=true   # polkit agent, network manager, bluetooth, lock/idle, etc.

for arg in "$@"; do
  case $arg in
    --dry-run)        DRY_RUN=true ;;
    --no-sddm)        INSTALL_SDDM=false ;;
    --no-wallpapers)  INSTALL_WALLPAPERS=false ;;
    --no-extras)      INSTALL_EXTRAS=false ;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]
  --dry-run         Print commands instead of running them
  --no-sddm         Skip installing/configuring SDDM + Astronaut theme
  --no-wallpapers   Skip cloning the wallpaper pack
  --no-extras       Skip QoL extras (polkit agent, NetworkManager, Bluetooth,
                     hyprlock/hypridle, notifications, screenshots, etc.)
  -h, --help        Show this help
EOF
      exit 0
      ;;
    *)
      echo "⚠️  Unknown option: $arg (use --help to see valid options)"
      ;;
  esac
done

# -----------------------------
# Logging
# -----------------------------
HOME="${HOME:-$(eval echo ~"$(id -un)" 2>/dev/null)}"
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

# Runs a command safely (no eval, so quoting/spaces/globs behave correctly).
# Always pass args as separate words: run sudo pacman -S foo bar
run() {
  if $DRY_RUN; then
    printf '[dry-run]'; printf ' %q' "$@"; echo
  else
    "$@"
  fi
}

require() {
  command -v "$1" &>/dev/null || {
    echo "❌ Missing required command: $1"
    exit 1
  }
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

# network check (curl over HTTPS is more reliable than ICMP, which is
# frequently blocked by firewalls/VPNs even when the network is fine)
if command -v curl &>/dev/null; then
  curl -fsSL --max-time 5 -o /dev/null https://github.com || {
    echo "❌ No internet connection (HTTPS check failed)"
    exit 1
  }
else
  ping -c 1 -W 5 github.com &>/dev/null || {
    echo "❌ No internet connection"
    exit 1
  }
fi

# -----------------------------
# AUR helper (needed: qt5ct-kde, qt6ct-kde, app2unit are AUR-only)
# -----------------------------
AUR_HELPER=""
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
fi

if [[ -z "$AUR_HELPER" ]]; then
  step "No AUR helper found — installing yay"
  TMP_YAY=$(mktemp -d)
  run git clone https://aur.archlinux.org/yay-bin.git "$TMP_YAY"
  if ! $DRY_RUN; then
    (cd "$TMP_YAY" && makepkg -si --noconfirm)
  fi
  AUR_HELPER="yay"
fi

aur_install() {
  run "$AUR_HELPER" -S --needed --noconfirm "$@"
}

# -----------------------------
# System update
# -----------------------------
step "Updating system"
run sudo pacman -Syu --noconfirm

# -----------------------------
# Official repo packages
# -----------------------------
step "Installing packages (official repos)"
run sudo pacman -S --needed --noconfirm \
  hyprland \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  hyprpicker \
  wl-clipboard \
  cliphist \
  inotify-tools \
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
  qt5ct \
  qt6ct \
  ttf-jetbrains-mono-nerd \
  git

# -----------------------------
# AUR packages
# -----------------------------
step "Installing packages (AUR)"
aur_install app2unit qt5ct-kde qt6ct-kde

require Hyprland
require fish

# -----------------------------
# Desktop QoL extras (optional)
# -----------------------------
if $INSTALL_EXTRAS; then
  step "Installing desktop extras (polkit, network, bluetooth, lock/idle, utils)"

  run sudo pacman -S --needed --noconfirm \
    hyprpolkitagent \
    networkmanager \
    network-manager-applet \
    bluez \
    bluez-utils \
    blueman \
    hyprlock \
    hypridle \
    mako \
    grim \
    slurp \
    hyprshot \
    brightnessctl \
    hyprsunset \
    rofi-wayland \
    pavucontrol

  run sudo systemctl enable NetworkManager
  run sudo systemctl enable bluetooth
fi

# -----------------------------
# SDDM (optional)
# -----------------------------
if $INSTALL_SDDM; then
  step "Installing SDDM"

  run sudo pacman -S --needed --noconfirm \
    sddm qt5-graphicaleffects qt5-svg qt5-quickcontrols2

  run sudo systemctl enable sddm

  echo "⚠️ Disabling other display managers"
  for dm in gdm lightdm ly; do
    if systemctl is-enabled "$dm" &>/dev/null; then
      run sudo systemctl disable "$dm"
    fi
  done

  # Theme install
  step "Installing Astronaut theme"

  TMP_DIR=$(mktemp -d)
  run git clone https://github.com/Keyitdev/sddm-astronaut-theme.git "$TMP_DIR"

  ASTRONAUT_DIR="/usr/share/sddm/themes/astronaut"

  run sudo rm -rf "$ASTRONAUT_DIR"
  run sudo mv "$TMP_DIR" "$ASTRONAUT_DIR"

  if ! $DRY_RUN; then
    [[ -f "$ASTRONAUT_DIR/theme.conf" ]] || {
      echo "❌ Theme install failed"
      exit 1
    }
  fi

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

DOTS_DIR="$HOME/.local/share/caelestia"

mkdir -p "$(dirname "$DOTS_DIR")"

if [[ ! -d "$DOTS_DIR" ]]; then
  run git clone https://github.com/caelestia-dots/caelestia.git "$DOTS_DIR"
fi

INSTALL_FISH="$DOTS_DIR/install.fish"

if ! $DRY_RUN; then
  [[ -f "$INSTALL_FISH" ]] || {
    echo "❌ install.fish missing"
    exit 1
  }
fi

run fish "$INSTALL_FISH"

# -----------------------------
# Wallpapers (optional)
# -----------------------------
if $INSTALL_WALLPAPERS; then
  step "Installing wallpapers"

  # Respect XDG user dirs if set, otherwise fall back sanely
  PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
  WALL_DIR="$PICTURES_DIR/wallpapers"
  mkdir -p "$WALL_DIR"

  if [[ ! -d "$WALL_DIR/wallpaper" ]]; then
    run git clone https://github.com/mylinuxforwork/wallpaper.git "$WALL_DIR/wallpaper"
  fi
fi

# -----------------------------
# Wayland fix (idempotent)
# -----------------------------
step "Applying Wayland fix"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
mkdir -p "$(dirname "$HYPR_CONF")"
touch "$HYPR_CONF"

LINE="exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"

if ! grep -Fxq "$LINE" "$HYPR_CONF"; then
  if $DRY_RUN; then
    echo "[dry-run] append to $HYPR_CONF: $LINE"
  else
    echo "$LINE" >> "$HYPR_CONF"
  fi
fi

if $INSTALL_EXTRAS; then
  POLKIT_LINE="exec-once = systemctl --user start hyprpolkitagent"
  if ! grep -Fxq "$POLKIT_LINE" "$HYPR_CONF"; then
    if $DRY_RUN; then
      echo "[dry-run] append to $HYPR_CONF: $POLKIT_LINE"
    else
      echo "$POLKIT_LINE" >> "$HYPR_CONF"
    fi
  fi
fi

# -----------------------------
# Done
# -----------------------------
echo
echo "✅ Installation complete"
echo "➡️ Reboot → login → Hyprland"
echo "📄 Log: $LOG_FILE"
