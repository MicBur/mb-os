# MB-OS

> Ein schlankes, sicheres Linux-Betriebssystem mit Qt6/QML Desktop-Shell, AI-Gedächtnissystem und Privacy-Features.

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Ubuntu](https://img.shields.io/badge/Base-Ubuntu%2024.04-orange.svg)
![Qt6](https://img.shields.io/badge/Desktop-Qt6%20QML-green.svg)

## Features

- 🖥️ **Qt6/QML Desktop Shell** — Glassmorphism-Design mit App Drawer
- 🧠 **AI Gedächtnissystem** — Lokaler Memory Daemon (Markdown + SQLite)
- 🦊 **MB Browser** — Firefox-basiert, RAM-sparend
- 🔒 **Privacy** — Tor, Firewall (UFW), Bildschirmsperre
- 🤖 **Android Apps** — Waydroid + Google Play (on-demand)
- 🔊 **Audio** — PipeWire + WirePlumber
- 📶 **WiFi/Bluetooth** — NetworkManager, BlueZ
- 🖨️ **Drucker** — CUPS Support
- 📦 **App Store** — Flatpak + Flathub
- 🎬 **Multimedia** — mpv, feh, zathura, scrot
- ⬇️ **Installer** — TUI mit Hardware-Erkennung, UEFI Boot
- 🌍 **Deutsch** — Locale, Tastatur, Timezone Europe/Berlin
- 💻 **Developer Tools** — git, Node.js, Python3, Vulkan SDK
- 🚀 **Antigravity** — Desktop App + CLI (`agy`)

## Systemanforderungen

| | Minimum | Empfohlen |
|---|---|---|
| **RAM** | 512 MB | 4 GB |
| **Disk** | 8 GB | 20 GB |
| **CPU** | x86_64 | x86_64 |
| **GPU** | Integrated | NVIDIA RTX (CUDA) |

## Build

```bash
# In WSL2 (Ubuntu)
sudo bash build_iso.sh
```

Die ISO wird als `mb-os.iso` im Projektverzeichnis erstellt (~2 GB).

## Hyper-V testen

```powershell
# Gen2 UEFI VM erstellen + starten (als Admin)
powershell -ExecutionPolicy Bypass -File start_hyperv.ps1
```

## Installation

1. Von ISO booten (USB-Stick oder VM)
2. App Drawer → **"Installieren"**
3. Sprache, User, Passwort, Disk auswählen
4. Nach Installation: Boot-Reihenfolge auf Festplatte ändern

```powershell
# Hyper-V: Boot von Festplatte
powershell -ExecutionPolicy Bypass -File boot_from_disk.ps1
```

## Projektstruktur

```
MB-OS/
├── build_iso.sh          # Haupt-Build-Script
├── start_hyperv.ps1      # Hyper-V Gen2 VM erstellen
├── boot_from_disk.ps1    # Boot von Festplatte
├── gui/
│   ├── main.qml          # Desktop Shell (QML)
│   ├── main.cpp          # Qt6 Entry Point
│   └── CMakeLists.txt    # Build Config
├── browser/
│   ├── main.qml          # Qt WebEngine Browser
│   ├── main.cpp          # Browser Entry Point
│   └── CMakeLists.txt
├── daemon/
│   └── memory_daemon.py  # AI Memory Daemon
├── installer/
│   ├── mb-installer.sh   # System Installer
│   └── fix-grub.sh       # GRUB Reparatur
├── config/
│   ├── mb-os-xinitrc     # X11 Session Config
│   └── grub-theme/       # GRUB Bootloader Theme
└── wallpapers/           # Desktop Hintergrundbilder
```

## SSH Zugang

```bash
ssh mbuser@<IP>
# Passwort: mbos
```

## Lizenz

MIT License
