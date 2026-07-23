#!/usr/bin/env bash

TMP_PY=$(mktemp /tmp/lpm_XXXXXX.py)

cat << 'EOF' > "$TMP_PY"
import sys
import os
import json
import subprocess
import shutil
import re
import pty
import select
import time
from pathlib import Path
from datetime import datetime

# Base Paths
HOME = Path.home()
CONFIG_DIR = HOME / ".local/share/lpm"
APPIMAGE_DIR = HOME / "AppImages"
DESKTOP_DIR = HOME / ".local/share/applications"
LOCAL_BACKUP_DIR = CONFIG_DIR / "backups"
HISTORY_FILE = CONFIG_DIR / "history.json"
APPIMAGE_META = CONFIG_DIR / "appimages.json"
SYNC_CONFIG = CONFIG_DIR / "sync_config.json"

CONFIG_DIR.mkdir(parents=True, exist_ok=True)
APPIMAGE_DIR.mkdir(parents=True, exist_ok=True)
DESKTOP_DIR.mkdir(parents=True, exist_ok=True)
LOCAL_BACKUP_DIR.mkdir(parents=True, exist_ok=True)

# Initialize defaults
for path, default in [
    (HISTORY_FILE, []),
    (APPIMAGE_META, {}),
    (SYNC_CONFIG, {"provider": "Local", "path": str(LOCAL_BACKUP_DIR)}),
]:
    if not path.exists() or path.stat().st_size == 0:
        with open(path, "w") as f:
            json.dump(default, f, indent=2)

BUNDLES = {
    "Gaming Pack": {"pacman": ["steam", "lutris", "mangohud", "gamemode"], "flatpak": ["net.davidotek.pupgui2"]},
    "Dev Pack": {"pacman": ["git", "neovim", "docker", "docker-compose", "tmux"], "aur": ["visual-studio-code-bin"]},
    "Media Pack": {"pacman": ["vlc", "obs-studio", "gimp"], "flatpak": ["org.shotcut.Shotcut"]},
    "System Essentials": {"pacman": ["htop", "fastfetch", "btop", "ufw", "rsync", "rclone"]}
}

def get_current_backup_dir():
    try:
        with open(SYNC_CONFIG, "r") as f:
            data = json.load(f)
            p = Path(data.get("path", LOCAL_BACKUP_DIR))
            if p.exists():
                return p
    except Exception:
        pass
    return LOCAL_BACKUP_DIR

def log_transaction(action, name, source, details=""):
    try:
        with open(HISTORY_FILE, "r") as f:
            history = json.load(f)
    except Exception:
        history = []

    history.append({
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "action": action,
        "name": name,
        "source": source,
        "details": details
    })

    with open(HISTORY_FILE, "w") as f:
        json.dump(history, f, indent=2)

# --- LEAN AUTOMATIC RESTORE POINT ENGINE ---
def create_auto_restore_point(label="auto_backup"):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    target_dir = get_current_backup_dir()
    target = target_dir / f"{label}_{timestamp}"
    target.mkdir(parents=True, exist_ok=True)

    manifest = {"timestamp": timestamp, "packages": {}}

    try:
        manifest["packages"]["pacman"] = subprocess.check_output(
            ["pacman", "-Qeq"], text=True
        ).splitlines()
    except Exception:
        manifest["packages"]["pacman"] = []

    if shutil.which("flatpak"):
        try:
            manifest["packages"]["flatpak"] = subprocess.check_output(
                ["flatpak", "list", "--app", "--columns=application"], text=True
            ).splitlines()
        except Exception:
            manifest["packages"]["flatpak"] = []

    try:
        with open(APPIMAGE_META, "r") as f:
            apps = json.load(f)
            manifest["packages"]["appimages"] = list(apps.keys())
    except Exception:
        manifest["packages"]["appimages"] = []

    with open(target / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"📦 Lean backup created at: {target}")

# --- REAL-TIME SMOOTH PROGRESS BAR ENGINE ---
def run_clean_progress(cmd, package_label="Package"):
    print(f"\n🚀 Processing {package_label}...")

    master, slave = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    pct_regex = re.compile(r"(\d{1,3})\%")
    current_pct = 0
    buffer = ""

    while True:
        r, _, _ = select.select([master], [], [], 0.1)
        if master in r:
            try:
                data = os.read(master, 1024)
                if not data:
                    break
                buffer += data.decode("utf-8", errors="ignore")
                matches = pct_regex.findall(buffer)
                if matches:
                    current_pct = min(100, int(matches[-1]))
                if len(buffer) > 2000:
                    buffer = buffer[-500:]
            except OSError:
                break

        bar = '█' * (current_pct // 4) + '░' * (25 - (current_pct // 4))
        sys.stdout.write(f"\r📦 Progress: [{bar}] {current_pct}% ")
        sys.stdout.flush()

        if proc.poll() is not None:
            break

    os.close(master)
    proc.wait()

    if proc.returncode == 0:
        bar = '█' * 25
        sys.stdout.write(f"\r📦 Progress: [{bar}] 100% \n")
        print(f"✅ Successfully finished {package_label}!\n")
    else:
        sys.stdout.write("\n")
        print(f"❌ Operation failed for {package_label}.\n")
    return proc.returncode

# --- SYSTEM RESTORE ENGINE ---
def restore_system():
    print("\n====================================")
    print("        🔄 RESTORE SYSTEM           ")
    print("====================================")

    backup_dir = get_current_backup_dir()
    available_devices = [d.name for d in backup_dir.iterdir() if d.is_dir()] if backup_dir.exists() else []

    if not available_devices:
        print(f"❌ No system profiles found to restore in {backup_dir}.")
        return

    print(f"Select a profile to restore from ({backup_dir}):")
    for idx, dev in enumerate(available_devices, 1):
        print(f"{idx}. {dev}")

    sel = input("\nSelect profile number: ").strip()
    if not sel.isdigit() or not (1 <= int(sel) <= len(available_devices)):
        return

    create_auto_restore_point("pre_restore")
    target_device = available_devices[int(sel) - 1]
    manifest_file = backup_dir / target_device / "manifest.json"

    with open(manifest_file, "r") as f:
        manifest = json.load(f)

    print(f"\n🚀 Restoring system environment from '{target_device}'...")

    pacman_pkgs = manifest.get("packages", {}).get("pacman", [])
    if pacman_pkgs:
        run_clean_progress(["sudo", "pacman", "-S", "--needed", "--noconfirm"] + pacman_pkgs, "Pacman Packages")

    flatpaks = manifest.get("packages", {}).get("flatpak", [])
    if flatpaks and shutil.which("flatpak"):
        for fp in flatpaks:
            run_clean_progress(["flatpak", "install", "-y", "flathub", fp], f"[Flatpak] {fp}")

    log_transaction("Restore", f"Restored from {target_device}", "System Profile")
    print("\n✨ System Restore completed successfully!")

# --- BACKUP & RESTORE MENU ---
def backup_restore_storage_menu():
    print("\n📊 --- Backup & Restore Manager ---")
    print("1. Create New Backup Snapshot Now 📦")
    print("2. Restore System 🔄")
    print("3. Set Storage Destination (Local / External USB / Cloud Share) ⚙️")

    choice = input("\nSelect option (1-3): ").strip()

    if choice == "1":
        label = input("Enter label for this backup (default: manual_backup): ").strip()
        if not label:
            label = "manual_backup"
        create_auto_restore_point(label)

    elif choice == "2":
        restore_system()

    elif choice == "3":
        print("\nSelect Storage Target:")
        print("1. Local Storage (Default: ~/.local/share/lpm/backups)")
        print("2. External Drive (USB / Hard Drive Mount)")
        print("3. Online / Remote Mount (Nextcloud / Tailscale Share Path)")

        target_choice = input("\nSelect target (1-3): ").strip()

        if target_choice == "1":
            path = str(LOCAL_BACKUP_DIR)
            provider = "Local"

        elif target_choice == "2":
            media_path = Path("/run/media") / os.getlogin()
            print(f"\nScanning external mounts in {media_path}...")
            available_mounts = []
            if media_path.exists():
                available_mounts = [d for d in media_path.iterdir() if d.is_dir()]

            if available_mounts:
                print("Detected External Drives:")
                for idx, m in enumerate(available_mounts, 1):
                    print(f"  {idx}. {m}")
                drive_sel = input("Select drive number (or enter custom path): ").strip()
                if drive_sel.isdigit() and 1 <= int(drive_sel) <= len(available_mounts):
                    path = str(available_mounts[int(drive_sel) - 1] / "lpm_backups")
                else:
                    path = drive_sel
            else:
                path = input("Enter mount directory path for external drive: ").strip()

            provider = "External Drive"

        elif target_choice == "3":
            path = input("Enter full path to online/cloud mounted folder: ").strip()
            provider = "Online/Cloud Share"
        else:
            return

        if path:
            dest_path = Path(path)
            dest_path.mkdir(parents=True, exist_ok=True)
            sync_data = {"provider": provider, "path": str(dest_path)}
            with open(SYNC_CONFIG, "w") as f:
                json.dump(sync_data, f, indent=2)
            print(f"✅ Backup destination updated to [{provider}]: {dest_path}")

# --- REFLECTOR MIRROR OPTIMIZER ---
def optimize_mirrors():
    if not shutil.which("reflector"):
        print("\n❌ 'reflector' is not installed. Install it first via option 1.")
        return

    print("\n🌐 Optimizing Arch Linux mirrorlist for maximum download speed...")
    cmd = [
        "sudo", "reflector",
        "--latest", "20",
        "--protocol", "https",
        "--sort", "rate",
        "--save", "/etc/pacman.d/mirrorlist"
    ]
    run_clean_progress(cmd, "Mirror List Optimization")
    log_transaction("Optimize", "Pacman Mirrorlist", "Reflector")

# --- MULTI-SOURCE SEARCH ENGINE ---
def search_packages(query):
    print(f"\n🔍 Searching for '{query}' across all sources...\n")
    results = []

    try:
        pacman_out = subprocess.check_output(["pacman", "-Ss", query], text=True, stderr=subprocess.DEVNULL)
        lines = pacman_out.splitlines()
        for i in range(0, len(lines), 2):
            pkg_info = lines[i].split()
            if pkg_info:
                results.append({"source": "Pacman", "name": pkg_info[0], "desc": lines[i+1].strip() if i+1 < len(lines) else ""})
    except Exception:
        pass

    aur_helper = "paru" if shutil.which("paru") else "yay" if shutil.which("yay") else None
    if aur_helper:
        try:
            aur_out = subprocess.check_output([aur_helper, "-Ss", query], text=True, stderr=subprocess.DEVNULL)
            lines = aur_out.splitlines()
            for i in range(0, len(lines), 2):
                pkg_info = lines[i].split()
                if pkg_info and not any(r["name"] == pkg_info[0] for r in results):
                    results.append({"source": "AUR", "name": pkg_info[0], "desc": lines[i+1].strip() if i+1 < len(lines) else ""})
        except Exception:
            pass

    if shutil.which("flatpak"):
        try:
            fp_out = subprocess.check_output(["flatpak", "search", query], text=True, stderr=subprocess.DEVNULL)
            for line in fp_out.splitlines()[1:6]:
                parts = line.split("\t")
                if len(parts) >= 3:
                    results.append({"source": "Flatpak", "name": parts[2].strip(), "desc": parts[1].strip()})
        except Exception:
            pass

    if not results:
        print("❌ No packages found.")
        return

    for idx, item in enumerate(results[:20], 1):
        print(f"{idx:2d}. [{item['source']}] {item['name']}\n    └─ {item['desc'][:75]}")

    choice = input("\nEnter number to install (or Enter to skip): ").strip()
    if choice.isdigit() and 1 <= int(choice) <= len(results[:20]):
        create_auto_restore_point("pre_install")
        sel = results[int(choice) - 1]
        src, name = sel["source"], sel["name"]

        if src == "Pacman":
            run_clean_progress(["sudo", "pacman", "-S", "--noconfirm", name], f"[{src}] {name}")
        elif src == "AUR":
            run_clean_progress([aur_helper, "-S", "--noconfirm", name], f"[{src}] {name}")
        elif src == "Flatpak":
            run_clean_progress(["flatpak", "install", "-y", "flathub", name], f"[Flatpak] {name}")

        log_transaction("Install", name, src)

# --- APPIMAGE INSTALLER ---
def install_local_appimage():
    path = input("\nEnter full path to .AppImage file: ").strip()
    file_path = Path(path).expanduser()

    if not file_path.exists():
        print("❌ File does not exist.")
        return

    dest = APPIMAGE_DIR / file_path.name

    print(f"\n🚀 Installing AppImage '{file_path.name}'...")
    shutil.copy(file_path, dest)
    dest.chmod(0o755)

    app_name = file_path.stem.replace("-", " ").title()
    desktop_file = DESKTOP_DIR / f"{file_path.stem}.desktop"

    desktop_entry = f"""[Desktop Entry]
Name={app_name}
Exec={dest}
Icon=utilities-terminal
Type=Application
Categories=Utility;
Terminal=false
"""
    with open(desktop_file, "w") as f:
        f.write(desktop_entry)

    try:
        with open(APPIMAGE_META, "r") as f:
            apps = json.load(f)
    except Exception:
        apps = {}

    apps[app_name] = {"path": str(dest), "desktop": str(desktop_file)}
    with open(APPIMAGE_META, "w") as f:
        json.dump(apps, f, indent=2)

    create_auto_restore_point("pre_appimage")
    bar = '█' * 25
    print(f"📦 Progress: [{bar}] 100%")
    log_transaction("Install", app_name, "AppImage")
    print(f"✅ Installed & created shortcut for '{app_name}'!\n")

# --- CUSTOM APP BUNDLES ---
def install_bundles():
    print("\n⭐ --- Custom App Bundles ---")
    for idx, (name, pkgs) in enumerate(BUNDLES.items(), 1):
        print(f"{idx}. {name}")
        for src, items in pkgs.items():
            print(f"   └─ [{src.upper()}] {', '.join(items)}")

    choice = input("\nSelect bundle to install (1-4): ").strip()
    keys = list(BUNDLES.keys())
    if choice.isdigit() and 1 <= int(choice) <= len(keys):
        create_auto_restore_point("pre_bundle")
        b_name = keys[int(choice) - 1]
        bundle = BUNDLES[b_name]

        if "pacman" in bundle:
            for pkg in bundle["pacman"]:
                run_clean_progress(["sudo", "pacman", "-S", "--needed", "--noconfirm", pkg], f"[Pacman] {pkg}")
        if "aur" in bundle:
            helper = "paru" if shutil.which("paru") else "yay"
            for pkg in bundle["aur"]:
                run_clean_progress([helper, "-S", "--needed", "--noconfirm", pkg], f"[AUR] {pkg}")
        if "flatpak" in bundle and shutil.which("flatpak"):
            for pkg in bundle["flatpak"]:
                run_clean_progress(["flatpak", "install", "-y", "flathub", pkg], f"[Flatpak] {pkg}")

        log_transaction("Install Bundle", b_name, "Bundle")
        print(f"🎉 Bundle '{b_name}' installed!")

# --- SYSTEM CLEANER ---
def clean_system():
    print("\n🧹 --- Package & System Cleaner ---")
    try:
        orphans = subprocess.check_output(["pacman", "-Qtdq"], text=True).splitlines()
        if orphans:
            run_clean_progress(["sudo", "pacman", "-Rns", "--noconfirm"] + orphans, "Orphan Removal")
    except Exception:
        pass

    run_clean_progress(["sudo", "pacman", "-Scc", "--noconfirm"], "Pacman Cache Cleanup")

    yay_cache = HOME / ".cache" / "yay"
    if yay_cache.exists():
        shutil.rmtree(yay_cache, ignore_errors=True)

    if shutil.which("flatpak"):
        run_clean_progress(["flatpak", "uninstall", "--unused", "-y"], "Flatpak Runtime Pruning")

    log_transaction("Clean", "System Cache & Orphans", "System")
    print("🎉 System cleanup complete!")

def wait_for_enter():
    input("\n✨ Press [Enter] to return to main menu...")

def main():
    while True:
        os.system("clear" if os.name == "posix" else "cls")

        try:
            with open(SYNC_CONFIG, "r") as f:
                sync_data = json.load(f)
        except Exception:
            sync_data = {"provider": "Local", "path": str(LOCAL_BACKUP_DIR)}

        print("==============================================")
        print("    🚀 LINUX PACKAGE MANAGER v10.5")
        print(f"    ☁️ Active Location: {sync_data.get('provider')} ({sync_data.get('path')})")
        print("==============================================")
        print("1. Search & Install Packages 🔍")
        print("2. Install AppImage + Desktop Shortcut 📦")
        print("3. Install Custom App Bundles ⭐")
        print("4. Backup & Restore 📊")
        print("5. Optimize Arch Mirrors (Reflector) 🌐")
        print("6. Clean Orphans & Caches 🧹")
        print("7. Exit")

        try:
            choice = input("\nSelect option (1-7): ").strip()
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)

        if choice == "1":
            q = input("Search query: ").strip()
            if q:
                search_packages(q)
            wait_for_enter()
        elif choice == "2":
            install_local_appimage()
            wait_for_enter()
        elif choice == "3":
            install_bundles()
            wait_for_enter()
        elif choice == "4":
            backup_restore_storage_menu()
            wait_for_enter()
        elif choice == "5":
            optimize_mirrors()
            wait_for_enter()
        elif choice == "6":
            clean_system()
            wait_for_enter()
        elif choice == "7":
            sys.exit(0)

if __name__ == "__main__":
    main()
EOF

python3 "$TMP_PY"
rm -f "$TMP_PY"
