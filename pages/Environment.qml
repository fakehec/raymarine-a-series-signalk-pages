// Environment.qml — SAMPLE page for a Raymarine a-Series (LightHouse II) RMDS package.
//
// Shows the technique: native DataItem cells for catalog values, plus custom Text
// tiles fed by the HTTP bridge (/wx) for values the catalog can't express — here
// true wind, dew point, cloud cover, a weather headline and a barometer line.
//
// QtQuick 1.1. Author the content Item at your model's native resolution and scale
// it to the viewport (a12/a128 = 1280x800; 7"/9" units = 800x480 — see EmpirBus manual
// Table 3.1). Adapt IDs/paths/host to your boat.

import QtQuick 1.1
import "../Cells/Indicators"          // the YachtDevices DataItem cell library

FocusScope {
    id: page
    width:  view.width
    height: view.height

    // ---- values fed by the HTTP bridge ------------------------------------------
    property string tws:      "—"
    property string twd:      "—"
    property string dewpt:    "—"
    property string cloud:    "—"
    property string wxHead:   "—"
    property string baroLine: "—"

    function poll() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState === 4 && x.status === 200) {
                try {
                    var o = JSON.parse(x.responseText);
                    page.tws   = (o.tws == null) ? "—" : (o.tws * 1.94384).toFixed(1) + " kn";
                    if (o.twd == null) { page.twd = "—"; }
                    else { var d = Math.round(o.twd * 57.2958); page.twd = (((d % 360) + 360) % 360) + "°"; }
                    page.dewpt = (o.dewpoint == null) ? "—" : (o.dewpoint - 273.15).toFixed(1) + " °C";
                    page.cloud = (o.cloud == null) ? "—" : Math.round(o.cloud * 100) + " %";
                    page.wxHead = o.wxHead ? o.wxHead : "—";
                    var bl = o.baroTend ? o.baroTend : "";
                    if (o.baroBft) bl += (bl ? "  ·  " : "") + o.baroBft;
                    page.baroLine = (bl === "") ? "—" : bl;
                } catch (e) {}
            }
        };
        x.open("GET", "http://192.168.0.20:8888/wx?t=" + (new Date()).getTime());
        x.send();
    }

    Rectangle {
        width: view.width; height: view.height; color: "#000000"

        Item {
            id: content
            width: 1280; height: 800
            transform: Scale { xScale: view.width / 1280; yScale: view.height / 800 }

            Text { x: 30; y: 22; text: "Environment"; color: "#ffffff"; font.bold: true; font.pixelSize: 40 }

            // ---- native DataItem cells (catalog IDs) --------------------------------
            DigitalValueDataItemCenterAligned {
                x: 30;  y: 140; m_Name: "Air Temperature";   m_CellWidth: 290
                m_TitleFontSize: 23; m_ValueFontSize: 46; m_ValueColour: "#ffffff"
                m_DataItemID: 58; m_PrimaryDataItemInstance: 0
            }
            DigitalValueDataItemCenterAligned {
                x: 335; y: 140; m_Name: "Water Temperature"; m_CellWidth: 290
                m_TitleFontSize: 23; m_ValueFontSize: 46; m_ValueColour: "#ffffff"
                m_DataItemID: 55; m_PrimaryDataItemInstance: 0
            }
            DigitalValueDataItemCenterAligned {
                x: 640; y: 140; m_Name: "Pressure";          m_CellWidth: 290
                m_TitleFontSize: 23; m_ValueFontSize: 46; m_ValueColour: "#ffffff"
                m_DataItemID: 94; m_PrimaryDataItemInstance: 0
            }
            DigitalValueDataItemCenterAligned {
                x: 945; y: 140; m_Name: "Humidity";          m_CellWidth: 290
                m_TitleFontSize: 23; m_ValueFontSize: 46; m_ValueColour: "#ffffff"
                m_DataItemID: 95; m_PrimaryDataItemInstance: 0
            }

            // ---- custom HTTP tiles (values the catalog can't give) ------------------
            //      title (grey) + value (white), centered in a 290-wide cell
            Component {
                id: httpTile
                Item {
                    property alias title: t.text
                    property alias value: v.text
                    Text { id: t; width: 290; horizontalAlignment: Text.AlignHCenter; color: "#8a8a8a"; font.pixelSize: 23 }
                    Text { id: v; y: 34; width: 290; horizontalAlignment: Text.AlignHCenter; color: "#ffffff"; font.pixelSize: 46 }
                }
            }
            Loader { x: 30;  y: 300; sourceComponent: httpTile; onLoaded: { item.title = "Dew Point";       item.value = Qt.binding(function(){ return page.dewpt; }); } }
            Loader { x: 335; y: 300; sourceComponent: httpTile; onLoaded: { item.title = "Cloud Cover";      item.value = Qt.binding(function(){ return page.cloud; }); } }
            Loader { x: 640; y: 300; sourceComponent: httpTile; onLoaded: { item.title = "True Wind Speed";  item.value = Qt.binding(function(){ return page.tws; }); } }
            Loader { x: 945; y: 300; sourceComponent: httpTile; onLoaded: { item.title = "True Wind Dir";    item.value = Qt.binding(function(){ return page.twd; }); } }

            // ---- LLM/derived text lines --------------------------------------------
            Text { x: 30; y: 470; text: "Weather";   color: "#8a8a8a"; font.bold: true; font.pixelSize: 23 }
            Text { x: 30; y: 500; width: 1220; wrapMode: Text.WordWrap; text: page.wxHead;   color: "#ffffff"; font.pixelSize: 30 }
            Text { x: 30; y: 560; text: "Barometer"; color: "#8a8a8a"; font.bold: true; font.pixelSize: 23 }
            Text { x: 30; y: 590; width: 1220; text: page.baroLine; color: "#ffffff"; font.pixelSize: 26 }

            Timer { interval: 2000; running: true; repeat: true; onTriggered: page.poll() }
            Component.onCompleted: page.poll()
        }
    }
}
