#!/bin/bash
# Kopiere Qt6 6.10 Libs vom WSL ins ISO-rootfs und repacke
set -e

echo ">>> Qt6 6.10 Libs ins rootfs kopieren..."
ISO="/mnt/d/MB-OS/mb-os-v6.iso"
OUTISO="/mnt/d/MB-OS/mb-os-v7.iso"

rm -rf /tmp/iso-patch
mkdir -p /tmp/iso-patch/mnt /tmp/iso-patch/iso

# 1. ISO inhalt kopieren
sudo mount -o loop "$ISO" /tmp/iso-patch/mnt
cp -a /tmp/iso-patch/mnt/* /tmp/iso-patch/iso/
sudo umount /tmp/iso-patch/mnt

# 2. Squashfs entpacken
echo ">>> Entpacke squashfs..."
sudo unsquashfs -f -d /tmp/iso-patch/sqfs /tmp/iso-patch/iso/casper/filesystem.squashfs

# 3. Qt6 Core-Libs kopieren (von WSL System)
echo ">>> Kopiere Qt6 6.10 Libs..."
QT_LIBS=(
    libQt6Core.so.6
    libQt6Gui.so.6
    libQt6Qml.so.6
    libQt6Quick.so.6
    libQt6Network.so.6
    libQt6DBus.so.6
    libQt6OpenGL.so.6
    libQt6QmlModels.so.6
    libQt6QmlWorkerScript.so.6
    libQt6QuickControls2.so.6
    libQt6QuickControls2Impl.so.6
    libQt6QuickLayouts.so.6
    libQt6QuickTemplates2.so.6
    libQt6ShaderTools.so.6
    libQt6Svg.so.6
    libQt6WaylandClient.so.6
    libQt6WaylandEglClientHwIntegration.so.6
    libQt6WlShellIntegration.so.6
    libQt6XcbQpa.so.6
    libQt6EglFSDeviceIntegration.so.6
    libQt6OpenGLWidgets.so.6
    libQt6Widgets.so.6
)

LIBDIR="/usr/lib/x86_64-linux-gnu"
DESTDIR="/tmp/iso-patch/sqfs${LIBDIR}"

for lib in "${QT_LIBS[@]}"; do
    if [ -f "${LIBDIR}/${lib}" ]; then
        sudo cp -L "${LIBDIR}/${lib}" "${DESTDIR}/${lib}" 2>/dev/null || true
        # Auch die versionierten Symlinks
        for f in "${LIBDIR}/${lib}".*; do
            [ -f "$f" ] && sudo cp -L "$f" "${DESTDIR}/$(basename $f)" 2>/dev/null || true
        done
        echo "  ✓ ${lib}"
    fi
done

# 4. QML Module kopieren
echo ">>> Kopiere QML Module..."
QML_SRC="/usr/lib/x86_64-linux-gnu/qt6/qml"
QML_DST="/tmp/iso-patch/sqfs/usr/lib/x86_64-linux-gnu/qt6/qml"

# Kritische QML Module
QML_MODULES=(
    QtQuick
    QtQuick/Controls
    QtQuick/Layouts
    QtQuick/Templates
    QtQuick/Window
    QtQml
    QtQml/WorkerScript
)

for mod in "${QML_MODULES[@]}"; do
    if [ -d "${QML_SRC}/${mod}" ]; then
        sudo mkdir -p "${QML_DST}/${mod}"
        sudo cp -rL "${QML_SRC}/${mod}/"* "${QML_DST}/${mod}/" 2>/dev/null || true
        echo "  ✓ ${mod}"
    fi
done

# 5. Qt6 Plugins kopieren
echo ">>> Kopiere Qt6 Plugins..."
PLUGIN_SRC="/usr/lib/x86_64-linux-gnu/qt6/plugins"
PLUGIN_DST="/tmp/iso-patch/sqfs/usr/lib/x86_64-linux-gnu/qt6/plugins"

for pdir in platforms xcbglintegrations imageformats egldeviceintegrations platforminputcontexts; do
    if [ -d "${PLUGIN_SRC}/${pdir}" ]; then
        sudo mkdir -p "${PLUGIN_DST}/${pdir}"
        sudo cp -rL "${PLUGIN_SRC}/${pdir}/"* "${PLUGIN_DST}/${pdir}/" 2>/dev/null || true
        echo "  ✓ plugins/${pdir}"
    fi
done

# 6. Zusätzliche Dependencies
echo ">>> Kopiere zusätzliche Dependencies..."
EXTRA_DEPS=(
    libxkbcommon.so.0
    libxkbcommon-x11.so.0
    libdouble-conversion.so.3
    libmd4c.so.0
    libpcre2-16.so.0
    libb2.so.1
)

for dep in "${EXTRA_DEPS[@]}"; do
    if [ -f "${LIBDIR}/${dep}" ]; then
        sudo cp -L "${LIBDIR}/${dep}" "${DESTDIR}/${dep}" 2>/dev/null || true
        echo "  ✓ ${dep}"
    fi
done

# 7. mb-os-shell nochmal kopieren (sicherheitshalber)
sudo cp /mnt/d/MB-OS/gui/build/mb-os-shell /tmp/iso-patch/sqfs/usr/local/bin/mb-os-shell
sudo chmod +x /tmp/iso-patch/sqfs/usr/local/bin/mb-os-shell

# 8. Verify
echo ">>> Verifikation: ldd mb-os-shell..."
sudo chroot /tmp/iso-patch/sqfs /bin/bash -c "ldd /usr/local/bin/mb-os-shell 2>&1 | grep -i 'not found'" || echo "  ✓ Alle Dependencies gefunden!"

# 9. Squashfs neu packen
echo ">>> Squashfs neu packen..."
rm -f /tmp/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs /tmp/iso-patch/sqfs /tmp/iso-patch/iso/casper/filesystem.squashfs -noappend

# 10. Rootfs löschen
rm -rf /tmp/iso-patch/sqfs

# 11. ISO bauen
echo ">>> ISO bauen..."
sudo grub-mkrescue -o "$OUTISO" /tmp/iso-patch/iso/

ls -lh "$OUTISO"
echo "=== Qt6 PATCH FERTIG ==="
