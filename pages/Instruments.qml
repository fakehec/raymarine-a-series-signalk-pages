// Instruments.qml — a128 (LightHouse II) page 7 (self-drawn, QtQuick 1.1).
// Left: 2x2 gauge cluster (apparent wind, heading/COG, depth+alarm, battery SoC).
// Middle: four tank gauges. Right: scene toggles. Bottom: ChangeView page links.
// Data from Signal K REST (192.168.0.20:3000); fresh water from bridge /wx; scenes via /set.
import QtQuick 1.1

FocusScope {
    id: page
    width:  view.width
    height: view.height
    property string sk:     "http://192.168.0.20:3000/signalk/v1/api/vessels/self/"
    property string bridge: "http://192.168.0.20:8888"

    property real   awaDeg: 0;   property string awsTxt: "--"
    property real   hdgDeg: 0;   property string hdgTxt: "--";  property real cogDeg: 0; property bool cogOk: false
    property string depTxt: "--"; property real depVal: 999
    property string socTxt: "--"; property real socVal: 0; property string vBatTxt: "--"
    property real lvlFresh:0; property string txtFresh:"--"
    property real lvlFuelP:0; property string txtFuelP:"--"
    property real lvlFuelS:0; property string txtFuelS:"--"
    property real lvlBlack:0; property string txtBlack:"--"
    property string scene: ""

    function skGet(path, cb){ var x=new XMLHttpRequest(); x.onreadystatechange=function(){ if(x.readyState===4&&x.status===200){try{cb(JSON.parse(x.responseText).value);}catch(e){}} }; x.open("GET",page.sk+path+"?t="+(new Date()).getTime()); x.send(); }
    function poll(){
        skGet("environment/wind/angleApparent", function(v){ if(v!==null) page.awaDeg=v*57.2958; });
        skGet("environment/wind/speedApparent", function(v){ if(v!==null) page.awsTxt=(v*1.94384).toFixed(1); });
        skGet("navigation/headingTrue", function(v){ if(v!==null){ var d=Math.round(v*57.2958); page.hdgDeg=d; page.hdgTxt=(((d%360)+360)%360)+"°"; } });
        skGet("navigation/courseOverGroundTrue", function(v){ if(v!==null){ page.cogDeg=v*57.2958; page.cogOk=true; } });
        skGet("environment/depth/belowSurface", function(v){ if(v!==null){ page.depVal=v; page.depTxt=v.toFixed(1)+" m"; } });
        skGet("electrical/batteries/0/capacity/stateOfCharge", function(v){ if(v!==null){ page.socVal=v; page.socTxt=Math.round(v*100)+"%"; } });
        skGet("electrical/batteries/0/voltage", function(v){ if(v!==null) page.vBatTxt=v.toFixed(1)+" V"; });
        skGet("tanks/fuel/0/currentLevel", function(v){ if(v!==null){ page.lvlFuelP=v; page.txtFuelP=Math.round(v*100)+"%"; } });
        skGet("tanks/fuel/1/currentLevel", function(v){ if(v!==null){ page.lvlFuelS=v; page.txtFuelS=Math.round(v*100)+"%"; } });
        skGet("tanks/blackWater/0/currentLevel", function(v){ if(v!==null){ page.lvlBlack=v; page.txtBlack=Math.round(v*100)+"%"; } });
        var w=new XMLHttpRequest(); w.onreadystatechange=function(){ if(w.readyState===4&&w.status===200){try{var o=JSON.parse(w.responseText); if(o.fwPct!=null){page.lvlFresh=o.fwPct/100.0; page.txtFresh=Math.round(o.fwPct)+"%";}}catch(e){}} }; w.open("GET",page.bridge+"/wx?t="+(new Date()).getTime()); w.send();
    }
    function set(ch,on){ var x=new XMLHttpRequest(); x.open("GET",page.bridge+"/set/"+ch+"/"+(on?1:0)+"?t="+(new Date()).getTime()); x.send(); }
    function anchor(){ if(page.scene==="ANCHOR"){set(4,false);set(3,false);page.scene="";}else{set(4,true);set(3,false);page.scene="ANCHOR";} }
    function underway(){ if(page.scene==="UNDERWAY"){set(4,false);set(3,false);page.scene="";}else{set(4,false);set(3,true);page.scene="UNDERWAY";} }
    function depColor(){ return page.depVal<2.0?"#ff3b30":(page.depVal<4.0?"#e8820c":"#38b24a"); }
    function socColor(){ return page.socVal<0.5?"#ff3b30":(page.socVal<0.75?"#e8820c":"#38b24a"); }

    Rectangle {
        width: view.width; height: view.height; color:"#000000"
        Item {
            id: content; width:1280; height:800
            transform: Scale { xScale: view.width/1280; yScale: view.height/800 }
            Text { x:30; y:22; text:"Instruments"; color:"#ffffff"; font.bold:true; font.pixelSize:38 }

            // ===== 2x2 gauge cluster (left) =====
            // --- helper: small compass dial as a Component instantiated twice ---
            // Apparent wind (top-left) center (150,215) r=92
            Rectangle { x:58; y:123; width:184; height:184; radius:92; color:"#12161c"; border.color:"#2a3138"; border.width:2 }
            Repeater { model:12; Rectangle { width:2; height:(index%3===0)?12:7; color:(index%3===0)?"#6b7680":"#3a424b"; x:149; y:127; transform: Rotation{ origin.x:1; origin.y:88; angle:index*30 } } }
            Rectangle { x:147; y:150; width:5; height:75; radius:2; color:"#ff3b30"; transform: Rotation{ origin.x:2; origin.y:65; angle:page.awaDeg } }
            Rectangle { x:143; y:208; width:14; height:14; radius:7; color:"#ff3b30"; border.color:"#fff"; border.width:1 }
            Text { x:58; y:200; width:184; horizontalAlignment:Text.AlignHCenter; text:page.awsTxt+" kn"; color:"#fff"; font.bold:true; font.pixelSize:26 }
            Text { x:58; y:312; width:184; horizontalAlignment:Text.AlignHCenter; text:"App Wind"; color:"#ffcc33"; font.bold:true; font.pixelSize:18 }

            // Heading / COG (top-right) center (400,215) r=92
            Rectangle { x:308; y:123; width:184; height:184; radius:92; color:"#12161c"; border.color:"#2a3138"; border.width:2 }
            Repeater { model:12; Rectangle { width:2; height:(index%3===0)?12:7; color:(index%3===0)?"#6b7680":"#3a424b"; x:399; y:127; transform: Rotation{ origin.x:1; origin.y:88; angle:index*30 } } }
            Text { x:393; y:129; text:"N"; color:"#8a8a8a"; font.pixelSize:13 }
            Rectangle { visible:page.cogOk; x:397; y:131; width:8; height:16; color:"#22cc44"; transform: Rotation{ origin.x:4; origin.y:84; angle:page.cogDeg } }
            Rectangle { x:397; y:150; width:6; height:75; radius:2; color:"#e6e6e6"; transform: Rotation{ origin.x:3; origin.y:65; angle:page.hdgDeg } }
            Rectangle { x:393; y:208; width:14; height:14; radius:7; color:"#e6e6e6"; border.color:"#333"; border.width:1 }
            Text { x:308; y:200; width:184; horizontalAlignment:Text.AlignHCenter; text:page.hdgTxt; color:"#fff"; font.bold:true; font.pixelSize:26 }
            Text { x:308; y:312; width:184; horizontalAlignment:Text.AlignHCenter; text:"Heading  (COG ▸)"; color:"#ffcc33"; font.bold:true; font.pixelSize:16 }

            // Depth (bottom-left)
            Rectangle { x:40; y:352; width:220; height:200; radius:12; color:"#12161c"; border.color:"#2a3138"; border.width:2 }
            Text { x:40; y:372; width:220; horizontalAlignment:Text.AlignHCenter; text:"DEPTH"; color:"#8a8a8a"; font.bold:true; font.pixelSize:20 }
            Text { x:40; y:420; width:220; horizontalAlignment:Text.AlignHCenter; text:page.depTxt; color:page.depColor(); font.bold:true; font.pixelSize:60 }
            Text { x:40; y:512; width:220; horizontalAlignment:Text.AlignHCenter; text:"below surface"; color:"#8a8a8a"; font.pixelSize:17 }

            // Battery SoC (bottom-right)
            Rectangle { x:280; y:352; width:220; height:200; radius:12; color:"#12161c"; border.color:"#2a3138"; border.width:2 }
            Text { x:280; y:372; width:220; horizontalAlignment:Text.AlignHCenter; text:"SERVICE BANK"; color:"#8a8a8a"; font.bold:true; font.pixelSize:18 }
            Text { x:280; y:412; width:220; horizontalAlignment:Text.AlignHCenter; text:page.socTxt; color:page.socColor(); font.bold:true; font.pixelSize:52 }
            Rectangle { x:300; y:490; width:180; height:14; radius:7; color:"#0b0e12"; border.color:"#3a424b"; border.width:1
                Rectangle { x:2; y:2; width:Math.max((176)*page.socVal,2); height:10; radius:5; color:page.socColor() } }
            Text { x:280; y:512; width:220; horizontalAlignment:Text.AlignHCenter; text:page.vBatTxt; color:"#cccccc"; font.pixelSize:20 }

            // ===== tanks (middle) =====
            Text { x:560; y:96; text:"TANKS"; color:"#ffcc33"; font.bold:true; font.pixelSize:22 }
            Repeater {
                model: ListModel {
                    ListElement { tx:560; lab:"Fresh"; col:"#2e86de"; which:"Fresh" }
                    ListElement { tx:672; lab:"Fuel P"; col:"#e8820c"; which:"FuelP" }
                    ListElement { tx:784; lab:"Fuel S"; col:"#e8820c"; which:"FuelS" }
                    ListElement { tx:896; lab:"Black"; col:"#4a4f57"; which:"Black" }
                }
                Item {
                    property real lvl: which==="Fresh"?page.lvlFresh:which==="FuelP"?page.lvlFuelP:which==="FuelS"?page.lvlFuelS:page.lvlBlack
                    property string val: which==="Fresh"?page.txtFresh:which==="FuelP"?page.txtFuelP:which==="FuelS"?page.txtFuelS:page.txtBlack
                    Rectangle { id:box; x:tx; y:130; width:96; height:420; radius:10; color:"#12161c"; border.color:"#2a3138"; border.width:2 }
                    Rectangle { x:tx+6; width:84; radius:6; height:Math.max(408*parent.lvl,4); y:544-Math.max(408*parent.lvl,4); color:col }
                    Text { x:tx; width:96; horizontalAlignment:Text.AlignHCenter; y:300; text:parent.val; color:"#fff"; font.bold:true; font.pixelSize:28 }
                    Text { x:tx; width:96; horizontalAlignment:Text.AlignHCenter; y:558; text:lab; color:"#8a8a8a"; font.bold:true; font.pixelSize:18 }
                }
            }

            // ===== scenes (right) =====
            Text { x:1035; y:96; text:"LIGHTS"; color:"#ffcc33"; font.bold:true; font.pixelSize:22 }
            Rectangle { x:1035; y:130; width:200; height:130; radius:12; color:page.scene==="ANCHOR"?"#ffcc00":"#1b2027"; border.color:"#3a444f"; border.width:2
                Text { anchors.centerIn:parent; text:"ANCHOR"; color:page.scene==="ANCHOR"?"#000":"#fff"; font.bold:true; font.pixelSize:24 }
                MouseArea { anchors.fill:parent; onClicked: page.anchor() } }
            Rectangle { x:1035; y:280; width:200; height:130; radius:12; color:page.scene==="UNDERWAY"?"#22cc44":"#1b2027"; border.color:"#3a444f"; border.width:2
                Text { anchors.centerIn:parent; text:"UNDERWAY"; color:"#fff"; font.bold:true; font.pixelSize:22 }
                MouseArea { anchors.fill:parent; onClicked: page.underway() } }

            // ===== ChangeView links =====
            Text { x:30; y:632; text:"Go to page:"; color:"#8a8a8a"; font.pixelSize:20 }
            Repeater {
                model: ListModel {
                    ListElement { lab:"Circuit Control"; idx:0 }
                    ListElement { lab:"Power"; idx:1 }
                    ListElement { lab:"Environment"; idx:2 }
                    ListElement { lab:"Engines"; idx:3 }
                    ListElement { lab:"Meteo"; idx:4 }
                    ListElement { lab:"Grib"; idx:5 }
                }
                Rectangle { x:30+index*203; y:665; width:190; height:66; radius:12; color:"#1b2027"; border.color:"#3a444f"; border.width:2
                    Text { anchors.centerIn:parent; text:lab; color:"#fff"; font.bold:true; font.pixelSize:21 }
                    MouseArea { anchors.fill:parent; onClicked: view.currentIndex=idx } }
            }
            Timer { interval:2000; running:true; repeat:true; onTriggered: page.poll() }
            Component.onCompleted: page.poll()
        }
    }
}
