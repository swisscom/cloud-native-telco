#!/usr/bin/env python3
"""Serve the demo-3 architecture diagram with box colours driven by live Deployment state."""

from __future__ import annotations

import json
import re
import threading
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from kubernetes import client, config, watch

SVG_PATH = Path(__file__).resolve().parent.parent / "2-cluster-dns-arch.drawio.svg"
BIND_HOST = "127.0.0.1"
BIND_PORT = 8080

CONTEXTS = {"berne": "kind-berne", "zurich": "kind-zurich"}

# diagram label prefix -> (namespace, deployment)
BOXES = {
    "kubernetes dns": ("kube-system", "coredns"),
    "forwarder": ("dns", "forwarder-coredns"),
    "authorative server": ("dns", "pdns-deployment"),
}
# the two identical "External DNS" boxes per site, ordered by x: local instance left, remote right
EXTERNAL_DNS_LEFT_TO_RIGHT = {
    "berne": ("external-dns-berne", "external-dns-zurich"),
    "zurich": ("external-dns-zurich", "external-dns-berne"),
}
EXTERNAL_DNS_NAMESPACE = "dns"
EXTERNAL_DNS_LABEL = "external dns"
CLUSTER_BOX_LABELS = {"cluster site berne": "berne", "cluster site zurich": "zurich"}

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
S = f"{{{SVG_NS}}}"


# --------------------------------------------------------------------------- SVG


def _label(group: ET.Element) -> str:
    """Flatten every text node of a draw.io cell group; the label appears twice (foreignObject + fallback)."""
    parts = [
        text.strip()
        for node in group.iter()
        for text in (node.text, node.tail)
        if text and text.strip()
    ]
    return re.sub(r"\s+", " ", " ".join(parts)).strip().lower()


def _rect(group: ET.Element) -> ET.Element | None:
    rect = group.find(f".//{S}rect")
    if rect is None or rect.get("width") is None:
        return None
    return rect


def _labelled_rects(root: ET.Element) -> list[tuple[str, ET.Element]]:
    """draw.io emits a shape group directly followed by the group holding its label."""
    top = root.find(f"./{S}g")
    if top is None:
        raise SystemExit("unexpected SVG: no top-level <g> with the diagram cells")
    cells: list[tuple[str, ET.Element]] = []
    pending: ET.Element | None = None
    for group in top:
        rect = _rect(group)
        if group.find(f".//{S}switch") is None:
            pending = rect
            continue
        shape = rect if rect is not None else pending
        label = _label(group)
        if shape is not None and label:
            cells.append((label, shape))
        pending = None
    return cells


def _bbox(rect: ET.Element) -> tuple[float, float, float, float]:
    return (
        float(rect.get("x", 0)),
        float(rect.get("y", 0)),
        float(rect.get("width", 0)),
        float(rect.get("height", 0)),
    )


def _center(rect: ET.Element) -> tuple[float, float]:
    x, y, w, h = _bbox(rect)
    return x + w / 2, y + h / 2


def prepare_svg() -> tuple[str, dict[str, tuple[str, str, str]]]:
    """Tag the watched boxes with data-state-key and return the inline SVG plus the watched workloads."""
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", XLINK_NS)
    root = ET.parse(SVG_PATH).getroot()
    root.attrib.pop("content", None)  # ~1 MB of draw.io source, irrelevant for rendering

    cells = _labelled_rects(root)

    sites = {}
    for label, rect in cells:
        for prefix, site in CLUSTER_BOX_LABELS.items():
            if label.startswith(prefix):
                sites[site] = _bbox(rect)
    missing_sites = set(CLUSTER_BOX_LABELS.values()) - sites.keys()
    if missing_sites:
        raise SystemExit(f"cluster container boxes not found in SVG: {sorted(missing_sites)}")

    def site_of(rect: ET.Element) -> str | None:
        cx, cy = _center(rect)
        for site, (x, y, w, h) in sites.items():
            if x <= cx <= x + w and y <= cy <= y + h:
                return site
        return None

    watched: dict[str, tuple[str, str, str]] = {}

    def tag(rect: ET.Element, site: str, namespace: str, name: str) -> None:
        key = f"{site}/{namespace}/{name}"
        rect.set("data-state-key", key)
        watched[key] = (site, namespace, name)

    external_dns: dict[str, list[ET.Element]] = {site: [] for site in sites}
    for label, rect in cells:
        if label.startswith(tuple(CLUSTER_BOX_LABELS)):
            continue
        site = site_of(rect)
        if site is None:
            continue
        if label.startswith(EXTERNAL_DNS_LABEL):
            external_dns[site].append(rect)
            continue
        for prefix, (namespace, name) in BOXES.items():
            if label.startswith(prefix):
                tag(rect, site, namespace, name)
                break

    for site, rects in external_dns.items():
        names = EXTERNAL_DNS_LEFT_TO_RIGHT[site]
        if len(rects) != len(names):
            raise SystemExit(
                f"expected {len(names)} 'External DNS' boxes in site {site}, found {len(rects)}"
            )
        for rect, name in zip(sorted(rects, key=lambda r: _bbox(r)[0]), names):
            tag(rect, site, EXTERNAL_DNS_NAMESPACE, name)

    expected = len(sites) * (len(BOXES) + len(EXTERNAL_DNS_LEFT_TO_RIGHT["berne"]))
    if len(watched) != expected:
        raise SystemExit(
            f"resolved {len(watched)} of {expected} boxes: {sorted(watched)}\n"
            f"labels seen: {sorted({label[:40] for label, _ in cells if label})}"
        )

    return ET.tostring(root, encoding="unicode"), watched


# --------------------------------------------------------------------------- state


class Store:
    def __init__(self, watched: dict[str, tuple[str, str, str]]) -> None:
        self._cond = threading.Condition()
        self._states = {key: "unknown" for key in watched}
        self.version = 0

    def set(self, key: str, state: str) -> None:
        with self._cond:
            if self._states.get(key) == state:
                return
            self._states[key] = state
            self.version += 1
            self._cond.notify_all()

    def snapshot(self) -> tuple[int, dict[str, str]]:
        with self._cond:
            return self.version, dict(self._states)

    def wait(self, seen: int, timeout: float) -> tuple[int, dict[str, str]] | None:
        with self._cond:
            if self.version == seen:
                self._cond.wait(timeout)
            if self.version == seen:
                return None
            return self.version, dict(self._states)


def deployment_state(deployment) -> str:
    desired = deployment.spec.replicas or 0
    ready = deployment.status.ready_replicas or 0
    if desired == 0:
        return "down"
    if ready == 0:
        return "degraded"
    return "ok"


def watch_namespace(site: str, context: str, namespace: str, names: set[str], store: Store) -> None:
    keys = {name: f"{site}/{namespace}/{name}" for name in names}
    while True:
        try:
            api = client.AppsV1Api(config.new_client_from_config(context=context))
            listing = api.list_namespaced_deployment(namespace)
            for deployment in listing.items:
                if deployment.metadata.name in keys:
                    store.set(keys[deployment.metadata.name], deployment_state(deployment))
            for event in watch.Watch().stream(
                api.list_namespaced_deployment,
                namespace=namespace,
                resource_version=listing.metadata.resource_version,
                timeout_seconds=300,
            ):
                deployment = event["object"]
                key = keys.get(deployment.metadata.name)
                if key is None:
                    continue
                store.set(
                    key,
                    "unknown" if event["type"] == "DELETED" else deployment_state(deployment),
                )
        except Exception as exc:  # watch expiry, API restart, cluster gone
            print(f"[{context}/{namespace}] watch failed: {exc}", flush=True)
            for key in keys.values():
                store.set(key, "unknown")
            time.sleep(2)


# --------------------------------------------------------------------------- http

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>DNS demo &ndash; live cluster state</title>
<style>
  html, body {{ margin: 0; height: 100%; overflow: hidden; background: #fff; font-family: sans-serif; }}
  svg {{ display: block; width: 100%; height: 100%; }}
  @keyframes flash-red {{
    0%, 49% {{ fill: var(--orig-fill); }}
    50%, 100% {{ fill: #e53935; }}
  }}
  [data-state-key].flash {{ animation: flash-red 1s steps(1, end) infinite; }}
</style></head>
<body>
{svg}
<script>
const DOWN = "#e53935", UNKNOWN = "#bdbdbd";
const boxes = new Map();
for (const el of document.querySelectorAll("[data-state-key]")) {{
  el.style.setProperty("--orig-fill", el.style.fill || el.getAttribute("fill") || "#ffffff");
  boxes.set(el.dataset.stateKey, el);
}}
function apply(states) {{
  for (const [key, el] of boxes) {{
    const state = states[key] || "unknown";
    el.style.fill = state === "down" ? DOWN : state === "unknown" ? UNKNOWN : "var(--orig-fill)";
    el.classList.toggle("flash", state === "degraded");
  }}
}}
const events = new EventSource("/events");
events.onmessage = (e) => apply(JSON.parse(e.data));
</script>
</body></html>
"""


def make_handler(page: bytes, store: Store):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            pass

        def do_GET(self):
            if self.path in ("/", "/index.html"):
                self._send(page, "text/html; charset=utf-8")
            elif self.path == "/events":
                self._events()
            else:
                self.send_error(404)

        def _send(self, body: bytes, content_type: str) -> None:
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _events(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            seen, states = store.snapshot()
            try:
                self._push(states)
                while True:
                    update = store.wait(seen, timeout=15)
                    if update is None:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                        continue
                    seen, states = update
                    self._push(states)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def _push(self, states: dict[str, str]) -> None:
            self.wfile.write(f"data: {json.dumps(states)}\n\n".encode())
            self.wfile.flush()

    return Handler


def main() -> None:
    svg, watched = prepare_svg()
    store = Store(watched)

    by_namespace: dict[tuple[str, str], set[str]] = {}
    for site, namespace, name in watched.values():
        by_namespace.setdefault((site, namespace), set()).add(name)
    for (site, namespace), names in by_namespace.items():
        threading.Thread(
            target=watch_namespace,
            args=(site, CONTEXTS[site], namespace, names, store),
            daemon=True,
        ).start()

    page = PAGE.format(svg=svg).encode()
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), make_handler(page, store))
    server.daemon_threads = True
    print(f"watching {len(watched)} boxes, serving on http://{BIND_HOST}:{BIND_PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
