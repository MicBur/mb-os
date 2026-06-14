#!/bin/bash
# ══════════════════════════════════════════════════════════════
# MB-OS Installer v2.0
# Grafischer Terminal-Installer für MB-OS
# ══════════════════════════════════════════════════════════════

set -e

# Colors & Constants
export NEWT_COLORS='
root=,black
window=cyan,black
border=cyan,black
title=white,black
textbox=white,black
button=black,cyan
actbutton=black,white
compactbutton=white,black
listbox=white,black
actlistbox=black,cyan
actsellistbox=black,cyan
checkbox=white,black
actcheckbox=black,cyan
entry=white,black
label=cyan,black
'

INSTALLER_VERSION="2.0"
TITLE="MB-OS Installer v${INSTALLER_VERSION}"
BACKTITLE="MB-OS Installation"
LOG_FILE="/tmp/mb-installer.log"

# Variables set during installation
INSTALL_LANG="de_DE.UTF-8"
INSTALL_COUNTRY="DE"
INSTALL_TIMEZONE="Europe/Berlin"
INSTALL_KEYBOARD="de"
INSTALL_HOSTNAME="mb-os"
INSTALL_USERNAME=""
INSTALL_FULLNAME=""
INSTALL_PASSWORD=""
INSTALL_DISK=""
INSTALL_PARTITION=""

# ──────────────────────────────────────────────────────────────
# Helper Functions
# ──────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

die() {
    whiptail --title "Fehler" --msgbox "$1" 10 60
    log "FATAL: $1"
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Der Installer muss als root ausgeführt werden!\n\nBitte starte mit: sudo mb-installer"
    fi
}

# ──────────────────────────────────────────────────────────────
# Step 1: Welcome Screen
# ──────────────────────────────────────────────────────────────

step_welcome() {
    whiptail --title "$TITLE" --yesno \
"
    ╔══════════════════════════════════════╗
    ║         Willkommen bei MB-OS        ║
    ║     Custom Linux Environment 2.0    ║
    ╚══════════════════════════════════════╝

  Dieser Assistent installiert MB-OS auf deinem
  Computer. Du kannst MB-OS neben Windows
  installieren (Dual-Boot) oder als einziges
  Betriebssystem.

  Was wird installiert:
  • Qt6/QML Glassmorphism Desktop
  • MB-Browser (Chromium-basiert)
  • Antigravity AI Assistant
  • Tor-Netzwerk Integration
  • Clipboard Bridge

  Möchtest du fortfahren?" 24 50 \
    --yes-button "Weiter" --no-button "Abbrechen"

    if [ $? -ne 0 ]; then
        clear
        echo "Installation abgebrochen."
        exit 0
    fi
    log "Step 1: Welcome - OK"
}

# ──────────────────────────────────────────────────────────────
# Step 2: Language & Country
# ──────────────────────────────────────────────────────────────

step_language() {
    INSTALL_LANG=$(whiptail --title "$TITLE - Sprache" --menu \
        "\nWähle deine Systemsprache:" 18 60 6 \
        "de_DE.UTF-8" "Deutsch (Deutschland)" \
        "de_AT.UTF-8" "Deutsch (Österreich)" \
        "de_CH.UTF-8" "Deutsch (Schweiz)" \
        "en_US.UTF-8" "English (US)" \
        "en_GB.UTF-8" "English (UK)" \
        "fr_FR.UTF-8" "Français (France)" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 2a: Language = $INSTALL_LANG"

    INSTALL_COUNTRY=$(whiptail --title "$TITLE - Land" --menu \
        "\nWähle dein Land:" 20 60 8 \
        "DE" "Deutschland" \
        "AT" "Österreich" \
        "CH" "Schweiz" \
        "US" "United States" \
        "GB" "United Kingdom" \
        "FR" "France" \
        "NL" "Netherlands" \
        "IT" "Italia" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 2b: Country = $INSTALL_COUNTRY"

    INSTALL_TIMEZONE=$(whiptail --title "$TITLE - Zeitzone" --menu \
        "\nWähle deine Zeitzone:" 20 60 8 \
        "Europe/Berlin" "Berlin (MEZ/MESZ)" \
        "Europe/Vienna" "Wien (MEZ/MESZ)" \
        "Europe/Zurich" "Zürich (MEZ/MESZ)" \
        "Europe/London" "London (GMT/BST)" \
        "Europe/Paris" "Paris (MEZ/MESZ)" \
        "America/New_York" "New York (EST/EDT)" \
        "America/Los_Angeles" "Los Angeles (PST/PDT)" \
        "Asia/Tokyo" "Tokyo (JST)" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 2c: Timezone = $INSTALL_TIMEZONE"

    INSTALL_KEYBOARD=$(whiptail --title "$TITLE - Tastatur" --menu \
        "\nWähle dein Tastaturlayout:" 18 60 6 \
        "de" "Deutsch (QWERTZ)" \
        "us" "US English (QWERTY)" \
        "gb" "UK English (QWERTY)" \
        "fr" "Français (AZERTY)" \
        "ch" "Schweizerdeutsch" \
        "at" "Österreich" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 2d: Keyboard = $INSTALL_KEYBOARD"
}

# ──────────────────────────────────────────────────────────────
# Step 3: Hardware Detection
# ──────────────────────────────────────────────────────────────

step_hardware() {
    # Detect hardware
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unbekannt")
    local cpu_cores=$(nproc 2>/dev/null || echo "?")
    local ram_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")
    local gpu_info=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | cut -d: -f3 | head -1 | xargs || echo "Unbekannt")
    local disk_info=$(lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v "loop\|sr\|ram" | head -5 || echo "Keine erkannt")
    local net_info=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v "lo" | head -3 | tr '\n' ', ' || echo "Keine")
    local uefi_mode="Nein (BIOS/Legacy)"
    [ -d /sys/firmware/efi ] && uefi_mode="Ja (UEFI)"
    local secure_boot="Unbekannt"
    if [ -f /sys/firmware/efi/efivars/SecureBoot-* ] 2>/dev/null; then
        secure_boot="Aktiv"
    fi

    whiptail --title "$TITLE - Hardwareerkennung" --msgbox \
"
  ┌─────────────────────────────────────────┐
  │         Erkannte Hardware               │
  └─────────────────────────────────────────┘

  CPU:        $cpu_model
  Kerne:      $cpu_cores
  RAM:        $ram_total
  GPU:        $gpu_info

  UEFI:       $uefi_mode
  Secure Boot: $secure_boot

  Netzwerk:   ${net_info%,}

  Festplatten:
  $disk_info

  Falls Hardware fehlt, kann sie nach der
  Installation manuell konfiguriert werden.
" 26 60

    log "Step 3: Hardware Detection done"
    log "  CPU: $cpu_model ($cpu_cores cores)"
    log "  RAM: $ram_total"
    log "  GPU: $gpu_info"
    log "  UEFI: $uefi_mode"
}

# ──────────────────────────────────────────────────────────────
# Step 4: User Setup
# ──────────────────────────────────────────────────────────────

step_user() {
    INSTALL_FULLNAME=$(whiptail --title "$TITLE - Benutzerkonto" --inputbox \
        "\nGib deinen vollständigen Namen ein:" 10 50 "" \
        3>&1 1>&2 2>&3) || return 1

    [ -z "$INSTALL_FULLNAME" ] && die "Name darf nicht leer sein!"

    # Auto-generate username from full name
    local auto_user=$(echo "$INSTALL_FULLNAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '.' | sed 's/[^a-z0-9.]//g' | cut -c1-20)

    INSTALL_USERNAME=$(whiptail --title "$TITLE - Benutzername" --inputbox \
        "\nWähle einen Benutzernamen (nur Kleinbuchstaben):" 10 50 "$auto_user" \
        3>&1 1>&2 2>&3) || return 1

    [ -z "$INSTALL_USERNAME" ] && die "Benutzername darf nicht leer sein!"

    # Validate username
    if ! echo "$INSTALL_USERNAME" | grep -qE '^[a-z][a-z0-9._-]*$'; then
        die "Ungültiger Benutzername!\n\nNur Kleinbuchstaben, Zahlen, Punkt, Unterstrich und Bindestrich erlaubt."
    fi

    INSTALL_PASSWORD=$(whiptail --title "$TITLE - Passwort" --passwordbox \
        "\nWähle ein Passwort für '$INSTALL_USERNAME':" 10 50 \
        3>&1 1>&2 2>&3) || return 1

    [ -z "$INSTALL_PASSWORD" ] && die "Passwort darf nicht leer sein!"

    local pw_confirm=$(whiptail --title "$TITLE - Passwort bestätigen" --passwordbox \
        "\nPasswort wiederholen:" 10 50 \
        3>&1 1>&2 2>&3) || return 1

    if [ "$INSTALL_PASSWORD" != "$pw_confirm" ]; then
        die "Passwörter stimmen nicht überein!"
    fi

    INSTALL_HOSTNAME=$(whiptail --title "$TITLE - Hostname" --inputbox \
        "\nWähle einen Computernamen (Hostname):" 10 50 "mb-os" \
        3>&1 1>&2 2>&3) || return 1

    [ -z "$INSTALL_HOSTNAME" ] && INSTALL_HOSTNAME="mb-os"

    log "Step 4: User = $INSTALL_USERNAME ($INSTALL_FULLNAME), Host = $INSTALL_HOSTNAME"
}

# ──────────────────────────────────────────────────────────────
# Step 5: Disk Selection & Partitioning
# ──────────────────────────────────────────────────────────────

step_disk() {
    # Get available disks
    local disk_list=""
    local disk_count=0
    while IFS= read -r line; do
        local dname=$(echo "$line" | awk '{print $1}')
        local dsize=$(echo "$line" | awk '{print $2}')
        local dmodel=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
        [ -z "$dmodel" ] && dmodel="Unbekannt"
        disk_list="$disk_list /dev/$dname \"$dsize - $dmodel\""
        disk_count=$((disk_count + 1))
    done < <(lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v "loop\|sr\|ram")

    if [ $disk_count -eq 0 ]; then
        die "Keine Festplatten erkannt!\n\nBitte überprüfe die Hardware."
    fi

    INSTALL_DISK=$(eval whiptail --title \"$TITLE - Festplatte\" --menu \
        \"\\nWähle die Festplatte für die Installation:\\n\\n⚠️  ACHTUNG: Alle Daten auf der gewählten\\n   Partition werden gelöscht!\" 20 60 $disk_count \
        $disk_list \
        3>&1 1>&2 2>&3) || return 1

    log "Step 5a: Disk = $INSTALL_DISK"

    # Show current partitions
    local part_info=$(lsblk -n -o NAME,SIZE,FSTYPE,MOUNTPOINT "$INSTALL_DISK" 2>/dev/null || echo "Keine Partitionen")

    # Ask for partitioning method
    local part_method=$(whiptail --title "$TITLE - Partitionierung" --menu \
        "\nAktuelle Partitionen auf $INSTALL_DISK:\n$part_info\n\nWie soll partitioniert werden?" 22 65 3 \
        "auto" "Gesamte Festplatte verwenden (alles löschen)" \
        "alongside" "Neben bestehendem OS installieren (Dual-Boot)" \
        "manual" "Manuelle Partitionierung (Experten)" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 5b: Partition method = $part_method"

    # Confirmation
    if [ "$part_method" = "auto" ]; then
        whiptail --title "$TITLE - WARNUNG" --yesno \
"
  ⚠️  WARNUNG: DATENVERLUST! ⚠️

  Alle Daten auf $INSTALL_DISK werden
  UNWIDERRUFLICH gelöscht!

  Festplatte: $INSTALL_DISK
  Methode:    Gesamte Festplatte verwenden

  Bist du sicher?" 16 50 \
        --yes-button "Ja, löschen" --no-button "Abbrechen" || return 1
    fi

    # Store partition method
    INSTALL_PART_METHOD="$part_method"
}

# ──────────────────────────────────────────────────────────────
# Step 6: Summary & Confirmation
# ──────────────────────────────────────────────────────────────

step_summary() {
    whiptail --title "$TITLE - Zusammenfassung" --yesno \
"
  ┌─────────────────────────────────────────┐
  │       Installationsübersicht            │
  └─────────────────────────────────────────┘

  Sprache:      $INSTALL_LANG
  Land:         $INSTALL_COUNTRY
  Zeitzone:     $INSTALL_TIMEZONE
  Tastatur:     $INSTALL_KEYBOARD

  Benutzer:     $INSTALL_FULLNAME ($INSTALL_USERNAME)
  Hostname:     $INSTALL_HOSTNAME

  Festplatte:   $INSTALL_DISK
  Methode:      $INSTALL_PART_METHOD

  ──────────────────────────────────────────

  Alles korrekt? Installation starten?" 26 55 \
    --yes-button "Installieren" --no-button "Zurück" || return 1

    log "Step 6: Summary confirmed - starting installation"
}

# ──────────────────────────────────────────────────────────────
# Step 7: Installation
# ──────────────────────────────────────────────────────────────

do_install() {
    local PROGRESS=0
    local TARGET="/target"

    (
    echo "5"
    echo "XXX"
    echo "Festplatte vorbereiten..."
    echo "XXX"
    log "Partitioning $INSTALL_DISK..."

    # Partitioning
    if [ "$INSTALL_PART_METHOD" = "auto" ]; then
        # Wipe and create partitions
        wipefs -a "$INSTALL_DISK" >> "$LOG_FILE" 2>&1 || true

        if [ -d /sys/firmware/efi ]; then
            # UEFI: EFI + Root + Swap
            parted -s "$INSTALL_DISK" mklabel gpt >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" mkpart ESP fat32 1MiB 512MiB >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" set 1 esp on >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" mkpart primary linux-swap 512MiB 4GiB >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" mkpart primary ext4 4GiB 100% >> "$LOG_FILE" 2>&1

            local efi_part="${INSTALL_DISK}1"
            local swap_part="${INSTALL_DISK}2"
            local root_part="${INSTALL_DISK}3"

            # Handle NVMe naming (p1, p2, p3)
            if echo "$INSTALL_DISK" | grep -q "nvme\|mmcblk"; then
                efi_part="${INSTALL_DISK}p1"
                swap_part="${INSTALL_DISK}p2"
                root_part="${INSTALL_DISK}p3"
            fi

            sleep 1
            mkfs.fat -F32 "$efi_part" >> "$LOG_FILE" 2>&1
            mkswap "$swap_part" >> "$LOG_FILE" 2>&1
            mkfs.ext4 -F "$root_part" >> "$LOG_FILE" 2>&1
        else
            # BIOS: Root + Swap
            parted -s "$INSTALL_DISK" mklabel msdos >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" mkpart primary linux-swap 1MiB 4GiB >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" mkpart primary ext4 4GiB 100% >> "$LOG_FILE" 2>&1

            local swap_part="${INSTALL_DISK}1"
            local root_part="${INSTALL_DISK}2"

            if echo "$INSTALL_DISK" | grep -q "nvme\|mmcblk"; then
                swap_part="${INSTALL_DISK}p1"
                root_part="${INSTALL_DISK}p2"
            fi

            sleep 1
            mkswap "$swap_part" >> "$LOG_FILE" 2>&1
            mkfs.ext4 -F "$root_part" >> "$LOG_FILE" 2>&1
        fi
    fi

    echo "15"
    echo "XXX"
    echo "Dateisysteme mounten..."
    echo "XXX"

    mkdir -p "$TARGET"
    mount "$root_part" "$TARGET" >> "$LOG_FILE" 2>&1

    if [ -d /sys/firmware/efi ]; then
        mkdir -p "$TARGET/boot/efi"
        mount "$efi_part" "$TARGET/boot/efi" >> "$LOG_FILE" 2>&1
    fi

    swapon "$swap_part" >> "$LOG_FILE" 2>&1 || true

    echo "20"
    echo "XXX"
    echo "Basissystem kopieren (dies dauert einige Minuten)..."
    echo "XXX"
    log "Copying filesystem..."

    # Copy the live filesystem to target
    unsquashfs -f -d "$TARGET" /cdrom/casper/filesystem.squashfs >> "$LOG_FILE" 2>&1 || \
    cp -a /rofs/* "$TARGET/" >> "$LOG_FILE" 2>&1 || \
    rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/target"} / "$TARGET/" >> "$LOG_FILE" 2>&1

    echo "60"
    echo "XXX"
    echo "System konfigurieren..."
    echo "XXX"
    log "Configuring system..."

    # Mount virtual filesystems
    mount --bind /dev "$TARGET/dev" >> "$LOG_FILE" 2>&1
    mount --bind /proc "$TARGET/proc" >> "$LOG_FILE" 2>&1
    mount --bind /sys "$TARGET/sys" >> "$LOG_FILE" 2>&1

    # Configure hostname
    echo "$INSTALL_HOSTNAME" > "$TARGET/etc/hostname"
    cat > "$TARGET/etc/hosts" << HOSTS
127.0.0.1   localhost
127.0.1.1   $INSTALL_HOSTNAME

::1         localhost ip6-localhost ip6-loopback
HOSTS

    echo "70"
    echo "XXX"
    echo "Benutzer einrichten..."
    echo "XXX"

    # Create user
    chroot "$TARGET" useradd -m -s /bin/bash -c "$INSTALL_FULLNAME" "$INSTALL_USERNAME" >> "$LOG_FILE" 2>&1 || true
    echo "${INSTALL_USERNAME}:${INSTALL_PASSWORD}" | chroot "$TARGET" chpasswd >> "$LOG_FILE" 2>&1
    chroot "$TARGET" usermod -aG sudo,video,audio,plugdev "$INSTALL_USERNAME" >> "$LOG_FILE" 2>&1 || true

    # Auto-login
    mkdir -p "$TARGET/etc/systemd/system/getty@tty1.service.d"
    cat > "$TARGET/etc/systemd/system/getty@tty1.service.d/autologin.conf" << AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $INSTALL_USERNAME --noclear %I \$TERM
AUTOLOGIN

    echo "75"
    echo "XXX"
    echo "Sprache und Zeitzone setzen..."
    echo "XXX"

    # Locale
    echo "$INSTALL_LANG UTF-8" >> "$TARGET/etc/locale.gen"
    chroot "$TARGET" locale-gen >> "$LOG_FILE" 2>&1 || true
    echo "LANG=$INSTALL_LANG" > "$TARGET/etc/default/locale"

    # Timezone
    chroot "$TARGET" ln -sf "/usr/share/zoneinfo/$INSTALL_TIMEZONE" /etc/localtime >> "$LOG_FILE" 2>&1
    echo "$INSTALL_TIMEZONE" > "$TARGET/etc/timezone"

    # Keyboard
    cat > "$TARGET/etc/default/keyboard" << KEYBOARD
XKBMODEL="pc105"
XKBLAYOUT="$INSTALL_KEYBOARD"
XKBVARIANT=""
XKBOPTIONS=""
KEYBOARD

    echo "80"
    echo "XXX"
    echo "fstab generieren..."
    echo "XXX"

    # Generate fstab
    local root_uuid=$(blkid -s UUID -o value "$root_part")
    cat > "$TARGET/etc/fstab" << FSTAB
# MB-OS fstab - generated by installer
UUID=$root_uuid   /         ext4   errors=remount-ro  0  1
FSTAB

    if [ -d /sys/firmware/efi ]; then
        local efi_uuid=$(blkid -s UUID -o value "$efi_part")
        echo "UUID=$efi_uuid   /boot/efi vfat   umask=0077         0  1" >> "$TARGET/etc/fstab"
    fi

    local swap_uuid=$(blkid -s UUID -o value "$swap_part")
    echo "UUID=$swap_uuid   none      swap   sw                 0  0" >> "$TARGET/etc/fstab"

    echo "85"
    echo "XXX"
    echo "Bootloader installieren (GRUB)..."
    echo "XXX"
    log "Installing GRUB..."

    if [ -d /sys/firmware/efi ]; then
        chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MB-OS >> "$LOG_FILE" 2>&1
    else
        chroot "$TARGET" grub-install --target=i386-pc "$INSTALL_DISK" >> "$LOG_FILE" 2>&1
    fi

    # Copy GRUB theme
    mkdir -p "$TARGET/boot/grub/themes/mb-os"
    cp -r /boot/grub/themes/mb-os/* "$TARGET/boot/grub/themes/mb-os/" 2>/dev/null || true

    # Update GRUB config
    chroot "$TARGET" update-grub >> "$LOG_FILE" 2>&1

    echo "95"
    echo "XXX"
    echo "Aufräumen..."
    echo "XXX"

    # Cleanup
    umount "$TARGET/dev" 2>/dev/null || true
    umount "$TARGET/proc" 2>/dev/null || true
    umount "$TARGET/sys" 2>/dev/null || true

    echo "100"
    echo "XXX"
    echo "Installation abgeschlossen!"
    echo "XXX"

    log "Installation complete!"
    sleep 1

    ) | whiptail --title "$TITLE" --gauge "Installation wird vorbereitet..." 8 60 0
}

# ──────────────────────────────────────────────────────────────
# Step 8: Done
# ──────────────────────────────────────────────────────────────

step_done() {
    whiptail --title "$TITLE - Fertig!" --yesno \
"
  ╔══════════════════════════════════════╗
  ║    ✓ Installation abgeschlossen!    ║
  ╚══════════════════════════════════════╝

  MB-OS wurde erfolgreich auf
  $INSTALL_DISK installiert!

  Benutzer:  $INSTALL_USERNAME
  Hostname:  $INSTALL_HOSTNAME

  Beim nächsten Start kannst du zwischen
  MB-OS und anderen Betriebssystemen wählen.

  Log-Datei: $LOG_FILE

  Jetzt neu starten?" 22 50 \
    --yes-button "Neu starten" --no-button "Weiter testen"

    if [ $? -eq 0 ]; then
        reboot
    fi
}

# ──────────────────────────────────────────────────────────────
# Main Flow
# ──────────────────────────────────────────────────────────────

main() {
    log "=============================="
    log "MB-OS Installer v$INSTALLER_VERSION started"
    log "=============================="

    check_root

    step_welcome   || exit 0
    step_language   || step_language || exit 1
    step_hardware
    step_user       || step_user || exit 1
    step_disk       || step_disk || exit 1
    step_summary    || { step_user; step_disk; step_summary || exit 1; }

    do_install
    step_done

    log "Installer finished."
}

main "$@"
