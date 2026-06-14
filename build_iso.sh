#!/bin/bash
set -e

# Configuration
WORKSPACE="/tmp/mb-os-build"
ROOTFS="$WORKSPACE/rootfs"
ISO_DIR="$WORKSPACE/iso"
PROJECT_DIR="$(pwd)"
OUTPUT_ISO="$PROJECT_DIR/mb-os.iso"

echo "=== MB-OS Build System ==="
echo "Project Directory: $PROJECT_DIR"
echo "Workspace:         $WORKSPACE"
echo "Output ISO:        $OUTPUT_ISO"

# 1. Install build requirements on host
echo ">>> Checking/Installing host build dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    debootstrap \
    squashfs-tools \
    xorriso \
    mtools \
    grub-common \
    grub-pc-bin \
    grub-efi-amd64-bin \
    cmake \
    g++ \
    qt6-base-dev \
    qt6-wayland \
    qt6-webengine-dev \
    qml6-module-qtquick-controls \
    qml6-module-qtwebengine

# 2. Build the Qt 6 Desktop Shell and Browser
echo ">>> Building Qt 6 Desktop Shell..."
mkdir -p "$PROJECT_DIR/gui/build"
cd "$PROJECT_DIR/gui/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
cd "$PROJECT_DIR"

echo ">>> Building MB-Browser..."
mkdir -p "$PROJECT_DIR/browser/build"
cd "$PROJECT_DIR/browser/build"
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
cd "$PROJECT_DIR"

# 3. Initialize clean workspace
echo ">>> Preparing workspace directories..."
mkdir -p "$WORKSPACE"
sudo rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/casper"
mkdir -p "$ISO_DIR/boot/grub"

# 4. Bootstrap minimal Ubuntu system
if [ ! -d "$ROOTFS/etc" ]; then
    echo ">>> Bootstrapping minimal Ubuntu Noble system..."
    sudo debootstrap --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/
else
    echo ">>> Reusing existing bootstrapped rootfs at $ROOTFS"
fi

# 5. Copy custom shell configuration and executables
echo ">>> Copying custom configurations..."
sudo mkdir -p "$ROOTFS/usr/local/bin"
sudo cp "$PROJECT_DIR/gui/build/mb-os-shell" "$ROOTFS/usr/local/bin/mb-os-shell"
sudo chmod +x "$ROOTFS/usr/local/bin/mb-os-shell"

sudo cp "$PROJECT_DIR/browser/build/mb-browser" "$ROOTFS/usr/local/bin/mb-browser"
sudo chmod +x "$ROOTFS/usr/local/bin/mb-browser"

sudo cp "$PROJECT_DIR/config/mb-db-init" "$ROOTFS/usr/local/bin/mb-db-init"
sudo chmod +x "$ROOTFS/usr/local/bin/mb-db-init"

sudo mkdir -p "$ROOTFS/usr/local/share/mb-os"
sudo cp "$PROJECT_DIR/daemon/memory_daemon.py" "$ROOTFS/usr/local/share/mb-os/memory_daemon.py"

sudo mkdir -p "$ROOTFS/etc/mb-os"
sudo cp "$PROJECT_DIR/config/mb-os-xinitrc" "$ROOTFS/etc/mb-os/mb-os-xinitrc"
sudo chmod +x "$ROOTFS/etc/mb-os/mb-os-xinitrc"

# Generate and copy custom boot logo watermark for Plymouth
python3 "$PROJECT_DIR/config/generate_logo.py"
sudo mkdir -p "$ROOTFS/usr/share/plymouth/themes/spinner"
sudo cp "$PROJECT_DIR/config/watermark.png" "$ROOTFS/usr/share/plymouth/themes/spinner/watermark.png"
sudo cp "$PROJECT_DIR/config/bgrt-fallback.png" "$ROOTFS/usr/share/plymouth/themes/spinner/bgrt-fallback.png"

# Create systemd service for memory daemon (lightweight, MD-based)
sudo tee "$ROOTFS/etc/systemd/system/mb-memory-daemon.service" > /dev/null << 'EOF'
[Unit]
Description=MB-OS AI Memory Daemon
After=network.target

[Service]
Type=simple
User=mbuser
WorkingDirectory=/usr/local/share/mb-os
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 /usr/local/share/mb-os/memory_daemon.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service to launch our GUI
sudo tee "$ROOTFS/etc/systemd/system/mb-os-gui.service" > /dev/null << 'EOF'
[Unit]
Description=MB-OS Graphical Interface
After=systemd-user-sessions.service plymouth-quit-active.service
Conflicts=getty@tty1.service

[Service]
Type=simple
ExecStart=/usr/bin/xinit /etc/mb-os/mb-os-xinitrc -- -keeptty vt1
Restart=always
RestartSec=1
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=graphical.target
EOF

# Setup standard repository list inside rootfs
sudo tee "$ROOTFS/etc/apt/sources.list" > /dev/null << 'EOF'
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

# 6. Mount filesystem helper and configure inside chroot
cleanup() {
    echo ">>> Cleaning up mounts..."
    sudo umount -lf "$ROOTFS/proc" || true
    sudo umount -lf "$ROOTFS/sys" || true
    sudo umount -lf "$ROOTFS/dev" || true
}
trap cleanup EXIT

echo ">>> Mounting virtual filesystems for chroot..."
sudo mount --bind /proc "$ROOTFS/proc"
sudo mount --bind /sys "$ROOTFS/sys"
sudo mount --bind /dev "$ROOTFS/dev"

echo ">>> Configuring OS packages inside chroot..."
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null || echo "nameserver 8.8.8.8" | sudo tee "$ROOTFS/etc/resolv.conf" > /dev/null

# Copy Antigravity Desktop App into rootfs (if available)
if [ -f "$PROJECT_DIR/Antigravity.tar.gz" ]; then
    sudo mkdir -p "$ROOTFS/opt/antigravity"
    sudo cp "$PROJECT_DIR/Antigravity.tar.gz" "$ROOTFS/opt/antigravity/"
    echo ">>> Antigravity.tar.gz in rootfs kopiert"
fi

# Copy MB-OS Installer into rootfs
sudo cp "$PROJECT_DIR/installer/mb-installer.sh" "$ROOTFS/usr/local/bin/mb-installer"
sudo chmod +x "$ROOTFS/usr/local/bin/mb-installer"
echo ">>> MB-OS Installer in rootfs kopiert"

(sudo chroot "$ROOTFS" /bin/bash << 'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install Kernel, Live boot system, X11 server, Openbox WM, Qt6/WebEngine, databases, python, tor
apt-get install -y --no-install-recommends \
    linux-image-generic \
    casper \
    systemd-sysv \
    dbus \
    xserver-xorg-core \
    xserver-xorg \
    xserver-xorg-video-fbdev \
    xserver-xorg-video-vesa \
    xserver-xorg-input-all \
    xinit \
    x11-xserver-utils \
    openbox \
    xterm \
    pcmanfm \
    mousepad \
    libqt6core6 \
    libqt6gui6 \
    libqt6qml6 \
    libqt6quick6 \
    qml6-module-qtquick \
    qml6-module-qtquick-templates \
    qml6-module-qtquick-layouts \
    qml6-module-qtquick-window \
    qml6-module-qtquick-controls \
    qml6-module-qtqml-workerscript \
    qml6-module-qtwebengine \
    libqt6webenginecore6-bin \
    sudo \
    plymouth \
    plymouth-themes \
    wget \
    curl \
    git \
    jq \
    htop \
    openssh-server \
    micro \
    python3-pip \
    python3-fastapi \
    python3-uvicorn \
    python3-requests \
    isc-dhcp-client \
    iproute2 \
    iputils-ping \
    fonts-noto-color-emoji \
    zstd \
    ca-certificates \
    gnupg \
    tor \
    xrdp \
    xorgxrdp \
    vulkan-tools \
    libvulkan-dev \
    libvulkan1 \
    mesa-vulkan-drivers \
    spirv-tools \
    glslang-tools \
    vulkan-validationlayers \
    libasound2t64 \
    xdg-utils \
    xdotool \
    xclip \
    xsel \
    whiptail \
    parted \
    dosfstools \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    wpasupplicant \
    network-manager \
    udisks2 \
    ufw \
    i3lock \
    systemd-timesyncd \
    locales \
    bluez \
    bluez-tools \
    policykit-1 \
    acpi \
    acpid \
    pm-utils \
    cups \
    avahi-daemon \
    ntfs-3g \
    exfatprogs \
    unzip \
    zip \
    p7zip-full \
    mpv \
    feh \
    zathura \
    zathura-pdf-poppler \
    scrot \
    galculator \
    flatpak \
    lxpolkit \
    dmz-cursor-theme \
    firefox

# GPU Driver Auto-Detection (runs on first boot, not in ISO)
# Keeps ISO small — installs NVIDIA/CUDA only when RTX hardware is detected
cat > /usr/local/bin/mb-gpu-setup << 'GPUSCRIPT'
#!/bin/bash
# MB-OS GPU + AI Accelerator Setup — erkennt Hardware und installiert passende Treiber

echo "🔍 Erkenne GPU-Hardware..."

# --- GPU Treiber ---
if lspci | grep -qi nvidia; then
    echo "🎮 NVIDIA GPU erkannt!"
    echo "📦 Installiere proprietären Treiber + CUDA..."
    
    apt-get update -qq
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:graphics-drivers/ppa
    apt-get update -qq
    
    ubuntu-drivers autoinstall 2>&1 || apt-get install -y nvidia-driver-550 2>&1 || apt-get install -y nvidia-driver-535 2>&1
    apt-get install -y nvidia-cuda-toolkit 2>&1 || echo "⚠ CUDA nicht verfügbar"
    
    echo "✅ NVIDIA-Treiber installiert!"
    
elif lspci | grep -qi "amd.*radeon\|amd.*rx"; then
    echo "🔴 AMD GPU erkannt — amdgpu-Treiber bereits aktiv."
    apt-get install -y mesa-opencl-icd 2>&1 || true
    
elif lspci | grep -qi intel; then
    echo "🔵 Intel GPU erkannt — i915-Treiber bereits aktiv."
fi

# --- AI Acceleration (immer verfügbar) ---
echo ""
echo "🧠 Installiere AI Acceleration Tools..."

# OpenVINO — Intel Neural Network Optimization (funktioniert auch auf CPU)
echo "📦 OpenVINO Toolkit..."
pip3 install openvino openvino-dev 2>&1 || echo "⚠ OpenVINO pip install fehlgeschlagen"

# ONNX Runtime — universeller Model-Inferenz-Layer
echo "📦 ONNX Runtime..."
pip3 install onnxruntime 2>&1 || true

# Falls NVIDIA erkannt → auch GPU-beschleunigte Varianten
if lspci | grep -qi nvidia; then
    pip3 install onnxruntime-gpu 2>&1 || true
    echo "✅ ONNX Runtime GPU aktiviert"
fi

echo ""
echo "=== MB-OS AI Stack ==="
echo "  OpenVINO:     $(python3 -c 'import openvino; print(openvino.__version__)' 2>/dev/null || echo 'nicht installiert')"
echo "  ONNX Runtime: $(python3 -c 'import onnxruntime; print(onnxruntime.__version__)' 2>/dev/null || echo 'nicht installiert')"
command -v nvidia-smi >/dev/null && echo "  NVIDIA:       $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'Treiber installiert')"
echo "  CUDA:         $(nvcc --version 2>/dev/null | grep release | awk '{print $6}' || echo 'nicht installiert')"
echo ""
echo "🚀 Fertig! Neustart empfohlen bei GPU-Treiberinstallation."
GPUSCRIPT
chmod +x /usr/local/bin/mb-gpu-setup

# Pre-install AI inference tools (work on ANY CPU, especially Intel)
echo ">>> Installing OpenVINO + ONNX Runtime (CPU)..."
pip3 install --break-system-packages openvino onnxruntime 2>&1 || \
    pip3 install openvino onnxruntime 2>&1 || \
    echo "⚠ OpenVINO/ONNX pip install fehlgeschlagen"

# Install Node.js 20 LTS from NodeSource
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -qq
apt-get install -y --no-install-recommends nodejs

# Install Antigravity 2.0 — Gemini CLI
npm install -g @google/gemini-cli 2>&1 || true

# Install Antigravity 2.0 — Desktop App + CLI
mkdir -p /opt/antigravity
cd /opt/antigravity

# 1. Install CLI via official installer
curl -fsSL https://antigravity.google/cli/install.sh -o install.sh 2>&1 || true
if [ -f install.sh ]; then
    HOME=/home/mbuser bash install.sh 2>&1 || true
fi

# 2. Install Desktop App from local tar.gz
if [ -f /opt/antigravity/Antigravity.tar.gz ]; then
    echo ">>> Installing Antigravity Desktop App from local archive..."
    cd /opt/antigravity
    tar xzf Antigravity.tar.gz 2>&1 || true
    rm -f Antigravity.tar.gz
    # Find the binary
    AGBIN=$(find /opt/antigravity -maxdepth 3 -type f \( -name "antigravity" -o -name "Antigravity" -o -name "antigravity-desktop" \) 2>/dev/null | head -1)
    if [ -n "$AGBIN" ]; then
        chmod +x "$AGBIN"
        ln -sf "$AGBIN" /usr/local/bin/antigravity-desktop
        echo "✅ Antigravity Desktop App installiert!"
    else
        # Electron apps often have the binary with a different name
        AGBIN=$(find /opt/antigravity -maxdepth 3 -type f -executable -name "antigravity*" -o -name "Antigravity*" 2>/dev/null | head -1)
        if [ -n "$AGBIN" ]; then
            chmod +x "$AGBIN"
            ln -sf "$AGBIN" /usr/local/bin/antigravity-desktop
            echo "✅ Antigravity Desktop App installiert! (Binary: $AGBIN)"
        else
            echo "⚠ Binary nicht gefunden — Inhalt:"
            ls -la /opt/antigravity/
        fi
    fi
else
    echo "⚠ Antigravity.tar.gz nicht gefunden — CLI + Web fallback."
fi

# Create launch wrapper for Antigravity (QProcess can't handle nested bash quotes)
cat > /usr/local/bin/launch-antigravity << 'LAUNCHER'
#!/bin/bash
export DISPLAY=:0
if [ -x /usr/local/bin/antigravity-desktop ]; then
    /usr/local/bin/antigravity-desktop --no-sandbox &
elif [ -x /usr/local/bin/agy ]; then
    xterm -bg black -fg white -fs 12 -e /usr/local/bin/agy &
else
    mb-browser --url https://antigravity.google &
fi
LAUNCHER
chmod +x /usr/local/bin/launch-antigravity

# 3. Create symlinks for CLI
if [ -f /home/mbuser/.local/bin/agy ]; then
    ln -sf /home/mbuser/.local/bin/agy /usr/local/bin/agy
    ln -sf /home/mbuser/.local/bin/agy /usr/local/bin/antigravity
    echo "✅ Antigravity CLI (agy) installiert und verlinkt!"
fi

# 4. Create .desktop entry for App Drawer
cat > /usr/share/applications/antigravity.desktop << 'DESKTOP'
[Desktop Entry]
Name=Antigravity 2.0
Comment=Google AI Agent Platform
Exec=antigravity-desktop
Icon=antigravity
Type=Application
Categories=Development;IDE;
DESKTOP

cd /

# Create MB-OS memory directory structure (MD-based, no databases needed)
mkdir -p /home/mbuser/.mb-os/memory/Skills

# Initialize memory files
cat > /home/mbuser/.mb-os/memory/Memory.md << 'MEMEOF'
# MB-OS Memory

> Selbstverwaltet vom AI-System. Wird automatisch aktualisiert.

## System
- MB-OS Custom Linux mit Qt6/QML Shell
- Memory: Markdown-basiert (leichtgewichtig)
- Tools: git, curl, jq, htop, micro, python3
MEMEOF

cat > /home/mbuser/.mb-os/memory/User.md << 'USREOF'
# Nutzerprofil

## Vorlieben
- Sprache: Deutsch
- Stil: Pragmatisch, ergebnisorientiert
USREOF

# Configure user 'mbuser' with passwordless sudo
useradd -m -s /bin/bash mbuser || true
passwd -d mbuser
usermod -aG sudo,video,audio mbuser || true
mkdir -p /etc/sudoers.d
echo 'mbuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/mbuser
chmod 0440 /etc/sudoers.d/mbuser

# Create cache directory for Qt/WebEngine shader cache
mkdir -p /home/mbuser/.cache
chown mbuser:mbuser /home/mbuser/.cache

# Set micro as default editor and custom terminal experience
cat >> /home/mbuser/.bashrc << 'BASHRC'

# MB-OS Terminal Branding
export EDITOR=micro
export VISUAL=micro
export TERM=xterm-256color
export PATH="$HOME/.local/bin:$PATH"

# Custom MB-OS Prompt
PS1='\[\e[38;5;45m\]MB-OS\[\e[0m\] \[\e[38;5;99m\]\w\[\e[0m\] \[\e[38;5;245m\]>\[\e[0m\] '

# Aliases
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias cls='clear'
alias mem='cat ~/.mb-os/memory/Memory.md'
alias skills='ls ~/.mb-os/memory/Skills/'
alias sysinfo='echo -e "\n  \e[38;5;45mMB-OS\e[0m v1.0 | $(uname -r)\n  \e[38;5;99mCPU:\e[0m $(nproc) cores | \e[38;5;99mRAM:\e[0m $(free -h | awk "/Mem:/{print \$3\"/\"\$2}")\n  \e[38;5;99mDisk:\e[0m $(df -h / | awk "NR==2{print \$3\"/\"\$2}") | \e[38;5;99mUptime:\e[0m $(uptime -p)\n"'
BASHRC

# System info on login (lightweight neofetch alternative)
cat > /home/mbuser/.bash_login << 'LOGIN'
echo ""
echo -e "  \e[38;5;45m  __  __ ____        ___  ____  \e[0m"
echo -e "  \e[38;5;45m |  \/  | __ )      / _ \/ ___| \e[0m"
echo -e "  \e[38;5;45m | |\/| |  _ \ ____| | | \___ \ \e[0m"
echo -e "  \e[38;5;99m | |  | | |_) |____| |_| |___) |\e[0m"
echo -e "  \e[38;5;99m |_|  |_|____/      \___/|____/ \e[0m"
echo ""
echo -e "  \e[38;5;245mKernel:\e[0m  $(uname -r)"
echo -e "  \e[38;5;245mMemory:\e[0m  $(free -h | awk '/Mem:/{print $3"/"$2}')"
echo -e "  \e[38;5;245mDisk:\e[0m    $(df -h / | awk 'NR==2{print $3"/"$2}')"
echo -e "  \e[38;5;245mUptime:\e[0m  $(uptime -p)"
echo -e "  \e[38;5;245mDaemon:\e[0m  $(systemctl is-active mb-memory-daemon 2>/dev/null || echo 'unknown')"
echo ""
LOGIN
chmod +x /home/mbuser/.bash_login

# Better xterm defaults
cat > /home/mbuser/.Xresources << 'XRES'
xterm*faceName: DejaVu Sans Mono
xterm*faceSize: 11
xterm*background: #0a0e17
xterm*foreground: #d1d5db
xterm*cursorColor: #20c2f8
xterm*scrollBar: false
xterm*saveLines: 5000
xterm*color0: #1a1e2e
xterm*color1: #ff4060
xterm*color2: #22c55e
xterm*color3: #f59e0b
xterm*color4: #3b82f6
xterm*color5: #f820c2
xterm*color6: #20c2f8
xterm*color7: #d1d5db
xterm*color8: #4b5563
xterm*color9: #ff6b80
xterm*color10: #4ade80
xterm*color11: #fbbf24
xterm*color12: #60a5fa
xterm*color13: #f472b6
xterm*color14: #22d3ee
xterm*color15: #ffffff
XRES

# Configure custom browser directories for extensions
mkdir -p /home/mbuser/.config/mb-browser/extensions
chown -R mbuser:mbuser /home/mbuser/.config
chown -R mbuser:mbuser /home/mbuser/.mb-os

# Set custom MB-OS branding
echo 'mb-os' > /etc/hostname
cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   mb-os

::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS

cat > /etc/os-release << 'OSRELEASE'
NAME="MB-OS"
VERSION="1.0"
ID=mb-os
ID_LIKE=ubuntu
PRETTY_NAME="MB-OS 1.0"
VERSION_ID="1.0"
HOME_URL="https://github.com/user/mb-os"
SUPPORT_URL="https://github.com/user/mb-os"
BUG_REPORT_URL="https://github.com/user/mb-os"
PRIVACY_POLICY_URL="https://github.com/user/mb-os"
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble
OSRELEASE

cat > /etc/lsb-release << 'LSBRELEASE'
DISTRIB_ID=MB-OS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="MB-OS 1.0"
LSBRELEASE

echo "MB-OS 1.0 \n \l" > /etc/issue
echo "MB-OS 1.0" > /etc/issue.net

# Configure automatic DHCP networking for all ethernet interfaces
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired.network << 'NETCFG'
[Match]
Name=en* eth*

[Network]
DHCP=yes
DNS=8.8.8.8
DNS=8.8.4.4
NETCFG

# Enable DNS resolution (remove dangling symlink first)
rm -f /etc/resolv.conf
cat > /etc/resolv.conf << 'RESOLV'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
RESOLV

# Enable systemd services
systemctl enable systemd-networkd
systemctl enable tor
systemctl enable ssh
systemctl enable xrdp
systemctl enable mb-memory-daemon.service
systemctl enable mb-os-gui.service
systemctl enable NetworkManager
systemctl enable udisks2
systemctl enable acpid
systemctl enable avahi-daemon
systemctl enable cups
systemctl enable bluetooth
systemctl enable systemd-timesyncd
systemctl set-default graphical.target

# Firewall: SSH + xrdp erlauben, rest blocken
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 3389/tcp
ufw allow 9876/tcp
echo "y" | ufw enable 2>/dev/null || true

# Locale: Deutsch + English
sed -i 's/# de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen 2>/dev/null || true
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen 2>/dev/null || true
echo 'LANG=de_DE.UTF-8' > /etc/default/locale

# Timezone: Europe/Berlin
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo "Europe/Berlin" > /etc/timezone

# PipeWire Audio: Auto-Start fuer User
mkdir -p /home/mbuser/.config/systemd/user/default.target.wants
mkdir -p /home/mbuser/.config/systemd/user/sockets.target.wants

# Screen Lock Script
cat > /usr/local/bin/mb-lock << 'LOCKSCRIPT'
#!/bin/bash
i3lock -c 0a0e1a -e --nofork
LOCKSCRIPT
chmod +x /usr/local/bin/mb-lock

# Waydroid (Android Apps) Setup Script
cat > /usr/local/bin/mb-android-setup << 'ANDROIDSCRIPT'
#!/bin/bash
echo "=== MB-OS Android App Support (Waydroid) ==="
echo ""

if command -v waydroid &>/dev/null; then
    echo "Waydroid ist bereits installiert!"
    echo "Starte mit: waydroid show-full-ui"
    exit 0
fi

echo "Installiere Waydroid..."
apt-get update
apt-get install -y curl ca-certificates
curl -s https://repo.waydro.id | bash
apt-get install -y waydroid

echo ""
echo "Initialisiere Android System (GAPPS)..."
waydroid init -s GAPPS -f

echo ""
echo "=== Fertig! ==="
echo "Starte Android mit: waydroid show-full-ui"
echo "Oder nutze den App Drawer -> Android"
ANDROIDSCRIPT
chmod +x /usr/local/bin/mb-android-setup

# Waydroid Launcher
cat > /usr/local/bin/launch-android << 'ANDROIDLAUNCH'
#!/bin/bash
export DISPLAY=:0
if ! command -v waydroid &>/dev/null; then
    xterm -fa Monospace -fs 12 -e sudo mb-android-setup
else
    # Start waydroid session if not running
    waydroid session start 2>/dev/null &
    sleep 2
    waydroid show-full-ui &
fi
ANDROIDLAUNCH
chmod +x /usr/local/bin/launch-android

# Flatpak: Flathub App Store
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

# Screenshot Tool
cat > /usr/local/bin/mb-screenshot << 'SCREENSHOT'
#!/bin/bash
export DISPLAY=:0
FILENAME="$HOME/screenshot_$(date +%Y%m%d_%H%M%S).png"
scrot "$FILENAME" && feh "$FILENAME" &
SCREENSHOT
chmod +x /usr/local/bin/mb-screenshot

# System Update Script
cat > /usr/local/bin/mb-update << 'UPDATESCRIPT'
#!/bin/bash
echo "=== MB-OS System Update ==="
echo ""
echo ">>> Paketlisten aktualisieren..."
apt-get update
echo ""
echo ">>> Pakete upgraden..."
apt-get upgrade -y
echo ""
echo ">>> Flatpak Updates..."
flatpak update -y 2>/dev/null || true
echo ""
echo "=== Update abgeschlossen! ==="
read -p "Druecke Enter zum Beenden..."
UPDATESCRIPT
chmod +x /usr/local/bin/mb-update

# PolicyKit Agent (noetig fuer GUI-Auth-Dialoge)
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/lxpolkit.desktop << 'POLKIT'
[Desktop Entry]
Type=Application
Name=LXPolKit
Exec=lxpolkit
Hidden=false
NoDisplay=true
POLKIT

# PipeWire autostart
cat > /etc/xdg/autostart/pipewire.desktop << 'PIPEWIRE'
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=pipewire
Hidden=false
NoDisplay=true
PIPEWIRE

cat > /etc/xdg/autostart/wireplumber.desktop << 'WIREPLUMBER'
[Desktop Entry]
Type=Application
Name=WirePlumber
Exec=wireplumber
Hidden=false
NoDisplay=true
WIREPLUMBER

# SSH: Allow password auth and set known password
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'mbuser:mbos' | chpasswd

# SSH: Add host SSH key for passwordless access
mkdir -p /home/mbuser/.ssh
chmod 700 /home/mbuser/.ssh
cat > /home/mbuser/.ssh/authorized_keys << 'SSHKEY'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCklHrbmUSFN7wzDWK0ATiksIumNu+W0VugC7heT6FtfgwpCT56hK2oXmfJq8HNLOVAEXsy0NEL13tpaT2RWMcZFTJxRbBJovj4Lella++EpqPtJjXRy2gBUSh8cdcc15zr5nXw34GSIYINLOJyqSOiBszOUtWq43rfz5ec1bXfErmtvr1ePwFKb6Of1qEql+YvSwOgkPps6fPVu/dVJEiZ7Xme/yEgPZha7OYVgHdsxDwTV3j5vY0eJsqd9Q8cqsM6mWPtuWWAFJ0+JzqnK1OQ2JOih8HICHwJrO/R0SIosl5m7G/62UdTloOEvsCN82PO4dMRxauL9HPyo/vVod072i599IJl89dd+1RfDaodMLoHwjS9vte6tic1pg6wZ26bQGy+OJ+X9PnEpAn/Fb2nqJFdjgtXcy/t+DltBmsOHi6jGfxFfOBKJkqOW36cOGgE02XsRZyDi0ALk2jXXX96HsiCfGznlTpk4x/BJDI6dh27LxMoQGyN/JbRFJ9HGnr5v2KAf5pFvIxEQl3Te9igM4g5IAC/bsVNx3P7/jsBkfhFwvB84qwmKPHMJylO77ndMT7oEMJl/99w9uuZo923C5pkqqt6uaa54BlYgb90hkEJXe/1vKI0AUXVUts+r5lHkQvAKfJx50aH8oyVhXhAMFcHifMNwFk72oMnC6AoQw== nutzer@LAPTOP-RBU7SDCN
SSHKEY
chmod 600 /home/mbuser/.ssh/authorized_keys
chown -R mbuser:mbuser /home/mbuser/.ssh

# Pre-create directories needed by Antigravity Desktop App
mkdir -p /home/mbuser/.gemini /home/mbuser/.config/Antigravity/logs
chown -R mbuser:mbuser /home/mbuser

# MB-OS Installer is already at /usr/local/bin/mb-installer (copied pre-chroot)
chmod +x /usr/local/bin/mb-installer 2>/dev/null || true

# Wrapper for QML App Drawer (avoids QProcess quoting issues)
cat > /usr/local/bin/launch-installer << 'LAUNCHWRAP'
#!/bin/bash
export TERM=xterm-256color
exec sudo /usr/local/bin/mb-installer
LAUNCHWRAP
chmod +x /usr/local/bin/launch-installer

# Desktop entry for installer
cat > /usr/share/applications/mb-installer.desktop << 'INSTDESKTOP'
[Desktop Entry]
Name=MB-OS Installieren
Comment=MB-OS auf Festplatte installieren
Exec=sudo mb-installer
Terminal=true
Type=Application
Icon=system-software-install
Categories=System;
INSTDESKTOP


# Configure xrdp to use our desktop (for Hyper-V Enhanced Session)
cat > /home/mbuser/.xsession << 'XSESSION'
#!/bin/bash
export DISPLAY=:10.0
openbox &
/opt/mb-os/bin/mb-shell
XSESSION
chmod +x /home/mbuser/.xsession
chown mbuser:mbuser /home/mbuser/.xsession

# Clipboard Bridge — Web-based clipboard for Host ↔ VM
cp /mnt/d/MB-OS/clipboard_bridge.py /opt/mb-os/bin/clipboard_bridge.py 2>/dev/null || true
if [ -f /opt/mb-os/bin/clipboard_bridge.py ]; then
    chmod +x /opt/mb-os/bin/clipboard_bridge.py
    cat > /etc/systemd/system/mb-clipboard-bridge.service << 'CLIPSERVICE'
[Unit]
Description=MB-OS Clipboard Bridge
After=mb-os-gui.service

[Service]
Type=simple
User=mbuser
Environment=DISPLAY=:0
ExecStart=/usr/bin/python3 /opt/mb-os/bin/clipboard_bridge.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
CLIPSERVICE
    systemctl enable mb-clipboard-bridge.service
fi

# Configure xrdp to allow any user without password
sed -i 's/^port=3389/port=vsock:\/\/-1:3389/' /etc/xrdp/xrdp.ini 2>/dev/null || true
# Allow root login for xrdp 
echo "allowed_users=anybody" >> /etc/X11/Xwrapper.config 2>/dev/null || true

# Right-click context menu for Copy/Paste
cat > /usr/local/bin/mb-context-menu << 'CTXMENU'
#!/bin/bash
# MB-OS Right-Click Context Menu
export DISPLAY=:0

ACTION=$(NEWT_COLORS='root=,black window=cyan,black border=cyan,black title=white,black button=black,cyan actbutton=black,white listbox=white,black actlistbox=black,cyan' \
whiptail --title "MB-OS" --menu "" 12 30 5 \
  "copy"   "  Kopieren       Ctrl+C" \
  "paste"  "  Einfuegen      Ctrl+V" \
  "cut"    "  Ausschneiden   Ctrl+X" \
  "selall" "  Alles markieren" \
  "---"    "  Abbrechen" \
  3>&1 1>&2 2>&3)

case "$ACTION" in
    copy)   xdotool key ctrl+c ;;
    paste)  xdotool key ctrl+v ;;
    cut)    xdotool key ctrl+x ;;
    selall) xdotool key ctrl+a ;;
esac
CTXMENU
chmod +x /usr/local/bin/mb-context-menu

# Disable casper-md5check (causes unnecessary FAILED in boot log)
systemctl mask casper-md5check.service 2>/dev/null || true

# Create .desktop launcher for Antigravity Desktop App
mkdir -p /usr/share/applications
cat > /usr/share/applications/antigravity.desktop << 'DESKTOP'
[Desktop Entry]
Name=Antigravity
Comment=Antigravity 2.0 AI Desktop App
Exec=/opt/antigravity/Antigravity-x64/antigravity --no-sandbox %U
Icon=antigravity
Terminal=false
Type=Application
Categories=Development;AI;
StartupWMClass=Antigravity
DESKTOP

# Create mb-browser as Firefox wrapper
cat > /usr/local/bin/mb-browser << 'MBBROWSER'
#!/bin/bash
# MB Browser - Firefox-basiert
exec firefox "$@"
MBBROWSER
chmod +x /usr/local/bin/mb-browser

# Create .desktop launcher for MB-Browser
cat > /usr/share/applications/mb-browser.desktop << 'DESKTOP'
[Desktop Entry]
Name=MB Browser
Comment=MB-OS Browser (Firefox)
Exec=/usr/local/bin/mb-browser %U
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/about;
DESKTOP

# Set mb-browser as default browser
ln -sf /usr/local/bin/mb-browser /usr/local/bin/x-www-browser
ln -sf /usr/local/bin/mb-browser /usr/local/bin/sensible-browser
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/mb-browser 200 2>/dev/null || true
mkdir -p /home/mbuser/.config
cat > /home/mbuser/.config/mimeapps.list << 'MIME'
[Default Applications]
x-scheme-handler/http=mb-browser.desktop
x-scheme-handler/https=mb-browser.desktop
text/html=mb-browser.desktop
application/xhtml+xml=mb-browser.desktop
MIME
chown -R mbuser:mbuser /home/mbuser/.config

# Create .desktop launcher for Terminal
cat > /usr/share/applications/terminal.desktop << 'DESKTOP'
[Desktop Entry]
Name=Terminal
Comment=MB-OS Terminal
Exec=xterm -fa "Monospace" -fs 11
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
DESKTOP

# Regenerate initramfs to pack our custom Plymouth logos into the initrd
update-initramfs -u

# Clean up apt caches to save space
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
) || echo "⚠ Chroot exited non-zero (harmless)"

# 7. Cleanly unmount filesystems before packaging
echo ">>> Unmounting virtual filesystems before packaging..."
sudo umount -lf "$ROOTFS/proc" || true
sudo umount -lf "$ROOTFS/sys" || true
sudo umount -lf "$ROOTFS/dev" || true

# 8. Extract Kernel & Initrd and build SquashFS
echo ">>> Copying Kernel and Initrd to ISO layout..."
KERNEL_FILE=$(ls -1v "$ROOTFS/boot/vmlinuz-"* | tail -n 1)
INITRD_FILE=$(ls -1v "$ROOTFS/boot/initrd.img-"* | tail -n 1)

sudo cp "$KERNEL_FILE" "$ISO_DIR/casper/vmlinuz"
sudo cp "$INITRD_FILE" "$ISO_DIR/casper/initrd.img"

echo ">>> Compressing filesystem into SquashFS..."
sudo mksquashfs "$ROOTFS" "$ISO_DIR/casper/filesystem.squashfs" -noappend

# 8. Create bootloader configuration (GRUB)
echo ">>> Configuring Bootloader (GRUB)..."

# Copy GRUB theme files
sudo mkdir -p "$ISO_DIR/boot/grub/themes/mb-os"
sudo cp /mnt/d/MB-OS/grub-theme/background.png "$ISO_DIR/boot/grub/themes/mb-os/"
sudo cp /mnt/d/MB-OS/grub-theme/theme.txt "$ISO_DIR/boot/grub/themes/mb-os/"
sudo cp /mnt/d/MB-OS/grub-theme/select_*.png "$ISO_DIR/boot/grub/themes/mb-os/"
sudo cp /mnt/d/MB-OS/grub-theme/dejavu_*.pf2 "$ISO_DIR/boot/grub/themes/mb-os/"

# Load all fonts into GRUB fonts directory
sudo mkdir -p "$ISO_DIR/boot/grub/fonts"
sudo cp /mnt/d/MB-OS/grub-theme/dejavu_*.pf2 "$ISO_DIR/boot/grub/fonts/"

sudo tee "$ISO_DIR/boot/grub/grub.cfg" > /dev/null << 'EOF'
set default=0
set timeout=15

# Graphics mode
set gfxmode=1024x768x32,1280x1024x32,auto
set gfxpayload=keep
load_video
terminal_output gfxterm

# Load fonts
loadfont /boot/grub/themes/mb-os/dejavu_36.pf2
loadfont /boot/grub/themes/mb-os/dejavu_16.pf2
loadfont /boot/grub/themes/mb-os/dejavu_bold_16.pf2
loadfont /boot/grub/themes/mb-os/dejavu_14.pf2
loadfont /boot/grub/themes/mb-os/dejavu_12.pf2
loadfont /boot/grub/themes/mb-os/dejavu_11.pf2

# Apply MB-OS theme
set theme=/boot/grub/themes/mb-os/theme.txt

# Fallback colors (for BIOS/text mode when theme can't load)
set menu_color_normal=cyan/black
set menu_color_highlight=white/blue
set color_normal=light-cyan/black
set color_highlight=white/blue

menuentry "  MB-OS - Starten  " {
    linux /casper/vmlinuz boot=casper hostname=MB-OS nomodeset video=hyperv_fb:1920x1080 console=tty1 console=ttyS0 systemd.journald.forward_to_console=1 ---
    initrd /casper/initrd.img
}

menuentry "  MB-OS - Abgesicherter Modus  " {
    linux /casper/vmlinuz boot=casper hostname=MB-OS nomodeset single console=tty1 ---
    initrd /casper/initrd.img
}

menuentry "  Speichertest (memtest86+)  " {
    linux16 /boot/memtest86+.bin
}
EOF

# 9. Build the bootable ISO (write to /tmp to avoid NTFS/Hyper-V locks)
echo ">>> Generating bootable ISO image..."
TEMP_ISO="/tmp/mb-os-output.iso"
sudo grub-mkrescue -o "$TEMP_ISO" "$ISO_DIR"

# Copy to project directory
echo ">>> Copying ISO to project directory..."
cp -f "$TEMP_ISO" "$OUTPUT_ISO" 2>/dev/null || sudo cp -f "$TEMP_ISO" "$OUTPUT_ISO"
rm -f "$TEMP_ISO"

echo "=== MB-OS Build Complete! ISO available at: $OUTPUT_ISO ==="
