"""Core test flows: launch, navigation, deep links, permissions, input fuzz.

Every flow is generic: it acts only on what discovery actually found, with
per-action timeouts, budget enforcement, and live crash monitoring. Any flow
can run against ANY apk.
"""
import time

from . import discovery, fuzzer, safety, ui_model
from .discovery import BudgetExhausted


class FlowResult:
    def __init__(self, name, status="passed", notes=None):
        self.name = name
        self.status = status          # passed / failed / warned / skipped
        self.notes = notes or []
        self.failed_action = None

    def to_dict(self):
        return {"flow": self.name, "status": self.status, "notes": self.notes,
                "failed_action": self.failed_action}


def _check_alive(ctx, res, where):
    pid = ctx.adb.pidof(ctx.package)
    if not pid:
        res.status = "failed"
        res.failed_action = where
        ctx.finding("critical", "process-death", "app process died during %s" % where,
                    res.name)
        return False
    crash = ctx.monitor.has_critical()
    if crash is not None:
        res.status = "failed"
        res.failed_action = where
        ctx.finding("critical", "crash", "crash/ANR event during %s: %s"
                    % (where, crash.line[:160]), res.name)
        return False
    return True


# ---------------------------------------------------------------------------
def flow_launch(ctx):
    """Cold start: install verification already done by runner. Startup path."""
    res = FlowResult("launch")
    info, scr = discovery.launch_and_observe(ctx, "flow-launch")
    res.notes.append("startup elapsed %.1fs, resumed=%s, pid=%s"
                     % (info["elapsed"], info["resumed"], info["pid"]))
    if not info["resumed"]:
        res.status = "failed"
        res.failed_action = "launch"
        return res
    time.sleep(6)
    _check_alive(ctx, res, "startup settle")
    return res


def flow_navigation(ctx):
    """Walk discovered navigation paths; detect loops / dead ends / crashes."""
    res = FlowResult("navigation")
    if ctx.model.canvas_app and not ctx.model.screens:
        res.status = "skipped"
        res.notes.append("canvas app without UI hierarchy — navigation via monkey flow")
        return res
    before = len(ctx.model.screens)
    try:
        discovery.probe_navigation(ctx, max_clicks=max(6, ctx.cfg.max_actions // 3))
    except BudgetExhausted:
        res.notes.append("stopped at budget")
    res.notes.append("screens discovered: %d (+%d this run)"
                     % (len(ctx.model.screens), len(ctx.model.screens) - before))
    _check_alive(ctx, res, "navigation")
    # navigation loop detection: same edge cycle >= 3
    edge_counts = {}
    for e in ctx.model.edges:
        edge_counts[(e[0], e[2])] = edge_counts.get((e[0], e[2]), 0) + 1
    loops = [k for k, v in edge_counts.items() if v >= 4]
    if loops:
        ctx.finding("minor", "navigation-loop",
                    "%d navigation edge(s) traversed >=4 times" % len(loops),
                    res.name)
    return res


def flow_back_stack(ctx):
    """Back navigation: from current screen, repeated back, rapid nav."""
    res = FlowResult("back-stack")
    scr = discovery.screen_snapshot(ctx, "backstack-start")
    if not scr.meta.get("available"):
        res.status = "skipped"
        res.notes.append("canvas app — back stack via lifecycle restart instead")
        return res
    backs = 0
    for i in range(5):
        ctx.adb.back()
        time.sleep(1.5)
        backs += 1
        pid = ctx.adb.pidof(ctx.package)
        if not pid:
            # app exited via back on home screen: acceptable only if graceful
            res.notes.append("app exited after %d backs (home behavior)" % backs)
            info = ctx.adb.launch(ctx.package)
            if not info["resumed"]:
                res.status = "failed"
                res.failed_action = "relaunch-after-back-exit"
                ctx.finding("critical", "relaunch", "could not relaunch after back-exit",
                            res.name)
                return res
            break
        _check_alive(ctx, res, "back x%d" % backs)
    # rapid navigation: 8 fast taps on first interactive target
    scr = discovery.screen_snapshot(ctx, "backstack-rapid")
    if scr.interactive:
        e = scr.interactive[0]
        risk = safety.classify(e)
        if risk.level == safety.SAFE:
            for _ in range(8):
                try:
                    ctx.adb.tap(*e.center)
                    time.sleep(0.25)
                except Exception:
                    break
            time.sleep(3)
            _check_alive(ctx, res, "rapid-taps")
            ctx.adb.back()
            time.sleep(1.5)
    return res


def flow_deep_links(ctx):
    res = FlowResult("deep-links")
    links = ctx.apkinfo.deep_links
    if not links:
        res.status = "skipped"
        res.notes.append("no deep links declared in manifest")
        return res
    for link in links[:6]:
        try:
            ok = ctx.adb.start_view(link)
            time.sleep(3)
            alive = bool(ctx.adb.pidof(ctx.package))
            res.notes.append("%s -> launched=%s alive=%s" % (link, ok, alive))
            if not alive:
                res.status = "failed"
                res.failed_action = "deeplink:%s" % link
                ctx.finding("critical", "deeplink-crash", "app died after opening %s" % link,
                            res.name)
                return res
            _check_alive(ctx, res, "deeplink:%s" % link)
            # malformed variant (robustness)
            ctx.adb.start_view(link.rstrip("/") + "/%%invalid%%")
            time.sleep(2)
            _check_alive(ctx, res, "deeplink-malformed:%s" % link)
            ctx.adb.force_stop(ctx.package)
            time.sleep(1)
            ctx.adb.launch(ctx.package, wait_timeout=60)
        except Exception as exc:
            res.notes.append("%s -> error: %s" % (link, exc))
    return res


def flow_permissions(ctx):
    """Grant/deny/revoke each runtime permission; verify graceful handling."""
    res = FlowResult("permissions")
    perms = ctx.apkinfo.runtime_permissions()
    if not perms:
        res.status = "skipped"
        res.notes.append("no dangerous runtime permissions requested")
        return res
    ctx.adb.force_stop(ctx.package)
    for perm in perms:
        short = perm.split(".")[-1]
        # 1) deny baseline (fresh state, nothing granted)
        try:
            ctx.adb.revoke(ctx.package, perm)
        except Exception:
            pass
        info = ctx.adb.launch(ctx.package, wait_timeout=90)
        time.sleep(4)
        deny_alive = bool(ctx.adb.pidof(ctx.package))
        res.notes.append("%s deny -> alive=%s resumed=%s" % (short, deny_alive, info["resumed"]))
        if not deny_alive:
            res.status = "failed"
            res.failed_action = "deny:%s" % short
            ctx.finding("critical", "permission-deny-crash",
                        "app crashed when %s not granted" % short, res.name)
            return res
        # 2) grant and re-run
        try:
            ctx.adb.grant(ctx.package, perm)
        except Exception as exc:
            res.notes.append("%s grant failed: %s" % (short, exc))
        ctx.adb.force_stop(ctx.package)
        ctx.adb.launch(ctx.package, wait_timeout=90)
        time.sleep(4)
        if not _check_alive(ctx, res, "grant:%s" % short):
            return res
        ctx.model.features.add("permissions-handled")
    # revoke everything back to a clean baseline
    for perm in perms:
        ctx.adb.revoke(ctx.package, perm)
    ctx.adb.force_stop(ctx.package)
    return res


def flow_input_fuzz(ctx):
    """Type bounded fuzz corpus into discovered text fields, detect fallout."""
    res = FlowResult("input-fuzz")
    if not ctx.model.fields:
        res.status = "skipped"
        res.notes.append("no text fields discovered")
        return res
    values = fuzzer.corpus(max_values=ctx.cfg.fuzz_values)
    tested = 0
    for field in ctx.model.fields[:3]:
        x = (field["bounds"][0] + field["bounds"][2]) // 2
        y = (field["bounds"][1] + field["bounds"][3]) // 2
        for v in values:
            if not ctx.budget_left:
                res.notes.append("stopped at budget after %d inputs" % tested)
                return res
            can, norm = fuzzer.typed(v)
            try:
                ctx.adb.tap(x, y)
                time.sleep(1)
                if can:
                    ok = ctx.adb.type_text(v["value"][:4096])
                    tested += 1
                else:
                    res.notes.append("skipped typing %s value (device limitation)"
                                     % v["kind"])
                    ctx.adb.back()          # close keyboard
                    continue
                time.sleep(1.5)
                if not _check_alive(ctx, res, "fuzz:%s:%s" % (field.get("id") or "field",
                                                              v["kind"])):
                    return res
                # clear the field (select-all + delete via back is generic-ish)
                for _ in range(3):
                    ctx.adb.key(67)         # DEL
                ctx.adb.key(111)            # ESC
            except Exception as exc:
                res.notes.append("fuzz error %s: %s" % (v["kind"], exc))
                break
    res.notes.append("fuzz inputs typed: %d" % tested)
    if tested:
        ctx.model.features.add("input-handling")
    ctx.adb.back()
    time.sleep(1)
    return res


def flow_forms(ctx):
    """Submit flows around discovered fields: empty submit + validation check."""
    res = FlowResult("forms")
    if not ctx.model.fields:
        res.status = "skipped"
        return res
    scr = discovery.screen_snapshot(ctx, "forms")
    submit = None
    for e in scr.interactive:
        if safety.CONFIRM_RE.match((e.text or e.desc or "").strip()):
            submit = e
            break
    if submit is None:
        res.status = "skipped"
        res.notes.append("no submit-like control visible next to fields")
        return res
    risk = safety.classify(submit)
    if risk.level != safety.SAFE:
        res.notes.append("submit control not classified safe: %s" % risk.reason)
        return res
    # empty submit
    ctx.adb.tap(*submit.center)
    time.sleep(2.5)
    if not _check_alive(ctx, res, "empty-submit"):
        return res
    after = discovery.screen_snapshot(ctx, "after-empty-submit")
    validation = any(("required" in (e.text or "").lower()
                      or "invalid" in (e.text or "").lower()
                      or "error" in (e.text or "").lower())
                     for e in after.elements)
    res.notes.append("empty submit -> validation-shown=%s" % validation)
    if not validation:
        ctx.finding("minor", "validation",
                    "no visible validation feedback after empty submit", res.name)
    ctx.model.features.add("forms")
    return res


FLOW_ORDER = [
    flow_launch,
    flow_navigation,
    flow_back_stack,
    flow_deep_links,
    flow_permissions,
    flow_input_fuzz,
    flow_forms,
]
FLOW_NAMES = {f.__name__: f for f in FLOW_ORDER}
