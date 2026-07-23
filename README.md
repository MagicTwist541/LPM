# Linux Package Manager (LPM) 🚀

A lightweight, feature-packed terminal application for Arch Linux and rolling distributions. LPM simplifies package management across `pacman`, `AUR` (`paru`/`yay`), and `flatpak`, while providing built-in snapshot backups, custom app bundles, and AppImage integration.

---

## ✨ Key Features

* 🔍 **Multi-Source Search & Install**: Simultaneously search and install packages from official Arch repos, AUR, and Flathub.
* 📦 **AppImage Management**: Automatically moves AppImages, sets execution permissions, and generates `.desktop` menu shortcuts.
* ⭐ **Custom App Bundles**: One-click setup for common package groups:
  * **Gaming Pack** (`steam`, `lutris`, `mangohud`, `gamemode`, `pupgui2`)
  * **Dev Pack** (`git`, `neovim`, `docker`, `tmux`, `vscode`)
  * **Media Pack** (`vlc`, `obs-studio`, `gimp`, `shotcut`)
  * **System Essentials** (`htop`, `fastfetch`, `btop`, `ufw`, `rsync`, `rclone`)
* 📊 **Backup & Restore**:
  * Auto-generates lean JSON system manifests before major changes.
  * System restore capabilities to replicate package environments across setups.
  * Configurable backup destinations (Local, External USB Drives, or Remote/Cloud Mounts).
* 🌐 **Mirror Optimization**: Uses `reflector` to pull and rate top HTTPS mirrors for maximum download speeds.
* 🧹 **System Maintenance**: Easily clear orphan dependencies and package caches.

---

## 🛠️ Usage

### Prerequisites
Make sure you have Python 3 and basic build tools installed on your Arch Linux setup:

```bash
sudo pacman -S python git
