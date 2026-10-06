#!/usr/bin/env bash
# Installs on vanilla Arch: NVIDIA open driver, Hyprland, Noctalia (v5) and helpers.
# Does NOT touch your Hyprland/Noctalia config files.
#
# Usage:          bash install-hypr-noctalia.sh
# Optional early loading of NVIDIA modules in the initramfs:
#                 EARLY_KMS=1 bash install-hypr-noctalia.sh

set -euo pipefail

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- checks ----------
[[ $EUID -eq 0 ]] && die "Run as your normal user (not root). The script uses sudo when needed."
command -v pacman >/dev/null || die "pacman not found - this script is for Arch Linux."
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "No internet. Connect first (nmtui)."

say "Asking for sudo once"
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null || true' EXIT

# ---------- 1. full system update ----------
say "Updating system"
sudo pacman -Syu --noconfirm

# ---------- 2. pick the NVIDIA driver package for installed kernel(s) ----------
say "Detecting kernel(s)"
kernels=()
for f in /usr/lib/modules/*/pkgbase; do
  [[ -r "$f" ]] && kernels+=("$(<"$f")")
done
[[ ${#kernels[@]} -eq 0 ]] && kernels=(linux)
echo "Kernels: ${kernels[*]}"

if   [[ ${#kernels[@]} -eq 1 && ${kernels[0]} == linux     ]]; then
  nvidia_pkgs=(nvidia-open)                       # prebuilt stock module
elif [[ ${#kernels[@]} -eq 1 && ${kernels[0]} == linux-lts ]]; then
  nvidia_pkgs=(nvidia-open-lts)                   # prebuilt LTS module
else
  nvidia_pkgs=(dkms nvidia-open-dkms)             # dynamic kernel module build
  for k in "${kernels[@]}"; do
    if pacman -Si "${k}-headers" >/dev/null 2>&1; then
      nvidia_pkgs+=("${k}-headers")
    else
      say "Warning: ${k}-headers not found in pacman repos. Ensure custom headers are installed manually."
    fi
  done
fi

nvidia_pkgs+=(libva-nvidia-driver)

main_pkgs=(
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  qt5-wayland qt6-wayland polkit
  upower power-profiles-daemon
  bluez bluez-utils
  pipewire pipewire-pulse wireplumber sof-firmware
  kitty thunar
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  noctalia
)

# ---------- 3. verify package availability ----------
say "Checking package availability in configured repos"
missing=0
for p in "${nvidia_pkgs[@]}" "${main_pkgs[@]}"; do
  if ! pacman -Si "$p" >/dev/null 2>&1; then
    echo "  not found in repos: $p"; missing=1
  fi
done
[[ $missing -eq 0 ]] || die "Some packages were not found (see above). Check your pacman mirrors and retry."

# ---------- 4. install ----------
say "Installing NVIDIA driver: ${nvidia_pkgs[*]}"
sudo pacman -S --needed --noconfirm "${nvidia_pkgs[@]}"

say "Installing Hyprland, Noctalia and essentials"
sudo pacman -S --needed --noconfirm "${main_pkgs[@]}"

# ---------- 5. optional early KMS ----------
if [[ "${EARLY_KMS:-0}" == "1" ]]; then
  say "Enabling early loading of NVIDIA modules (EARLY_KMS=1)"
  sudo mkdir -p /etc/mkinitcpio.conf.d
  echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' | sudo tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null
  sudo mkinitcpio -P
fi

# ---------- 6. services ----------
say "Enabling services"
sudo systemctl enable --now bluetooth.service power-profiles-daemon.service upower.service

# ---------- done ----------
say "All done."
echo "1) Ensure your bootloader includes: nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
echo "2) Reboot:                          sudo reboot"
echo "3) Log in on TTY, run:              Hyprland"
echo "4) Check NVIDIA DRM is active:      cat /sys/module/nvidia_drm/parameters/modeset (should print Y)"
