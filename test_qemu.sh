#!/bin/bash
# QEMU headless test with serial log
rm -f /tmp/qemu-serial.log

echo ">>> Starting QEMU (headless, 150s timeout)..."
timeout 180 qemu-system-x86_64 \
    -m 2048 \
    -cdrom /mnt/d/MB-OS/mb-os.iso \
    -boot d \
    -display none \
    -serial file:/tmp/qemu-serial.log \
    -bios /usr/share/ovmf/OVMF.fd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22 &
QPID=$!
echo "QEMU PID: $QPID"

# Wait for boot (no KVM = slow)
sleep 150

echo "=== SERIAL OUTPUT (last 80 lines) ==="
tail -80 /tmp/qemu-serial.log 2>/dev/null || echo "No serial log!"

# Try SSH
echo "=== SSH TEST ==="
sshpass -p mbos ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2222 mbuser@localhost \
    'cat /tmp/mb-gui.log 2>/dev/null; echo "---"; cat /tmp/mb-shell-error.log 2>/dev/null; echo "---LDD---"; ldd /usr/local/bin/mb-os-shell 2>&1 | grep -i "not found"' 2>&1 || echo "SSH failed (expected without KVM)"

kill $QPID 2>/dev/null
echo "=== QEMU TEST DONE ==="
