# MB-OS — Custom Linux Desktop Distribution

> Ein intelligentes, modernes Linux-Betriebssystem mit Qt6/QML Desktop-Shell, AI-Integration und Glassmorphism-Design.

![MB-OS](gui/assets/wallpaper.png)

## Features

### 🖥️ Desktop Shell (Qt6/QML)
- **Glassmorphism Design** mit HSL-basiertem Wallpaper-Color-Extraction (automatische Theme-Anpassung)
- **App Drawer** mit 25+ vorinstallierten Apps
- **System Monitor** in der Topbar: CPU, RAM, GPU, Temperatur
- **Per-Core CPU Overlay** — klickbar für detaillierte Kernauslastung
- **Micro-Animationen**, Hover-Effekte, dynamische Farbpaletten
- **Kontextmenü** (Rechtsklick auf Desktop)
- **Bildschirmsperre** (i3lock)

### 🌐 Web & Apps
- **MB Browser** (Firefox-basiert mit Wrapper-Script)
- **Tor/Darkweb** Toggle (`--tor` Flag, SOCKS5 Proxy, separates Profil)
- **WhatsApp Web** — direkt aus dem App Drawer
- **Google Maps** — Web-App Integration
- **OOONO** — Verkehrswarner Web-App
- **ChatGPT, GitHub, YouTube** — Quick-Launch aus dem Drawer

### 🤖 AI Integration
- **Antigravity CLI** (`agy`) — Google Gemini AI Agent
- **Antigravity Desktop App** (Electron)
- **Memory Daemon** — SQLite + Markdown basiertes Langzeitgedächtnis

### 📱 Android (Waydroid)
- **Waydroid** für Android-App-Emulation (auf kompatiblen Systemen)
- **Weston** als Wayland-Compositor
- Kernel Binder-Modul Unterstützung

### 🔧 System
- **UEFI Boot** mit GRUB Theme (Cyan/Blau Design)
- **Calamares Installer** mit automatischem GRUB-Repair
- **SSH Server** (Key-Auth vorinstalliert)
- **xRDP** Remote Desktop
- **WiFi** (NetworkManager + wpa_supplicant)
- **Bluetooth** (BlueZ)
- **Audio** (PipeWire + WirePlumber)
- **USB Automount** (udisks2)
- **Firewall** (UFW)
- **Flatpak + Flathub**

### 🎮 Hardware-Support
- **NVIDIA CUDA/RTX** (nvidia-driver-560 + cuda-toolkit)
- **Intel HD Graphics** (i915, GPU-Monitoring)
- **OpenVINO + ONNX Runtime** (CPU AI Inference)
- **Vulkan SDK**

## Technischer Stack

| Komponente | Technologie |
|---|---|
| Basis | Ubuntu 26.04 (Resolute) |
| Desktop Shell | Qt6 6.10.2 / QML / C++ |
| AI Backend | Python FastAPI + SQLite |
| Browser | Firefox .deb (PPA mozillateam) |
| Privacy | Tor, SOCKS5 Proxy |
| Audio | PipeWire + WirePlumber |
| Init | systemd |
| Kernel | 7.0.x |

## Build

### Voraussetzungen
- Windows 11 mit WSL2 (Ubuntu 26.04)
- ~20 GB freier Speicher
- Qt6 Development Packages in WSL

### ISO bauen
```bash
# In WSL2:
cd /mnt/d/MB-OS
sudo bash build_iso.sh
```

### Schnelles ISO-Patching (3 Min statt 15 Min)
```bash
sudo bash patch_iso.sh
```

### Shell kompilieren
```bash
cd /mnt/d/MB-OS/gui
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### USB-Stick schreiben (PowerShell als Admin)
```powershell
.\write_usb.ps1
```

## Installation

1. USB-Stick erstellen mit `write_usb.ps1`
2. Von USB booten (UEFI)
3. **Calamares** Installer starten (im App Drawer)
4. Nach Installation: System bootet automatisch mit GRUB

### UEFI Boot Fix
Falls das System nach Installation nicht bootet:
```bash
# Von USB-Stick booten, dann:
sudo mount /dev/sdaX /mnt
sudo mount /dev/sdaY /mnt/boot/efi
sudo chroot /mnt
apt install grub-efi-amd64 grub-efi-amd64-bin efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
update-grub
```

## Remote Deployment (SSH)
```bash
# Shell-Binary deployen:
scp mb-os-shell mbuser@<IP>:/tmp/
ssh mbuser@<IP> "sudo killall mb-os-shell; sudo cp /tmp/mb-os-shell /usr/local/bin/; sudo chmod +x /usr/local/bin/mb-os-shell"
```

## Projektstruktur

```
MB-OS/
├── build_iso.sh          # Haupt-Build-Script
├── patch_iso.sh          # Schnelles ISO-Patching
├── patch_calamares.sh    # Calamares + GRUB Fix
├── write_usb.ps1         # USB-Stick Flasher
├── gui/                  # Qt6/QML Desktop Shell
│   ├── main.cpp          # SystemMonitor (CPU/RAM/GPU/Temp)
│   ├── main.qml          # Desktop UI + App Drawer
│   ├── ThemeManager.cpp  # Wallpaper Color Extraction
│   └── assets/           # Wallpaper, Icons
├── config/               # System-Konfiguration
│   ├── mb-os-xinitrc     # X11 Autostart
│   ├── mb-browser        # Firefox Wrapper + Tor
│   └── fix-efi-boot.sh   # GRUB Repair Script
├── calamares/            # Installer-Konfiguration
├── installer/            # TUI Installer
├── grub-theme/           # GRUB Boot Theme
└── daemon/               # Memory Daemon (Python)
```

## Hardware-Zielgeräte

| Gerät | CPU | RAM | GPU | Status |
|---|---|---|---|---|
| Acer Laptop | i3-5005U | 4 GB | Intel HD 5500 | ✅ Läuft |
| Desktop PC | diverse | 16+ GB | RTX | ✅ Unterstützt |
| Low-End | Celeron | 2+ GB | Intel | ✅ Unterstützt |

## Lizenz

MIT

## Autor

**MicBur** — [github.com/MicBur](https://github.com/MicBur)
