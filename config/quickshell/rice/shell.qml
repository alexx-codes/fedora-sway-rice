// Quickshell widgets — fedora-sway-rice
//
// Division of labor (confirmed): Waybar owns the bar, swaync owns
// notifications, rofi owns launching. Quickshell owns only:
//   * power menu     — `qs -c rice ipc call powermenu toggle`
//   * volume/brightness OSD — `qs -c rice ipc call osd show <kind> <pct>`
//   * keybind cheatsheet    — `qs -c rice ipc call cheatsheet toggle`
//   * theme reload          — `qs -c rice ipc call theme reload`
// Every widget is driven from shell scripts via IPC, so this file has no
// service bindings that could break with a Quickshell update; if quickshell
// is down entirely, the calling scripts fall back to rofi/notify-send.
//
// Colors come from ~/.config/rice/active/quickshell.json (the active theme).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ------------------------------------------------------------ theme
    property var theme: ({})
    function col(name, fallback) {
        try {
            if (root.theme && root.theme.colors && root.theme.colors[name])
                return root.theme.colors[name];
        } catch (e) {}
        return fallback;
    }
    property color cBg:      col("bg", "#1a1b26")
    property color cBgAlt:   col("bg-alt", "#16161e")
    property color cBgHl:    col("bg-hl", "#292e42")
    property color cFg:      col("fg", "#c0caf5")
    property color cFgDim:   col("fg-dim", "#a9b1d6")
    property color cBorder:  col("border", "#3b4261")
    property color cAccent:  col("accent", "#7aa2f7")
    property color cAccent2: col("accent2", "#bb9af7")
    property color cPink:    col("pink", "#ff9ac1")
    property color cRed:     col("red", "#f7768e")

    property string fontName: "JetBrainsMono Nerd Font"

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/rice/active/quickshell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.theme = JSON.parse(themeFile.text()); } catch (e) {}
        }
    }

    IpcHandler {
        target: "theme"
        function reload(): void { themeFile.reload(); }
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // ------------------------------------------------------------ power menu
    IpcHandler {
        target: "powermenu"
        function toggle(): void { powerMenu.visible = !powerMenu.visible; }
    }

    PanelWindow {
        id: powerMenu
        visible: false
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: powerMenu.visible = false }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.45 }

        Rectangle {
            anchors.centerIn: parent
            width: powerRow.implicitWidth + 48
            height: powerRow.implicitHeight + 72
            radius: 18
            color: root.cBg
            border.color: root.cAccent
            border.width: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                text: (root.theme && root.theme.name) ? root.theme.name + "  ·  session" : "session"
                color: root.cFgDim
                font.family: root.fontName
                font.pixelSize: 13
            }

            RowLayout {
                id: powerRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 10
                spacing: 14

                Repeater {
                    model: [
                        { icon: "󰌾", label: "Lock",     accent: root.cAccent,  cmd: "swaylock -f" },
                        { icon: "󰍃", label: "Logout",   accent: root.cAccent2, cmd: "swaymsg exit" },
                        { icon: "󰒲", label: "Suspend",  accent: root.cPink,    cmd: "systemctl suspend" },
                        { icon: "󰖔", label: "Theme",    accent: root.cPink,    cmd: "~/.config/rice/scripts/theme-toggle.sh" },
                        { icon: "󰜉", label: "Reboot",   accent: root.cAccent2, cmd: "systemctl reboot" },
                        { icon: "󰐥", label: "Shutdown", accent: root.cRed,     cmd: "systemctl poweroff" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: 96
                        height: 96
                        radius: 14
                        color: hover.hovered ? root.cBgHl : root.cBgAlt
                        border.color: hover.hovered ? modelData.accent : root.cBorder
                        border.width: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                color: modelData.accent
                                font.family: root.fontName
                                font.pixelSize: 30
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: root.cFg
                                font.family: root.fontName
                                font.pixelSize: 12
                            }
                        }

                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: {
                                powerMenu.visible = false;
                                root.run(modelData.cmd);
                            }
                        }
                    }
                }
            }

            focus: powerMenu.visible
            Keys.onEscapePressed: powerMenu.visible = false
        }
    }

    // ------------------------------------------------------------ OSD
    property string osdKind: "volume"
    property int osdValue: 0

    IpcHandler {
        target: "osd"
        function show(kind: string, value: int): void {
            root.osdKind = kind;
            root.osdValue = Math.max(0, Math.min(100, value));
            osd.visible = true;
            osdTimer.restart();
        }
    }

    Timer {
        id: osdTimer
        interval: 1400
        onTriggered: osd.visible = false
    }

    PanelWindow {
        id: osd
        visible: false
        anchors.bottom: true
        margins.bottom: 90
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        implicitWidth: 300
        implicitHeight: 56

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.cBg
            border.color: root.cBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: {
                        if (root.osdKind.indexOf("muted") >= 0) return "󰝟";  // 󰝟
                        if (root.osdKind === "brightness") return "󰃟";       // 󰃟
                        if (root.osdKind === "mic") return "󰍬";              // 󰍬
                        return "󰕾";                                          // 󰕾
                    }
                    color: root.osdKind.indexOf("muted") >= 0 ? root.cRed : root.cPink
                    font.family: root.fontName
                    font.pixelSize: 20
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: root.cBgHl
                    Rectangle {
                        width: parent.width * root.osdValue / 100.0
                        height: parent.height
                        radius: 4
                        color: root.osdKind.indexOf("muted") >= 0 ? root.cRed : root.cAccent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Text {
                    text: root.osdValue + "%"
                    color: root.cFg
                    font.family: root.fontName
                    font.pixelSize: 13
                }
            }
        }
    }

    // ------------------------------------------------------------ cheatsheet
    property var cheatModel: []

    FileView {
        id: keybindsFile
        path: Quickshell.env("HOME") + "/.config/rice/keybinds.tsv"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseKeybinds()
    }

    function parseKeybinds() {
        var sections = [];
        var byCat = {};
        try {
            var lines = keybindsFile.text().split("\n");
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i];
                if (line.trim() === "" || line.trim().charAt(0) === "#") continue;
                var f = line.split("\t");
                if (f.length !== 5) continue;
                if (f[2].indexOf("hide") >= 0) continue;
                if (!byCat[f[0]]) {
                    byCat[f[0]] = { category: f[0], entries: [] };
                    sections.push(byCat[f[0]]);
                }
                byCat[f[0]].entries.push({ keys: f[1], desc: f[4] });
            }
        } catch (e) {}
        root.cheatModel = sections;
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { cheatsheet.visible = !cheatsheet.visible; }
    }

    PanelWindow {
        id: cheatsheet
        visible: false
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: cheatsheet.visible = false }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.45 }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 1100)
            height: Math.min(parent.height - 60, 720)
            radius: 18
            color: root.cBg
            border.color: root.cAccent2
            border.width: 2

            Text {
                id: cheatTitle
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 14
                text: "Keybindings   ·   $mod = Super   ·   Esc to close"
                color: root.cAccent2
                font.family: root.fontName
                font.pixelSize: 15
                font.bold: true
            }

            Flickable {
                anchors.top: cheatTitle.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 18
                contentHeight: cheatFlow.implicitHeight
                clip: true

                Flow {
                    id: cheatFlow
                    width: parent.width
                    spacing: 18

                    Repeater {
                        model: root.cheatModel

                        delegate: Column {
                            required property var modelData
                            width: 500
                            spacing: 3

                            Text {
                                text: modelData.category
                                color: root.cPink
                                font.family: root.fontName
                                font.pixelSize: 13
                                font.bold: true
                                bottomPadding: 4
                            }

                            Repeater {
                                model: modelData.entries
                                delegate: Row {
                                    required property var modelData
                                    spacing: 10
                                    Text {
                                        width: 230
                                        text: modelData.keys
                                        color: root.cAccent
                                        font.family: root.fontName
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: 250
                                        text: modelData.desc
                                        color: root.cFgDim
                                        font.family: root.fontName
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }

            focus: cheatsheet.visible
            Keys.onEscapePressed: cheatsheet.visible = false
        }
    }
}
