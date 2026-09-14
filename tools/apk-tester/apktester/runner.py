"""Runner — orchestrates the full autonomous loop for ANY release APK.

    verify apk -> install -> launch -> discover -> generate flows -> execute
    -> detect errors -> collect diagnostics -> analyze root cause
    -> [autofix] modify source -> rebuild -> reinstall -> re-run failed flow
    -> regression -> report -> release gate verdict

Usage:
    python -m apktester.runner --apk app.apk --mode SMOKE --out artifacts \
        [--repo .] [--build-cmd "..."] [--autofix] [--serial emulator-5554]
        [--seed 42] [--flows flow_launch,flow_navigation]
"""
import argparse
import json
import os
import sys
import time

from . import analyzer, diagnostics, discovery, fixers, reporting
from .apk_info import ApkInfo
from .config import TestConfig, MODES
from .device import Adb, DeviceError
from .flows import FlowResult, _check_alive
from . import flows as flows_core
from . import flows_extra
from .monitor import CrashMonitor


class Trace:
    """action-trace.json — every executed action, replayable order."""

    def __init__(self, out_dir):
        self.path = os.path.join(out_dir, "traces", "action-trace.json")
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.entries = []
        self._flush()

    def add(self, entry):
        entry = dict(entry)
        entry.setdefault("ts", round(time.time(), 3))
        self.entries.append(entry)
        self._flush()

    def _flush(self):
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(self.entries[-3000:], f, indent=1, default=str)
        except OSError:
            pass


class Runner:
    def __init__(self, args):
        self.args = args
        self.cfg = TestConfig(mode=args.mode, seed=args.seed, out_dir=args.out,
                              max_repair_attempts=args.max_repair_attempts)
        self.repo = os.path.abspath(args.repo) if args.repo else None
        self.autofix_enabled = bool(args.autofix and self.repo and args.build_cmd)
        self.monitor_events_cache = []
        self._install_error = ""
        self._last_crash_text = ""
        os.makedirs(args.out, exist_ok=True)
        diagnostics.ensure_tree(args.out)

    # ------------------------------------------------------------------
    def resolve_apk(self):
        apk = self.args.apk
        if os.path.isdir(apk):
            picked, abi, note = None, None, ""
            # local import to avoid cycle
            from .apk_info import pick_apk
            picked, abi, note = pick_apk(
                [os.path.join(apk, f) for f in os.listdir(apk)
                 if f.endswith(".apk")], self.args.prefer_abi)
            print("[apktester] picked APK: %s (%s)" % (picked, note))
            return picked
        return apk

    def run(self):
        apk = self.resolve_apk()
        if not apk or not os.path.exists(apk):
            print("FATAL: APK not found: %s" % apk)
            return 2
        adb = Adb(self.args.serial)
        print("[apktester] device: %s" % json.dumps(adb.info()))
        results = self._test_once(apk, adb)
        ok = all(r["status"] != "failed" for r in results)
        # ---- repair loop (spec 21) --------------------------------------
        autofix_logs = []
        attempts = 0
        while (not ok and self.autofix_enabled
               and attempts < self.cfg.max_repair_attempts):
            attempts += 1
            print("[apktester] auto-fix attempt %d/%d" % (attempts, self.cfg.max_repair_attempts))
            rca = analyzer.analyze(
                self.monitor_events_cache or [],
                self._crash_text(), self._install_error, self.repo)
            analyzer.save(rca, self.args.out)
            applied, log = fixers.propose_and_apply(rca, self.repo, self.args.out)
            autofix_logs.append(log)
            real = [p for p in applied if p.fixer != "GenericFixer"]
            if not real:
                print("[apktester] no safe automatic fix for defect class '%s' "
                      "— stopping repair loop (report-only)" % rca.kind)
                break
            okbuild, blog = fixers.run_build(self.args.build_cmd, self.repo)
            print("[apktester] rebuild ok=%s" % okbuild)
            if not okbuild:
                print("[apktester] rebuild failed; static output tail:\n%s" % blog[-1500:])
                break
            new_apk = fixers.newest_apk(self.args.apk_dir or os.path.dirname(apk)) or apk
            if os.path.abspath(new_apk) == os.path.abspath(apk):
                print("[apktester] warning: rebuild produced same APK path")
            failed_names = [r["flow"] for r in results if r["status"] == "failed"]
            results = self._test_once(new_apk, adb, only_flows=failed_names + self._regression_set())
            ok = all(r["status"] != "failed" for r in results)
        # ---- final report --------------------------------------------------
        summary = self._summarize(results, autofix_logs, attempts)
        verdict = summary["gate"]
        print("[apktester] RESULT: status=%s gate=%s" % (summary["status"], verdict))
        return 0 if verdict == "RELEASE" else 1

    # ------------------------------------------------------------------
    def _regression_set(self):
        return ["flow_launch", "flow_lifecycle_core"]

    def _crash_text(self):
        return getattr(self, "_last_crash_text", "")

    def _test_once(self, apk, adb, only_flows=None):
        """One full test pass (fresh install). Returns list of flow dicts."""
        cfg = self.cfg
        apkinfo = ApkInfo.from_file(apk)
        ok, issues = apkinfo.verify()
        for i in issues:
            print("[apktester] apk-verify: %s" % i)
        if not ok and self.args.gate_verify:
            self._install_error = "; ".join(issues)
        diagnostics.save_json(os.path.join(self.args.out, "apk", "apk-metadata.json"),
                              apkinfo.to_dict())
        # uninstall any older install (signature changes between attempts)
        if apkinfo.package:
            adb.uninstall(apkinfo.package)
        oki, out = adb.install(apk, timeout=cfg_install_timeout())
        self._install_error = "" if oki else out
        print("[apktester] install ok=%s: %s" % (oki, out.splitlines()[-1] if out else ""))
        results = []
        if not oki:
            fr = FlowResult("install", status="failed")
            fr.notes.append(out[:300])
            results.append(fr.to_dict())
            return results
        adb.root()
        adb.shell("settings put secure immersive_mode_confirmations confirmed",
                  timeout=15)
        adb.shell("settings put global window_animation_scale 0.0", timeout=15)
        adb.clear_logcat()
        monitor = CrashMonitor(adb, apkinfo.package,
                               os.path.join(self.args.out, "logs"))
        monitor.start()
        self.monitor = monitor
        ctx = discovery.DiscoveryContext(adb, apkinfo.package, apkinfo, cfg,
                                         self.args.out)
        self.ctx = ctx
        trace = Trace(self.args.out)
        ctx.recorder = trace
        try:
            discovery.build_model(ctx, do_probe=(cfg.mode != "SMOKE"))
        except Exception as exc:
            ctx.finding("warning", "discovery", "discovery error: %s" % exc, "discovery")
        model_path = ctx.model.save(self.args.out, apkinfo)
        print("[apktester] application model: %s" % model_path)
        # choose flows
        seq = (only_flows or flows_extra.mode_flow_sequence(cfg.mode, cfg))
        # SMOKE still needs model even without probe (canvas-app aware)
        for name in seq:
            fn = (flows_core.FLOW_NAMES.get(name)
                  or flows_extra.FLOW_NAMES.get(name))
            if fn is None:
                print("[apktester] unknown flow %s — skipped" % name)
                continue
            if not ctx.budget_left:
                ctx.finding("info", "budget", "test budget exhausted; remaining "
                            "flows skipped", "budget")
                break
            print("[apktester] flow: %s" % name)
            try:
                res = fn(ctx)
            except Exception as exc:
                res = FlowResult(name, status="failed")
                res.notes.append("flow crashed: %r" % exc)
                ctx.finding("major", "flow-error", "%s raised %r" % (name, exc), name)
                diagnostics.collect_failure(ctx, name)
            trace.add({"flow": name, "status": res.status, "notes": res.notes})
            if res.status == "failed":
                diagnostics.collect_failure(ctx, name)
            results.append(res.to_dict())
            print("[apktester]   -> %s %s" % (res.status, "; ".join(res.notes)[:140]))
        self.monitor_events_cache = monitor.event_dicts()
        self._last_crash_text = monitor.snapshot_tail(800)
        monitor.stop()
        # final liveness + crash scan
        alive = bool(adb.pidof(apkinfo.package))
        if not alive:
            ctx.finding("critical", "process-death", "app process dead at session end",
                        "final")
        final = FlowResult("final-liveness",
                           status="passed" if alive else "failed")
        final.notes.append("alive=%s" % alive)
        results.append(final.to_dict())
        self._apk_dict = apkinfo.to_dict()
        return results

    def _summarize(self, results, autofix_logs, attempts):
        summary = reporting.summarize(self.ctx, results,
                                      self.monitor_events_cache)
        summary["auto_fix_attempts"] = attempts
        summary["regression"] = ["tools/apk-tester/tests (unit)",
                                 "flow_launch", "flow_lifecycle_core"]
        if autofix_logs:
            last = autofix_logs[-1]
            summary["autofix"] = last["rca"]
        apk_dict = getattr(self, "_apk_dict", {})
        md = reporting.render_report(
            summary, apk_dict,
            autofix_log={"proposals": sum([l["proposals"] for l in autofix_logs], [])}
            if autofix_logs else None)
        spath, rpath = reporting.write_session(self.args.out, summary, apk_dict, md)
        print("[apktester] report: %s" % rpath)
        print("[apktester] summary: %s" % spath)
        return summary


def cfg_install_timeout():
    from .config import INSTALL_TIMEOUT
    return INSTALL_TIMEOUT


def main(argv=None):
    p = argparse.ArgumentParser(prog="apktester",
                                description="Universal APK autonomous tester")
    p.add_argument("--apk", required=True, help="APK file or directory of APKs")
    p.add_argument("--mode", default="SMOKE", choices=MODES)
    p.add_argument("--out", default="artifacts")
    p.add_argument("--serial", default=None)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--repo", default=None, help="source checkout for RCA/autofix")
    p.add_argument("--build-cmd", default=None,
                   help="shell command that rebuilds the release APK")
    p.add_argument("--apk-dir", default=None,
                   help="directory scanned for the rebuilt APK")
    p.add_argument("--autofix", action="store_true")
    p.add_argument("--max-repair-attempts", type=int, default=5)
    p.add_argument("--prefer-abi", default="x86_64")
    p.add_argument("--flows", default=None,
                   help="comma-separated flow subset (replay/regression)")
    p.add_argument("--gate-verify", action="store_true", default=True)
    args = p.parse_args(argv)
    if args.flows:
        args._flows_list = args.flows.split(",")
    os.environ.setdefault("APKTEST_COMMIT", os.environ.get("GITHUB_SHA", ""))
    r = Runner(args)
    if args.flows:
        orig = r._test_once
        r._test_once = lambda apk, adb, only_flows=None: orig(
            apk, adb, only_flows=args.flows.split(",") if only_flows is None else only_flows)
    try:
        return r.run()
    except DeviceError as exc:
        print("FATAL device error: %s" % exc)
        return 2


if __name__ == "__main__":
    sys.exit(main())
