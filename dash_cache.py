#!/usr/bin/env python3
"""dash_cache.py — companion service that turns "a web page / dashboard / GRIB map" into an
image tile the MFD can show (see pages/Tile.qml).

For each configured tile it fetches a render URL (e.g. a Grafana panel rendered by Grafana's
image-renderer), converts it to JPEG, and serves the cached file on the boat network. On a
fetch failure it keeps serving the last good image. Deliberately SEPARATE from the digital-
switching control bridge (http_bridge.py): a slow or failed fetch must never stall relay control.

Locally generated tiles (e.g. a GRIB wind map you render yourself, see the README) are just
written into CACHE_DIR by another job and served the same way — the handler serves any <name>.jpg.
Adapt LISTEN/TILES/token to your setup. No secrets in the file — keep it that way if you fork it.
"""
import io, os, ssl, time, threading, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from PIL import Image

LISTEN    = ("0.0.0.0", 8889)                    # reachable by the MFD on the boat network
CACHE_DIR = "/var/lib/dash_cache"
REFRESH_S = 60                                    # image changes slowly; be gentle
JPEG_Q    = 82
TOKEN     = os.environ.get("RENDER_TOKEN", "")    # e.g. a Grafana render token — stays on the host

# tile name -> render URL. Grafana example: a dashboard rendered at the MFD's native size with
# the chrome hidden (kiosk). Point this at your own render endpoint.
TILES = {
    "5": "https://grafana.example:3000/render/d/<uid>/x?width=1280&height=800&theme=dark&kiosk=1",
}

_ctx = ssl.create_default_context(); _ctx.check_hostname = False; _ctx.verify_mode = ssl.CERT_NONE

def fetch_jpeg(url):
    req = urllib.request.Request(url)
    if TOKEN: req.add_header("Authorization", "Bearer " + TOKEN)
    png = urllib.request.urlopen(req, timeout=25, context=_ctx).read()
    im = Image.open(io.BytesIO(png)).convert("RGB")
    out = io.BytesIO(); im.save(out, "JPEG", quality=JPEG_Q, optimize=True)
    return out.getvalue()

def _write_atomic(path, data):
    tmp = path + ".tmp"; open(tmp, "wb").write(data); os.replace(tmp, path)

def refresh_loop():
    os.makedirs(CACHE_DIR, exist_ok=True)
    while True:
        for name, url in TILES.items():
            try: _write_atomic(os.path.join(CACHE_DIR, name + ".jpg"), fetch_jpeg(url))
            except Exception as e: print("dash_cache: %s failed: %s" % (name, e), flush=True)  # keep last good
        time.sleep(REFRESH_S)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?")[0].strip("/")
        if name.endswith(".jpg"): name = name[:-4]
        fn = os.path.join(CACHE_DIR, name + ".jpg")
        if name and name.replace("_", "").isalnum() and os.path.exists(fn):
            data = open(fn, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers(); self.wfile.write(data)
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass

if __name__ == "__main__":
    threading.Thread(target=refresh_loop, daemon=True).start()
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
