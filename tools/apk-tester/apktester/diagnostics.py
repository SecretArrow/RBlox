"""Failure diagnostics collection (spec 19).

On any failure: logcat, screenshot, UI hierarchy, stack trace, ANR traces,
tombstones, dumpsys snapshots, memory/CPU, action trace, APK metadata —
stored under the standard artifacts/ tree.
"""
import glob
import json
import os
import re
import time

SUBDIRS = ("apk", "logs", "screenshots", "traces", "crashes", "anr", "reports")


def ensure_tree(root):
    for d in SUBDIRS:
        os.makedirs(os.path.join(root, d), exist_ok=True)
    return root


def save_json(path, obj):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, default=str)


def collect_failure(ctx, where, extra=None):
    """Collect a full diagnostic bundle for one failure. Returns bundle path."""
    ts = time.strftime("%Y%m%d-%H%M%S")
    tag = "%s-%s" % (ts, re.sub(r"[^A-Za-z0-9_.-]", "_", where)[:40])
    bundle = ensure_tree(os.path.join(ctx.out_dir))
    adb = ctx.adb
    pkg = ctx.package
    out = {"where": where, "ts": ts, "package": pkg}

    # screenshot
    try:
        shot = os.path.join(bundle, "screenshots", "failure-%s.png" % tag)
        adb.screencap(shot)
        out["screenshot"] = shot
    except Exception:
        pass
    # UI hierarchy
    try:
        xml = adb.uidump(timeout=15)
        if xml:
            p = os.path.join(bundle, "traces", "uidump-%s.xml" % tag)
            with open(p, "w", encoding="utf-8") as f:
                f.write(xml)
            out["uidump"] = p
    except Exception:
        pass
    # logcat snapshots
    for buf in ("crash", "main", "events"):
        try:
            txt = adb.logcat(buffer=buf, lines=1500, timeout=30)
            p = os.path.join(bundle, "logs", "logcat-%s-%s.txt" % (buf, tag))
            with open(p, "w", encoding="utf-8", errors="replace") as f:
                f.write(txt)
            out["logcat_%s" % buf] = p
        except Exception:
            pass
    # stack trace extraction
    try:
        crash_txt = adb.logcat(buffer="crash", lines=1200, timeout=25)
        stack = extract_fatal(crash_txt)
        if stack:
            p = os.path.join(bundle, "crashes", "stack-%s.txt" % tag)
            with open(p, "w", encoding="utf-8") as f:
                f.write(stack)
            out["stack"] = p
    except Exception:
        pass
    # ANR traces + tombstones (needs root; best effort)
    try:
        anrs = sorted(glob.glob("/data/anr/*.txt")) if adb.root() else []
        # pull via adb root shell ls
    except Exception:
        anrs = []
    try:
        r = adb.shell("ls -t /data/anr/ 2>/dev/null | head -3", timeout=15)
        files = [f.strip() for f in r.splitlines() if f.strip().endswith(("txt", "trace"))]
        for i, fn in enumerate(files):
            dst = os.path.join(bundle, "anr", "anr-%s-%d" % (tag, i))
            if adb.pull("/data/anr/%s" % fn, dst):
                out.setdefault("anr", []).append(dst)
    except Exception:
        pass
    try:
        r = adb.shell("ls -t /data/tombstones/ 2>/dev/null | head -3", timeout=15)
        files = [f.strip() for f in r.splitlines() if f.strip().startswith("tombstone")]
        for i, fn in enumerate(files[:2]):
            dst = os.path.join(bundle, "crashes", "%s-%d" % (fn, i))
            if adb.pull("/data/tombstones/%s" % fn, dst):
                out.setdefault("tombstones", []).append(dst)
    except Exception:
        pass
    # dumpsys snapshots
    for section, short in (("activity", "activity"), ("package %s" % pkg, "package"),
                           ("meminfo %s" % pkg, "meminfo"), ("cpuinfo", "cpuinfo")):
        try:
            txt = adb.dumpsys(section, timeout=25)
            p = os.path.join(bundle, "reports", "dumpsys-%s-%s.txt" % (short, tag))
            with open(p, "w", encoding="utf-8", errors="replace") as f:
                f.write(txt[-200000:])
        except Exception:
            pass
    # action trace copy
    if ctx.recorder and ctx.recorder.path and os.path.exists(ctx.recorder.path):
        out["action_trace"] = ctx.recorder.path
    # apk metadata
    try:
        save_json(os.path.join(bundle, "apk", "apk-metadata.json"),
                  ctx.apkinfo.to_dict())
    except Exception:
        pass
    if extra:
        out.update(extra)
    save_json(os.path.join(bundle, "reports", "failure-%s.json" % tag), out)
    return out


def extract_fatal(log_text):
    """Return the FATAL EXCEPTION / Fatal signal section if present."""
    for needle in ("FATAL EXCEPTION", "Fatal signal", "ANR in "):
        idx = log_text.find(needle)
        if idx >= 0:
            return "\n".join(log_text[idx:].splitlines()[:80])
    return ""
