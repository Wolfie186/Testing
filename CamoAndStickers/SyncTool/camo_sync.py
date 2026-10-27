#!/usr/bin/env python3
"""Camo & Stickers co-op sync: mirrors the mod's Sync folder between players.

The host runs a tiny HTTP server over its Sync folder; every other player runs `join`,
which uploads their own player folder and downloads everybody else's. Each mod writes
only its own folder (named in Sync/.me), so there are never conflicting edits.

  host:  python camo_sync.py host [--port 27777] [--key SECRET] [--folder PATH]
  join:  python camo_sync.py join HOST[:PORT]    [--key SECRET] [--folder PATH]

HOST is the host's IP address: LAN, a VPN like Radmin VPN / ZeroTier / Tailscale, or the
public IP with the port forwarded. Python 3.8+, standard library only.
"""
import argparse
import hashlib
import hmac
import http.server
import json
import os
import socketserver
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_PORT = 27777
DEFAULT_FOLDER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Sync")
ALLOWED_EXT = {".txt", ".png", ".jpg", ".jpeg", ".bmp", ".tga"}
MAX_FILE = 16 * 1024 * 1024
MAX_DEPTH = 3  # player/images/file


def log(msg):
    print(time.strftime("[%H:%M:%S] ") + msg, flush=True)


def safe_rel(rel):
    """Validates a relative path from the network; returns its parts or None."""
    if not isinstance(rel, str) or "\\" in rel or "\0" in rel:
        return None
    parts = rel.split("/")
    if not 2 <= len(parts) <= MAX_DEPTH:
        return None
    for p in parts:
        if not p or p.startswith(".") or p in ("..", ".") or ":" in p:
            return None
    if os.path.splitext(parts[-1])[1].lower() not in ALLOWED_EXT:
        return None
    return parts


def manifest(root, only=None, exclude=None):
    """{ "player/images/file.png": sha1 } for synced files under root."""
    out = {}
    if not os.path.isdir(root):
        return out
    for top in os.listdir(root):
        if top.startswith(".") or not os.path.isdir(os.path.join(root, top)):
            continue
        if only is not None and top != only:
            continue
        if exclude is not None and top == exclude:
            continue
        for dirpath, dirs, files in os.walk(os.path.join(root, top)):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files:
                rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
                if safe_rel(rel) is None:
                    continue  # .tmp files, dot files, anything else
                with open(os.path.join(dirpath, name), "rb") as f:
                    out[rel] = hashlib.sha1(f.read()).hexdigest()
    return out


def write_atomic(root, rel, data):
    path = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def remove_file(root, rel):
    path = os.path.join(root, *rel.split("/"))
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
    # Drop empty folders left behind.
    d = os.path.dirname(path)
    while os.path.abspath(d) != os.path.abspath(root):
        try:
            os.rmdir(d)
        except OSError:
            break
        d = os.path.dirname(d)


# ------------------------------------------------------------------ host

def make_handler(root, key):
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "CamoSync/1"

        def log_message(self, fmt, *args):
            pass

        def _auth(self):
            if key and not hmac.compare_digest(self.headers.get("X-CAS-Key", ""), key):
                self.send_error(403, "bad key")
                return False
            return True

        def _rel(self, writing=False):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            rel = q.get("path", [None])[0]
            if safe_rel(rel) is None:
                self.send_error(400, "bad path")
                return None
            if writing and rel.split("/")[0] == read_me(root):
                self.send_error(403, "that's the host's own folder")
                return None
            return rel

        def _reply(self, code, body=b"", ctype="application/octet-stream"):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self._auth():
                return
            route = urllib.parse.urlparse(self.path).path
            if route == "/manifest":
                self._reply(200, json.dumps(manifest(root)).encode(), "application/json")
            elif route == "/file":
                rel = self._rel()
                if rel is None:
                    return
                try:
                    with open(os.path.join(root, *rel.split("/")), "rb") as f:
                        self._reply(200, f.read())
                except FileNotFoundError:
                    self.send_error(404)
            else:
                self.send_error(404)

        def do_PUT(self):
            if not self._auth():
                return
            rel = self._rel(writing=True)
            if rel is None:
                return
            length = int(self.headers.get("Content-Length", "0"))
            if length > MAX_FILE:
                self.send_error(413)
                return
            write_atomic(root, rel, self.rfile.read(length))
            log(f"received {rel}")
            self._reply(204)

        def do_DELETE(self):
            if not self._auth():
                return
            rel = self._rel(writing=True)
            if rel is None:
                return
            remove_file(root, rel)
            log(f"removed {rel}")
            self._reply(204)

    return Handler


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def run_host(args):
    os.makedirs(args.folder, exist_ok=True)
    server = Server(("0.0.0.0", args.port), make_handler(args.folder, args.key))
    log(f"Hosting camo sync on port {args.port}, folder {args.folder}")
    log("Friends run:  join <your IP>" + (f":{args.port}" if args.port != DEFAULT_PORT else "")
        + (" --key <key>" if args.key else ""))
    log("Leave this window open while you play. Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


# ------------------------------------------------------------------ join

class Client:
    def __init__(self, base, key):
        self.base = base.rstrip("/")
        self.key = key

    def _req(self, method, route, rel=None, data=None):
        url = self.base + route
        if rel is not None:
            url += "?path=" + urllib.parse.quote(rel)
        req = urllib.request.Request(url, data=data, method=method)
        if self.key:
            req.add_header("X-CAS-Key", self.key)
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.read()

    def manifest(self):
        return json.loads(self._req("GET", "/manifest"))

    def get(self, rel):
        return self._req("GET", "/file", rel)

    def put(self, rel, data):
        self._req("PUT", "/file", rel, data)

    def delete(self, rel):
        self._req("DELETE", "/file", rel)


def read_me(root):
    try:
        with open(os.path.join(root, ".me"), encoding="utf-8") as f:
            me = f.read().strip()
        return me if me and "/" not in me and "\\" not in me and not me.startswith(".") else None
    except FileNotFoundError:
        return None


def sync_once(client, root):
    """One round: push my folder, pull everyone else's. Returns the number of changes."""
    me = read_me(root)
    remote = client.manifest()
    changes = 0
    if me:
        mine = manifest(root, only=me)
        for rel, digest in mine.items():
            if remote.get(rel) != digest:
                with open(os.path.join(root, *rel.split("/")), "rb") as f:
                    client.put(rel, f.read())
                log(f"sent {rel}")
                changes += 1
        for rel in remote:
            if rel.split("/")[0] == me and rel not in mine:
                client.delete(rel)
                changes += 1
    others_local = manifest(root, exclude=me)
    for rel, digest in remote.items():
        if safe_rel(rel) is None or rel.split("/")[0] == me:
            continue
        if others_local.get(rel) != digest:
            write_atomic(root, rel, client.get(rel))
            log(f"got  {rel}")
            changes += 1
    for rel in others_local:
        if rel not in remote:
            remove_file(root, rel)
            changes += 1
    return changes, me


def run_join(args):
    host = args.host if "://" in args.host else "http://" + args.host
    if not urllib.parse.urlparse(host).port:
        host += f":{DEFAULT_PORT}"
    os.makedirs(args.folder, exist_ok=True)
    client = Client(host, args.key)
    log(f"Syncing {args.folder} with {host} every {args.interval}s. Ctrl+C to stop.")
    warned, ok_before = False, None
    while True:
        try:
            _, me = sync_once(client, args.folder)
            if not me and not warned:
                log("Waiting for the game: start ITR2 with Sync.Enabled = true so the mod creates your profile.")
                warned = True
            if ok_before is not True:
                log("Connected.")
            ok_before = True
        except (urllib.error.URLError, OSError, ValueError) as e:
            if ok_before is not False:
                log(f"Can't reach the host ({e}); retrying...")
            ok_before = False
        if args.once:
            return
        time.sleep(args.interval)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)
    h = sub.add_parser("host", help="share your Sync folder (one player does this)")
    h.add_argument("--port", type=int, default=DEFAULT_PORT)
    j = sub.add_parser("join", help="sync with a host")
    j.add_argument("host", help="host IP or name, optionally :port")
    j.add_argument("--interval", type=float, default=2.0)
    j.add_argument("--once", action="store_true", help="sync one round and exit")
    for p in (h, j):
        p.add_argument("--folder", default=DEFAULT_FOLDER, help="the mod's Sync folder (default: next to this tool)")
        p.add_argument("--key", default="", help="shared password; must match on all sides")
    args = ap.parse_args()
    args.folder = os.path.abspath(args.folder)
    run_host(args) if args.mode == "host" else run_join(args)


if __name__ == "__main__":
    sys.exit(main())
