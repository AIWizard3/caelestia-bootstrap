#!/usr/bin/env bash

# ---------------------------------
# Strict mode (without fragile -u)
# ---------------------------------
set -Ee -o pipefail

# Ensure HOME exists
HOME="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
if [[ -z "$HOME" ]]; then
  echo "❌ Could not determine HOME directory"
  exit 1
fi

LOG_FILE="$HOME/caelestia-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------
# Error handling
# ---------------------------------
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

error_handler() {
  echo
  echo "❌ ERROR"
  echo "  Command : $3"
  echo "  Line    : $2"
  echo "  Code    : $1"
  echo "📄 Log    : $LOG_FILE"
  exit "$1"
}

step() {
  echo
  echo "==> $1"
}

require() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌ Required command '$1' not found"
    exit 1
  fi
}

# ---------------------------------
# Preconditions
# ---------------------------------
require pacman
require git
require sudo

# ---------------------------------
# Update system
# ---------------------------------
step "Updating system"
sudo pacman -Syu --noconfirm

# ---------------------------------
# Install packages
# ---------------------------------
step "Installing required packages"
sudo pacman -S --needed --noconfirm \
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

# ---------------------------------
# Validate Hyprland installation
# ---------------------------------
if ! command -v Hyprland &>/dev/null; then
  echo "❌ Hyprland was not installed correctly"
  exit 1
fi

# ---------------------------------
# Install SDDM
# ---------------------------------
step "Installing SDDM"
sudo pacman -S --needed --noconfirm \
  sddm \
  qt5-graphicaleffects \
  qt5-svg \
  qt5-quickcontrols2

sudo systemctl enable sddm

if ! systemctl is-enabled sddm &>/dev/null; then
  echo "❌ Failed to enable SDDM"
  exit 1
fi

sudo systemctl disable gdm lightdm ly 2>/dev/null || true

# ---------------------------------
# Astronaut theme
# ---------------------------------
step "Installing Astronaut SDDM theme"

ASTRONAUT_DIR="/usr/share/sddm/themes/astronaut"

if [[ ! -d "$ASTRONAUT_DIR" ]]; then
  git clone https://github.com/Keyitdev/sddm-astronaut-theme.git /tmp/astronaut
  sudo mv /tmp/astronaut "$ASTRONAUT_DIR"
fi

if [[ ! -f "$ASTRONAUT_DIR/theme.conf" ]]; then
  echo "❌ Astronaut theme installation incomplete"
  exit 1
fi

# ---------------------------------
# Backup and configure SDDM
# ---------------------------------
step "Configuring SDDM"

if [[ -f /etc/sddm.conf ]]; then
  sudo cp /etc/sddm.conf /etc/sddm.conf.bak.$(date +%s)
  echo "📦 Existing SDDM config backed up"
fi

sudo tee /etc/sddm.conf > /dev/null <<EOF
[Theme]
Current=astronaut

[General]
Numlock=on
EOF

# ---------------------------------
# Hyprland session entry
# ---------------------------------
step "Ensuring Hyprland session entry"

SESSION_FILE="/usr/share/wayland-sessions/hyprland.desktop"

if [[ ! -f "$SESSION_FILE" ]]; then
  sudo tee "$SESSION_FILE" > /dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=Dynamic Wayland Compositor
Exec=Hyprland
Type=Application
EOF
fi

# ---------------------------------
# Caelestia dots
# ---------------------------------
step "Installing Caelestia dots"

mkdir -p "$HOME/.local/share"

if [[ ! -d "$HOME/.local/share/caelestia" ]]; then
  git clone https://github.com/caelestia-dots/caelestia.git "$HOME/.local/share/caelestia"
fi

INSTALL_FISH="$HOME/.local/share/caelestia/install.fish"

if [[ -f "$INSTALL_FISH" ]]; then
  fish "$INSTALL_FISH"
else
  echo "❌ Caelestia install.fish not found"
  exit 1
fi

# ---------------------------------
# Wallpapers (safe cd)
# ---------------------------------
step "Installing wallpapers"

mkdir -p "$HOME/pictures/wallpapers"
cd "$HOME/pictures/wallpapers" || {
  echo "❌ Failed to cd into wallpapers directory"
  exit 1
}

if [[ ! -d wallpaper ]]; then
  git clone https://github.com/mylinuxforwork/wallpaper.git
fi

# ---------------------------------
# Wayland / VM fix
# ---------------------------------
step "Applying Wayland environment fix"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
mkdir -p "$(dirname "$HYPR_CONF")"

grep -q "dbus-update-activation-environment" "$HYPR_CONF" 2>/dev/null || \
  echo "exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" \
  >> "$HYPR_CONF"

# ---------------------------------
# Done
# ---------------------------------
echo
echo "✅ Installation complete"
echo "➡️  Reboot → Astronaut SDDM → Hyprland"
echo "📄 Log: $LOG_FILE"
