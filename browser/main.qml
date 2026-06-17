import QtQuick
import QtQuick.Controls
import QtWebEngine

ApplicationWindow {
    id: window
    visible: true
    width: 1280
    height: 800
    title: webView.title ? webView.title : "MB-Browser"

    // Persistent browser profile
    WebEngineProfile {
        id: customProfile
        storageName: "MBBrowser"
        offTheRecord: false
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    }

    // Top Header & Toolbar (Futuristic dark glassmorphic styling)
    header: ToolBar {
        background: Rectangle {
            color: "#0f111a"
            border.color: "#20ffffff"
            border.width: 1
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            spacing: 12

            // Navigation: Back
            Button {
                id: backBtn
                width: 32
                height: 32
                flat: true
                enabled: webView.canGoBack
                background: Rectangle {
                    color: backBtn.hovered ? "#20ffffff" : "transparent"
                    radius: 6
                }
                contentItem: Text {
                    text: "◀"
                    color: backBtn.enabled ? "#ffffff" : "#40ffffff"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: webView.goBack()
            }

            // Navigation: Forward
            Button {
                id: forwardBtn
                width: 32
                height: 32
                flat: true
                enabled: webView.canGoForward
                background: Rectangle {
                    color: forwardBtn.hovered ? "#20ffffff" : "transparent"
                    radius: 6
                }
                contentItem: Text {
                    text: "▶"
                    color: forwardBtn.enabled ? "#ffffff" : "#40ffffff"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: webView.goForward()
            }

            // Navigation: Reload
            Button {
                id: reloadBtn
                width: 32
                height: 32
                flat: true
                background: Rectangle {
                    color: reloadBtn.hovered ? "#20ffffff" : "transparent"
                    radius: 6
                }
                contentItem: Text {
                    text: webView.loading ? "■" : "↻"
                    color: "#ffffff"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: webView.loading ? webView.stop() : webView.reload()
            }

            // URL Address Input
            Rectangle {
                width: parent.width - 250
                height: 36
                color: "#181a26"
                border.color: urlInput.activeFocus ? "#00f0ff" : "#30ffffff"
                border.width: 1
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextInput {
                    id: urlInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    color: "#ffffff"
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true
                    text: webView.url.toString()

                    onAccepted: {
                        var targetUrl = text.trim();
                        if (targetUrl.indexOf("://") === -1) {
                            if (targetUrl.indexOf(".") === -1 || targetUrl.indexOf(" ") !== -1) {
                                // Search Google/DuckDuckGo
                                targetUrl = "https://duckduckgo.com/?q=" + encodeURIComponent(targetUrl);
                            } else {
                                targetUrl = "https://" + targetUrl;
                            }
                        }
                        webView.url = targetUrl;
                    }
                }
            }

            // Tor Toggle Button (Futuristic glowing look)
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "Tor"
                    color: torToggle.checked ? "#bd00ff" : "#a0a5c0"
                    font.pixelSize: 12
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Switch {
                    id: torToggle
                    anchors.verticalCenter: parent.verticalCenter
                    
                    indicator: Rectangle {
                        implicitWidth: 44
                        implicitHeight: 22
                        x: torToggle.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 11
                        color: torToggle.checked ? "#30bd00ff" : "#20ffffff"
                        border.color: torToggle.checked ? "#bd00ff" : "#40ffffff"
                        border.width: 1

                        Rectangle {
                            x: torToggle.checked ? 24 : 2
                            y: 2
                            width: 18
                            height: 18
                            radius: 9
                            color: torToggle.checked ? "#bd00ff" : "#ffffff"
                            Behavior on x {
                                NumberAnimation { duration: 150 }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }
                    }

                    onCheckedChanged: {
                        if (checked) {
                            statusLabel.text = "Routing active via TOR (127.0.0.1:9050)";
                            statusLabel.color = "#bd00ff";
                        } else {
                            statusLabel.text = "Direct connection active (No Proxy)";
                            statusLabel.color = "#00f0ff";
                        }
                    }
                }
            }
        }
    }

    // Web View containing the Chromium engine
    WebEngineView {
        id: webView
        anchors.fill: parent
        profile: customProfile
        url: typeof startUrl !== "undefined" ? startUrl : "https://duckduckgo.com"

        // Auto-grant notification permissions for all sites
        onFeaturePermissionRequested: function(securityOrigin, feature) {
            if (feature === WebEngineView.Notifications) {
                console.log("Notification permission granted for: " + securityOrigin);
                webView.grantFeaturePermission(securityOrigin, feature, true);
            } else if (feature === WebEngineView.MediaAudioCapture ||
                       feature === WebEngineView.MediaVideoCapture ||
                       feature === WebEngineView.MediaAudioVideoCapture) {
                webView.grantFeaturePermission(securityOrigin, feature, true);
            }
        }

        // Handle new window requests (popups) - open in same view
        onNewWindowRequested: function(request) {
            webView.url = request.requestedUrl;
        }

        // Inject notification bridge script after page load
        onLoadingChanged: function(loadRequest) {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                // Override browser Notification to also call notify-send
                webView.runJavaScript("
                    if (window._mbNotifyPatched === undefined) {
                        window._mbNotifyPatched = true;
                        var OrigNotification = window.Notification;
                        window.Notification = function(title, options) {
                            var n = new OrigNotification(title, options);
                            // Use a hidden image to ping our notification forwarder
                            var img = new Image();
                            img.src = 'mb-notify://' + encodeURIComponent(title) + '/' + encodeURIComponent(options && options.body ? options.body : '');
                            return n;
                        };
                        window.Notification.permission = 'granted';
                        window.Notification.requestPermission = function(cb) {
                            if (cb) cb('granted');
                            return Promise.resolve('granted');
                        };
                    }
                ");
            }
        }

        // Loading indicator
        ProgressBar {
            id: loadProgress
            width: parent.width
            height: 3
            anchors.top: parent.top
            value: webView.loadProgress / 100
            visible: webView.loading
            background: Rectangle { color: "transparent" }
            contentItem: Item {
                Rectangle {
                    width: loadProgress.visualPosition * loadProgress.width
                    height: parent.height
                    color: torToggle.checked ? "#bd00ff" : "#00f0ff"
                }
            }
        }
    }

    // Status bar at the bottom
    footer: ToolBar {
        height: 24
        background: Rectangle {
            color: "#0c0e14"
            border.color: "#15ffffff"
            border.width: 1
        }
        Text {
            id: statusLabel
            text: "Direct connection active (No Proxy)"
            color: "#00f0ff"
            font.pixelSize: 10
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
