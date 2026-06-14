#!/bin/bash
# ══════════════════════════════════════════════════════════════
# MB-OS Installer v3.0
# Terminal-Installer mit Dual-Boot Support
# ══════════════════════════════════════════════════════════════

# Don't use set -e: causes silent failures in gauge subshells

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

INSTALLER_VERSION="3.0"
TITLE="MB-OS Installer v${INSTALLER_VERSION}"
LOG_FILE="/tmp/mb-installer.log"

# Variables
INSTALL_LANG="de_DE.UTF-8"
INSTALL_COUNTRY="DE"
INSTALL_TIMEZONE="Europe/Berlin"
INSTALL_KEYBOARD="de"
INSTALL_HOSTNAME="mb-os"
INSTALL_USERNAME=""
INSTALL_FULLNAME=""
INSTALL_PASSWORD=""
INSTALL_DISK=""
INSTALL_PART_METHOD=""

# Partition variables (set during partitioning)
efi_part=""
swap_part=""
root_part=""

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
        die "Der Installer muss als root ausgefuehrt werden!\n\nBitte starte mit: sudo mb-installer"
    fi
}

# ──────────────────────────────────────────────────────────────
# Step 1: Welcome
# ──────────────────────────────────────────────────────────────

step_welcome() {
    whiptail --title "$TITLE" --yesno \
"
    MB-OS Installer v${INSTALLER_VERSION}

  Dieser Assistent installiert MB-OS auf
  deinem Computer.

  Optionen:
  - Neben Windows installieren (Dual-Boot)
  - Gesamte Festplatte verwenden
  - Freien Speicher nutzen

  Was wird installiert:
  - Qt6/QML Glassmorphism Desktop
  - MB Browser (Firefox)
  - AI Memory System
  - PipeWire Audio, WiFi, Bluetooth
  - Flatpak App Store

  Fortfahren?" 24 50 \
    --yes-button "Weiter" --no-button "Abbrechen"

    [ $? -ne 0 ] && exit 0
    log "Step 1: Welcome - OK"
}

# ──────────────────────────────────────────────────────────────
# Step 2: Language
# ──────────────────────────────────────────────────────────────

step_language() {
    INSTALL_LANG=$(whiptail --title "$TITLE - Sprache" --menu \
        "\nWaehle deine Systemsprache:" 18 60 6 \
        "de_DE.UTF-8" "Deutsch (Deutschland)" \
        "de_AT.UTF-8" "Deutsch (Oesterreich)" \
        "de_CH.UTF-8" "Deutsch (Schweiz)" \
        "en_US.UTF-8" "English (US)" \
        "en_GB.UTF-8" "English (UK)" \
        "fr_FR.UTF-8" "Francais (France)" \
        3>&1 1>&2 2>&3) || return 1

    INSTALL_TIMEZONE=$(whiptail --title "$TITLE - Zeitzone" --menu \
        "\nWaehle deine Zeitzone:" 18 60 6 \
        "Europe/Berlin" "Berlin (MEZ/MESZ)" \
        "Europe/Vienna" "Wien (MEZ/MESZ)" \
        "Europe/Zurich" "Zuerich (MEZ/MESZ)" \
        "Europe/London" "London (GMT/BST)" \
        "America/New_York" "New York (EST/EDT)" \
        "Asia/Tokyo" "Tokyo (JST)" \
        3>&1 1>&2 2>&3) || return 1

    INSTALL_KEYBOARD=$(whiptail --title "$TITLE - Tastatur" --menu \
        "\nWaehle dein Tastaturlayout:" 16 60 4 \
        "de" "Deutsch (QWERTZ)" \
        "us" "US English (QWERTY)" \
        "gb" "UK English (QWERTY)" \
        "fr" "Francais (AZERTY)" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 2: Lang=$INSTALL_LANG TZ=$INSTALL_TIMEZONE KB=$INSTALL_KEYBOARD"
}

# ──────────────────────────────────────────────────────────────
# Step 3: Hardware Detection
# ──────────────────────────────────────────────────────────────

step_hardware() {
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unbekannt")
    local cpu_cores=$(nproc 2>/dev/null || echo "?")
    local ram_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")
    local gpu_info=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | cut -d: -f3 | head -1 | xargs || echo "Unbekannt")
    local disk_info=$(lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v "loop\|sr\|ram" | head -5 || echo "Keine")
    local uefi_mode="Nein (BIOS)"
    [ -d /sys/firmware/efi ] && uefi_mode="Ja (UEFI)"

    whiptail --title "$TITLE - Hardware" --msgbox \
"
  Erkannte Hardware:

  CPU:     $cpu_model ($cpu_cores Kerne)
  RAM:     $ram_total
  GPU:     $gpu_info
  UEFI:    $uefi_mode

  Festplatten:
  $disk_info
" 20 65

    log "Step 3: HW - CPU=$cpu_model RAM=$ram_total UEFI=$uefi_mode"
}

# ──────────────────────────────────────────────────────────────
# Step 4: User Setup
# ──────────────────────────────────────────────────────────────

step_user() {
    INSTALL_FULLNAME=$(whiptail --title "$TITLE - Benutzer" --inputbox \
        "\nDein Name:" 10 50 "" \
        3>&1 1>&2 2>&3) || return 1
    [ -z "$INSTALL_FULLNAME" ] && die "Name darf nicht leer sein!"

    local auto_user=$(echo "$INSTALL_FULLNAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '.' | sed 's/[^a-z0-9.]//g' | cut -c1-20)

    INSTALL_USERNAME=$(whiptail --title "$TITLE - Benutzername" --inputbox \
        "\nBenutzername (Kleinbuchstaben):" 10 50 "$auto_user" \
        3>&1 1>&2 2>&3) || return 1
    [ -z "$INSTALL_USERNAME" ] && die "Benutzername darf nicht leer sein!"

    INSTALL_PASSWORD=$(whiptail --title "$TITLE - Passwort" --passwordbox \
        "\nPasswort fuer '$INSTALL_USERNAME':" 10 50 \
        3>&1 1>&2 2>&3) || return 1
    [ -z "$INSTALL_PASSWORD" ] && die "Passwort darf nicht leer sein!"

    local pw_confirm=$(whiptail --title "$TITLE - Passwort" --passwordbox \
        "\nPasswort wiederholen:" 10 50 \
        3>&1 1>&2 2>&3) || return 1
    [ "$INSTALL_PASSWORD" != "$pw_confirm" ] && die "Passwoerter stimmen nicht ueberein!"

    INSTALL_HOSTNAME=$(whiptail --title "$TITLE - Hostname" --inputbox \
        "\nComputername:" 10 50 "mb-os" \
        3>&1 1>&2 2>&3) || return 1
    [ -z "$INSTALL_HOSTNAME" ] && INSTALL_HOSTNAME="mb-os"

    log "Step 4: User=$INSTALL_USERNAME Host=$INSTALL_HOSTNAME"
}

# ──────────────────────────────────────────────────────────────
# Step 5: Disk & Partitioning (mit Dual-Boot!)
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

    [ $disk_count -eq 0 ] && die "Keine Festplatten erkannt!"

    INSTALL_DISK=$(eval whiptail --title \"$TITLE - Festplatte\" --menu \
        \"\\nWaehle die Festplatte:\" 18 65 $disk_count \
        $disk_list \
        3\>\&1 1\>\&2 2\>\&3) || return 1

    log "Step 5a: Disk=$INSTALL_DISK"

    # Show current partitions
    local part_info=$(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$INSTALL_DISK" 2>/dev/null || echo "Keine")

    # Partitioning method
    INSTALL_PART_METHOD=$(whiptail --title "$TITLE - Partitionierung" --menu \
        "\nPartitionen auf $INSTALL_DISK:\n$part_info\n\nInstallationsart:" 22 65 3 \
        "alongside" "Neben Windows installieren (Dual-Boot)" \
        "auto" "Gesamte Festplatte verwenden (LOESCHT ALLES)" \
        "partition" "Bestehende Partition waehlen" \
        3>&1 1>&2 2>&3) || return 1

    log "Step 5b: Method=$INSTALL_PART_METHOD"

    case "$INSTALL_PART_METHOD" in
        alongside)
            step_disk_alongside
            ;;
        auto)
            step_disk_auto
            ;;
        partition)
            step_disk_partition
            ;;
    esac
}

# --- Dual-Boot: Partition verkleinern + MB-OS daneben ---
step_disk_alongside() {
    # Find shrinkable partitions (NTFS/ext4, > 20GB)
    local shrink_list=""
    local shrink_count=0
    while IFS= read -r line; do
        local pname=$(echo "$line" | awk '{print $1}')
        local psize=$(echo "$line" | awk '{print $2}')
        local pfs=$(echo "$line" | awk '{print $3}')
        local plabel=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs)
        [ -z "$plabel" ] && plabel="$pfs"
        # Only show partitions > 15GB
        local size_bytes=$(lsblk -b -n -o SIZE "/dev/$pname" 2>/dev/null | head -1)
        if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 16000000000 ] 2>/dev/null; then
            shrink_list="$shrink_list /dev/$pname \"$psize $plabel\""
            shrink_count=$((shrink_count + 1))
        fi
    done < <(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$INSTALL_DISK" 2>/dev/null | grep -v "^$(basename $INSTALL_DISK) ")

    if [ $shrink_count -eq 0 ]; then
        whiptail --title "$TITLE" --msgbox \
            "Keine Partitionen > 15GB gefunden.\nVersuche 'Bestehende Partition waehlen'." 10 50
        step_disk_partition
        return
    fi

    local shrink_part=$(eval whiptail --title \"$TITLE - Partition verkleinern\" --menu \
        \"\\nWelche Partition soll verkleinert werden\\num Platz fuer MB-OS zu schaffen?\\n\\nMB-OS braucht mind. 10 GB.\" 20 65 $shrink_count \
        $shrink_list \
        3\>\&1 1\>\&2 2\>\&3) || return 1

    local current_size_gb=$(lsblk -b -n -o SIZE "$shrink_part" 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
    local min_new_size=$((current_size_gb / 2))
    [ $min_new_size -lt 10 ] && min_new_size=10
    local default_new_size=$((current_size_gb - 15))
    [ $default_new_size -lt $min_new_size ] && default_new_size=$min_new_size

    local new_size=$(whiptail --title "$TITLE - Groesse" --inputbox \
        "\nAktuelle Groesse: ${current_size_gb} GB\n\nWie gross soll die Partition bleiben (GB)?\n(Der Rest wird fuer MB-OS verwendet)\n\nMinimum: ${min_new_size} GB" 16 50 "$default_new_size" \
        3>&1 1>&2 2>&3) || return 1

    local mbos_size=$((current_size_gb - new_size))
    if [ $mbos_size -lt 8 ]; then
        die "Zu wenig Platz fuer MB-OS! Mindestens 8 GB noetig.\nVerfuegbar: ${mbos_size} GB"
    fi

    whiptail --title "$TITLE - Bestaetigung" --yesno \
"
  Partition verkleinern:
  $shrink_part: ${current_size_gb}GB -> ${new_size}GB

  MB-OS bekommt: ${mbos_size} GB

  Windows/bestehendes OS bleibt erhalten!

  Fortfahren?" 16 55 \
    --yes-button "Ja" --no-button "Abbrechen" || return 1

    # Store for do_install
    SHRINK_PART="$shrink_part"
    SHRINK_NEW_SIZE="${new_size}"
    MBOS_SIZE="$mbos_size"

    log "Step 5c: Shrink $shrink_part to ${new_size}GB, MB-OS gets ${mbos_size}GB"
}

# --- Gesamte Festplatte ---
step_disk_auto() {
    whiptail --title "$TITLE - WARNUNG" --yesno \
"
  WARNUNG: DATENVERLUST!

  Alle Daten auf $INSTALL_DISK werden
  UNWIDERRUFLICH geloescht!

  Bist du sicher?" 14 50 \
    --yes-button "Ja, loeschen" --no-button "Abbrechen" || return 1

    log "Step 5c: Auto - full disk confirmed"
}

# --- Bestehende Partition waehlen ---
step_disk_partition() {
    INSTALL_PART_METHOD="partition"

    local part_list=""
    local part_count=0
    while IFS= read -r line; do
        local pname=$(echo "$line" | awk '{print $1}')
        local psize=$(echo "$line" | awk '{print $2}')
        local pfs=$(echo "$line" | awk '{print $3}')
        local plabel=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs)
        [ -z "$plabel" ] && plabel="$pfs"
        [ -z "$plabel" ] && plabel="Leer"
        part_list="$part_list /dev/$pname \"$psize $plabel\""
        part_count=$((part_count + 1))
    done < <(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$INSTALL_DISK" 2>/dev/null | grep -v "^$(basename $INSTALL_DISK) ")

    if [ $part_count -eq 0 ]; then
        die "Keine Partitionen auf $INSTALL_DISK gefunden!"
    fi

    INSTALL_PARTITION=$(eval whiptail --title \"$TITLE - Partition\" --menu \
        \"\\nWaehle eine Partition fuer MB-OS:\\n\\nDie gewaehlte Partition wird formatiert!\" 20 65 $part_count \
        $part_list \
        3\>\&1 1\>\&2 2\>\&3) || return 1

    whiptail --title "$TITLE - WARNUNG" --yesno \
        "\nPartition $INSTALL_PARTITION wird formatiert!\nAlle Daten darauf gehen verloren.\n\nFortfahren?" 12 55 \
        --yes-button "Ja" --no-button "Abbrechen" || return 1

    log "Step 5c: Partition=$INSTALL_PARTITION"
}

# ──────────────────────────────────────────────────────────────
# Step 6: Summary
# ──────────────────────────────────────────────────────────────

step_summary() {
    local method_text="$INSTALL_PART_METHOD"
    case "$INSTALL_PART_METHOD" in
        alongside) method_text="Dual-Boot (neben Windows)" ;;
        auto) method_text="Gesamte Festplatte" ;;
        partition) method_text="Partition: $INSTALL_PARTITION" ;;
    esac

    whiptail --title "$TITLE - Zusammenfassung" --yesno \
"
  Installationsuebersicht:

  Sprache:    $INSTALL_LANG
  Zeitzone:   $INSTALL_TIMEZONE
  Tastatur:   $INSTALL_KEYBOARD

  Benutzer:   $INSTALL_FULLNAME ($INSTALL_USERNAME)
  Hostname:   $INSTALL_HOSTNAME

  Festplatte: $INSTALL_DISK
  Methode:    $method_text

  Alles korrekt?" 22 55 \
    --yes-button "Installieren" --no-button "Zurueck" || return 1

    log "Step 6: Summary confirmed"
}

# ──────────────────────────────────────────────────────────────
# Step 7: Installation
# ──────────────────────────────────────────────────────────────

do_install() {
    local TARGET="/target"
    local ERRLOG="/tmp/mb-install-errors.log"
    echo "" > "$ERRLOG"

    # Run the actual installation, capture exit code
    (
    exec 2>>"$ERRLOG"

    echo "5"
    echo "XXX"
    echo "Festplatte vorbereiten..."
    echo "XXX"
    log "Partitioning $INSTALL_DISK (method=$INSTALL_PART_METHOD)..."

    case "$INSTALL_PART_METHOD" in
        auto)
            do_partition_auto || echo "FEHLER: Partitionierung fehlgeschlagen" >> "$ERRLOG"
            ;;
        alongside)
            do_partition_alongside || echo "FEHLER: Alongside-Partitionierung fehlgeschlagen" >> "$ERRLOG"
            ;;
        partition)
            do_partition_existing || echo "FEHLER: Partition-Auswahl fehlgeschlagen" >> "$ERRLOG"
            ;;
    esac

    log "Partitions: efi=$efi_part swap=$swap_part root=$root_part"

    # Validate we have a root partition
    if [ -z "$root_part" ]; then
        echo "FEHLER: Keine Root-Partition gesetzt!" >> "$ERRLOG"
        echo "100"; echo "XXX"; echo "FEHLER: Keine Root-Partition!"; echo "XXX"
        sleep 3
        exit 1
    fi

    echo "10"
    echo "XXX"
    echo "Dateisysteme mounten..."
    echo "XXX"

    mkdir -p "$TARGET"
    if ! mount "$root_part" "$TARGET" >> "$LOG_FILE" 2>&1; then
        echo "FEHLER: mount $root_part failed" >> "$ERRLOG"
        echo "100"; echo "XXX"; echo "FEHLER: Mount fehlgeschlagen!"; echo "XXX"
        sleep 3
        exit 1
    fi

    if [ -n "$efi_part" ]; then
        mkdir -p "$TARGET/boot/efi"
        mount "$efi_part" "$TARGET/boot/efi" >> "$LOG_FILE" 2>&1 || true
    fi

    [ -n "$swap_part" ] && swapon "$swap_part" >> "$LOG_FILE" 2>&1 || true

    echo "15"
    echo "XXX"
    echo "System kopieren (dauert mehrere Minuten)..."
    echo "XXX"
    log "Copying filesystem..."

    # Try multiple sources for the live filesystem
    local copy_ok=0

    # Method 1: unsquashfs from casper
    if [ -f /cdrom/casper/filesystem.squashfs ]; then
        log "Copy method: unsquashfs /cdrom/casper/filesystem.squashfs"
        unsquashfs -f -d "$TARGET" /cdrom/casper/filesystem.squashfs >> "$LOG_FILE" 2>&1 && copy_ok=1
    fi

    # Method 2: copy from /rofs (read-only filesystem mount)
    if [ $copy_ok -eq 0 ] && [ -d /rofs ]; then
        log "Copy method: cp -a /rofs/*"
        cp -a /rofs/* "$TARGET/" >> "$LOG_FILE" 2>&1 && copy_ok=1
    fi

    # Method 3: find squashfs anywhere
    if [ $copy_ok -eq 0 ]; then
        local sqfs=$(find /cdrom /media /mnt -name "filesystem.squashfs" 2>/dev/null | head -1)
        if [ -n "$sqfs" ]; then
            log "Copy method: unsquashfs $sqfs"
            unsquashfs -f -d "$TARGET" "$sqfs" >> "$LOG_FILE" 2>&1 && copy_ok=1
        fi
    fi

    # Method 4: rsync the running system
    if [ $copy_ok -eq 0 ]; then
        log "Copy method: rsync / (last resort)"
        rsync -aAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/target","/cdrom"} / "$TARGET/" >> "$LOG_FILE" 2>&1 && copy_ok=1
    fi

    if [ $copy_ok -eq 0 ]; then
        echo "FEHLER: Konnte Dateisystem nicht kopieren!" >> "$ERRLOG"
        echo "100"; echo "XXX"; echo "FEHLER: Kopieren fehlgeschlagen!"; echo "XXX"
        sleep 3
        exit 1
    fi

    echo "60"
    echo "XXX"
    echo "System konfigurieren..."
    echo "XXX"
    log "Configuring system..."

    mount --bind /dev "$TARGET/dev" >> "$LOG_FILE" 2>&1 || true
    mount --bind /proc "$TARGET/proc" >> "$LOG_FILE" 2>&1 || true
    mount --bind /sys "$TARGET/sys" >> "$LOG_FILE" 2>&1 || true

    # DNS in chroot
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # Hostname
    echo "$INSTALL_HOSTNAME" > "$TARGET/etc/hostname"
    cat > "$TARGET/etc/hosts" << HOSTS
127.0.0.1   localhost
127.0.1.1   $INSTALL_HOSTNAME
HOSTS

    echo "70"
    echo "XXX"
    echo "Benutzer einrichten..."
    echo "XXX"

    chroot "$TARGET" useradd -m -s /bin/bash -c "$INSTALL_FULLNAME" "$INSTALL_USERNAME" >> "$LOG_FILE" 2>&1 || true
    echo "${INSTALL_USERNAME}:${INSTALL_PASSWORD}" | chroot "$TARGET" chpasswd >> "$LOG_FILE" 2>&1 || true
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
    echo "Sprache und Zeitzone..."
    echo "XXX"

    echo "$INSTALL_LANG UTF-8" >> "$TARGET/etc/locale.gen"
    chroot "$TARGET" locale-gen >> "$LOG_FILE" 2>&1 || true
    echo "LANG=$INSTALL_LANG" > "$TARGET/etc/default/locale"

    chroot "$TARGET" ln -sf "/usr/share/zoneinfo/$INSTALL_TIMEZONE" /etc/localtime >> "$LOG_FILE" 2>&1 || true
    echo "$INSTALL_TIMEZONE" > "$TARGET/etc/timezone"

    cat > "$TARGET/etc/default/keyboard" << KEYBOARD
XKBMODEL="pc105"
XKBLAYOUT="$INSTALL_KEYBOARD"
KEYBOARD

    echo "80"
    echo "XXX"
    echo "fstab generieren..."
    echo "XXX"

    # Generate fstab
    local root_uuid=$(blkid -s UUID -o value "$root_part" 2>/dev/null)
    cat > "$TARGET/etc/fstab" << FSTAB
# MB-OS fstab
UUID=$root_uuid   /         ext4   errors=remount-ro  0  1
FSTAB

    if [ -n "$efi_part" ]; then
        local efi_uuid=$(blkid -s UUID -o value "$efi_part" 2>/dev/null)
        echo "UUID=$efi_uuid   /boot/efi vfat   umask=0077         0  1" >> "$TARGET/etc/fstab"
    fi

    if [ -n "$swap_part" ]; then
        local swap_uuid=$(blkid -s UUID -o value "$swap_part" 2>/dev/null)
        echo "UUID=$swap_uuid   none      swap   sw                 0  0" >> "$TARGET/etc/fstab"
    fi

    echo "85"
    echo "XXX"
    echo "Bootloader installieren (GRUB)..."
    echo "XXX"
    log "Installing GRUB..."

    if [ -d /sys/firmware/efi ]; then
        chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MB-OS --recheck >> "$LOG_FILE" 2>&1 || true
        # UEFI Fallback
        mkdir -p "$TARGET/boot/efi/EFI/BOOT"
        cp "$TARGET/boot/efi/EFI/MB-OS/grubx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
    else
        chroot "$TARGET" grub-install --target=i386-pc "$INSTALL_DISK" >> "$LOG_FILE" 2>&1 || true
    fi

    # Enable os-prober for dual-boot detection
    echo "GRUB_DISABLE_OS_PROBER=false" >> "$TARGET/etc/default/grub"

    chroot "$TARGET" update-grub >> "$LOG_FILE" 2>&1 || true

    echo "95"
    echo "XXX"
    echo "Aufraeumen..."
    echo "XXX"

    umount "$TARGET/dev" 2>/dev/null || true
    umount "$TARGET/proc" 2>/dev/null || true
    umount "$TARGET/sys" 2>/dev/null || true

    echo "100"
    echo "XXX"
    echo "Installation abgeschlossen!"
    echo "XXX"

    log "Installation complete!"
    sleep 2

    ) | whiptail --title "$TITLE" --gauge "Installation wird vorbereitet..." 8 60 0

    # Show errors if any
    if [ -s "$ERRLOG" ] && grep -q "FEHLER" "$ERRLOG" 2>/dev/null; then
        whiptail --title "Installations-Fehler" --scrolltext --msgbox \
            "$(cat $ERRLOG)\n\nLog: $LOG_FILE" 20 70
    fi
}

# --- Auto: Full disk ---
do_partition_auto() {
    wipefs -a "$INSTALL_DISK" >> "$LOG_FILE" 2>&1 || true

    if [ -d /sys/firmware/efi ]; then
        parted -s "$INSTALL_DISK" mklabel gpt >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" mkpart ESP fat32 1MiB 512MiB >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" set 1 esp on >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" mkpart primary linux-swap 512MiB 4GiB >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" mkpart primary ext4 4GiB 100% >> "$LOG_FILE" 2>&1

        efi_part="${INSTALL_DISK}1"
        swap_part="${INSTALL_DISK}2"
        root_part="${INSTALL_DISK}3"
    else
        parted -s "$INSTALL_DISK" mklabel msdos >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" mkpart primary linux-swap 1MiB 4GiB >> "$LOG_FILE" 2>&1
        parted -s "$INSTALL_DISK" mkpart primary ext4 4GiB 100% >> "$LOG_FILE" 2>&1

        swap_part="${INSTALL_DISK}1"
        root_part="${INSTALL_DISK}2"
    fi

    # Handle NVMe/eMMC naming
    if echo "$INSTALL_DISK" | grep -q "nvme\|mmcblk"; then
        [ -n "$efi_part" ] && efi_part="${INSTALL_DISK}p1"
        swap_part="${INSTALL_DISK}p$( [ -d /sys/firmware/efi ] && echo 2 || echo 1)"
        root_part="${INSTALL_DISK}p$( [ -d /sys/firmware/efi ] && echo 3 || echo 2)"
    fi

    sleep 1
    [ -n "$efi_part" ] && mkfs.fat -F32 "$efi_part" >> "$LOG_FILE" 2>&1
    mkswap "$swap_part" >> "$LOG_FILE" 2>&1
    mkfs.ext4 -F "$root_part" >> "$LOG_FILE" 2>&1

    log "Auto partitioning done: efi=$efi_part swap=$swap_part root=$root_part"
}

# --- Alongside: Shrink + create MB-OS partitions ---
do_partition_alongside() {
    log "Alongside: Shrinking $SHRINK_PART to ${SHRINK_NEW_SIZE}GB..."

    local shrink_fs=$(blkid -s TYPE -o value "$SHRINK_PART" 2>/dev/null)

    if [ "$shrink_fs" = "ntfs" ]; then
        # NTFS: Use ntfsresize
        ntfsfix "$SHRINK_PART" >> "$LOG_FILE" 2>&1 || true
        local new_bytes=$((SHRINK_NEW_SIZE * 1024 * 1024 * 1024))
        ntfsresize -f -s "${new_bytes}" "$SHRINK_PART" >> "$LOG_FILE" 2>&1
    elif [ "$shrink_fs" = "ext4" ] || [ "$shrink_fs" = "ext3" ]; then
        # EXT4: Use resize2fs
        e2fsck -f -y "$SHRINK_PART" >> "$LOG_FILE" 2>&1 || true
        resize2fs "$SHRINK_PART" "${SHRINK_NEW_SIZE}G" >> "$LOG_FILE" 2>&1
    fi

    # Get partition number and shrink in parted
    local part_num=$(echo "$SHRINK_PART" | grep -oE '[0-9]+$')
    local shrink_end_mb=$((SHRINK_NEW_SIZE * 1024))

    # Resize the partition itself
    parted -s "$INSTALL_DISK" resizepart "$part_num" "${shrink_end_mb}MiB" >> "$LOG_FILE" 2>&1 || true

    # Find where free space starts
    local free_start=$(parted -s "$INSTALL_DISK" unit MiB print free 2>/dev/null | grep "Free Space" | tail -1 | awk '{print $1}' | tr -d 'MiB')

    if [ -z "$free_start" ]; then
        free_start=$((shrink_end_mb + 1))
    fi

    log "Free space starts at ${free_start}MiB"

    # Create MB-OS partitions in the free space
    if [ -d /sys/firmware/efi ]; then
        # Check if EFI partition already exists
        local existing_efi=$(blkid -t TYPE=vfat -o device 2>/dev/null | head -1)
        if [ -n "$existing_efi" ]; then
            efi_part="$existing_efi"
            log "Using existing EFI partition: $efi_part"
        else
            parted -s "$INSTALL_DISK" mkpart ESP fat32 "${free_start}MiB" "$((free_start + 512))MiB" >> "$LOG_FILE" 2>&1
            parted -s "$INSTALL_DISK" set $(parted -s "$INSTALL_DISK" print 2>/dev/null | tail -2 | head -1 | awk '{print $1}') esp on >> "$LOG_FILE" 2>&1
            free_start=$((free_start + 512))
            # Find new EFI partition
            sleep 1
            efi_part=$(lsblk -n -o NAME "$INSTALL_DISK" 2>/dev/null | tail -3 | head -1 | xargs)
            efi_part="/dev/$efi_part"
            mkfs.fat -F32 "$efi_part" >> "$LOG_FILE" 2>&1
        fi
    fi

    # Swap (2GB for low-RAM systems)
    local swap_end=$((free_start + 2048))
    parted -s "$INSTALL_DISK" mkpart primary linux-swap "${free_start}MiB" "${swap_end}MiB" >> "$LOG_FILE" 2>&1
    free_start=$swap_end

    # Root (rest)
    parted -s "$INSTALL_DISK" mkpart primary ext4 "${free_start}MiB" 100% >> "$LOG_FILE" 2>&1

    sleep 1

    # Find new partitions
    local all_parts=$(lsblk -n -o NAME "$INSTALL_DISK" 2>/dev/null | grep -v "^$(basename $INSTALL_DISK)$")
    swap_part="/dev/$(echo "$all_parts" | tail -2 | head -1 | xargs)"
    root_part="/dev/$(echo "$all_parts" | tail -1 | xargs)"

    mkswap "$swap_part" >> "$LOG_FILE" 2>&1
    mkfs.ext4 -F "$root_part" >> "$LOG_FILE" 2>&1

    log "Alongside done: efi=$efi_part swap=$swap_part root=$root_part"
}

# --- Use existing partition ---
do_partition_existing() {
    root_part="$INSTALL_PARTITION"
    mkfs.ext4 -F "$root_part" >> "$LOG_FILE" 2>&1

    # Try to find existing EFI partition
    if [ -d /sys/firmware/efi ]; then
        efi_part=$(blkid -t TYPE=vfat -o device 2>/dev/null | head -1)
        log "Using existing EFI: $efi_part"
    fi

    # No swap for partition install
    swap_part=""

    log "Partition install: root=$root_part efi=$efi_part"
}

# ──────────────────────────────────────────────────────────────
# Step 8: Done
# ──────────────────────────────────────────────────────────────

step_done() {
    whiptail --title "$TITLE - Fertig!" --yesno \
"
  Installation abgeschlossen!

  MB-OS auf $INSTALL_DISK installiert.

  Benutzer:  $INSTALL_USERNAME
  Hostname:  $INSTALL_HOSTNAME

  Beim naechsten Start kannst du zwischen
  MB-OS und Windows waehlen (GRUB Menu).

  Jetzt neu starten?" 18 50 \
    --yes-button "Neu starten" --no-button "Weiter testen"

    [ $? -eq 0 ] && reboot
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

main() {
    log "=============================="
    log "MB-OS Installer v$INSTALLER_VERSION"
    log "=============================="

    check_root
    step_welcome    || exit 0
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
