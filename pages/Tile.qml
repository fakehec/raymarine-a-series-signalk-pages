// Tile.qml — SAMPLE a-Series (LightHouse II) page: show any rendered image full-screen.
// Anything you can render to a PNG/JPG on the companion host — a Grafana panel, a GRIB wind
// map, a screenshot of a web page — can be shown here. The companion caches it and serves it;
// the MFD just polls the image. QtQuick 1.1's Image loads a remote http URL directly (verified
// on a real a128), so no browser/WebView is needed. Point `src` at your companion host.
import QtQuick 1.1
FocusScope {
    id: page
    property string src: "http://192.168.0.20:8889/5.jpg"   // companion cache (see dash_cache.py)
    property int    refreshMs: 60000                          // image changes slowly; poll gently
    width:  view.width
    height: view.height
    Rectangle {
        width: view.width; height: view.height; color: "#000000"
        Item {
            id: content; width: 1280; height: 800
            transform: Scale { xScale: view.width/1280; yScale: view.height/800 }
            Image {
                id: tile; x:0; y:0; width:1280; height:800
                fillMode: Image.PreserveAspectFit; asynchronous: true
                cache: false                                  // always take the cache-busted URL
                source: page.src + "?t=0"
            }
            Text { anchors.centerIn: parent; visible: tile.status !== Image.Ready
                   text: tile.status === Image.Loading ? "Loading…" : "tile offline"
                   color:"#8a8a8a"; font.pixelSize:30 }
            Timer { interval: page.refreshMs; running:true; repeat:true
                    onTriggered: tile.source = page.src + "?t=" + (new Date()).getTime() }
            Component.onCompleted: tile.source = page.src + "?t=" + (new Date()).getTime()
        }
    }
}
