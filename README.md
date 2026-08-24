# Custom digital-switching & data pages on a Raymarine a-Series MFD (LightHouse II)

**Turning a Raymarine a-Series chartplotter into a full boat-control and data dashboard —
including LLM-written weather/engine reports — using YachtDevices digital switching,
Signal K, and a small HTTP bridge.**

This is the full story of how four custom pages were built for a twin-diesel motor
yacht: a boat-plan **electrical control** page, and three data pages (**Power & Tanks**,
**Environment**, **Engines**). It documents not just the final technique but the
**dead ends** — most importantly why the "obvious" CZone route doesn't work on
a-Series, and how an HTTP bridge solved both control and arbitrary data.

Everything here uses public, documented mechanisms (Signal K REST, NMEA 2000 PGNs, the
LightHouse "RMDS" QML page format, a YachtDevices circuit-control gateway). No MFD
firmware is modified; pages install through the MFD's normal **Import Configuration
File** menu.

> Platform: a-Series MFD, **LightHouse II**, logical page canvas **800×480**, QML in the
> **QtQuick 1.1** dialect. Companion host: a small Linux box already running Signal K
> and ingesting the N2K bus.

- [Part 1 — Electrical control (the boat-plan page)](#part-1--electrical-control-the-boat-plan-page)
- [Part 2 — The data pages](#part-2--the-data-pages)
- [Part 3 — Deploy & iterate](#part-3--deploy--iterate)
- [Gotchas & lessons](#gotchas--lessons)

![The a-Series MFD at the helm running the custom Electrical Control page](figures/0-helm.jpg)

![Electrical Control](figures/1-electrical-control.jpg)
![Power & Tanks](figures/2-power-tanks.jpg)
![Environment](figures/3-environment.jpg)
![Engines](figures/4-engines.jpg)

---

## Background: how LightHouse II "digital switching" is built

On a-Series/LightHouse II, digital-switching pages are QML, drawn from a "cell" library
that ships inside a **RMDS package** (a `.zip` of a QML tree — the same format
YachtDevices' DataMaster tools produce). Two kinds of cell:

- **Control cells** — toggle / momentary / dimmer, meant to drive a switching channel.
- **DataItem cells** — a numeric/gauge bound to a fixed **DataItem ID** from the
  EmpirBus/CZone catalog (RPM = 73, coolant temp = 79, fresh-water level = 3, battery
  voltage = 107, and so on).

The whole page is plain QML, and — crucially — QtQuick 1.1 ships **`XMLHttpRequest`**.
That one fact is what makes everything below possible.

---

## Tools & downloads

- **[CAN Log Viewer](https://www.yachtd.com/products/can_view.html)** — YachtDevices'
  free NMEA 2000 viewer/recorder (Windows/macOS/Linux). Used here to talk to the bus
  through the gateway and to send the `YD:` configuration commands to the modules.
- **[EmpirBus](https://www.empirbus.com/)** configuration software — used to author a
  digital-switching page and, as a side effect, to **read the DataItem catalog IDs** out
  of the QML it produces (see Part 2). The current tool is **EmpirBus LogiX** (the older
  **EmpirBus Studio** reached end-of-life in 2023); both are free but need an EmpirBus
  account. The DataItem name→ID map is not published anywhere else.
- **Signal K** server on the companion host (open source) — already ingesting your N2K
  bus. This is what the HTTP bridge reads from.

You do **not** need the CZone Configuration Tool (that route is a dead end on a-Series —
see Part 1).

---

## Part 1 — Electrical control (the boat-plan page)

### What we wanted

A single page showing a **deck plan of the boat** with a colored dot at each consumer
(nav lights, anchor light, engine-room fans, bilge pumps, black-water pump, windlass),
each dot acting as an on/off control and a live state indicator, plus a labelled
channel list underneath.

### Attempt 1: native CZone — and why it fails on a-Series

The instinct is to use the boat's **CZone** digital switching, which LightHouse
supports natively on the larger multifunction systems. On **a-Series it does not run** —
the native CZone switching UI reports **"Not Available"**. The a-Series line only
exposes digital switching through the **YachtDevices DataMaster / RMDS** path, not the
CZone display engine. So binding controls to CZone circuits was a dead end from the
start; the page renders but the control layer never comes alive.

We went the whole way down this path first: a **CZone configuration file (`.zcf`)**
defines the circuits (names, IDs, and which YDCC/YDRI channel each drives), is **tied to
each module's serial number**, and is edited with the **CZone Configuration Tool
(Windows)**; the QML control cells then bind to a circuit via `controlId` /
`m_DBIdentifier`. All of that is irrelevant on a-Series — the circuits never light up —
so **the `.zcf` is not part of the working solution and you don't need one.** The HTTP
approach below drives the relay directly and ignores CZone entirely.

Take-away: **on a-Series, plan for the YachtDevices RMDS path, not CZone.**

### The approach that worked

Two halves:

1. **The page** is a customized RMDS package: a background plan image, a set of markers,
   and a channel list — authored in QML.
2. **The control layer** does *not* try to bind to a native switching provider. Instead
   each control calls a **small HTTP service on the companion host**, which talks to the
   **YachtDevices circuit-control (YDCC) relay** over the gateway and, importantly,
   **reads real state back** so the page can stay in sync.

### Building the plan page

The plan is one background image (a top-down deck render) scaled into the logical
canvas. Markers are a `ListModel` of `{ n, fx, fy, onColor }` — `fx/fy` are fractional
positions over the image, so the dots land on the right cabins regardless of scaling:

```qml
Image { id: plan; source: "plan.jpg"; x: 0; y: 0; width: content.width }

ListModel {
    id: markers
    ListElement { n: "3"; fx: 0.62; fy: 0.15; onColor: "#22cc44" }  // nav light (green)
    ListElement { n: "3"; fx: 0.63; fy: 0.87; onColor: "#ff3b30" }  // nav light (red)
    ListElement { n: "4"; fx: 0.70; fy: 0.51; onColor: "#fff2a0" }  // anchor (white-ish)
    // ...
}

Repeater {
    model: markers
    delegate: Rectangle {
        width: 34; height: 34; radius: 17
        x: plan.x + fx * plan.width - 17
        y: plan.y + fy * plan.height - 17
        color: channelOn(n) ? onColor : "#3a3a3a"    // live state → color
        Text { anchors.centerIn: parent; text: n; color: "white" }
        MouseArea { anchors.fill: parent; onClicked: toggle(n) }
    }
}
```

(A design note that cost time: on a light plan image, plain white markers vanish. The
masthead/anchor whites became a **very pale yellow** `#fff2a0` to read against the deck.)

### Driving the outputs

`toggle(n)` / the channel list buttons call the HTTP service, which emits **PGN 127502
(Switch Bank Control)** onto the bus via the gateway's TCP interface. The relay reports
its actual state with **PGN 127501 (Binary Status Report)**, on change.

### One-time module configuration (CAN Log Viewer)

Before any of this, the YachtDevices modules want a **one-time setup over the gateway
with CAN Log Viewer** (point it at the gateway's TCP port), using the device `YD:`
command set — done once at the dock with a laptop. **Read first, change only what's
needed:**

- `YD:CZONE`, `YD:BANK`, `YD:DIPSWITCH` (no argument) — read the current CZone mode,
  switch-bank number and dipswitch. Make sure the **output relay, the input module and
  the MFD are on three different dipswitches** and that the relay sits on a known bank
  (the page emits PGN 127502 to *that* bank). In practice the output module was already
  on sane defaults, so this was mostly *confirming* rather than changing.
- If you also have an **input module** shipping run-indicators, **disable its
  battery-status emulation** per channel (`YD:DAT A OFF` … `D OFF`) — otherwise it
  injects phantom battery data (a fake ~2 V "bank") onto the bus and trips false alarms.

Each command answers `… DONE`. That's roughly half a dozen commands, once.

### The hard part: state synchronization

This is where most of the real work went.

**Problem 1 — the relay latches and only reports on change.** If the page assumes its
last command "stuck", it drifts out of sync with reality (someone flips a physical
switch, a command is lost, the module reboots). Fix: treat **PGN 127501 as the single
source of truth**. The HTTP service keeps **one persistent TCP connection** to the
gateway (these gateways have a *very low* connection limit — open sockets carelessly, or
port-scan it, and you starve the control link), reads real bank state, and the page
reconciles its indicators to that.

**Problem 2 — flicker.** Tapping a control and waiting a full poll cycle for the state
to come back makes the button blink off-then-on. Fix: a short **debounce + optimistic
hold** — the indicator holds the commanded state for ~1.5 s, then follows real state.

**Problem 3 — "the nav lights turned on by themselves."** The scariest one. An early
version treated **any** switch-ON it observed on the bus as a "manual override" and
latched it — so a stray/delayed command (or leftover test traffic) could turn nav lights
on at the dock and keep re-asserting them. The fix was a **panel rule**:

- The HTTP service writes a small **sticky panel-state file** recording what the *MFD
  panel* set each channel to.
- The auto-controller (a rules flow) computes the desired auto state (e.g. nav lights
  on only when actually underway at night, well away from the berth).
- Final command per channel = **`panel-said-ON ? ON : auto-state`.**
  Panel-ON is respected; panel-OFF releases the channel back to auto; a spurious ON that
  the panel never set is forced back off within one control cycle.

Net result: the page reflects the bus, the bus reflects intent, and nothing "wakes up"
on its own. The `Server: on/off` indicator top-right just reports whether the page can
reach the HTTP service.

---

## Part 2 — The data pages

Once the HTTP bridge existed for control, the same trick delivered *data* the native
DataItems can't.

### Software & workflow

There is no fancy toolchain. The workflow is:

1. Start from an RMDS package (the YachtDevices cell library + a page QML).
2. **Hand-edit the page QML** — add/remove/position DataItem cells and custom `Text`
   tiles.

   **Getting the DataItem IDs is the catch.** The name→ID catalog is **not publicly
   documented** — it lives inside the dealer software. In practice you build a page in
   the **EmpirBus Graphic Tool** (the Windows configuration program), drop in the named
   DataItems you want, and then **read the assigned IDs straight out of the QML it
   produces** — every cell carries an `m_Name` ↔ `m_DataItemID` pair. Extract that map
   once and reuse it. (It's full of surprises: `86 = Fuel Pressure`, and there are *two*
   economy items — `84 = Inst. Fuel Economy` and `104 = Fuel Economy`.) Without the
   EmpirBus tool (or a page someone already built with it), you're guessing IDs — don't.
3. **Zip** the tree into `RMDS_<name>.zip`.
4. **Import** on the MFD (Part 3).

Native cell (catalog value, unchanged):

```qml
DigitalValueDataItemCenterAligned {
    x: 30; y: 140
    m_Name: "Air Temperature"; m_CellWidth: 290; m_ValueFontSize: 46
    m_DataItemID: 58; m_PrimaryDataItemInstance: 0
}
```

### Calculated / unavailable data over HTTP (`/wx`)

The bridge exposes a `GET /wx` endpoint that reads Signal K and returns a flat JSON blob.
Reading a path is one GET:

```python
SK = "http://localhost:3000/signalk/v1/api/vessels/self/"
def sk(path):
    try: return json.load(urllib.request.urlopen(SK + path, timeout=2)).get("value")
    except Exception: return None
```

`/wx` then serves everything the DataItem catalog can't, for example:

| Tile on the MFD | Where it comes from |
|---|---|
| **True wind** speed & direction | Signal K derived (`environment.wind.speedOverGround` / `directionTrue`) — not on the bus as a PGN here |
| **Dew point** | Signal K derived (Magnus from temp+humidity) |
| **Cloud cover** | a weather bridge plugin (`environment.weather.cloudCover`) |
| **Barometric tendency** | a barometer-trend plugin (`…pressure.trend.tendency`, Beaufort text) |
| **Fresh-water %/litres** | raw tank level, **rescaled + capacity-corrected** in the bridge (see below) |
| **Oil level OK/LOW** | a *binary* lube path shown as a colored OK/LOW instead of a fake % |
| **Fuel pressure** | `propulsion.*.fuel.pressure` (served until a native DataItem was confirmed) |

Each is a custom `Text` tile bound to a `page.*` property, updated by an
`XMLHttpRequest` poll (unit conversions done in the QML: m/s→kn ×1.94384, rad→° ×57.2958,
K→°C −273.15, 0..1→% ×100).

```qml
function poll() {
    var x = new XMLHttpRequest();
    x.onreadystatechange = function() {
        if (x.readyState === 4 && x.status === 200) {
            var o = JSON.parse(x.responseText);
            page.tws = (o.tws == null) ? "—" : (o.tws * 1.94384).toFixed(1) + " kn";
            // ...dewpoint, cloud, oil, headlines...
        }
    };
    x.open("GET", "http://10.0.0.1:8888/wx?t=" + (new Date()).getTime());
    x.send();
}
Timer { interval: 2000; running: true; repeat: true; onTriggered: page.poll() }
Component.onCompleted: page.poll()
```

#### Correcting a broken sensor in the bridge

A worked example that shows the power of serving values yourself. A resistive fresh-water
sender was damaged: its float sticks so the tank reads **"empty" at 17.4%** instead of 0,
and the boat's real capacity differs from the brochure figure. Rather than show a lie,
the bridge rescales:

```python
raw = sk("tanks/freshWater/1/currentLevel")               # 0..1 from the bus
frac = max(0.0, min(1.0, (raw - 0.174) / (1.0 - 0.174)))  # 17.4% → 0
pct, litres = round(frac * 100), round(frac * CAPACITY_L)
```

…and the tile shows `"100%  520 L"`. (Fix the sender eventually — but keep the gauge
honest until you do.)

### LLM report headlines on the MFD

The most unusual tiles: **plain-language summaries written by an LLM.** A Signal K plugin
runs periodic analyzers over the boat's own data (a weather forecast every few hours,
a per-engine session summary when an engine stops, a daily battery-health note) and
writes each as a short report whose **first line is a ≤80-char headline**. The bridge
grabs that first line for the latest report of a given analyzer:

```python
def headline(analyzer):
    best = None
    for line in open(REPORTS_JSONL, encoding="utf-8", errors="replace"):
        if ('"' + analyzer + '"') not in line: continue
        try: o = json.loads(line)
        except Exception: continue
        if o.get("analyzer") == analyzer: best = o
    return None if not best else best.get("report","").split("\n")[0].strip()
```

So the **Environment** page carries a *Weather* headline
(*"Clouds are thickening, but no major deterioration is evident"*) and a *Barometer*
tendency line; the **Engines** page carries per-engine *session* summaries
(*"Port engine session completed without reported alarms"*) and a *consumption/drift*
line; the **Power & Tanks** page carries a *battery health* note. All are just text tiles
on the same poll.

---

## Part 3 — Deploy & iterate

Pages ship as a standard **RMDS `.zip`**; installing needs no special access to the MFD:

1. Copy `RMDS_<name>.zip` to the MFD's **SD card**.
2. On the MFD: **digital switching → Import Configuration File → pick the zip.**

Iterate by rebuilding the zip and re-importing.

---

## Gotchas & lessons

- **CZone is a dead end on a-Series** — use the YachtDevices RMDS path.
- **Logical canvas is 800×480.** Author to that (or author at 1280×800 and scale the
  content `Item`), or fonts/positions come out wrong.
- **Cache-bust every HTTP URL** (`?t=<epoch>`).
- **Gateway connection limit is tiny** — one persistent connection, never scan it.
- **State comes from PGN 127501, not from hope.** Reconcile the UI to reported state.
- **QML insertion trap:** if a page keeps its `Timer` / `Component.onCompleted` *outside*
  the content `Item` (siblings under the root), don't blindly append tiles "before the
  last brace" — you can land *inside* an `onCompleted { … }` and the **entire config
  silently fails to load** (the MFD shows **0 digital-switching pages**, not a broken
  single page). Insert before the real content-`Item` close and verify nothing landed in
  a handler body.
- **Two "Fuel Economy" DataItems exist** (Inst. vs plain) — check the catalog, don't
  guess IDs.

---

## Repository layout (example)

```
http_bridge.py            # the companion HTTP service (data + control endpoints)
pages/
  ElectricalControl.qml   # boat-plan control page
  PowerTanks.qml
  Environment.qml
  Engines.qml
figures/                  # the four screenshots
```

## License / disclaimer

Technique and example code are provided as-is for educational use. "Raymarine",
"LightHouse", "YachtDevices", "EmpirBus", "CZone", "Signal K" are trademarks of their
respective owners; this project is not affiliated with or endorsed by any of them.
Nothing here modifies MFD firmware. Keep a known-good configuration and test at the dock.
