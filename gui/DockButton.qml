import QtQuick
import QtQuick.Controls

Button {
    id: control
    width: 60
    height: 60
    
    property string iconText: "★"
    property string label: "App"
    property color colorCode: "#00f0ff"

    background: Rectangle {
        id: bgRect
        color: control.hovered ? Qt.rgba(control.colorCode.r, control.colorCode.g, control.colorCode.b, 0.18) : themeManager.glassBgColor
        radius: 15
        border.color: control.hovered ? control.colorCode : themeManager.glassBorderColor
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        
        // Lightfield highlight: a soft white glow circle that follows the mouse
        Rectangle {
            width: 40
            height: 40
            radius: 20
            color: Qt.rgba(1.0, 1.0, 1.0, 0.08) // very soft white reflection
            x: mouseTracker.mouseX - width / 2
            y: mouseTracker.mouseY - height / 2
            visible: control.hovered
            layer.enabled: true
            // Smooth movement behavior
            Behavior on x { NumberAnimation { duration: 80 } }
            Behavior on y { NumberAnimation { duration: 80 } }
        }

        // Small glow dot below active hover
        Rectangle {
            width: 6
            height: 6
            radius: 3
            color: control.colorCode
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: control.hovered ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    contentItem: Item {
        anchors.fill: parent
        
        Text {
            text: control.iconText
            font.pixelSize: 20
            font.bold: true
            color: control.hovered ? control.colorCode : "#d1d5db"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
            text: control.label
            color: control.hovered ? "#ffffff" : "#8890a5"
            font.pixelSize: 9
            font.bold: true
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    MouseArea {
        id: mouseTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: -1
    }
}
