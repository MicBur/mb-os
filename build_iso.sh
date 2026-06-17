#!/bin/bash
set -e

# Configuration
WORKSPACE="/var/mb-os-build"
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
    sudo debootstrap --variant=minbase resolute "$ROOTFS" http://archive.ubuntu.com/ubuntu/
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

# Copy EFI boot repair script
sudo cp "$PROJECT_DIR/config/fix-efi-boot.sh" "$ROOTFS/usr/local/bin/fix-efi-boot.sh"
sudo chmod +x "$ROOTFS/usr/local/bin/fix-efi-boot.sh"

# System-wide cursor theme (KRITISCH für sichtbaren Mauszeiger!)
sudo mkdir -p "$ROOTFS/usr/share/icons/default"
sudo tee "$ROOTFS/usr/share/icons/default/index.theme" > /dev/null << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=DMZ-White
EOF

# X11 default cursor
sudo mkdir -p "$ROOTFS/etc/X11/Xresources"
echo 'Xcursor.theme: DMZ-White' | sudo tee "$ROOTFS/etc/X11/Xresources/x11-cursor" > /dev/null
echo 'Xcursor.size: 24' | sudo tee -a "$ROOTFS/etc/X11/Xresources/x11-cursor" > /dev/null

# GTK cursor
sudo mkdir -p "$ROOTFS/etc/gtk-3.0"
sudo tee "$ROOTFS/etc/gtk-3.0/settings.ini" > /dev/null << 'EOF'
[Settings]
gtk-cursor-theme-name=DMZ-White
gtk-cursor-theme-size=24
EOF

# Environment.d for all sessions
sudo mkdir -p "$ROOTFS/etc/environment.d"
echo 'XCURSOR_THEME=DMZ-White' | sudo tee "$ROOTFS/etc/environment.d/99-cursor.conf" > /dev/null
echo 'XCURSOR_SIZE=24' | sudo tee -a "$ROOTFS/etc/environment.d/99-cursor.conf" > /dev/null

# Also write to /etc/environment for login shells
echo 'XCURSOR_THEME=DMZ-White' | sudo tee -a "$ROOTFS/etc/environment" > /dev/null
echo 'XCURSOR_SIZE=24' | sudo tee -a "$ROOTFS/etc/environment" > /dev/null

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
deb http://archive.ubuntu.com/ubuntu/ resolute main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ resolute-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ resolute-security main restricted universe multiverse
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
export DEBCONF_NONINTERACTIVE_SEEN=true
# Automatisch bestehende Configs behalten (kein GTK-Prompt!)
echo 'Dpkg::Options {"--force-confold";"--force-confdef";};' > /etc/apt/apt.conf.d/99force-conf
apt-get update

# --- Firefox PPA (echtes .deb statt Snap-Stub!) ---
apt-get install -y software-properties-common
add-apt-repository -y ppa:mozillateam/ppa
cat > /etc/apt/preferences.d/mozilla << 'MOZPIN'
Package: firefox
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
MOZPIN
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
    xterm xfonts-base xfonts-75dpi \
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
    dunst \
    libnotify-bin \
    snapd \
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
    polkitd \
    pkexec \
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
    firefox \
    os-prober \
    ntfs-3g-dev \
    grub-efi-amd64 \
    grub-efi-amd64-bin \
    efibootmgr \
    calamares \
    calamares-settings-ubuntu-common

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

# Install Node.js 20 LTS from NodeSource (with timeout)
mkdir -p /etc/apt/keyrings
timeout 15 curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | timeout 10 gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
if [ -f /etc/apt/keyrings/nodesource.gpg ]; then
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    apt-get update -qq 2>/dev/null || true
    apt-get install -y --no-install-recommends nodejs 2>/dev/null || true
else
    echo ">>> NodeSource GPG failed, installing nodejs from Ubuntu repos..."
    apt-get install -y --no-install-recommends nodejs npm 2>/dev/null || true
fi

# Install Antigravity 2.0 — CLI + Desktop App
echo ">>> Installing Antigravity CLI + Desktop..."
mkdir -p /opt/antigravity /home/mbuser/.local/bin

# 1. CLI: Official installer (writes to ~/.local/bin/agy)
export HOME=/home/mbuser
rm -f /tmp/agy-install.sh
if curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh; then
    bash /tmp/agy-install.sh || true
    rm -f /tmp/agy-install.sh
fi

# Symlink CLI to /usr/local/bin for system-wide access
if [ -f /home/mbuser/.local/bin/agy ]; then
    ln -sf /home/mbuser/.local/bin/agy /usr/local/bin/agy
    ln -sf /home/mbuser/.local/bin/agy /usr/local/bin/antigravity
    echo "✅ Antigravity CLI (agy) installiert"
else
    echo "⚠ agy CLI nicht gefunden — wird beim ersten Boot nachinstalliert"
fi

# 2. Desktop App: Download tarball from official source if available
cd /opt/antigravity
if [ -f /opt/antigravity/Antigravity.tar.gz ]; then
    echo ">>> Antigravity Desktop aus lokalem Archiv..."
    tar xzf Antigravity.tar.gz 2>&1 || true
    rm -f Antigravity.tar.gz
fi
# Find the actual binary (Electron apps have various names)
AGBIN=$(find /opt/antigravity -maxdepth 3 -type f \( -name "antigravity" -o -name "Antigravity" -o -name "antigravity-desktop" \) ! -name "*.tar.gz" ! -name "*.zip" 2>/dev/null | head -1)
if [ -z "$AGBIN" ]; then
    AGBIN=$(find /opt/antigravity -maxdepth 3 -type f -executable \( -name "antigravity*" -o -name "Antigravity*" \) ! -name "*.tar.gz" ! -name "*.zip" ! -name "*.sh" 2>/dev/null | head -1)
fi
if [ -n "$AGBIN" ]; then
    chmod +x "$AGBIN"
    ln -sf "$AGBIN" /usr/local/bin/antigravity-desktop
    echo "✅ Antigravity Desktop App: $AGBIN"
else
    echo "⚠ Keine Desktop-App Binary — CLI + Browser Fallback aktiv"
fi

# 3. Fix ownership
chown -R mbuser:mbuser /home/mbuser/.local /home/mbuser/.cache 2>/dev/null || true

# Antigravity Memory-System konfigurieren
mkdir -p /home/mbuser/.gemini/memory/Skills
mkdir -p /home/mbuser/.gemini/config

cat > /home/mbuser/.gemini/config/AGENTS.md << 'AGENTS'
# MB-OS Agent Rules

## Sprache
Antworte IMMER auf Deutsch.

## Gedächtnissystem
Lese bei Session-Start:
- ~/.gemini/memory/Memory.md
- ~/.gemini/memory/User.md
- ~/.gemini/memory/Skills/

Aktualisiere diese bei neuen Erkenntnissen.
AGENTS

chown -R mbuser:mbuser /home/mbuser/.gemini 2>/dev/null || true

cd /

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

# (casper.conf + autologin + .profile werden am Ende des chroot-Blocks geschrieben)

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
VERSION_CODENAME=resolute
UBUNTU_CODENAME=resolute
OSRELEASE

cat > /etc/lsb-release << 'LSBRELEASE'
DISTRIB_ID=MB-OS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=resolute
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
systemctl enable systemd-networkd || true
systemctl enable tor || true
systemctl enable ssh || true
systemctl enable xrdp || true
systemctl enable mb-memory-daemon.service || true
systemctl enable mb-os-gui.service || true
systemctl enable NetworkManager || true
systemctl enable udisks2 || true
systemctl enable acpid || true
systemctl enable avahi-daemon || true
systemctl enable cups || true
systemctl enable bluetooth || true
systemctl enable systemd-timesyncd || true
systemctl set-default graphical.target || true

# Manual symlink fallback (chroot systemctl is unreliable!)
mkdir -p /etc/systemd/system/graphical.target.wants
ln -sf /etc/systemd/system/mb-os-gui.service /etc/systemd/system/graphical.target.wants/mb-os-gui.service 2>/dev/null || true
ln -sf /etc/systemd/system/mb-memory-daemon.service /etc/systemd/system/multi-user.target.wants/mb-memory-daemon.service 2>/dev/null || true
ln -sf /lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service 2>/dev/null || true
ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service 2>/dev/null || true
rm -f /etc/systemd/system/default.target
ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target

# Casper-Bottom Hook für SSH Auto-Start (zuverlässiger als systemctl enable)
mkdir -p /usr/share/initramfs-tools/scripts/casper-bottom
cat > /usr/share/initramfs-tools/scripts/casper-bottom/99-enable-ssh << 'SSHOOK'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0 ;; esac
chroot "${rootmnt}" /bin/systemctl enable ssh.service 2>/dev/null || true
chroot "${rootmnt}" /bin/systemctl enable ssh.socket 2>/dev/null || true
if [ ! -f "${rootmnt}/etc/ssh/ssh_host_ed25519_key" ]; then
    chroot "${rootmnt}" /usr/bin/ssh-keygen -A 2>/dev/null || true
fi
exit 0
SSHOOK
chmod +x /usr/share/initramfs-tools/scripts/casper-bottom/99-enable-ssh

# Auch SSH Socket aktivieren (Ubuntu 24.04+)
mkdir -p /etc/systemd/system/sockets.target.wants
ln -sf /lib/systemd/system/ssh.socket /etc/systemd/system/sockets.target.wants/ssh.socket 2>/dev/null || true

# SSH Host-Keys vorab generieren
ssh-keygen -A 2>/dev/null || true

# === PERFORMANCE (2GB RAM Celeron) ===
# ZRAM Swap (komprimierter RAM-Swap)
apt-get install -y zram-tools 2>/dev/null || true
cat > /etc/default/zramswap << 'ZRAM'
ALGO=zstd
PERCENT=75
PRIORITY=100
ZRAM
systemctl enable zramswap 2>/dev/null || true

# Kernel-Parameter für wenig RAM
cat > /etc/sysctl.d/99-mbos-performance.conf << 'SYSCTL'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
SYSCTL

# Journald begrenzen
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf << 'JOURNAL'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=30M
JOURNAL

# WiFi Auto-Connect (iPhone Hotspot)
mkdir -p /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/iPhone-von-mic.nmconnection << 'WIFICFG'
[connection]
id=iPhone von mic
type=wifi
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=iPhone von mic

[wifi-security]
key-mgmt=wpa-psk
psk=00070008

[ipv4]
method=auto

[ipv6]
method=auto
WIFICFG
chmod 600 /etc/NetworkManager/system-connections/iPhone-von-mic.nmconnection

# NetworkManager: Alle Interfaces managen
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-manage-all.conf << 'NMCONF'
[device]
wifi.scan-rand-mac-address=no
[main]
plugins=ifupdown,keyfile
[ifupdown]
managed=true
NMCONF

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
export DISPLAY=:0
URL="about:blank"
TOR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) URL="$2"; shift 2;;
        --tor) TOR=true; shift;;
        *) URL="$1"; shift;;
    esac
done

if [ "$TOR" = true ]; then
    systemctl start tor 2>/dev/null
    mkdir -p /home/mbuser/.mozilla/firefox/tor-profile
    firefox --class="MBBrowser-Tor" --profile /home/mbuser/.mozilla/firefox/tor-profile -no-remote --new-instance "$URL" &
else
    firefox "$URL" &
fi
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

# ============================================================
# CASPER + AUTO-LOGIN + GUI AUTOSTART (MUSS NACH ALLEN PAKETEN!)
# ============================================================

# Casper Live-System: User = mbuser (überschreibt Paket-Default!)
cat > /etc/casper.conf << 'CASPERCONF'
export USERNAME="mbuser"
export USERFULLNAME="MB-OS User"
export HOST="MB-OS"
export BUILD_SYSTEM="Ubuntu"
CASPERCONF

# Auto-Login auf tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOCONF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin mbuser --noclear %I $TERM
AUTOCONF

# Auto-Start GUI auf tty1 (Live + installiert)
cat > /home/mbuser/.profile << 'XPROFILE'
# Starte GUI automatisch auf tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec sudo /usr/bin/xinit /etc/mb-os/mb-os-xinitrc -- -keeptty vt1 2>/dev/null
fi
XPROFILE
chown mbuser:mbuser /home/mbuser/.profile

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

# ============================================================
# KRITISCH: Configs NACH chroot direkt ins rootfs schreiben
# (chroot kann diese nicht mehr überschreiben!)
# ============================================================

# Casper: User = mbuser
sudo tee "$ROOTFS/etc/casper.conf" > /dev/null << 'CASPERCONF'
export USERNAME="mbuser"
export USERFULLNAME="MB-OS User"
export HOST="MB-OS"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="MB-OS"
CASPERCONF

# Auto-Login auf tty1
sudo mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
sudo tee "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" > /dev/null << 'AUTOCONF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin mbuser --noclear %I $TERM
AUTOCONF

# GUI Auto-Start aus .profile
sudo mkdir -p "$ROOTFS/home/mbuser"
sudo tee "$ROOTFS/home/mbuser/.profile" > /dev/null << 'XPROFILE'
# Starte GUI automatisch auf tty1 (mit Loop-Schutz)
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ ! -f /tmp/.mb-gui-started ]; then
    touch /tmp/.mb-gui-started
    echo ">>> MB-OS GUI startet..." > /tmp/mb-gui.log 2>&1
    sudo /usr/bin/xinit /etc/mb-os/mb-os-xinitrc -- :0 vt1 -keeptty >> /tmp/mb-gui.log 2>&1
    echo ">>> xinit beendet mit Code: $?" >> /tmp/mb-gui.log 2>&1
    # Bei Fehler: nicht loopen, Shell offen lassen
    echo ""
    echo "  GUI konnte nicht gestartet werden."
    echo "  Log: cat /tmp/mb-gui.log"
    echo "  Neustart: rm /tmp/.mb-gui-started && startx"
    echo ""
fi
XPROFILE
sudo chown -R 1000:1000 "$ROOTFS/home/mbuser" 2>/dev/null || true

echo ">>> Configs geschrieben: casper.conf=mbuser, autologin, .profile=xinit"

# ============================================================
# POST-CHROOT SAFETY NET: Launcher-Scripts + SSH + Firefox + mb-browser
# (Geschrieben NACH dem chroot, damit sie garantiert im squashfs landen)
# ============================================================
echo ">>> Post-Chroot: Launcher-Scripts + Configs schreiben..."

# --- SSH Key ---
SSHPUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoSIm6BfLUNinWvtQHljyckGno+hn47vFIyUTpI33E2 nutzer@LAPTOP-RBU7SDCN"
sudo mkdir -p "$ROOTFS/home/mbuser/.ssh"
echo "$SSHPUB" | sudo tee "$ROOTFS/home/mbuser/.ssh/authorized_keys" > /dev/null
sudo chmod 700 "$ROOTFS/home/mbuser/.ssh"
sudo chmod 600 "$ROOTFS/home/mbuser/.ssh/authorized_keys"
sudo chown -R 1000:1000 "$ROOTFS/home/mbuser/.ssh"
sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' "$ROOTFS/etc/ssh/sshd_config"
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$ROOTFS/etc/ssh/sshd_config"

# --- Firefox PPA Pin (damit apt echtes .deb statt snap-stub installiert) ---
sudo tee "$ROOTFS/etc/apt/preferences.d/mozilla" > /dev/null << 'MOZPIN'
Package: firefox
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
MOZPIN

# --- Antigravity Desktop Symlink sichern ---
if [ -f "$ROOTFS/opt/antigravity/Antigravity-x64/antigravity" ]; then
    sudo ln -sf /opt/antigravity/Antigravity-x64/antigravity "$ROOTFS/usr/local/bin/antigravity-desktop"
    echo "  ✓ antigravity-desktop -> Antigravity-x64/antigravity"
fi
# --- agy CLI Symlink sichern ---
if [ -f "$ROOTFS/home/mbuser/.local/bin/agy" ]; then
    sudo ln -sf /home/mbuser/.local/bin/agy "$ROOTFS/usr/local/bin/agy"
    sudo ln -sf /home/mbuser/.local/bin/agy "$ROOTFS/usr/local/bin/antigravity"
    echo "  ✓ agy CLI symlinked"
fi

# --- EFI Boot repair script safety net ---
sudo cp "$PROJECT_DIR/config/fix-efi-boot.sh" "$ROOTFS/usr/local/bin/fix-efi-boot.sh"
sudo chmod +x "$ROOTFS/usr/local/bin/fix-efi-boot.sh"

# --- launch-antigravity ---
sudo tee "$ROOTFS/usr/local/bin/launch-antigravity" > /dev/null << 'LAUNCHER'
#!/bin/bash
export DISPLAY=:0
if [ -x /usr/local/bin/antigravity-desktop ]; then
    /usr/local/bin/antigravity-desktop --no-sandbox &
elif [ -x /usr/local/bin/agy ]; then
    xterm -bg '#0a0c16' -fg '#00ffcc' -fs 12 -T "Antigravity AI" -e /usr/local/bin/agy &
else
    mb-browser --url "https://gemini.google.com" &
fi
LAUNCHER

# --- mb-browser (Firefox + Tor Toggle) ---
sudo tee "$ROOTFS/usr/local/bin/mb-browser" > /dev/null << 'MBBROWSER'
#!/bin/bash
export DISPLAY=:0
URL="about:blank"
TOR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) URL="$2"; shift 2;;
        --tor) TOR=true; shift;;
        *) URL="$1"; shift;;
    esac
done

if [ "$TOR" = true ]; then
    systemctl start tor 2>/dev/null
    mkdir -p /home/mbuser/.mozilla/firefox/tor-profile
    firefox --class="MBBrowser-Tor" --profile /home/mbuser/.mozilla/firefox/tor-profile -no-remote --new-instance "$URL" &
else
    firefox "$URL" &
fi
MBBROWSER

# --- Calamares Installer Konfiguration ---
echo ">>> Calamares Installer konfigurieren..."
sudo mkdir -p "$ROOTFS/etc/calamares/modules"
sudo mkdir -p "$ROOTFS/etc/calamares/branding/mb-os"
if [ -d "$PROJECT_DIR/calamares" ]; then
    sudo cp "$PROJECT_DIR/calamares/settings.conf" "$ROOTFS/etc/calamares/settings.conf"
    sudo cp "$PROJECT_DIR/calamares/modules/"*.conf "$ROOTFS/etc/calamares/modules/" 2>/dev/null || true
    sudo cp "$PROJECT_DIR/calamares/branding/mb-os/branding.desc" "$ROOTFS/etc/calamares/branding/mb-os/" 2>/dev/null || true
    # Logo für Calamares Branding
    if [ -f "$PROJECT_DIR/config/watermark.png" ]; then
        sudo cp "$PROJECT_DIR/config/watermark.png" "$ROOTFS/etc/calamares/branding/mb-os/logo.png"
    fi
    echo "  ✓ Calamares Konfiguration kopiert"
fi

# --- launch-installer (Calamares mit Fallback) ---
sudo tee "$ROOTFS/usr/local/bin/launch-installer" > /dev/null << 'INST'
#!/bin/bash
export DISPLAY=:0
export TERM=xterm-256color
if command -v calamares &>/dev/null; then
    sudo calamares &
elif [ -x /usr/local/bin/mb-installer ]; then
    xterm -fa Monospace -fs 11 -bg '#0a0c16' -fg '#d1d5db' -T 'MB-OS Installer' -maximized -e sudo /usr/local/bin/mb-installer
else
    xterm -e bash -c 'echo Installer nicht gefunden!; read'
fi
INST

# --- launch-android ---
sudo tee "$ROOTFS/usr/local/bin/launch-android" > /dev/null << 'ANDROID'
#!/bin/bash
export DISPLAY=:0
command -v waydroid &>/dev/null && waydroid show-full-ui & || xterm -e bash -c 'echo "Waydroid nicht installiert. sudo apt install waydroid"; read' &
ANDROID

# --- mb-lock / mb-screenshot / mb-update ---
echo '#!/bin/bash' | sudo tee "$ROOTFS/usr/local/bin/mb-lock" > /dev/null
echo 'i3lock -c 0a0c16 -e' | sudo tee -a "$ROOTFS/usr/local/bin/mb-lock" > /dev/null

sudo tee "$ROOTFS/usr/local/bin/mb-screenshot" > /dev/null << 'SHOT'
#!/bin/bash
D="/home/mbuser/Screenshots"; mkdir -p "$D"
F="$D/screenshot_$(date +%Y%m%d_%H%M%S).png"
scrot "$F" && feh "$F" &
SHOT

sudo tee "$ROOTFS/usr/local/bin/mb-update" > /dev/null << 'UPD'
#!/bin/bash
echo "=== MB-OS System Update ==="
apt-get update && apt-get upgrade -y && apt-get autoremove -y
echo "Update fertig!"; read -p "Enter..."
UPD

# Alle executable machen
sudo chmod +x "$ROOTFS/usr/local/bin/launch-antigravity" \
    "$ROOTFS/usr/local/bin/launch-installer" \
    "$ROOTFS/usr/local/bin/launch-android" \
    "$ROOTFS/usr/local/bin/mb-browser" \
    "$ROOTFS/usr/local/bin/mb-lock" \
    "$ROOTFS/usr/local/bin/mb-screenshot" \
    "$ROOTFS/usr/local/bin/mb-update"

echo "  ✓ 7 Launcher-Scripts + SSH + Firefox-Pin geschrieben"

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
    linux /casper/vmlinuz boot=casper username=mbuser hostname=MB-OS nomodeset mitigations=off nowatchdog nmi_watchdog=0 console=tty1 ---
    initrd /casper/initrd.img
}

menuentry "  MB-OS - Abgesicherter Modus  " {
    linux /casper/vmlinuz boot=casper username=mbuser hostname=MB-OS nomodeset single console=tty1 ---
    initrd /casper/initrd.img
}

menuentry "  Speichertest (memtest86+)  " {
    linux16 /boot/memtest86+.bin
}
EOF

# 9. Build the bootable ISO (free rootfs first to make space in /tmp)
echo ">>> Generating bootable ISO image..."
rm -rf "$ROOTFS"
TEMP_ISO="/tmp/mb-os-output.iso"
sudo grub-mkrescue -o "$TEMP_ISO" "$ISO_DIR"

# Copy to project directory
echo ">>> Copying ISO to project directory..."
sudo cp -f "$TEMP_ISO" "$OUTPUT_ISO" 2>/dev/null || cp -f "$TEMP_ISO" "$OUTPUT_ISO"
rm -f "$TEMP_ISO"

echo "=== MB-OS Build Complete! ISO available at: $OUTPUT_ISO ==="
