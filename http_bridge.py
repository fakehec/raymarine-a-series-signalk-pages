#!/usr/bin/env python3
"""
http_bridge.py — a tiny HTTP bridge between Signal K / an NMEA 2000 gateway and
custom Raymarine a-Series (LightHouse II) QML pages.

It exposes two families of endpoints that the MFD pages poll with XMLHttpRequest:

  DATA            GET /wx        -> JSON blob of values the native DataItems can't show
                                    (true wind, dew point, cloud, barometer, corrected
                                    tank level, LLM report headlines)

  CONTROL         GET /state     -> real switch-bank state read back from PGN 127501
                  GET /set/<n>/<0|1>
                  GET /toggle/<n>            -> emit PGN 127502 to the relay bank

This is an EXAMPLE. Adapt the paths, capacity, and gateway address to your boat.
Nothing here contains secrets; keep it that way if you fork it.

Public technique — see the README. Provided as-is, no warranty. Test at the dock.
"""

import json
import socket
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler
from socketserver import ThreadingMixIn, TCPServer

# ----------------------------------------------------------------------------- config
LISTEN         = ("0.0.0.0", 8888)                 # where the MFD pages reach us
SK             = "http://localhost:3000/signalk/v1/api/vessels/self/"
GATEWAY        = ("192.168.0.10", 2002)            # YachtDevices gateway, RAW TCP
BANK           = 0                                  # relay switch-bank instance
SOURCE_ADDR    = 0x64                               # our N2K source address
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
    span = 1.0 - FRESH_WATER_EMPTY_RAW
    frac = max(0.0, min(1.0, (raw - FRESH_WATER_EMPTY_RAW) / span))
    return round(frac * 100), round(frac * FRESH_WATER_CAPACITY_L)


def wx():
    pct, litres = fresh_water()
    return {
        # true wind (Signal K derived; not on the bus as a PGN here)
        "tws": sk("environment/wind/speedOverGround"),   # m/s  -> knots in QML
        "twd": sk("environment/wind/directionTrue"),     # rad  -> deg   in QML
        # comfort / weather
        "dewpoint": sk("environment/outside/dewPointTemperature"),  # K
        "cloud":    sk("environment/weather/cloudCover"),           # 0..1
        # barometric tendency (barometer-trend plugin)
        "baroTend": sk("environment/outside/pressure/trend/tendency"),
        "baroBft":  sk("environment/outside/pressure/prediction/beaufort/description"),
        # corrected tank
        "fwPct": pct, "fwL": litres,
        # LLM report headlines (optional)
        "wxHead":     report_headline("forecast"),
        "healthHead": report_headline("health"),
    }


# --------------------------------------------------------------- one persistent gateway
class Gateway:
    """Single persistent TCP connection to the YD gateway (they cap connections).
    Reads PGN 127501 for real state; writes PGN 127502 to switch."""

    def __init__(self, addr):
        self.addr = addr
        self.sock = None
        self.lock = threading.Lock()
        self.state = [0, 0, 0, 0]         # last known real state, 4 channels

    def _connect(self):
        if self.sock is None:
            self.sock = socket.create_connection(self.addr, timeout=4)

    def emit_127502(self, chan_states):
        """chan_states: list of 4 ints (0/1). Build the bank-control frame."""
        b1 = 0
        for i, v in enumerate(chan_states):
            b1 |= (v & 3) << (2 * i)
        # RAW YD frame: <CAN-id> <8 data bytes>; PGN 127502, our source address
        can_id = "%02X%02X0E%02X" % (0x0D, 0xF2, SOURCE_ADDR)
        frame = "%s 00 %02X 00 00 00 00 00 00\r\n" % (can_id, b1)
        with self.lock:
            self._connect()
            for _ in range(10):              # relays like a short burst
                self.sock.sendall(frame.encode())
                time.sleep(0.02)

    def read_state(self):
        """Best-effort read of the current bank state from Signal K
        (which already decodes PGN 127501) — simpler and more robust than
        parsing the raw stream ourselves."""
        st = [0, 0, 0, 0]
        for ch in range(1, 5):
            v = sk("electrical/switches/bank/%d/%d/state" % (BANK, ch))
            st[ch - 1] = 1 if v else 0
        self.state = st
        return st


GW = Gateway(GATEWAY)


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
                st = GW.read_state()
                st[int(p[1]) - 1] = 1 if p[2] in ("1", "on", "true") else 0
                GW.emit_127502(st)
                self._json(200, {"ch": st})
            elif p[0] == "toggle" and len(p) == 2:
                st = GW.read_state()
                i = int(p[1]) - 1
                st[i] = 0 if st[i] else 1
                GW.emit_127502(st)
                self._json(200, {"ch": st})
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
    print("http_bridge on %s:%d" % LISTEN)
    Server(LISTEN, Handler).serve_forever()
