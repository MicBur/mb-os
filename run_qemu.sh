#!/bin/bash

ISO_PATH="mb-os.iso"

if [ ! -f "$ISO_PATH" ]; then
    echo "Error: $ISO_PATH not found. Run ./build_iso.sh first!"
    exit 1
fi

VM_ISO_PATH="/tmp/mb-os.iso"
echo "=== Preparing ISO ==="
echo "Copying ISO to local WSL disk ($VM_ISO_PATH) to prevent host-mount I/O timeouts..."
cp "$ISO_PATH" "$VM_ISO_PATH"

echo "=== Starting QEMU for MB-OS ==="
echo "Memory: 8GB"
echo "CD-ROM: $VM_ISO_PATH"

QEMU_OPTS="-m 8G -cdrom $VM_ISO_PATH -vga std -serial file:qemu_serial.log -nic user,model=virtio"

# Fix KVM permissions (WSL2 resets them on restart)
if [ -e /dev/kvm ]; then
    sudo chmod 666 /dev/kvm 2>/dev/null
fi

# Check if KVM is available
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM acceleration enabled."
    QEMU_OPTS="$QEMU_OPTS -enable-kvm -cpu host"
else
    echo "KVM not available. Running in software emulation mode (slower)."
    QEMU_OPTS="$QEMU_OPTS -cpu max"
fi

echo "Launching QEMU..."
qemu-system-x86_64 $QEMU_OPTS

