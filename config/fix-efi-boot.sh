#!/bin/bash
# =====================================================================
# MB-OS EFI Boot Repair Script
# =====================================================================
# This script is executed inside the installed system (chroot) during 
# installation (e.g. by Calamares shellprocess module) to install
# GRUB EFI properly with a --removable fallback for Acer systems.
# =====================================================================

set -e
set -x

echo ">>> Starting MB-OS EFI Boot Repair Hook..."

# 1. Verify EFI environment
if [ ! -d /sys/firmware/efi ]; then
    echo "Warning: Not booted in UEFI mode or /sys/firmware/efi is missing."
    echo "This script is only applicable to UEFI systems."
    exit 0
fi

# 2. Determine target partitions and UUIDs
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -z "$ROOT_DEV" ]; then
    # Fallback if findmnt failed
    ROOT_UUID=$(awk '$2=="/" {print $1}' /etc/fstab | grep UUID | cut -d= -f2)
    ROOT_DEV=$(blkid -U "$ROOT_UUID" || true)
else
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV" || true)
fi

if [ -z "$ROOT_UUID" ]; then
    echo "Error: Could not determine ROOT UUID."
    exit 1
fi
echo "Root device: $ROOT_DEV, UUID: $ROOT_UUID"

# Find EFI partition
EFI_DEV=$(findmnt -n -o SOURCE /boot/efi)
if [ -z "$EFI_DEV" ]; then
    # Fallback to fstab
    EFI_UUID=$(awk '$2=="/boot/efi" {print $1}' /etc/fstab | grep UUID | cut -d= -f2)
    EFI_DEV=$(blkid -U "$EFI_UUID" || true)
else
    EFI_UUID=$(blkid -s UUID -o value "$EFI_DEV" || true)
fi

if [ -z "$EFI_DEV" ] || [ -z "$EFI_UUID" ]; then
    echo "Error: Could not determine EFI partition or UUID."
    exit 1
fi
echo "EFI device: $EFI_DEV, UUID: $EFI_UUID"

# 3. Mount efivars inside chroot (if not already mounted)
if [ ! -d /sys/firmware/efi/efivars ] || [ -z "$(ls -A /sys/firmware/efi/efivars 2>/dev/null)" ]; then
    echo "Mounting efivarfs..."
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
fi

# 4. Install grub packages just in case
echo "Installing grub-efi-amd64 and efibootmgr..."
apt-get install -y --no-install-recommends grub-efi-amd64 grub-efi-amd64-bin efibootmgr || true

# 5. GRUB Installation (Removable Fallback + NVRAM)
# --removable is crucial for Acer, as it copies grubx64.efi to EFI/BOOT/BOOTX64.EFI
echo "Running grub-install with --removable..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MB-OS --removable --recheck

echo "Running standard grub-install..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MB-OS --recheck || \
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=MB-OS --no-nvram --recheck

# 6. Ensure double redirect grub.cfg configs
echo "Configuring redirect grub.cfg files..."
mkdir -p /boot/efi/EFI/MB-OS
mkdir -p /boot/efi/EFI/BOOT

# Copy shim/grub files manually to BOOT directory as backup
if [ -f /boot/efi/EFI/MB-OS/grubx64.efi ]; then
    cp /boot/efi/EFI/MB-OS/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
fi

for grubdir in /boot/efi/EFI/MB-OS /boot/efi/EFI/BOOT; do
    cat > "$grubdir/grub.cfg" << EFIGRUB
search.fs_uuid $ROOT_UUID root
set prefix=(\$root)/boot/grub
configfile \$prefix/grub.cfg
EFIGRUB
done

# 7. Configure /etc/default/grub settings
echo "Updating /etc/default/grub configurations..."
if [ -f /etc/default/grub ]; then
    # Ensure os-prober is enabled for dual boot
    if ! grep -q "GRUB_DISABLE_OS_PROBER" /etc/default/grub; then
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    else
        sed -i 's/GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    fi
fi

# 8. Re-register NVRAM boot entry using efibootmgr
echo "Registering UEFI NVRAM entry..."
EFI_DISK=$(echo "$EFI_DEV" | sed 's/[0-9]*$//')
EFI_PART=$(echo "$EFI_DEV" | grep -oE '[0-9]+$')

if [ -n "$EFI_DISK" ] && [ -n "$EFI_PART" ]; then
    # Delete existing duplicate entries for MB-OS
    efibootmgr | grep "MB-OS" | cut -d' ' -f1 | tr -d 'Boot*' | xargs -I{} efibootmgr -B -b {} 2>/dev/null || true
    # Create new entry
    efibootmgr --create --disk "$EFI_DISK" --part "$EFI_PART" --label "MB-OS" --loader '\\EFI\\MB-OS\\grubx64.efi' || true
fi

# 9. Update grub configuration file
echo "Updating main grub.cfg..."
update-grub

echo ">>> MB-OS EFI Boot Repair Hook completed successfully!"
