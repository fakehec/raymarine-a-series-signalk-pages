#!/usr/bin/env python3
"""
http_bridge.py — a tiny HTTP bridge between Signal K / an NMEA 2000 gateway and
custom Raymarine a-Series (LightHouse II) QML pages.

Endpoints the MFD pages poll with XMLHttpRequest:

  DATA     GET /wx           -> JSON of values the native DataItems can't show
                               (true wind, dew point, cloud, barometer, corrected
                               tank level, LLM report headlines)

  CONTROL  GET /state        -> real switch-bank state (from PGN 127501 via Signal K)
           GET /set/<n>/<0|1>-> panel sets a channel  (sticky)
           GET /toggle/<n>   -> panel toggles a channel (sticky)

Control uses the **panel rule** so nothing auto-asserts itself:

    cmd[ch] = ON if the MFD panel set it ON (sticky)  else  compute_auto()[ch]

The gateway must expose a **bidirectional RAW server on TCP :2002** (read AND write),
or the toggles will do nothing.

This is an EXAMPLE. Adapt paths, capacity, gateway address and compute_auto() to your
boat. No secrets here — keep it that way if you fork it. Provided as-is; test at the dock.
"""

import json
import os
import socket
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler
from socketserver import ThreadingMixIn, TCPServer

# ----------------------------------------------------------------------------- config
LISTEN         = ("0.0.0.0", 8888)                 # where the MFD pages reach us
SK             = "http://localhost:3000/signalk/v1/api/vessels/self/"
GATEWAY        = ("192.168.0.10", 2002)            # YD gateway, RAW TCP (bidirectional!)
BANK           = 0                                  # YDCC switch-bank instance
SOURCE_ADDR    = 0x64                               # our N2K source address
PANEL_FILE     = "/run/panel_state.json"            # sticky "what the panel set" file
AUTO_PERIOD_S  = 30                                 # how often auto is re-asserted
REPORTS_JSONL  = "/path/to/llm/reports.jsonl"       # analyzer reports (optional)
FRESH_WATER_CAPACITY_L = 520                        # real tank capacity (litres)
FRESH_WATER_EMPTY_RAW  = 0.174                       # raw level that reads "empty"


# ------------------------------------------------------------------------- signal k io
def sk(path):
    """Read one Signal K path's .value, or None."""
    try:
        d = json.load(urllib.request.urlopen(SK + path, timeout=2))
        return d.get("value")
    except Exception:
        return None


def report_headline(analyzer):
    """First line of the latest report written by <analyzer>, or None."""
    best = None
    try:
        for line in open(REPORTS_JSONL, encoding="utf-8", errors="replace"):
            if ('"' + analyzer + '"') not in line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("analyzer") == analyzer:
                best = o
    except Exception:
        return None
    return None if not best else best.get("report", "").split("\n")[0].strip()


def fresh_water():
    """Rescale a stuck/mis-scaled sender to honest percent + litres."""
    raw = sk("tanks/freshWater/0/currentLevel")
    if raw is None:
        return None, None
    frac = max(0.0, min(1.0, (raw - FRESH_WATER_EMPTY_RAW) / (1.0 - FRESH_WATER_EMPTY_RAW)))
    return round(frac * 100), round(frac * FRESH_WATER_CAPACITY_L)


def wx():
    pct, litres = fresh_water()
    return {
        "tws": sk("environment/wind/speedOverGround"),   # m/s  -> knots in QML
        "twd": sk("environment/wind/directionTrue"),     # rad  -> deg   in QML
        "dewpoint": sk("environment/outside/dewPointTemperature"),  # K
        "cloud":    sk("environment/weather/cloudCover"),           # 0..1
        "baroTend": sk("environment/outside/pressure/trend/tendency"),
        "baroBft":  sk("environment/outside/pressure/prediction/beaufort/description"),
        "fwPct": pct, "fwL": litres,
        "wxHead":     report_headline("forecast"),
        "healthHead": report_headline("health"),
    }


# ----------------------------------------------------------------- the panel-state file
def read_panel():
    try:
        return json.load(open(PANEL_FILE))
    except Exception:
        return {}


def write_panel(ch, on):
    """Record sticky panel intent for one channel (survives restarts)."""
    p = read_panel()
    p[str(ch)] = "on" if on else "off"
    tmp = PANEL_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(p, f)
    os.replace(tmp, PANEL_FILE)


# --------------------------------------------------------------------- the auto rules
def compute_auto():
    """Return the desired AUTO state of the 4 output channels, [0/1, ...].

    Fill this in with YOUR boat's rules. Example for nav lights on channel 3:
    on only when actually underway at night, away from the berth. Everything else
    defaults OFF (fail-safe: if a value is missing, leave the channel OFF).
    """
    auto = [0, 0, 0, 0]
    # --- example: channel 3 = navigation lights -----------------------------------
    # sog   = sk("navigation/speedOverGround") or 0            # m/s
    # state = sk("navigation/state")                           # "moored"/"anchored"/...
    # is_night   = ...   # sun-below-horizon test from navigation/position + time
    # underway   = (state in ("motoring", "sailing")) or (sog and sog > 0.5)
    # if is_night and underway:
    #     auto[2] = 1
    return auto


# --------------------------------------------------------------- one persistent gateway
class Gateway:
    """Single persistent TCP connection to the YD gateway (they cap connections).
    RAW :2002 must be bidirectional. Writes PGN 127502; state is read from Signal K."""

    def __init__(self, addr):
        self.addr = addr
        self.sock = None
        self.lock = threading.Lock()

    def _connect(self):
        if self.sock is None:
            self.sock = socket.create_connection(self.addr, timeout=4)

    def emit_127502(self, chan_states):
        """chan_states: list of 4 ints (0/1) -> one Switch Bank Control frame."""
        b1 = 0
        for i, v in enumerate(chan_states):
            b1 |= (v & 3) << (2 * i)
        can_id = "%02X%02X0E%02X" % (0x0D, 0xF2, SOURCE_ADDR)   # PGN 127502, our SA
        # data byte 0 = the switch-bank INSTANCE (must match BANK, or you address the
        # wrong bank and nothing switches); byte 1 = the four 2-bit channel states.
        frame = "%s %02X %02X 00 00 00 00 00 00\r\n" % (can_id, BANK, b1)
        with self.lock:
            self._connect()
            for _ in range(10):              # relays like a short burst
                self.sock.sendall(frame.encode())
                time.sleep(0.02)

    def read_state(self):
        """Real bank state from Signal K (it already decodes PGN 127501)."""
        st = [0, 0, 0, 0]
        for ch in range(1, 5):
            v = sk("electrical/switches/bank/%d/%d/state" % (BANK, ch))
            st[ch - 1] = 1 if v else 0
        return st


GW = Gateway(GATEWAY)


def apply_control():
    """The panel rule: cmd = panel-ON ? ON : auto, then emit it."""
    panel = read_panel()
    auto = compute_auto()
    cmd = [1 if panel.get(str(ch)) == "on" else auto[ch - 1] for ch in range(1, 5)]
    GW.emit_127502(cmd)
    return cmd


def auto_loop():
    """Re-assert the panel rule periodically so auto (and anti-stray) keep working."""
    while True:
        try:
            apply_control()
        except Exception:
            pass
        time.sleep(AUTO_PERIOD_S)


# ----------------------------------------------------------------------------- http api
class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0].strip("/").split("/")
        try:
            if p[0] == "wx":
                self._json(200, wx())
            elif p[0] == "state":
                self._json(200, {"ch": GW.read_state()})
            elif p[0] == "set" and len(p) == 3:
                write_panel(int(p[1]), p[2] in ("1", "on", "true"))
                self._json(200, {"ch": apply_control()})
            elif p[0] == "toggle" and len(p) == 2:
                ch = int(p[1])
                cur = read_panel().get(str(ch)) == "on"
                write_panel(ch, not cur)
                self._json(200, {"ch": apply_control()})
            else:
                self._json(404, {"error": "unknown endpoint"})
        except Exception as e:
            self._json(500, {"error": str(e)})

    def log_message(self, *a):
        pass


class Server(ThreadingMixIn, TCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    threading.Thread(target=auto_loop, daemon=True).start()
    print("http_bridge on %s:%d" % LISTEN)
    Server(LISTEN, Handler).serve_forever()
