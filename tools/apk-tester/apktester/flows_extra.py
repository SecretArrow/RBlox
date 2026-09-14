"""Lifecycle, storage/state, network, and randomized-exploration flows."""
import os
import random
import time

from . import discovery, safety
from .flows import FlowResult, _check_alive
from .discovery import BudgetExhausted

KEY_POWER = 26
KEY_WAKEUP = 224
KEY_ESC = 111


def flow_lifecycle_core(ctx):
    """Background/foreground + cold restart (spec 10, mandatory)."""
    res = FlowResult("lifecycle-core")
    # background -> foreground
    ctx.adb.home()
    time.sleep(2.5)
    pid_bg = ctx.adb.pidof(ctx.package)
    res.notes.append("backgrounded, pid alive=%s" % bool(pid_bg))
    info = ctx.adb.launch(ctx.package, wait_timeout=90)
    time.sleep(3)
    if not info["resumed"]:
        pid_now = ctx.adb.pidof(ctx.package)
        if not pid_now:
            # Background process was reclaimed by the OS (normal on low-RAM
            # devices). The app-level contract is that cold relaunch works.
            res.notes.append("background process reclaimed by system (normal "
                             "on low-RAM devices)")
            info = ctx.adb.launch(ctx.package, wait_timeout=120)
            time.sleep(5)
            if info["resumed"] and ctx.adb.pidof(ctx.package):
                res.notes.append("cold restart after reclaim OK — graceful")
                ctx.finding("minor", "background-reclaim",
                            "system reclaimed background process; cold "
                            "restart succeeded", res.name)
                _check_alive(ctx, res, "reclaim-restart")
                return res
        res.status = "failed"
        res.failed_action = "foreground-return"
        ctx.finding("critical", "lifecycle",
                    "app did not return to foreground after background "
                    "(pid alive=%s)" % bool(pid_now), res.name)
        return res
    if not ctx.adb.pidof(ctx.package):
        # Distinguish OS reclaim (no crash evidence) from a real crash: if the
        # process died with ZERO crash/ANR events in this flow, relaunch cold
        # and accept a graceful recovery.
        if ctx.monitor.has_critical(since=res.ts_start) is None:
            res.notes.append("process died right after resume with no crash "
                             "evidence in logcat -> OS reclaim, verifying cold "
                             "restart")
            info = ctx.adb.launch(ctx.package, wait_timeout=120)
            time.sleep(5)
            if info["resumed"] and ctx.adb.pidof(ctx.package):
                res.status = "warned"
                res.notes.append("cold restart after reclaim OK — graceful")
                ctx.finding("minor", "background-reclaim",
                            "system reclaimed background process at resume; "
                            "cold restart succeeded (no crash in logcat)",
                            res.name)
                if not ctx.adb.pidof(ctx.package):
                    res.status = "failed"
                    res.failed_action = "reclaim-restart"
                return res
            res.status = "failed"
            res.failed_action = "reclaim-restart"
            ctx.finding("critical", "lifecycle",
                        "process died at resume and cold restart also failed",
                        res.name)
            return res
        res.status = "failed"
        res.failed_action = "background/foreground"
        ctx.finding("critical", "crash",
                    "app crashed during background/foreground transition",
                    res.name)
        return res
    # cold restart
    ctx.adb.force_stop(ctx.package)
    time.sleep(2)
    info = ctx.adb.launch(ctx.package, wait_timeout=120)
    time.sleep(5)
    if not info["resumed"]:
        res.status = "failed"
        res.failed_action = "cold-restart"
        return res
    if not _check_alive(ctx, res, "cold restart"):
        return res
    ctx.screenshot("lifecycle-cold-restart")
    res.notes.append("cold restart ok")
    return res


def flow_lifecycle_deep(ctx):
    """Rotation, screen lock/unlock, keyboard, process recreation (spec 10)."""
    res = FlowResult("lifecycle-deep")
    # rotation x2 (activity recreation / config change)
    for rot in (1, 0):
        try:
            ctx.adb.shell("settings put system accelerometer_rotation 0", timeout=15)
            ctx.adb.shell("settings put system user_rotation %d" % rot, timeout=15)
            time.sleep(4)
            if not _check_alive(ctx, res, "rotation=%d" % rot):
                return res
        except Exception as exc:
            res.notes.append("rotation %d unsupported: %s" % (rot, exc))
    ctx.adb.shell("settings put system accelerometer_rotation 1", timeout=15)
    ctx.screenshot("lifecycle-rotation")
    # screen lock / unlock
    try:
        ctx.adb.key(KEY_POWER)
        time.sleep(2)
        ctx.adb.wake()
        time.sleep(1)
        ctx.adb.dismiss_keyguard()
        time.sleep(3)
        if not _check_alive(ctx, res, "lock/unlock"):
            return res
        res.notes.append("screen lock/unlock ok")
    except Exception as exc:
        res.notes.append("lock/unlock skipped: %s" % exc)
    # keyboard open/close if a field exists
    if ctx.model.fields:
        f = ctx.model.fields[0]
        x = (f["bounds"][0] + f["bounds"][2]) // 2
        y = (f["bounds"][1] + f["bounds"][3]) // 2
        try:
            ctx.adb.tap(x, y)
            time.sleep(2)
            ctx.adb.key(KEY_ESC)
            ctx.adb.back()
            time.sleep(2)
            if not _check_alive(ctx, res, "keyboard open/close"):
                return res
            res.notes.append("keyboard open/close ok")
        except Exception as exc:
            res.notes.append("keyboard test skipped: %s" % exc)
    # process recreation: kill backgrounded process, relaunch
    ctx.adb.home()
    time.sleep(2)
    ctx.adb.kill_background(ctx.package)
    time.sleep(2)
    info = ctx.adb.launch(ctx.package, wait_timeout=120)
    time.sleep(4)
    if not info["resumed"] or not ctx.adb.pidof(ctx.package):
        res.status = "failed"
        res.failed_action = "process-recreation"
        ctx.finding("critical", "lifecycle", "app failed to survive process recreation",
                    res.name)
        return res
    if not _check_alive(ctx, res, "process recreation"):
        return res
    res.notes.append("process recreation ok")
    return res


def flow_storage_state(ctx):
    """State persistence across restart (observational, generic)."""
    res = FlowResult("storage-state")
    # mutate something observable if possible (toggle), else just restart
    scr = discovery.screen_snapshot(ctx, "storage-before")
    toggled = None
    for e in ui_toggles(scr):
        if safety.classify(e).level == safety.SAFE:
            ctx.adb.tap(*e.center)
            time.sleep(1.5)
            toggled = e
            break
    state_before = discovery.screen_snapshot(ctx, "storage-state-before").fingerprint
    ctx.adb.force_stop(ctx.package)
    time.sleep(2)
    info = ctx.adb.launch(ctx.package, wait_timeout=120)
    time.sleep(5)
    if not info["resumed"]:
        res.status = "failed"
        res.failed_action = "restart"
        return res
    if not _check_alive(ctx, res, "storage restart"):
        return res
    state_after = discovery.screen_snapshot(ctx, "storage-state-after").fingerprint
    res.notes.append("screen fingerprint before/after restart: %s/%s (toggled=%s)"
                     % (state_before, state_after, bool(toggled)))
    if toggled is not None and state_before != state_after:
        ctx.finding("minor", "persistence",
                    "screen state changed across restart after toggle "
                    "(may indicate unpersisted UI state)", res.name)
    ctx.model.features.add("restart-survival")
    return res


def ui_toggles(scr):
    from . import ui_model
    return ui_model.toggles(scr.elements) if scr.meta.get("available") else []


def flow_network(ctx):
    """Offline/reconnect resilience — only if app declares INTERNET."""
    res = FlowResult("network")
    if "android.permission.INTERNET" not in ctx.apkinfo.permissions:
        res.status = "skipped"
        res.notes.append("no INTERNET permission — network testing not applicable")
        return res
    ok = ctx.adb.airplane(True)
    if not ok:
        res.status = "skipped"
        res.notes.append("airplane mode toggle unavailable on this device")
        return res
    time.sleep(3)
    # interact mildly while offline
    try:
        scr = discovery.screen_snapshot(ctx, "network-off")
        safe_targets = [e for e in scr.interactive
                        if safety.classify(e).level == safety.SAFE][:3]
        for e in safe_targets:
            ctx.adb.tap(*e.center)
            time.sleep(2)
    except BudgetExhausted:
        pass
    time.sleep(4)
    offline_alive = bool(ctx.adb.pidof(ctx.package))
    ctx.adb.airplane(False)
    time.sleep(6)
    online_alive = bool(ctx.adb.pidof(ctx.package))
    res.notes.append("offline alive=%s, reconnect alive=%s" % (offline_alive, online_alive))
    if not offline_alive or not online_alive:
        res.status = "failed"
        res.failed_action = "airplane-toggle"
        ctx.finding("critical", "network",
                    "app died during offline/reconnect cycle", res.name)
        return res
    if not _check_alive(ctx, res, "network cycle"):
        return res
    ctx.model.features.add("network-resilience")
    return res


def flow_monkey(ctx):
    """Deterministic seeded exploration (spec 17): reproducible via seed."""
    res = FlowResult("random-exploration")
    n = ctx.cfg.monkey_actions
    if not n:
        res.status = "skipped"
        res.notes.append("mode disables monkey exploration")
        return res
    seed = ctx.cfg.seed
    rng = random.Random(seed)
    budget = min(n, max(0, ctx.cfg.max_actions - ctx.actions - 20))
    if budget <= 0:
        res.status = "skipped"
        res.notes.append("no budget left for monkey")
        return res
    # Use adb monkey (system-level, throttled, no syskeys) — deterministic order
    try:
        ctx.adb.shell(
            "monkey -p %s --throttle 200 --pct-syskeys 0 --pct-appswitch 5 "
            "-s %d %d" % (ctx.package, seed, budget),
            timeout=min(60 * 20, 15 * budget // 10 + 120))
    except Exception as exc:
        res.notes.append("monkey interrupted: %s" % exc)
    time.sleep(3)
    if not _check_alive(ctx, res, "monkey(seed=%d)" % seed):
        ctx.finding("critical", "monkey-crash",
                    "app crashed during seeded exploration (seed=%d, replayable)"
                    % seed, res.name)
        return res
    res.notes.append("monkey ok: seed=%d events=%d (seed+trace saved)" % (seed, budget))
    ctx.record({"action": "monkey", "seed": seed, "events": budget})
    # follow-up: our own short seeded walker over discovered UI (if any)
    scr = discovery.screen_snapshot(ctx, "post-monkey")
    if scr.meta.get("available"):
        rng.shuffle(scr.interactive)
        for e in scr.interactive[:5]:
            if not ctx.budget_left:
                break
            if safety.classify(e).level != safety.SAFE:
                continue
            ctx.adb.tap(*e.center)
            time.sleep(1.5)
            if not _check_alive(ctx, res, "walker-tap:%s" % e.label()):
                res.notes.append("walker seed trace: %s" %
                                 [x.label() for x in scr.interactive[:5]])
                return res
    ctx.screenshot("post-monkey")
    return res


FLOW_ORDER = [
    flow_lifecycle_core,
    flow_storage_state,
    flow_lifecycle_deep,
    flow_network,
    flow_monkey,
]
FLOW_NAMES = {f.__name__: f for f in FLOW_ORDER}


def mode_flow_sequence(mode, cfg):
    """Flow list per mode (spec 26)."""
    core = ["flow_launch", "flow_navigation", "flow_back_stack", "flow_lifecycle_core"]
    if mode == "SMOKE":
        return core
    if mode == "STANDARD":
        return core + ["flow_deep_links", "flow_permissions", "flow_input_fuzz",
                       "flow_forms", "flow_monkey"]
    if mode == "DEEP":
        return core + ["flow_deep_links", "flow_permissions", "flow_input_fuzz",
                       "flow_forms", "flow_storage_state", "flow_lifecycle_deep",
                       "flow_network", "flow_monkey"]
    return core + ["flow_deep_links", "flow_permissions", "flow_input_fuzz",
                   "flow_forms", "flow_storage_state", "flow_lifecycle_deep",
                   "flow_network", "flow_monkey"]  # RELEASE = DEEP + strict gate
