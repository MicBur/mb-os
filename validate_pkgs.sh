#!/bin/bash
# Validate all packages exist in Ubuntu 26.04 resolute
PACKAGES="libqt6core6 libqt6gui6 libqt6qml6 libqt6quick6 qml6-module-qtquick qml6-module-qtquick-templates qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-controls qml6-module-qtqml-workerscript qml6-module-qtwebengine libqt6webenginecore6-bin isc-dhcp-client lxpolkit libasound2t64 wpasupplicant pm-utils p7zip-full ntfs-3g-dev plymouth plymouth-themes flatpak os-prober polkitd pkexec linux-image-generic casper"

for pkg in $PACKAGES; do
    apt-cache show "$pkg" > /dev/null 2>&1 && echo "OK: $pkg" || echo "MISSING: $pkg"
done
