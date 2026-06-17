import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    visible: true
    width: 1024
    height: 768
    visibility: ApplicationWindow.FullScreen
    title: "MB-OS Desktop Shell"

    property bool homeEditMode: false
    property int homeContextIndex: -1
    property int currentHomePage: 0

    // Deferred home screen add (avoids layout deadlock with popups)
    Timer {
        id: deferredHomeAdd
        interval: 300
        repeat: false
        property string pName; property string pIcon; property string pCmd; property string pClr; property int pPage
        onTriggered: {
            console.log("DEFERRED ADD: page=" + pPage + " name=" + pName + " cmd=" + pCmd);
            systemMonitor.addToHomeScreen(pPage, pName, pIcon, pCmd, pClr);
            mainWorkspace.refreshHomeGrid();
        }
    }

    // Background Image with deep dark premium hues and a soft glow
    background: Image {
        source: "qrc:/assets/wallpaper.png"
        fillMode: Image.PreserveAspectCrop

        // Dark overlay for readability
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.03, 0.04, 0.08, 0.5) // Glass-like tinted overlay
        }

        // Decorative subtle neon glow in the top-right
        Rectangle {
            width: 400
            height: 400
            radius: 200
            color: themeManager.glowColor
            x: parent.width - 250
            y: -150
            scale: 1.5
            opacity: 0.3
        }

        // Decorative subtle neon glow in the bottom-left
        Rectangle {
            width: 450
            height: 450
            radius: 225
            color: themeManager.glowColor2
            x: -200
            y: parent.height - 250
            scale: 1.5
            opacity: 0.25
        }
    }

    // Timer for time and date
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var date = new Date();
            timeLabel.text = date.toLocaleTimeString(Qt.locale(), "HH:mm:ss");
            dateLabel.text = date.toLocaleDateString(Qt.locale(), "dd. MMMM yyyy");
        }
    }

    // Top Status Bar (Glassmorphic)
    Rectangle {
        id: topBar
        width: parent.width
        height: 60
        color: themeManager.glassBgColor
        border.color: themeManager.glassBorderColor
        border.width: 1
        anchors.top: parent.top

        Item {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20

            Row {
                id: leftRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20
                height: parent.height

                // OS Logo / Title
                Text {
                    text: "MB-OS"
                    color: themeManager.accentColor
                    font.pixelSize: 22
                    font.bold: true
                    font.family: "Outfit, Inter, sans-serif"
                    anchors.verticalCenter: parent.verticalCenter
                    style: Text.Outline
                    styleColor: "#50000000"
                }

                Rectangle {
                    width: 1
                    height: 30
                    color: themeManager.glassBorderColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                // CPU Usage (clickable to toggle overlay)
                Item {
                    width: cpuRow.width
                    height: parent.height
                    Row {
                        id: cpuRow
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "CPU"
                            color: "#a0a5c0"
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Rectangle {
                            width: 120
                            height: 8
                            color: themeManager.glassBorderColor
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: parent.width * (systemMonitor.cpuUsage / 100.0)
                                height: parent.height
                                color: systemMonitor.cpuUsage > 80 ? "#ff4060" : themeManager.accentColor
                                radius: 4
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }
                        Text {
                            text: Math.round(systemMonitor.cpuUsage) + "%"
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.bold: true
                            width: 35
                        }
                        // Temp indicator
                        Text {
                            text: systemMonitor.cpuTempC > 0 ? Math.round(systemMonitor.cpuTempC) + "°" : ""
                            color: systemMonitor.cpuTempC > 80 ? "#ff4060" : "#a0a5c0"
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sysOverlay.visible = !sysOverlay.visible
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                // Memory Usage
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "RAM"
                        color: "#a0a5c0"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Rectangle {
                        width: 120
                        height: 8
                        color: themeManager.glassBorderColor
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * (systemMonitor.memUsage / 100.0)
                            height: parent.height
                            color: systemMonitor.memUsage > 80 ? "#ff4060" : themeManager.secondaryColor
                            radius: 4
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                    Text {
                        text: Math.round(systemMonitor.memUsage) + "%"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.bold: true
                        width: 35
                    }
                }

                // GPU in topbar
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: systemMonitor.gpuUsage > 0
                    Text {
                        text: "GPU"
                        color: "#a0a5c0"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Rectangle {
                        width: 80
                        height: 8
                        color: themeManager.glassBorderColor
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * (systemMonitor.gpuUsage / 100.0)
                            height: parent.height
                            color: systemMonitor.gpuUsage > 80 ? "#ff4060" : "#a78bfa"
                            radius: 4
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                    Text {
                        text: Math.round(systemMonitor.gpuUsage) + "%"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.bold: true
                        width: 35
                    }
                }
            }

            // Right side: Date & Time + Power
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: timeLabel
                        text: new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.bold: true
                        font.family: "monospace"
                        anchors.right: parent.right
                    }
                    Text {
                        id: dateLabel
                        text: new Date().toLocaleDateString(Qt.locale(), "dd. MMMM yyyy")
                        color: "#80a5c0"
                        font.pixelSize: 10
                        anchors.right: parent.right
                    }
                }
                // === Laptop Status Icons ===

                // WiFi Indicator
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: systemMonitor.wifiConnected ? "📶" : "📡"
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: systemMonitor.wifiConnected ? 1.0 : 0.4
                    }
                    Text {
                        text: systemMonitor.wifiConnected ? systemMonitor.wifiName : "Offline"
                        color: systemMonitor.wifiConnected ? "#a0a5c0" : "#606070"
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Volume Indicator
                Text {
                    text: systemMonitor.volumeMuted ? "🔇" :
                          systemMonitor.volumeLevel > 60 ? "🔊" :
                          systemMonitor.volumeLevel > 20 ? "🔉" : "🔈"
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: systemMonitor.volumeMuted ? 0.4 : 0.9
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: systemMonitor.toggleMute()
                    }
                }

                // Brightness
                Row {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "☀"
                        font.pixelSize: 12
                        color: "#a0a5c0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: systemMonitor.brightnessLevel + "%"
                        color: "#a0a5c0"
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Battery (only if present)
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: systemMonitor.batteryPresent
                    Text {
                        text: systemMonitor.batteryCharging ? "⚡" :
                              systemMonitor.batteryLevel > 80 ? "🔋" :
                              systemMonitor.batteryLevel > 15 ? "🪫" : "🪫"
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: systemMonitor.batteryLevel + "%"
                        color: systemMonitor.batteryLevel <= 15 ? "#ff4060" :
                               systemMonitor.batteryLevel <= 30 ? "#f59e0b" : "#a0a5c0"
                        font.pixelSize: 11
                        font.bold: systemMonitor.batteryLevel <= 15
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    width: 1
                    height: 30
                    color: themeManager.glassBorderColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Settings Icon Button
                Button {
                    id: settingsBtn
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    background: Rectangle {
                        color: settingsBtn.hovered ? "#30" + themeManager.accentColor.toString().substring(1) : "transparent"
                        radius: 18
                        border.color: settingsBtn.hovered ? themeManager.accentColor : themeManager.glassBorderColor
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: "\u2699"
                        color: settingsBtn.hovered ? themeManager.accentColor : "#ffffff"
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: settingsPanel.open()
                }

                Rectangle {
                    width: 1
                    height: 30
                    color: themeManager.glassBorderColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Power Icon Button
                Button {
                    id: powerBtn
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    background: Rectangle {
                        color: powerBtn.hovered ? "#30ff4060" : "transparent"
                        radius: 18
                        border.color: powerBtn.hovered ? "#ff4060" : themeManager.glassBorderColor
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: "⏻"
                        color: powerBtn.hovered ? "#ff4060" : "#ffffff"
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: powerMenu.open()
                }
            }
        }
    }

    // ===== System Monitor Overlay Panel =====
    Rectangle {
        id: sysOverlay
        visible: false
        width: 340
        height: overlayCol.implicitHeight + 32
        x: 100
        anchors.top: topBar.bottom
        anchors.topMargin: 4
        z: 900
        color: themeManager.glassBgColor
        border.color: themeManager.glassBorderColor
        border.width: 1
        radius: 16
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Close when clicking outside
        MouseArea {
            anchors.fill: parent
            // Consume clicks so they don't go through
        }

        Column {
            id: overlayCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Header
            Row {
                spacing: 10
                Text {
                    text: "System Monitor"
                    color: themeManager.accentColor
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: systemMonitor.cpuTempC > 0 ? Math.round(systemMonitor.cpuTempC) + " °C" : ""
                    color: systemMonitor.cpuTempC > 80 ? "#ff4060" : "#a0a5c0"
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 120; height: 1 }
                Text {
                    text: "✕"
                    color: "#a0a5c0"
                    font.pixelSize: 16
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sysOverlay.visible = false
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            // Separator
            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // CPU Cores Header
            Text {
                text: "CPU Kerne (" + systemMonitor.coreCount + ")"
                color: "#a0a5c0"
                font.pixelSize: 12
                font.bold: true
            }

            // Per-core bars
            Grid {
                columns: 2
                columnSpacing: 12
                rowSpacing: 6
                width: parent.width - 32

                Repeater {
                    model: systemMonitor.coreUsages
                    Row {
                        spacing: 6
                        width: 145
                        Text {
                            text: "C" + index
                            color: "#808590"
                            font.pixelSize: 11
                            width: 22
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            width: 85
                            height: 10
                            color: "#20ffffff"
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: parent.width * (modelData / 100.0)
                                height: parent.height
                                radius: 5
                                color: modelData > 90 ? "#ff4060" : modelData > 60 ? "#f59e0b" : themeManager.accentColor
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }
                        Text {
                            text: Math.round(modelData) + "%"
                            color: "#ffffff"
                            font.pixelSize: 11
                            width: 30
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Separator
            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // GPU Section
            Text {
                text: systemMonitor.gpuName
                color: "#a0a5c0"
                font.pixelSize: 12
                font.bold: true
            }
            Row {
                spacing: 8
                Text {
                    text: "Auslastung"
                    color: "#808590"
                    font.pixelSize: 11
                    width: 65
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 180
                    height: 10
                    color: "#20ffffff"
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: parent.width * (systemMonitor.gpuUsage / 100.0)
                        height: parent.height
                        radius: 5
                        color: systemMonitor.gpuUsage > 80 ? "#ff4060" : "#a78bfa"
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
                Text {
                    text: Math.round(systemMonitor.gpuUsage) + "%"
                    color: "#ffffff"
                    font.pixelSize: 11
                    width: 35
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Separator
            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // Summary line
            Row {
                spacing: 15
                Text {
                    text: "CPU " + Math.round(systemMonitor.cpuUsage) + "%"
                    color: themeManager.accentColor
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    text: "RAM " + Math.round(systemMonitor.memUsage) + "%"
                    color: themeManager.secondaryColor
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    text: "GPU " + Math.round(systemMonitor.gpuUsage) + "%"
                    color: "#a78bfa"
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }
    }

    // ===== Quick Settings Panel =====
    Rectangle {
        id: quickSettingsPanel
        visible: false
        width: 300
        height: qsCol.implicitHeight + 32
        anchors.top: topBar.bottom
        anchors.topMargin: 4
        anchors.right: parent.right
        anchors.rightMargin: 60
        z: 900
        color: themeManager.glassBgColor
        border.color: themeManager.glassBorderColor
        border.width: 1
        radius: 16

        MouseArea { anchors.fill: parent }

        Column {
            id: qsCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Row {
                spacing: 10
                Text { text: "Quick Settings"; color: themeManager.accentColor; font.pixelSize: 16; font.bold: true }
                Item { width: 80; height: 1 }
                Text { text: "✕"; color: "#a0a5c0"; font.pixelSize: 16
                    MouseArea { anchors.fill: parent; onClicked: quickSettingsPanel.visible = false; cursorShape: Qt.PointingHandCursor }
                }
            }

            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // WiFi
            Row {
                spacing: 8
                Text { text: "📶"; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    Text { text: systemMonitor.wifiConnected ? systemMonitor.wifiName : "Nicht verbunden"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                    Text { text: systemMonitor.wifiConnected ? "Signal: " + systemMonitor.wifiStrength + "%" : "WiFi: nmtui"; color: "#a0a5c0"; font.pixelSize: 10 }
                }
            }

            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // Volume
            Column {
                spacing: 6
                width: parent.width - 32
                Row {
                    spacing: 8
                    Text { text: systemMonitor.volumeMuted ? "🔇" : "🔊"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: systemMonitor.toggleMute() }
                    }
                    Text { text: "Lautstärke"; color: "#a0a5c0"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: systemMonitor.volumeLevel + "%"; color: "#ffffff"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                Slider {
                    id: volSlider
                    width: parent.width; from: 0; to: 100; value: systemMonitor.volumeLevel
                    onMoved: systemMonitor.setVolume(value)
                    background: Rectangle {
                        x: volSlider.leftPadding; y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200; implicitHeight: 6; width: volSlider.availableWidth; height: implicitHeight; radius: 3; color: "#20ffffff"
                        Rectangle { width: volSlider.visualPosition * parent.width; height: parent.height; radius: 3; color: themeManager.accentColor }
                    }
                    handle: Rectangle {
                        x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                        y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                        implicitWidth: 16; implicitHeight: 16; radius: 8; color: "#ffffff"
                    }
                }
            }

            // Brightness
            Column {
                spacing: 6
                width: parent.width - 32
                Row {
                    spacing: 8
                    Text { text: "☀"; font.pixelSize: 14; color: "#a0a5c0"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Helligkeit"; color: "#a0a5c0"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: systemMonitor.brightnessLevel + "%"; color: "#ffffff"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                Slider {
                    id: brightSlider
                    width: parent.width; from: 5; to: 100; value: systemMonitor.brightnessLevel
                    onMoved: systemMonitor.setBrightness(value)
                    background: Rectangle {
                        x: brightSlider.leftPadding; y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200; implicitHeight: 6; width: brightSlider.availableWidth; height: implicitHeight; radius: 3; color: "#20ffffff"
                        Rectangle { width: brightSlider.visualPosition * parent.width; height: parent.height; radius: 3; color: "#f59e0b" }
                    }
                    handle: Rectangle {
                        x: brightSlider.leftPadding + brightSlider.visualPosition * (brightSlider.availableWidth - width)
                        y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                        implicitWidth: 16; implicitHeight: 16; radius: 8; color: "#ffffff"
                    }
                }
            }

            Rectangle { width: parent.width - 32; height: 1; color: themeManager.glassBorderColor }

            // Toggle Buttons
            Row {
                spacing: 12
                Rectangle {
                    width: 80; height: 34; radius: 8; color: "#15ffffff"; border.color: themeManager.glassBorderColor
                    Column { anchors.centerIn: parent
                        Text { text: "📶"; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: "WiFi"; color: "#a0a5c0"; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { quickSettingsPanel.visible = false; systemMonitor.launchApp("xterm -fa Monospace -fs 12 -bg black -fg cyan -T WiFi -e nmtui") }
                    }
                }
                Rectangle {
                    width: 80; height: 34; radius: 8; color: "#15ffffff"; border.color: themeManager.glassBorderColor
                    Column { anchors.centerIn: parent
                        Text { text: "B"; font.pixelSize: 12; color: "#3b82f6"; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: "Bluetooth"; color: "#a0a5c0"; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { quickSettingsPanel.visible = false; systemMonitor.launchApp("xterm -e bash -c 'bluetoothctl show; read'") }
                    }
                }
                Rectangle {
                    width: 80; height: 34; radius: 8; color: "#15ffffff"; border.color: themeManager.glassBorderColor
                    Column { anchors.centerIn: parent
                        Text { text: "🧅"; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: "Tor"; color: "#a0a5c0"; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { quickSettingsPanel.visible = false; systemMonitor.launchApp("mb-browser --tor") }
                    }
                }
            }
        }
    }

    // Main Workspace Area
    Item {
        id: mainWorkspace
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: parent.width

        // ===== Android-Style Home Screen =====

        function refreshHomeGrid() {
            homeGridModel.clear();
            var apps = systemMonitor.getHomePageApps(currentHomePage);
            if (apps) {
                for (var i = 0; i < apps.length; i++) {
                    homeGridModel.append(apps[i]);
                }
            }
        }



        Component.onCompleted: refreshHomeGrid()

        // Refresh grid when C++ signals homeScreenChanged (add/remove/reorder)
        Connections {
            target: systemMonitor
            function onHomeScreenChanged() { refreshHomeGrid(); }
        }

        // Clock widget (page 0 only)
        Column {
            visible: currentHomePage === 0
            anchors.top: parent.top
            anchors.topMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            z: 5

            Text {
                text: Qt.formatTime(new Date(), "HH:mm")
                font.pixelSize: 64
                font.bold: true
                font.family: "Outfit, Inter, monospace"
                font.letterSpacing: 4
                color: "#ffffff"
                opacity: 0.2
                anchors.horizontalCenter: parent.horizontalCenter

                Timer {
                    interval: 1000; running: true; repeat: true
                    onTriggered: parent.text = Qt.formatTime(new Date(), "HH:mm")
                }
            }

            Text {
                text: Qt.formatDate(new Date(), "dddd, dd. MMMM yyyy")
                font.pixelSize: 16
                color: "#e2e8f0"
                opacity: 0.35
                font.family: "Outfit, Inter, sans-serif"
                font.weight: Font.Light
                anchors.horizontalCenter: parent.horizontalCenter

                Timer {
                    interval: 60000; running: true; repeat: true
                    onTriggered: parent.text = Qt.formatDate(new Date(), "dddd, dd. MMMM yyyy")
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: systemMonitor.launchApp("mb-browser --url https://calendar.google.com")
                }
            }
        }

        // App shortcuts grid
        GridView {
            id: homeGrid
            anchors.top: parent.top
            anchors.topMargin: currentHomePage === 0 ? 150 : 30
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 140
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            cellWidth: Math.max(90, Math.floor((width) / Math.floor(width / (100 * systemMonitor.uiScale))))
            cellHeight: 105 * systemMonitor.uiScale
            clip: true

            model: ListModel { id: homeGridModel }

            delegate: Item {
                width: homeGrid.cellWidth
                height: homeGrid.cellHeight

                // Full-area mouse handler for long-press edit mode + right-click remove
                MouseArea {
                    anchors.fill: parent
                    enabled: !homeEditMode
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressAndHold: homeEditMode = true
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            homeContextIndex = index;
                            homeContextMenu.x = mouse.x;
                            homeContextMenu.y = mouse.y;
                            homeContextMenu.open();
                        } else {
                            if (model.cmd === "__power_menu__") {
                                powerMenu.open();
                            } else if (model.cmd === "__ai_drawer__") {
                                aiDrawer.open();
                            } else if (model.cmd === "__antigravity__") {
                                systemMonitor.launchApp("launch-antigravity");
                            } else {
                                systemMonitor.launchApp(model.cmd);
                            }
                        }
                    }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        width: 56 * systemMonitor.uiScale
                        height: 56 * systemMonitor.uiScale
                        radius: 16 * systemMonitor.uiScale
                        color: homeIconMa.containsMouse ? Qt.rgba(1,1,1,0.15) : Qt.rgba(1,1,1,0.06)
                        border.color: model.clr ? model.clr : "#ffffff"
                        border.width: homeIconMa.containsMouse ? 2 : 1
                        anchors.horizontalCenter: parent.horizontalCenter

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            text: model.icon ? model.icon : "?"
                            anchors.centerIn: parent
                            color: model.clr ? model.clr : "#ffffff"
                            font.pixelSize: 20 * systemMonitor.uiScale
                            font.bold: true
                        }

                        // Delete badge in edit mode
                        Rectangle {
                            visible: homeEditMode
                            width: 20; height: 20; radius: 10
                            color: "#ff4060"
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -5
                            anchors.rightMargin: -5

                            Text {
                                text: "\u2715"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.bold: true
                                anchors.centerIn: parent
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: systemMonitor.removeFromHomeScreen(currentHomePage, index)
                            }
                        }

                        scale: homeIconMa.containsMouse ? 1.1 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        MouseArea {
                            id: homeIconMa
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            acceptedButtons: Qt.NoButton
                        }
                    }

                    Text {
                        text: model.name ? model.name : ""
                        color: "#c0c8d8"
                        font.pixelSize: 10 * systemMonitor.uiScale
                        horizontalAlignment: Text.AlignHCenter
                        width: 90 * systemMonitor.uiScale
                        elide: Text.ElideRight
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // Right-click context menu for homescreen apps
        Popup {
            id: homeContextMenu
            width: 180 * systemMonitor.uiScale
            height: 40 * systemMonitor.uiScale
            modal: true
            closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
            background: Rectangle {
                color: "#1a1e2e"
                border.color: "#ff4060"
                border.width: 1
                radius: 10
            }
            contentItem: Rectangle {
                color: "transparent"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: {
                        if (homeContextIndex >= 0) {
                            systemMonitor.removeFromHomeScreen(currentHomePage, homeContextIndex);
                        }
                        homeContextMenu.close();
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: parent.containsMouse ? "#30ff4060" : "transparent"
                        radius: 8
                        Text {
                            text: "🗑  Vom Startbildschirm entfernen"
                            color: "#ff4060"
                            font.pixelSize: 12 * systemMonitor.uiScale
                            anchors.centerIn: parent
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            visible: homeGridModel.count === 0 && currentHomePage > 0
            text: "Leere Seite\nApps aus dem Drawer hierher hinzuf\u00fcgen"
            color: "#50ffffff"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            anchors.centerIn: parent
            lineHeight: 1.6
        }

        // Page indicator + nav
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 128
            spacing: 8
            z: 10

            // Left arrow
            Text {
                text: "\u25C0"
                color: currentHomePage > 0 ? "#ffffff" : "#30ffffff"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: currentHomePage > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { if (currentHomePage > 0) { currentHomePage--; refreshHomeGrid(); } }
                }
            }

            Repeater {
                model: systemMonitor.homePageCount
                Rectangle {
                    width: currentHomePage === index ? 16 : 8
                    height: 8
                    radius: 4
                    color: currentHomePage === index ? themeManager.accentColor : "#40ffffff"
                    Behavior on width { NumberAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { currentHomePage = index; refreshHomeGrid(); }
                    }
                }
            }

            // Right arrow
            Text {
                text: "\u25B6"
                color: currentHomePage < systemMonitor.homePageCount - 1 ? "#ffffff" : "#30ffffff"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: currentHomePage < systemMonitor.homePageCount - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { if (currentHomePage < systemMonitor.homePageCount - 1) { currentHomePage++; refreshHomeGrid(); } }
                }
            }
        }

        // Edit mode toolbar
        Rectangle {
            visible: homeEditMode
            width: 260
            height: 40
            radius: 20
            color: themeManager.glassBgColor
            border.color: themeManager.accentColor
            border.width: 1
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 150
            anchors.horizontalCenter: parent.horizontalCenter
            z: 20

            Row {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    text: "+ Seite"
                    color: themeManager.accentColor
                    font.pixelSize: 13
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: systemMonitor.addHomePage()
                    }
                }

                Rectangle { width: 1; height: 20; color: themeManager.glassBorderColor; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    text: "\u2715 Fertig"
                    color: "#ff4060"
                    font.pixelSize: 13
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: homeEditMode = false
                    }
                }
            }
        }

        // App Dock (at the bottom)
        Rectangle {
            id: dock
            width: 600
            height: 80
            color: themeManager.glassBgColor
            radius: 20
            border.color: themeManager.glassBorderColor
            border.width: 1
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            anchors.horizontalCenter: parent.horizontalCenter

            // Mouse tracker for lightfield effect (must be behind buttons)
            MouseArea {
                id: dockMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                z: -1
            }

            // Dynamic hover lightfield glow (sliding glass flare)
            Rectangle {
                width: 140
                height: parent.height
                radius: 20
                x: dockMouseArea.mouseX - width / 2
                y: 0
                opacity: dockMouseArea.containsMouse ? 1.0 : 0.0
                visible: opacity > 0
                color: "transparent"
                z: 0
                
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1.0, 1.0, 1.0, 0.07) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on x { NumberAnimation { duration: 80 } }
            }

            Row {
                anchors.centerIn: parent
                spacing: 25
                z: 1

                // Terminal Launcher
                DockButton {
                    iconText: ">_"
                    label: "Terminal"
                    colorCode: themeManager.accentColor
                    onClicked: systemMonitor.launchApp("xterm -bg black -fg white -fs 12")
                }

                // File Manager Launcher
                DockButton {
                    iconText: "D"
                    label: "Dateien"
                    colorCode: "#3b82f6"
                    onClicked: systemMonitor.launchApp("pcmanfm")
                }

                // Web Browser Launcher
                DockButton {
                    iconText: "W"
                    label: "Web Browser"
                    colorCode: "#10b981"
                    onClicked: systemMonitor.launchApp("mb-browser")
                }

                // App Drawer Button (Android-style)
                DockButton {
                    iconText: ":::"
                    label: "Apps"
                    colorCode: "#8b5cf6"
                    onClicked: appDrawerOverlay.open()
                }

                // AI Memory Drawer Launcher
                DockButton {
                    iconText: "AI"
                    label: "AI"
                    colorCode: themeManager.secondaryColor
                    onClicked: aiDrawer.open()
                }
            }
        }
    }

    // ==================== APP DRAWER (Android-style) ====================
    Popup {
        id: appDrawerOverlay
        width: window.width
        height: window.height
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { property: "y"; from: 100; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }

        property bool appsLoaded: false
        onOpened: {
            if (!appsLoaded) {
                // Collect existing cmds to avoid duplicates
                var existingCmds = {};
                for (var i = 0; i < appModel.count; i++) {
                    existingCmds[appModel.get(i).cmd] = true;
                }
                // Add auto-discovered .desktop apps
                var installed = systemMonitor.getInstalledApps();
                for (var j = 0; j < installed.length; j++) {
                    if (!existingCmds[installed[j].cmd]) {
                        appModel.append(installed[j]);
                    }
                }
                appsLoaded = true;
                console.log("App Drawer: loaded " + installed.length + " installed apps");
            }
        }

        background: Rectangle {
            color: Qt.rgba(0.03, 0.04, 0.08, 0.92)
        }

        contentItem: Item {
            anchors.fill: parent

            // Close handle (swipe down indicator)
            Rectangle {
                width: 50; height: 4; radius: 2
                color: "#50ffffff"
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -20
                    onClicked: appDrawerOverlay.close()
                }
            }

            // Title
            Text {
                id: drawerTitle
                text: "Alle Apps"
                color: "#ffffff"
                font.pixelSize: 28
                font.bold: true
                anchors.top: parent.top
                anchors.topMargin: 35
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Search Bar
            TextField {
                id: appSearchField
                width: Math.min(parent.width - 80, 500)
                height: 40
                anchors.top: drawerTitle.bottom
                anchors.topMargin: 15
                anchors.horizontalCenter: parent.horizontalCenter
                placeholderText: "App suchen..."
                color: "#ffffff"
                placeholderTextColor: "#607090"
                font.pixelSize: 14
                verticalAlignment: Text.AlignVCenter
                leftPadding: 15

                background: Rectangle {
                    color: Qt.rgba(0.08, 0.10, 0.18, 0.8)
                    border.color: appSearchField.activeFocus ? themeManager.accentColor : "#30ffffff"
                    border.width: 1
                    radius: 20
                }
            }

            // App Grid
            GridView {
                id: appGrid
                anchors.top: appSearchField.bottom
                anchors.topMargin: 25
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 15
                anchors.rightMargin: 15
                cellWidth: Math.max(90, Math.floor(width / Math.floor(width / (110 * systemMonitor.uiScale))))
                cellHeight: 105 * systemMonitor.uiScale
                clip: true

                model: ListModel {
                    id: appModel
                    // System Apps
                    ListElement { name: "Terminal"; icon: ">_"; cmd: "xterm -bg black -fg white -fs 12"; clr: "#20c2f8"; category: "system" }
                    ListElement { name: "Dateien"; icon: "D"; cmd: "pcmanfm"; clr: "#3b82f6"; category: "system" }
                    ListElement { name: "Browser"; icon: "W"; cmd: "mb-browser"; clr: "#10b981"; category: "system" }
                    ListElement { name: "Editor"; icon: "E"; cmd: "mousepad"; clr: "#f59e0b"; category: "system" }
                    ListElement { name: "AI Gedaechtnis"; icon: "AI"; cmd: "__ai_drawer__"; clr: "#f820c2"; category: "ai" }
                    // Dev Tools
                    ListElement { name: "htop"; icon: "H"; cmd: "xterm -bg black -fg green -fs 11 -e htop"; clr: "#22c55e"; category: "dev" }
                    ListElement { name: "Git"; icon: "G"; cmd: "xterm -bg black -fg white -fs 12 -e bash"; clr: "#f97316"; category: "dev" }
                    ListElement { name: "micro"; icon: "m"; cmd: "xterm -bg black -fg white -fs 12 -e micro"; clr: "#06b6d4"; category: "dev" }
                    ListElement { name: "Python"; icon: "Py"; cmd: "xterm -bg black -fg white -fs 12 -e python3"; clr: "#3776ab"; category: "dev" }
                    ListElement { name: "Node.js"; icon: "JS"; cmd: "xterm -bg black -fg white -fs 12 -e node"; clr: "#68a063"; category: "dev" }
                    // Web Apps
                    ListElement { name: "Gmail"; icon: "@"; cmd: "mb-browser --url https://mail.google.com"; clr: "#ea4335"; category: "web" }
                    ListElement { name: "Gemini"; icon: "G*"; cmd: "mb-browser --url https://gemini.google.com"; clr: "#4285f4"; category: "web" }
                    ListElement { name: "YouTube"; icon: "YT"; cmd: "mb-browser --url https://youtube.com"; clr: "#ff0000"; category: "web" }
                    ListElement { name: "Google"; icon: "Go"; cmd: "mb-browser --url https://google.com"; clr: "#34a853"; category: "web" }
                    ListElement { name: "GitHub"; icon: "GH"; cmd: "mb-browser --url https://github.com"; clr: "#ffffff"; category: "web" }
                    ListElement { name: "ChatGPT"; icon: "GP"; cmd: "mb-browser --url https://chatgpt.com"; clr: "#10a37f"; category: "web" }
                    ListElement { name: "WhatsApp"; icon: "WA"; cmd: "mb-browser --url https://web.whatsapp.com"; clr: "#25d366"; category: "web" }
                    ListElement { name: "Maps"; icon: "📍"; cmd: "mb-browser --url https://maps.google.com"; clr: "#4285f4"; category: "web" }
                    ListElement { name: "OOONO"; icon: "🚗"; cmd: "mb-browser --url https://my.ooono.com"; clr: "#ff6b00"; category: "web" }
                    // Antigravity AI (Google Gemini CLI)
                    ListElement { name: "Antigravity"; icon: "AG"; cmd: "__antigravity__"; clr: "#a855f7"; category: "ai" }
                    // Darkweb / Tor Browser
                    ListElement { name: "Darkweb"; icon: "🧅"; cmd: "mb-browser --tor"; clr: "#7c3aed"; category: "web" }
                    // System Tools
                    ListElement { name: "Netzwerk"; icon: "N"; cmd: "xterm -bg black -fg cyan -fs 11 -e bash -c 'ip addr; echo ---; ping -c 4 google.com; read'"; clr: "#0ea5e9"; category: "system" }
                    ListElement { name: "WiFi"; icon: "📶"; cmd: "xterm -fa Monospace -fs 12 -bg black -fg cyan -T WiFi -e nmtui"; clr: "#0ea5e9"; category: "system" }
                    ListElement { name: "SSH"; icon: ">>"; cmd: "xterm -bg black -fg white -fs 12 -e bash"; clr: "#6366f1"; category: "system" }
                    ListElement { name: "Tor Status"; icon: "T"; cmd: "xterm -bg black -fg magenta -fs 11 -e bash -c 'systemctl status tor; read'"; clr: "#7c3aed"; category: "system" }
                    ListElement { name: "Installieren"; icon: "⬇"; cmd: "xterm -e launch-installer"; clr: "#f59e0b"; category: "system" }
                    ListElement { name: "Android"; icon: "🤖"; cmd: "launch-android"; clr: "#3ddc84"; category: "system" }
                    ListElement { name: "Sperren"; icon: "🔒"; cmd: "mb-lock"; clr: "#8b5cf6"; category: "system" }
                    ListElement { name: "Audio"; icon: "🔊"; cmd: "xterm -e bash -c 'wpctl status; read'"; clr: "#06b6d4"; category: "system" }
                    ListElement { name: "Bluetooth"; icon: "B"; cmd: "xterm -e bash -c 'bluetoothctl show; read'"; clr: "#3b82f6"; category: "system" }
                    ListElement { name: "Firewall"; icon: "🛡"; cmd: "xterm -e bash -c 'sudo ufw status verbose; read'"; clr: "#ef4444"; category: "system" }
                    ListElement { name: "Screenshot"; icon: "📸"; cmd: "mb-screenshot"; clr: "#f97316"; category: "system" }
                    ListElement { name: "Video"; icon: "🎬"; cmd: "mpv --player-operation-mode=pseudo-gui"; clr: "#ec4899"; category: "system" }
                    ListElement { name: "Bilder"; icon: "🖼"; cmd: "feh --scale-down"; clr: "#14b8a6"; category: "system" }
                    ListElement { name: "PDF"; icon: "📄"; cmd: "zathura"; clr: "#f43f5e"; category: "system" }
                    ListElement { name: "Rechner"; icon: "🔢"; cmd: "galculator"; clr: "#a855f7"; category: "system" }
                    ListElement { name: "Update"; icon: "🔄"; cmd: "xterm -e sudo mb-update"; clr: "#22c55e"; category: "system" }
                    ListElement { name: "Flatpak"; icon: "📦"; cmd: "xterm -e bash -c 'flatpak list; echo ---; echo Installieren: flatpak install flathub APP_NAME; read'"; clr: "#0891b2"; category: "system" }
                    ListElement { name: "Power"; icon: "P"; cmd: "__power_menu__"; clr: "#ef4444"; category: "system" }
                    // Google Tools
                    ListElement { name: "Kalender"; icon: "📅"; cmd: "mb-browser --url https://calendar.google.com"; clr: "#4285f4"; category: "google" }
                    ListElement { name: "Drive"; icon: "△"; cmd: "mb-browser --url https://drive.google.com"; clr: "#1fa463"; category: "google" }
                    ListElement { name: "Docs"; icon: "📝"; cmd: "mb-browser --url https://docs.google.com"; clr: "#4285f4"; category: "google" }
                    ListElement { name: "Sheets"; icon: "📊"; cmd: "mb-browser --url https://sheets.google.com"; clr: "#0f9d58"; category: "google" }
                    ListElement { name: "Meet"; icon: "📹"; cmd: "mb-browser --url https://meet.google.com"; clr: "#00897b"; category: "google" }
                    ListElement { name: "Keep"; icon: "📌"; cmd: "mb-browser --url https://keep.google.com"; clr: "#fbbc04"; category: "google" }
                    ListElement { name: "Translate"; icon: "🌐"; cmd: "mb-browser --url https://translate.google.com"; clr: "#4285f4"; category: "google" }
                    ListElement { name: "Fotos"; icon: "🖼"; cmd: "mb-browser --url https://photos.google.com"; clr: "#ea4335"; category: "google" }
                    ListElement { name: "Kontakte"; icon: "👥"; cmd: "mb-browser --url https://contacts.google.com"; clr: "#4285f4"; category: "google" }
                    ListElement { name: "Play Store"; icon: "▶"; cmd: "mb-browser --url https://play.google.com"; clr: "#01875f"; category: "google" }
                }

                delegate: Item {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    visible: {
                        var q = appSearchField.text.toLowerCase();
                        return q === "" || model.name.toLowerCase().indexOf(q) >= 0;
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        // App Icon
                        Rectangle {
                            width: 56 * systemMonitor.uiScale; height: 56 * systemMonitor.uiScale
                            radius: 16 * systemMonitor.uiScale
                            color: appIconMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.05)
                            border.color: model.clr
                            border.width: appIconMa.containsMouse ? 2 : 1
                            anchors.horizontalCenter: parent.horizontalCenter

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.width { NumberAnimation { duration: 120 } }

                            Text {
                                text: model.icon
                                anchors.centerIn: parent
                                color: model.clr
                                font.pixelSize: (model.icon.length > 2 ? 14 : 20) * systemMonitor.uiScale
                                font.bold: true
                            }

                            // Scale animation on hover
                            scale: appIconMa.containsMouse ? 1.1 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: appIconMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (model.cmd === "__ai_drawer__") {
                                        appDrawerOverlay.close();
                                        aiDrawer.open();
                                    } else if (model.cmd === "__power_menu__") {
                                        appDrawerOverlay.close();
                                        powerMenu.open();
                                    } else if (model.cmd === "__antigravity__") {
                                        appDrawerOverlay.close();
                                        // Desktop App → agy CLI → gemini CLI → Web
                                        systemMonitor.launchApp("launch-antigravity");
                                    } else {
                                        appDrawerOverlay.close();
                                        systemMonitor.launchApp(model.cmd);
                                    }
                                }
                                onPressAndHold: {
                                    addToHomePopup.appName = model.name;
                                    addToHomePopup.appIcon = model.icon;
                                    addToHomePopup.appCmd = model.cmd;
                                    addToHomePopup.appClr = model.clr;
                                    addToHomePopup.open();
                                }
                            }
                        }

                        // App Name
                        Text {
                            text: model.name
                            color: "#c0c8d8"
                            font.pixelSize: 10 * systemMonitor.uiScale
                            horizontalAlignment: Text.AlignHCenter
                            width: 100 * systemMonitor.uiScale
                            elide: Text.ElideRight
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    // ==================== ADD TO HOME SCREEN POPUP ====================
    Popup {
        id: addToHomePopup
        width: 320
        height: 280
        modal: true
        focus: true
        anchors.centerIn: parent
        padding: 20

        property string appName: ""
        property string appIcon: ""
        property string appCmd: ""
        property string appClr: ""
        property int targetPage: 0

        background: Rectangle {
            color: "#e00a0e1a"
            radius: 16
            border.color: themeManager.accentColor
            border.width: 1
        }

        contentItem: Column {
            id: addToHomeCol
            spacing: 16
            anchors.centerIn: parent
            width: parent.width - 40

            Text {
                text: "Zum Startbildschirm"
                color: "#ffffff"
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            // App preview
            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    width: 40; height: 40; radius: 12
                    color: Qt.rgba(1,1,1,0.08)
                    border.color: addToHomePopup.appClr
                    border.width: 1
                    Text {
                        text: addToHomePopup.appIcon
                        anchors.centerIn: parent
                        color: addToHomePopup.appClr
                        font.pixelSize: 16
                        font.bold: true
                    }
                }
                Text {
                    text: addToHomePopup.appName
                    color: "#ffffff"
                    font.pixelSize: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Page selector
            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    text: "Seite:"
                    color: "#a0a5c0"
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                Repeater {
                    model: systemMonitor.homePageCount
                    Rectangle {
                        width: 36; height: 36; radius: 8
                        color: addToHomePopup.targetPage === index ? Qt.rgba(0.1, 0.7, 0.95, 0.3) : Qt.rgba(1,1,1,0.06)
                        border.color: addToHomePopup.targetPage === index ? themeManager.accentColor : themeManager.glassBorderColor
                        border.width: addToHomePopup.targetPage === index ? 2 : 1
                        Text {
                            text: (index + 1).toString()
                            anchors.centerIn: parent
                            color: addToHomePopup.targetPage === index ? themeManager.accentColor : "#ffffff"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: addToHomePopup.targetPage = index
                        }
                    }
                }
            }

            Row {
                spacing: 15
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 120; height: 40; radius: 8
                    color: addBtnMa.containsMouse ? Qt.rgba(0.1, 0.7, 0.95, 0.3) : "#15ffffff"
                    border.color: themeManager.accentColor; border.width: 1
                    Text {
                        text: "Hinzuf\u00fcgen"
                        color: themeManager.accentColor
                        font.bold: true; font.pixelSize: 14
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        id: addBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("ADD TO HOME: page=" + addToHomePopup.targetPage + " name=" + addToHomePopup.appName);
                            deferredHomeAdd.pPage = addToHomePopup.targetPage;
                            deferredHomeAdd.pName = addToHomePopup.appName;
                            deferredHomeAdd.pIcon = addToHomePopup.appIcon;
                            deferredHomeAdd.pCmd = addToHomePopup.appCmd;
                            deferredHomeAdd.pClr = addToHomePopup.appClr;
                            addToHomePopup.close();
                            appDrawerOverlay.close();
                            deferredHomeAdd.start();
                        }
                    }
                }

                Rectangle {
                    width: 100; height: 40; radius: 8
                    color: cancelBtnMa.containsMouse ? "#20ffffff" : "transparent"
                    Text {
                        text: "Abbrechen"
                        color: cancelBtnMa.containsMouse ? "#ffffff" : "#80a5c0"
                        font.pixelSize: 13
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        id: cancelBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: addToHomePopup.close()
                    }
                }
            }
        }
    }

    // Power Overlay / Dialog
    Popup {
        id: powerMenu
        width: 320
        height: 200
        modal: true
        focus: true
        anchors.centerIn: parent

        background: Rectangle {
            color: themeManager.glassBgColor
            opacity: 0.95
            radius: 16
            border.color: themeManager.glassBorderColor
            border.width: 1
        }

        contentItem: Column {
            spacing: 20
            anchors.centerIn: parent
            width: parent.width - 40

            Text {
                text: "System herunterfahren?"
                color: "#ffffff"
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Row {
                spacing: 15
                anchors.horizontalCenter: parent.horizontalCenter

                Button {
                    id: rebootBtn
                    text: "Neustart"
                    width: 110
                    background: Rectangle {
                        color: rebootBtn.hovered ? themeManager.secondaryColor + "30" : themeManager.glassBgColor
                        border.color: themeManager.secondaryColor
                        radius: 8
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.bold: true
                    }
                    onClicked: {
                        powerMenu.close()
                        systemMonitor.reboot()
                    }
                }

                Button {
                    id: shutdownBtn
                    text: "Herunterfahren"
                    width: 110
                    background: Rectangle {
                        color: shutdownBtn.hovered ? "#30ff4060" : "#4e1b29"
                        border.color: "#ff4060"
                        radius: 8
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.bold: true
                    }
                    onClicked: {
                        powerMenu.close()
                        systemMonitor.powerOff()
                    }
                }
            }

            Button {
                id: cancelBtn
                text: "Abbrechen"
                anchors.horizontalCenter: parent.horizontalCenter
                flat: true
                contentItem: Text {
                    text: parent.text
                    color: cancelBtn.hovered ? "#ffffff" : "#80a5c0"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: powerMenu.close()
            }
        }
    }

    // AI & Memory Drawer (MD-based)
    Drawer {
        id: aiDrawer
        width: 450
        height: window.height
        edge: Qt.RightEdge

        background: Rectangle {
            color: Qt.rgba(0.04, 0.05, 0.1, 0.95)
            border.color: themeManager.glassBorderColor
            border.width: 1

            Rectangle {
                width: 2
                height: parent.height
                color: themeManager.secondaryColor
                anchors.left: parent.left
            }
        }

        contentItem: Flickable {
            anchors.fill: parent
            anchors.margins: 25
            contentHeight: drawerColumn.height
            clip: true

            Column {
                id: drawerColumn
                width: parent.width
                spacing: 16
                property bool daemonOnline: false

                // Title
                Text {
                    text: "AI Gedaechtnis"
                    color: "#ffffff"
                    font.pixelSize: 22
                    font.bold: true
                }

                Text {
                    text: "Markdown-basiert | Lokal | Permanent"
                    color: themeManager.accentColor
                    font.pixelSize: 11
                }

                // Status indicator
                Rectangle {
                    width: parent.width
                    height: 36
                    color: themeManager.glassBgColor
                    radius: 8
                    border.color: themeManager.glassBorderColor

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: drawerColumn.daemonOnline ? "#22c55e" : "#ef4444"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: drawerColumn.daemonOnline ? "Memory Daemon aktiv" : "Memory Daemon offline"
                            color: "#d1d5db"
                            font.pixelSize: 11
                        }
                    }
                }


                // Section: Skills
                Text {
                    text: "Gelernte Skills:"
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(skillsText.implicitHeight + 20, 80)
                    color: themeManager.glassBgColor
                    radius: 10
                    border.color: themeManager.glassBorderColor

                    Text {
                        id: skillsText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: "Skills werden geladen..."
                        color: "#a0a5c0"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }

                // Section: Add knowledge
                Text {
                    text: "Neues Wissen speichern:"
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.bold: true
                }

                Row {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: factInput
                        width: parent.width - 88
                        height: 36
                        placeholderText: "z.B. QEMU braucht -nic user"
                        color: "#ffffff"
                        placeholderTextColor: "#50a5c0"
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12

                        background: Rectangle {
                            color: themeManager.glassBgColor
                            border.color: factInput.activeFocus ? themeManager.secondaryColor : themeManager.glassBorderColor
                            border.width: 1
                            radius: 8
                        }
                    }

                    Button {
                        text: "+"
                        width: 36; height: 36

                        background: Rectangle {
                            color: parent.hovered ? themeManager.secondaryColor : themeManager.glassBgColor
                            border.color: themeManager.secondaryColor
                            radius: 8
                        }
                        contentItem: Text {
                            text: parent.text; color: "#ffffff"
                            font.bold: true; font.pixelSize: 18
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            var fact = factInput.text.trim();
                            if (fact !== "") {
                                var xhr = new XMLHttpRequest();
                                xhr.open("POST", "http://localhost:8000/memory/add");
                                xhr.setRequestHeader("Content-Type", "application/json");
                                xhr.onreadystatechange = function() {
                                    if (xhr.readyState === XMLHttpRequest.DONE) {
                                        factInput.text = "";
                                        addStatus.text = "Gespeichert!";
                                        addStatus.color = "#22c55e";
                                        refreshMemory();
                                    }
                                }
                                xhr.send(JSON.stringify({ "content": fact }));
                            }
                        }
                    }

                    Button {
                        text: "S"
                        width: 36; height: 36

                        background: Rectangle {
                            color: parent.hovered ? themeManager.accentColor : themeManager.glassBgColor
                            border.color: themeManager.accentColor
                            radius: 8
                        }
                        contentItem: Text {
                            text: parent.text; color: "#ffffff"
                            font.bold: true; font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            var q = factInput.text.trim();
                            if (q !== "") {
                                var xhr = new XMLHttpRequest();
                                xhr.open("POST", "http://localhost:8000/memory/query");
                                xhr.setRequestHeader("Content-Type", "application/json");
                                xhr.onreadystatechange = function() {
                                    if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                                        var data = JSON.parse(xhr.responseText);
                                        var txt = "";
                                        for (var i = 0; i < data.results.length; i++) {
                                            txt += ">> " + data.results[i].content + "\n\n";
                                        }
                                        queryResultText.text = txt || "Nichts gefunden.";
                                    }
                                }
                                xhr.send(JSON.stringify({ "query": q, "limit": 5 }));
                            }
                        }
                    }
                }

                Text {
                    id: addStatus
                    text: " "
                    color: "#22c55e"
                    font.pixelSize: 10
                }

                // Section: Search Results / Memory Content
                Text {
                    text: "Gedaechtnis-Inhalt:"
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(queryResultText.implicitHeight + 20, 120)
                    color: themeManager.glassBgColor
                    radius: 10
                    border.color: themeManager.glassBorderColor

                    Text {
                        id: queryResultText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: "Lade Gedaechtnis..."
                        color: "#a0a5c0"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // Load data when drawer opens
        onOpened: refreshMemory()

        function refreshMemory() {
            // Check daemon health
            var xhr1 = new XMLHttpRequest();
            xhr1.open("GET", "http://localhost:8000/health");
            xhr1.onreadystatechange = function() {
                if (xhr1.readyState === XMLHttpRequest.DONE) {
                    drawerColumn.daemonOnline = (xhr1.status === 200);
                }
            }
            xhr1.send();

            // Load skills
            var xhr2 = new XMLHttpRequest();
            xhr2.open("GET", "http://localhost:8000/memory/skills");
            xhr2.onreadystatechange = function() {
                if (xhr2.readyState === XMLHttpRequest.DONE && xhr2.status === 200) {
                    var data = JSON.parse(xhr2.responseText);
                    var txt = "";
                    for (var i = 0; i < data.skills.length; i++) {
                        txt += ">> " + data.skills[i].name + "\n   " + data.skills[i].trigger + "\n\n";
                    }
                    skillsText.text = txt || "Noch keine Skills gelernt.";
                }
            }
            xhr2.send();

            // Load recent memories
            var xhr3 = new XMLHttpRequest();
            xhr3.open("GET", "http://localhost:8000/memory/list");
            xhr3.onreadystatechange = function() {
                if (xhr3.readyState === XMLHttpRequest.DONE && xhr3.status === 200) {
                    var data = JSON.parse(xhr3.responseText);
                    var txt = "";
                    if (data.memories && data.memories.length > 0) {
                        for (var i = 0; i < data.memories.length; i++) {
                            var m = data.memories[i];
                            var time = m.created_at ? m.created_at.substring(5, 16) : "";
                            var cat = m.category ? " [" + m.category + "]" : "";
                            txt += "🧠 " + m.content + "\n";
                            txt += "   📅 " + time + cat + "\n\n";
                        }
                    } else {
                        txt = "Gedaechtnis ist leer.\nTippe oben etwas ein um es zu merken!";
                    }
                    queryResultText.text = txt;
                }
            }
            xhr3.send();
        }
    }

    // ==================== SETTINGS PANEL ====================
    Popup {
        id: settingsPanel
        width: window.width
        height: window.height
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: 0

        property int selectedCategory: 0
        property string currentTheme: "Dark"
        property int scalePercent: 100

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { property: "y"; from: 80; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }

        background: Rectangle {
            color: Qt.rgba(0.03, 0.04, 0.08, 0.95)
        }

        contentItem: Item {
            anchors.fill: parent

            // Header Bar
            Rectangle {
                id: settingsHeader
                width: parent.width
                height: 64
                color: themeManager.glassBgColor
                border.color: themeManager.glassBorderColor
                border.width: 1

                Text {
                    text: "\u2699  Einstellungen"
                    color: "#ffffff"
                    font.pixelSize: 24
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                }

                // Close Button
                Button {
                    id: settingsCloseBtn
                    width: 40
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    background: Rectangle {
                        color: settingsCloseBtn.hovered ? "#30ff4060" : "transparent"
                        radius: 20
                        border.color: settingsCloseBtn.hovered ? "#ff4060" : themeManager.glassBorderColor
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: "\u2715"
                        color: settingsCloseBtn.hovered ? "#ff4060" : "#ffffff"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: settingsPanel.close()
                }
            }

            // Content area: Sidebar + Main
            Row {
                anchors.top: settingsHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right

                // ── Sidebar ──
                Rectangle {
                    id: settingsSidebar
                    width: 220
                    height: parent.height
                    color: Qt.rgba(0.04, 0.05, 0.10, 0.90)
                    border.color: themeManager.glassBorderColor
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.topMargin: 15
                        spacing: 4

                        Repeater {
                            model: [
                                { label: "\uD83D\uDDA5  Display",      idx: 0 },
                                { label: "\uD83C\uDF10  Netzwerk",     idx: 1 },
                                { label: "\u2699  System",             idx: 2 },
                                { label: "\uD83C\uDFA8  Darstellung",  idx: 3 },
                                { label: "\u2139  \u00DCber",           idx: 4 },
                                { label: "\u267F  Barrierefreiheit",   idx: 5 }
                            ]

                            delegate: Rectangle {
                                width: settingsSidebar.width - 16
                                height: 44
                                x: 8
                                radius: 10
                                color: settingsPanel.selectedCategory === modelData.idx
                                       ? Qt.rgba(0.1, 0.6, 0.9, 0.2)
                                       : catMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                                border.color: settingsPanel.selectedCategory === modelData.idx
                                              ? themeManager.accentColor : "transparent"
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    text: modelData.label
                                    color: settingsPanel.selectedCategory === modelData.idx
                                           ? themeManager.accentColor : "#c0c8d8"
                                    font.pixelSize: 14
                                    font.bold: settingsPanel.selectedCategory === modelData.idx
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                }

                                MouseArea {
                                    id: catMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: settingsPanel.selectedCategory = modelData.idx
                                }
                            }
                        }
                    }
                }

                // ── Main Content Area ──
                Rectangle {
                    id: settingsContent
                    width: parent.width - settingsSidebar.width
                    height: parent.height
                    color: "transparent"

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 30
                        contentHeight: settingsMainCol.height
                        clip: true

                        Column {
                            id: settingsMainCol
                            width: parent.width
                            spacing: 20

                            // ──────── DISPLAY ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 0

                                Text {
                                    text: "Display"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                // Resolution
                                Rectangle {
                                    width: parent.width
                                    height: 90
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 8

                                        Text {
                                            text: "Aufl\u00f6sung"
                                            color: "#e2e8f0"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Row {
                                            spacing: 10

                                            Repeater {
                                                model: ["1920x1080", "1280x1024", "1024x768"]

                                                delegate: Button {
                                                    id: resBtn
                                                    text: modelData
                                                    width: 120
                                                    height: 34
                                                    background: Rectangle {
                                                        color: resBtn.hovered ? Qt.rgba(0.1, 0.6, 0.9, 0.25) : themeManager.glassBgColor
                                                        border.color: themeManager.accentColor
                                                        border.width: 1
                                                        radius: 8
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    contentItem: Text {
                                                        text: parent.text
                                                        color: "#ffffff"
                                                        font.pixelSize: 12
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    onClicked: {
                                                        var parts = modelData.split("x");
                                                        systemMonitor.launchApp("xrandr -s " + parts[0] + "x" + parts[1]);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Scale
                                Rectangle {
                                    width: parent.width
                                    height: 90
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 8

                                        Text {
                                            text: "Skalierung: " + settingsPanel.scalePercent + "%"
                                            color: "#e2e8f0"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Slider {
                                            id: scaleSlider
                                            width: Math.min(parent.width, 400)
                                            from: 100
                                            to: 200
                                            stepSize: 25
                                            value: settingsPanel.scalePercent
                                            onValueChanged: settingsPanel.scalePercent = value

                                            background: Rectangle {
                                                x: scaleSlider.leftPadding
                                                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                                                width: scaleSlider.availableWidth
                                                height: 6
                                                radius: 3
                                                color: themeManager.glassBorderColor

                                                Rectangle {
                                                    width: scaleSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    color: themeManager.accentColor
                                                    radius: 3
                                                }
                                            }

                                            handle: Rectangle {
                                                x: scaleSlider.leftPadding + scaleSlider.visualPosition * (scaleSlider.availableWidth - width)
                                                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                                                width: 20
                                                height: 20
                                                radius: 10
                                                color: themeManager.accentColor
                                                border.color: "#ffffff"
                                                border.width: 2
                                            }
                                        }

                                        Text {
                                            text: "Setzt QT_SCALE_FACTOR (Neustart n\u00f6tig)"
                                            color: "#607090"
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }

                            // ──────── NETZWERK ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 1

                                Text {
                                    text: "Netzwerk"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Rectangle {
                                    width: parent.width
                                    height: netCol.height + 32
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        id: netCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 16
                                        spacing: 14

                                        // Hostname
                                        Row {
                                            spacing: 10
                                            Text { text: "Hostname:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "mb-os-live"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        // IP Address
                                        Row {
                                            spacing: 10
                                            Text { text: "IP-Adresse:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "10.0.2.15 (DHCP)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        // Tor Status
                                        Row {
                                            spacing: 10
                                            Text { text: "Tor Status:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                color: "#22c55e"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text { text: "Aktiv"; color: "#22c55e"; font.pixelSize: 13; font.bold: true }
                                        }
                                    }
                                }
                            }

                            // ──────── SYSTEM ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 2

                                Text {
                                    text: "System"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Rectangle {
                                    width: parent.width
                                    height: sysCol.height + 32
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        id: sysCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 16
                                        spacing: 14

                                        Row {
                                            spacing: 10
                                            Text { text: "CPU:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 140 }
                                            Text { text: "Intel/AMD x86_64 (Live)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        Row {
                                            spacing: 10
                                            Text { text: "RAM:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 140 }
                                            Text { text: "4096 MB (Live-System)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        Row {
                                            spacing: 10
                                            Text { text: "Disk:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 140 }
                                            Text { text: "SquashFS (Read-Only)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        Row {
                                            spacing: 10
                                            Text { text: "Kernel:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 140 }
                                            Text { text: "6.8.0-generic (Ubuntu Noble)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }
                                    }
                                }
                            }

                            // ──────── DARSTELLUNG ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 3

                                Text {
                                    text: "Darstellung"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 100
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 12

                                        Text {
                                            text: "Theme w\u00e4hlen"
                                            color: "#e2e8f0"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Row {
                                            spacing: 12

                                            Repeater {
                                                model: [
                                                    { name: "Dark",  clr: "#20c2f8" },
                                                    { name: "Cyber", clr: "#f820c2" },
                                                    { name: "Ocean", clr: "#10b981" }
                                                ]

                                                delegate: Button {
                                                    id: themeBtn
                                                    width: 100
                                                    height: 38
                                                    background: Rectangle {
                                                        color: settingsPanel.currentTheme === modelData.name
                                                               ? Qt.rgba(0.1, 0.6, 0.9, 0.25) : themeBtn.hovered ? Qt.rgba(1, 1, 1, 0.08) : themeManager.glassBgColor
                                                        border.color: settingsPanel.currentTheme === modelData.name
                                                                      ? modelData.clr : themeManager.glassBorderColor
                                                        border.width: settingsPanel.currentTheme === modelData.name ? 2 : 1
                                                        radius: 10
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                                    }
                                                    contentItem: Row {
                                                        spacing: 8
                                                        anchors.centerIn: parent
                                                        Rectangle {
                                                            width: 12; height: 12; radius: 6
                                                            color: modelData.clr
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Text {
                                                            text: modelData.name
                                                            color: "#ffffff"
                                                            font.pixelSize: 13
                                                            font.bold: settingsPanel.currentTheme === modelData.name
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                    onClicked: {
                                                        settingsPanel.currentTheme = modelData.name;
                                                        if (typeof themeManager.setTheme === "function") {
                                                            themeManager.setTheme(modelData.name);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ──────── \u00dcBER ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 4

                                Text {
                                    text: "\u00DCber MB-OS"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Rectangle {
                                    width: parent.width
                                    height: aboutCol.height + 32
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        id: aboutCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 16
                                        spacing: 14

                                        // Logo
                                        Text {
                                            text: "MB-OS"
                                            color: themeManager.accentColor
                                            font.pixelSize: 36
                                            font.bold: true
                                            font.family: "Outfit, Inter, sans-serif"
                                            style: Text.Outline
                                            styleColor: "#30000000"
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        Row {
                                            spacing: 10
                                            Text { text: "Version:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "2.0.0 (Noble)"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Row {
                                            spacing: 10
                                            Text { text: "Build Date:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "2026-06-14"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Row {
                                            spacing: 10
                                            Text { text: "Basis:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "Ubuntu 24.04 Noble Numbat"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Row {
                                            spacing: 10
                                            Text { text: "Shell:"; color: "#a0a5c0"; font.pixelSize: 13; font.bold: true; width: 120 }
                                            Text { text: "Qt6/QML Glassmorphism"; color: "#ffffff"; font.pixelSize: 13 }
                                        }

                                        Rectangle { width: parent.width; height: 1; color: themeManager.glassBorderColor }

                                        Text {
                                            text: "Credits"
                                            color: "#e2e8f0"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Entwickelt mit Antigravity AI\nDesign: Glassmorphism Desktop Shell\nLizenz: Open Source"
                                            color: "#80a5c0"
                                            font.pixelSize: 12
                                            lineHeight: 1.4
                                            wrapMode: Text.Wrap
                                            width: parent.width
                                        }
                                    }
                                }
                            }

                            // ──────── BARRIEREFREIHEIT ────────
                            Column {
                                width: parent.width
                                spacing: 16
                                visible: settingsPanel.selectedCategory === 5

                                Text {
                                    text: "\u267F  Barrierefreiheit"
                                    color: "#ffffff"
                                    font.pixelSize: 22
                                    font.bold: true
                                }

                                Rectangle {
                                    width: parent.width
                                    height: accessCol.implicitHeight + 32
                                    radius: 12
                                    color: themeManager.glassBgColor
                                    border.color: themeManager.glassBorderColor
                                    border.width: 1

                                    Column {
                                        id: accessCol
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 16

                                        Text {
                                            text: "Sehbehinderung"
                                            color: "#e2e8f0"
                                            font.pixelSize: 16
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Vergr\u00f6\u00dfert alle Icons, Texte und Bedienelemente.\nAktueller Faktor: " + systemMonitor.uiScale.toFixed(1) + "x"
                                            color: "#a0a5c0"
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            width: parent.width - 32
                                        }

                                        Row {
                                            spacing: 12

                                            Repeater {
                                                model: [
                                                    { label: "Normal", scale: 1.0 },
                                                    { label: "Gro\u00df", scale: 1.5 },
                                                    { label: "Sehr Gro\u00df", scale: 2.0 },
                                                    { label: "Maximum", scale: 3.0 }
                                                ]

                                                delegate: Button {
                                                    id: scaleBtn
                                                    text: modelData.label
                                                    width: 100
                                                    height: 40
                                                    background: Rectangle {
                                                        color: Math.abs(systemMonitor.uiScale - modelData.scale) < 0.1
                                                               ? Qt.rgba(0.1, 0.7, 0.95, 0.3)
                                                               : scaleBtn.hovered ? Qt.rgba(1,1,1,0.08) : themeManager.glassBgColor
                                                        border.color: Math.abs(systemMonitor.uiScale - modelData.scale) < 0.1
                                                                      ? themeManager.accentColor : themeManager.glassBorderColor
                                                        border.width: Math.abs(systemMonitor.uiScale - modelData.scale) < 0.1 ? 2 : 1
                                                        radius: 10
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    contentItem: Text {
                                                        text: parent.text
                                                        color: Math.abs(systemMonitor.uiScale - modelData.scale) < 0.1
                                                               ? themeManager.accentColor : "#ffffff"
                                                        font.pixelSize: 13
                                                        font.bold: Math.abs(systemMonitor.uiScale - modelData.scale) < 0.1
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    onClicked: systemMonitor.setUiScale(modelData.scale)
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width - 32
                                            height: 60
                                            radius: 8
                                            color: "#10ffffff"
                                            border.color: themeManager.glassBorderColor

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 16
                                                Text {
                                                    text: "Vorschau:"
                                                    color: "#a0a5c0"
                                                    font.pixelSize: 12 * systemMonitor.uiScale
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Rectangle {
                                                    width: 24 * systemMonitor.uiScale
                                                    height: 24 * systemMonitor.uiScale
                                                    radius: 6 * systemMonitor.uiScale
                                                    color: themeManager.accentColor
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        text: "A"
                                                        anchors.centerIn: parent
                                                        color: "#ffffff"
                                                        font.pixelSize: 14 * systemMonitor.uiScale
                                                        font.bold: true
                                                    }
                                                }
                                                Text {
                                                    text: "App Name"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14 * systemMonitor.uiScale
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }

                                        Text {
                                            text: "\u26A0 \u00C4nderung wird sofort wirksam und beim Neustart beibehalten."
                                            color: "#f59e0b"
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Global Right-Click Context Menu (Copy / Paste / Cut / Select All)
    // ═══════════════════════════════════════════════════════════════
    MouseArea {
        id: globalRightClick
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        z: 1  // Above desktop content, below panels/popups
        propagateComposedEvents: true

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                contextMenu.x = Math.min(mouse.x, parent.width - 220);
                contextMenu.y = Math.min(mouse.y, parent.height - 300);
                contextMenu.open();
                mouse.accepted = true;
            }
        }
        onPressed: function(mouse) {
            if (mouse.button !== Qt.RightButton) {
                mouse.accepted = false;  // Let left-clicks through
            }
        }
    }

    Popup {
        id: contextMenu
        width: 200
        padding: 4
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Qt.rgba(0.06, 0.07, 0.12, 0.95)
            border.color: Qt.rgba(0.2, 0.25, 0.4, 0.6)
            border.width: 1
            radius: 10

            layer.enabled: true
            layer.effect: Item {}
        }

        contentItem: Column {
            spacing: 2
            width: parent.width

            Repeater {
                model: [
                    { label: "✂️  Ausschneiden", key: "ctrl+x" },
                    { label: "📋  Kopieren",      key: "ctrl+c" },
                    { label: "📥  Einfügen",      key: "ctrl+v" },
                    { label: "🔤  Alles Auswählen", key: "ctrl+a" }
                ]

                delegate: Rectangle {
                    width: 192
                    height: 36
                    radius: 6
                    color: menuItemMouse.containsMouse ? Qt.rgba(0.15, 0.55, 0.85, 0.3) : "transparent"

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.label
                        color: menuItemMouse.containsMouse ? "#20c2f8" : "#c9d1d9"
                        font.pixelSize: 14
                        font.family: "Segoe UI"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.key === "ctrl+x" ? "Ctrl+X" :
                              modelData.key === "ctrl+c" ? "Ctrl+C" :
                              modelData.key === "ctrl+v" ? "Ctrl+V" : "Ctrl+A"
                        color: "#484f58"
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: menuItemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            contextMenu.close();
                            systemMonitor.launchApp("xdotool key " + modelData.key);
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                width: 180; height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(0.3, 0.35, 0.5, 0.3)
            }

            // Clipboard Bridge Button
            Rectangle {
                width: 192
                height: 36
                radius: 6
                color: clipBridgeMouse.containsMouse ? Qt.rgba(0.85, 0.15, 0.55, 0.3) : "transparent"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: "🌐  Clipboard Bridge"
                    color: clipBridgeMouse.containsMouse ? "#f820c2" : "#c9d1d9"
                    font.pixelSize: 14
                }

                MouseArea {
                    id: clipBridgeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        contextMenu.close();
                        systemMonitor.launchApp("mb-browser --url http://127.0.0.1:9876");
                    }
                }
            }
        }
    }
}
