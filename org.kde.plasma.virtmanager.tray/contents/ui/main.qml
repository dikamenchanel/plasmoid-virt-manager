pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as Plasma5support
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import QtQuick 2.15
import QtQuick.Controls 2.15


PlasmoidItem {
    id: root

    Plasmoid.icon: "virt-manager-symbol"
    toolTipMainText: qsTr("My Tray Applet")
    toolTipSubText: qsTr("Click to open")
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    

    // --- Свойство состояния virt ---
    property bool virtInstalled: true
    
    // --- DataSource для проверки наличия virt ---
    Plasma5support.DataSource {
        id: checkVirt
        engine: "executable"
        connectedSources: []
    
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"].trim()
            if (stdout === "") {
                virtInstalled = false
                console.log("Virt-manager или virsh не установлен")
            } else {
                virtInstalled = true
                refreshVMs() // если установлен, загружаем список ВМ
            }
            disconnectSource(sourceName)
        }
    
        function execCheck() {
            connectSource("command -v virsh") // проверяем наличие virsh
        }
    }
    fullRepresentation: Item {
        implicitWidth: 400
        implicitHeight: 220
    
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            
            // --- Заглушка ---
            Text {
                visible: !virtInstalled
                text: "Virt-manager или virsh не установлен"
                color: "#ff5555"
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            }
            
            ListView {
                id: vmList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: vmModel
                clip: true
                visible: virtInstalled 
                spacing: 6
                
                delegate: Rectangle {
                    required property string name
                    required property string status
                    width: vmList.width
                    height: 50
                    radius: 8
    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12
    
                        ToolButton {
                           icon.name: "virt-manager-symbol"
                           onClicked: startAndOpenConsole(name)
                           ToolTip.text: "Start and Show VM"
                        }
   
                        // --- Индикатор работы ---
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            Layout.alignment: Qt.AlignVCenter
                            color: status === "работает" ? "#4CAF50" : "#F44336"
                        }
    
                        // --- Название ВМ ---
                        Text {
                            text: name
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
    
                        // --- Кнопки действий справа ---
                        RowLayout {
                            spacing: 6
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        
                            ToolButton {
                                icon.name: "pan-start-symbolic-rtl"
                                enabled: status !== "работает"
                                onClicked: startVM(name)
                                ToolTip.text: "Start VM"
                            }
                        
                            ToolButton {
                                icon.name: "view-refresh"
                                enabled: status === "работает"
                                onClicked: restartVM(name)
                                ToolTip.text: "Restart VM"
                            }
                        
                            ToolButton {
                                icon.name: "process-stop"
                                enabled: status === "работает"
                                onClicked: stopVM(name)
                                ToolTip.text: "Stop VM"
                            }
                        
                            ToolButton {
                                icon.name: "computer"
                                onClicked: openConsole(name)
                                ToolTip.text: "Open Console"
                            }
                        }
                    }
    
                    // MouseArea {
                    //     id: mouseArea
                    //     anchors.fill: parent
                    //     hoverEnabled: true
                    //     cursorShape: Qt.PointingHandCursor
                    //     onClicked: {
                    //         console.log("Клик на элемент", name)
                    //     }
                    //     propagateComposedEvents: true
                    // }
                }
            }
    
            Text {
                visible: vmModel.count === 0
                text: "Нет виртуальных машин\nСоздай в virt-manager"
                color: "#888888"
                font.italic: true
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            }
        }
    }
    
    // --- Модель ---
    ListModel { id: vmModel }

    // Автообновление через таймер
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: refreshVMs
    }

    // DataSource для выполнения команд
    Plasma5support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = data["stdout"]
            var exitCode = data["exit code"]

            if (sourceName.includes("sudo virsh list --all")) {
                parseVirshList(stdout)
            } else {
                // После start/stop/reboot просто обновляем список
                Qt.callLater(refreshVMs)
            }

            disconnectSource(sourceName)
        }

        function exec(cmd) { connectSource(cmd) }
    }

    // --- Функции ---
    function parseVirshList(output) {
        vmModel.clear()
        var lines = output.trim().split("\n")
        for (var i = 2; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var parts = line.split(/\s{2,}/)
            if (parts.length < 3) continue
            vmModel.append({ name: parts[1], status: parts[2] })
        }
        if (vmModel.count === 0) {
            vmModel.append({ name: "No VMs", status: "—" })
        }
    }

    function refreshVMs() {
        executable.exec("sudo virsh list --all")
    }

    function startVM(name) {
        executable.exec('sudo virsh start "' + name + '"')
        Qt.callLater(refreshVMs)
    }

    function stopVM(name) {
        executable.exec('sudo virsh shutdown "' + name + '"')
        Qt.callLater(refreshVMs)
    }

    function restartVM(name) {
        executable.exec('sudo virsh reboot "' + name + '"')
        Qt.callLater(refreshVMs)
    }
   
    function openConsole(name) {
        Qt.callLater(function() {
            executable.exec('virt-manager -c qemu:///system --show-domain-console "' + name + '"')
        })
    }

    function startAndOpenConsole(name) {
        executable.exec('sudo virsh start "' + name + '"')
        Qt.callLater(function() {
            executable.exec('virt-manager -c qemu:///system --show-domain-console "' + name + '"')
        })
    }


    Component.onCompleted: {
        plasmoid.icon = "virt-manager-symbol"
        checkVirt.execCheck()
    }
}
