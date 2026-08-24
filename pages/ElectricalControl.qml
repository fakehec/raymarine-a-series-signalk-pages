// ElectricalControl.qml — SAMPLE boat-plan control page for a Raymarine a-Series
// (LightHouse II) RMDS package.
//
// Shows how the page stays in sync with the server (http_bridge.py) on the companion
// host:
//   * poll  GET /state   -> real relay state (server decodes PGN 127501)  -> colors
//   * tap   GET /toggle/n -> ask the server to switch, with an "optimistic hold" so the
//                            dot doesn't flicker while the real state comes back
//
// Channels 1-4 here are YDCC relay OUTPUTS (controllable). Read-only inputs (a YDRI,
// channels 5-8) follow the exact same poll pattern but have no toggle — omitted for
// brevity. QtQuick 1.1. Set BRIDGE to your companion host's IP.

import QtQuick 1.1

FocusScope {
    id: page
    width:  view.width
    height: view.height

    property string bridge: "http://192.168.0.20:8888"   // companion host

    // real state (from /state) and an optimistic-hold overlay per channel
    property variant real:  [0, 0, 0, 0]     // last state reported by the server
    property variant hold:  [-1, -1, -1, -1] // commanded value while holding, else -1
    property variant until: [0, 0, 0, 0]     // hold expiry (ms epoch) per channel
    property bool    online: false           // did the last /state poll succeed?

    // displayed state = the optimistic hold if still active, else the real state
    function channelOn(n) {
        var i = parseInt(n) - 1;
        if (i < 0 || i > 3) return false;
        if (page.hold[i] !== -1 && (new Date()).getTime() < page.until[i])
            return page.hold[i] === 1;
        return page.real[i] === 1;
    }

    function pollState() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState === 4) {
                if (x.status === 200) {
                    try {
                        var o = JSON.parse(x.responseText);   // { "ch": [0,1,0,0] }
                        page.real = o.ch;
                        page.online = true;
                        // drop any hold that the real state has now caught up to
                        var h = page.hold.slice(), u = page.until.slice(), now = (new Date()).getTime();
                        for (var i = 0; i < 4; i++)
                            if (h[i] !== -1 && (now >= u[i] || page.real[i] === h[i])) { h[i] = -1; }
                        page.hold = h; page.until = u;
                    } catch (e) { page.online = false; }
                } else { page.online = false; }
            }
        };
        x.open("GET", page.bridge + "/state?t=" + (new Date()).getTime());
        x.send();
    }

    function toggle(n) {
        var i = parseInt(n) - 1;
        if (i < 0 || i > 3) return;
        var want = channelOn(n) ? 0 : 1;
        // optimistic hold ~1.5 s so the dot shows the new state immediately
        var h = page.hold.slice(), u = page.until.slice();
        h[i] = want; u[i] = (new Date()).getTime() + 1500;
        page.hold = h; page.until = u;
        var x = new XMLHttpRequest();
        x.open("GET", page.bridge + "/toggle/" + n + "?t=" + (new Date()).getTime());
        x.send();
    }

    Rectangle {
        width: view.width; height: view.height; color: "#000000"

        Item {
            id: content
            width: 1280; height: 800
            transform: Scale { xScale: view.width / 1280; yScale: view.height / 800 }

            // ---- header ------------------------------------------------------------
            Text { x: 30;  y: 22; text: "Electrical Control"; color: "#ffffff"; font.pixelSize: 34 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; y: 22
                   text: "BOAT"; color: "#ffffff"; font.bold: true; font.pixelSize: 34 }
            Text { x: 1050; y: 22
                   text: "Server: " + (page.online ? "on" : "off")
                   color: page.online ? "#22cc44" : "#ff3b30"; font.pixelSize: 28 }

            // ---- deck plan + control markers (channels 1-4) -----------------------
            Image { id: plan; source: "plan.jpg"; x: 30; y: 80; width: 1220 }

            ListModel {
                id: markers
                ListElement { n: "1"; fx: 0.45; fy: 0.55; onColor: "#22cc44" }
                ListElement { n: "2"; fx: 0.70; fy: 0.20; onColor: "#22cc44" }
                ListElement { n: "3"; fx: 0.62; fy: 0.55; onColor: "#ffcc00" }
                ListElement { n: "4"; fx: 0.70; fy: 0.55; onColor: "#fff2a0" }
            }
            Repeater {
                model: markers
                delegate: Rectangle {
                    width: 34; height: 34; radius: 17
                    x: plan.x + fx * plan.width  - 17
                    y: plan.y + fy * plan.height - 17
                    color: page.channelOn(n) ? onColor : "#3a3a3a"
                    Text { anchors.centerIn: parent; text: n; color: "#ffffff"; font.pixelSize: 18 }
                    MouseArea { anchors.fill: parent; onClicked: page.toggle(n) }
                }
            }

            // ---- channel list: buttons for the four controllable outputs ----------
            Repeater {
                model: ListModel {
                    ListElement { n: "1"; label: "Black Water Pump" }
                    ListElement { n: "2"; label: "Engine Room Ventilation" }
                    ListElement { n: "3"; label: "Navigation Lights" }
                    ListElement { n: "4"; label: "Anchor Lights" }
                }
                delegate: Item {
                    y: 560 + index * 55; x: 30; width: 600; height: 48
                    Text { x: 60; anchors.verticalCenter: parent.verticalCenter
                           text: n + "  " + label; color: "#ffffff"; font.pixelSize: 26 }
                    Rectangle {   // ON/OFF pill
                        x: 470; width: 90; height: 40; radius: 20
                        color: page.channelOn(n) ? "#ffcc00" : "#00000000"
                        border.color: "#8a8a8a"; border.width: 2
                        Text { anchors.centerIn: parent
                               text: page.channelOn(n) ? "ON" : "OFF"
                               color: page.channelOn(n) ? "#000000" : "#ffffff"; font.pixelSize: 22 }
                        MouseArea { anchors.fill: parent; onClicked: page.toggle(n) }
                    }
                }
            }

            // ---- keep in sync: poll real state ~1 Hz ------------------------------
            Timer { interval: 1000; running: true; repeat: true; onTriggered: page.pollState() }
            Component.onCompleted: page.pollState()
        }
    }
}
