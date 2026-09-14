"""Dynamic application discovery — builds application-model.json.

Merges the static model (manifest components from the APK) with what the app
actually shows at runtime (uiautomator dumps + screenshots), probing
navigation within the test budget. Nothing is assumed about the app: screens
and features exist only if observed.
"""
import json
import os
import time

from . import safety, ui_model

NAV_KEYWORDS = ("menu", "settings", "profile", "account", "search", "filter",
                "sort", "refresh", "retry", "help", "about", "open", "edit",
                "add", "create", "new", "start", "play", "continue", "browse",
                "library", "more", "close", "next", "tabs", "category")

class DiscoveryContext:
    """Shared per-session state handed to flows."""

    def __init__(self, adb, package, apkinfo, cfg, out_dir, recorder=None):
        self.adb = adb
        self.package = package
        self.apkinfo = apkinfo
        self.cfg = cfg
        self.out_dir = out_dir
        self.recorder = recorder
        self.shots = os.path.join(out_dir, "screenshots")
        os.makedirs(self.shots, exist_ok=True)
        self.actions = 0
        self.t0 = time.time()
        self.findings = []
        self.model = AppModel()

    # -- budget ------------------------------------------------------------
    @property
    def budget_left(self):
        return (self.actions < self.cfg.max_actions
                and (time.time() - self.t0) < self.cfg.max_test_seconds)

    def tick(self):
        self.actions += 1
        if self.actions >= self.cfg.max_actions:
            raise BudgetExhausted("max actions reached (%d)" % self.actions)
        if (time.time() - self.t0) >= self.cfg.max_test_seconds:
            raise BudgetExhausted("max test time reached (%ss)" % self.cfg.max_test_seconds)

    # -- findings ------------------------------------------------------------
    def finding(self, severity, kind, detail, flow=""):
        self.findings.append({"severity": severity, "kind": kind,
                              "detail": detail, "flow": flow})

    # -- primitives ------------------------------------------------------------
    def screenshot(self, name):
        path = os.path.join(self.shots, "%s.png" % name)
        try:
            if self.adb.screencap(path):
                return path
        except Exception:
            pass
        return None

    def screen(self, name=None):
        """Capture current UI state -> Screen (None hierarchy = surface app)."""
        xml = self.adb.uidump()
        elements, meta = ui_model.parse(xml)
        scr = Screen(elements, meta)
        if name:
            scr.screenshot = self.screenshot(name)
        return scr

    def has_surface_view(self):
        try:
            top = self.adb.dumpsys("activity top", timeout=20)
            return "SurfaceView" in top
        except Exception:
            return False

    def record(self, action):
        if self.recorder:
            self.recorder.add(action)


class BudgetExhausted(Exception):
    pass


class Screen:
    def __init__(self, elements, meta):
        self.elements = elements
        self.meta = meta
        self.fingerprint = ui_model.fingerprint(elements)
        self.screenshot = None
        self.ts = time.time()

    @property
    def interactive(self):
        return ui_model.interactive(self.elements)

    def to_dict(self):
        return {
            "fingerprint": self.fingerprint,
            "node_count": self.meta.get("count", 0),
            "hierarchy_available": self.meta.get("available", False),
            "screenshot": self.screenshot,
            "elements": [{
                "id": e.rid, "desc": e.desc, "text": e.text[:80],
                "class": e.cls, "role": e.role(),
                "bounds": [e.x1, e.y1, e.x2, e.y2],
                "clickable": e.clickable, "checkable": e.checkable,
                "scrollable": e.scrollable,
            } for e in self.elements[:200]],
        }


class AppModel:
    """application-model.json — the discovered truth about the app."""

    def __init__(self):
        self.screens = {}          # fingerprint -> Screen
        self.edges = []            # [from_fp, action, to_fp]
        self.canvas_app = False    # no view hierarchy at all (GL/game)
        self.fields = []
        self.toggles = []
        self.scrollables = []
        self.features = set()
        self.dialogs_seen = []
        self.probe_paths = []      # action trace of discovery itself

    def note_edge(self, src, action, dst):
        if src != dst and [src, action, dst] not in self.edges:
            self.edges.append([src, action, dst])

    def to_dict(self, apkinfo):
        return {
            "package": apkinfo.package,
            "version_name": apkinfo.version_name,
            "version_code": apkinfo.version_code,
            "min_sdk": apkinfo.min_sdk,
            "target_sdk": apkinfo.target_sdk,
            "abis": apkinfo.abis,
            "permissions": apkinfo.permissions,
            "runtime_permissions": apkinfo.runtime_permissions(),
            "activities": [a["name"] for a in apkinfo.activities],
            "services": [s["name"] for s in apkinfo.services],
            "receivers": [r["name"] for r in apkinfo.receivers],
            "providers": [p["name"] for p in apkinfo.providers],
            "exported_components": apkinfo.exported,
            "deep_links": apkinfo.deep_links,
            "launchable_activity": apkinfo.launchable_activity,
            "screens": [s.to_dict() for s in self.screens.values()],
            "navigation_edges": self.edges,
            "background_components": {"services": len(apkinfo.services),
                                      "receivers": len(apkinfo.receivers),
                                      "providers": len(apkinfo.providers)},
            "canvas_app": self.canvas_app,
            "discovered_features": sorted(self.features),
            "text_fields": self.fields,
            "toggles": self.toggles,
            "probe_paths": self.probe_paths,
        }

    def save(self, out_dir, apkinfo):
        path = os.path.join(out_dir, "application-model.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(apkinfo), f, indent=2, default=str)
        return path


# ---------------------------------------------------------------------------
def _settle(ctx, seconds=2.0):
    time.sleep(seconds)


def screen_snapshot(ctx, name):
    scr = ctx.screen(name=name)
    if scr.meta.get("available"):
        ctx.model.screens.setdefault(scr.fingerprint, scr)
    return scr


def launch_and_observe(ctx, tag="launch"):
    """Launch the app cold and observe startup state. Returns (info, screen)."""
    ctx.adb.force_stop(ctx.package)
    _settle(ctx, 1.5)
    ctx.adb.clear_logcat()
    info = ctx.adb.launch(ctx.package)
    if not info["resumed"]:
        ctx.finding("critical", "startup", "app never reached foreground", tag)
    _settle(ctx, 6)
    scr = screen_snapshot(ctx, tag)
    if scr.meta.get("available"):
        if ui_model.looks_blank(scr.elements, scr.meta, ctx.has_surface_view()):
            ctx.finding("warning", "blank-screen",
                        "empty UI hierarchy without SurfaceView at startup", tag)
        else:
            ctx.model.features.add("ui-hierarchy")
    else:
        # GL/canvas app: verify via process + engine evidence instead
        ctx.model.canvas_app = True
        if ctx.has_surface_view():
            ctx.model.features.add("surface-view")
    for e in scr.interactive:
        if e.role() == "textfield":
            ctx.model.fields.append(_elem_dict(e))
        if e.role() in ("checkbox", "switch", "toggle"):
            ctx.model.toggles.append(_elem_dict(e))
        if e.role() == "scrollable":
            ctx.model.scrollables.append(_elem_dict(e))
    return info, scr


def _elem_dict(e):
    return {"id": e.rid, "desc": e.desc, "text": e.text[:60], "class": e.cls,
            "bounds": [e.x1, e.y1, e.x2, e.y2]}


def probe_navigation(ctx, max_clicks=None):
    """Bounded exploration: tap likely-navigation targets, record screens.

    Respects the safe interaction engine: destructive targets open their flow
    but we back out before any irreversible step (handled by flows; here we
    skip destructive targets entirely to keep discovery side-effect-free).
    """
    max_clicks = max_clicks or max(4, ctx.cfg.max_actions // 4)
    home = screen_snapshot(ctx, "home")
    clicks = 0
    for round_no in range(2):
        scr = screen_snapshot(ctx, "probe-r%d" % round_no)
        targets = sorted(scr.interactive, key=safety.nav_priority)
        seen = set()
        for e in targets:
            if not ctx.budget_left or clicks >= max_clicks:
                return
            risk = safety.classify(e)
            if risk.level in (safety.DESTRUCTIVE, safety.FORBIDDEN):
                ctx.finding("info", "skipped-risky",
                            "discovery skipped destructive target: %s" % e.label(),
                            "discovery")
                continue
            key = (e.rid, e.desc, e.text, e.center)
            if key in seen:
                continue
            seen.add(key)
            clicks += 1
            try:
                ctx.adb.tap(*e.center)
            except Exception:
                continue
            _settle(ctx, 2.5)
            after = screen_snapshot(ctx, "probe-r%d-c%d" % (round_no, clicks))
            ctx.model.note_edge(scr.fingerprint,
                                "tap:%s" % e.label(), after.fingerprint)
            ctx.record({"action": "tap", "target": e.label(),
                        "from": scr.fingerprint, "to": after.fingerprint})
            if after.meta.get("available"):
                for el in after.interactive:
                    if el.role() == "textfield" and _elem_dict(el) not in ctx.model.fields:
                        ctx.model.fields.append(_elem_dict(el))
                    if el.role() in ("checkbox", "switch", "toggle"):
                        ctx.model.toggles.append(_elem_dict(el))
                if ui_model.dialogs(after.elements):
                    ctx.model.dialogs_seen.append(after.fingerprint)
                    ctx.model.features.add("dialogs")
            # feature keyword harvesting
            label = (e.rid + " " + e.desc + " " + e.text).lower()
            for kw in NAV_KEYWORDS:
                if kw in label:
                    ctx.model.features.add(kw)
            # navigate back home
            ctx.adb.back()
            _settle(ctx, 1.5)
            cur = screen_snapshot(ctx)
            tries = 0
            while (cur.fingerprint != home.fingerprint and tries < 3
                   and ctx.budget_left):
                ctx.adb.back()
                _settle(ctx, 1.2)
                cur = screen_snapshot(ctx)
                tries += 1
            if cur.fingerprint != home.fingerprint:
                # lost: relaunch cold to restore known state
                launch_and_observe(ctx, "rehome-r%d-c%d" % (round_no, clicks))
                home = screen_snapshot(ctx, "home-again-r%d" % round_no)
    if ctx.model.fields:
        ctx.model.features.add("forms")
    if ctx.model.toggles:
        ctx.model.features.add("toggles")
    if ctx.model.scrollables:
        ctx.model.features.add("scrolling")


def build_model(ctx, do_probe=True):
    """Full discovery pass. Returns the AppModel (also stored on ctx.model)."""
    launch_and_observe(ctx, "discovery-launch")
    if do_probe:
        try:
            probe_navigation(ctx)
        except BudgetExhausted:
            ctx.finding("info", "budget", "discovery stopped at budget", "discovery")
    return ctx.model
