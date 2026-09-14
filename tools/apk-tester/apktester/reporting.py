"""Report generation: release-test-report.md, summary.json, release gate.

The gate is the single source of truth for 'may this APK ship?'
"""
import glob
import json
import os
import time


def summarize(ctx, results, monitor_events, session_extra=None):
    """Build summary dict from a finished test session."""
    crit = [f for f in ctx.findings if f["severity"] == "critical"]
    major = [f for f in ctx.findings if f["severity"] == "major"]
    minor = [f for f in ctx.findings if f["severity"] == "minor"]
    warnings = [f for f in ctx.findings if f["severity"] in ("warning", "info")]
    crashes = [e for e in monitor_events
               if e["kind"] in ("fatal_exception", "native_fatal", "am_crash",
                                "oom", "godot_fatal")]
    anrs = [e for e in monitor_events if e["kind"] in ("anr", "am_anr")]
    failed = [r for r in results if r["status"] == "failed"]
    warned = [r for r in results if r["status"] == "warned"]
    tested = [r for r in results if r["status"] in ("passed", "failed", "warned")]
    status = "FAIL" if failed else ("WARN" if (warned or major) else "PASS")
    if crit and status != "FAIL":
        status = "FAIL"
    gate_ok = (not failed) and (not crit) and (not anrs)
    if ctx.cfg.strict and (major or (minor and len(minor) > 3)):
        gate_ok = False
    return {
        "mode": ctx.cfg.mode,
        "status": status,
        "gate": "RELEASE" if gate_ok else "DO_NOT_RELEASE",
        "package": ctx.package,
        "device": ctx.adb.info(),
        "config": ctx.cfg.to_dict(),
        "actions_executed": ctx.actions,
        "feature_discovery": {
            "discovered": len(ctx.model.features) + len(ctx.model.screens),
            "screens": len(ctx.model.screens),
            "features": sorted(ctx.model.features),
            "tested": len(tested), "passed": len([r for r in tested if r["status"] == "passed"]),
            "failed": len(failed),
        },
        "counts": {"crashes": len(crashes), "anrs": len(anrs),
                   "critical": len(crit), "major": len(major),
                   "minor": len(minor), "warnings": len(warnings)},
        "findings": ctx.findings,
        "flows": results,
        "monitor_events": monitor_events[:200],
        "remaining_problems": [f["detail"] for f in (crit + major + minor)],
        "recommendation": "RELEASE" if gate_ok else "DO_NOT_RELEASE",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }


def render_report(summary, apk_dict, autofix_log=None):
    """Render release-test-report.md exactly to the spec's section list."""
    s = summary
    fd = s.get("feature_discovery", {})
    c = s.get("counts", {})
    flows = s.get("flows", [])
    lines = []
    a = lines.append
    a("# Release Test Report")
    a("")
    a("| | |")
    a("|---|---|")
    a("| Application | %s |" % (apk_dict.get("label") or apk_dict.get("package", "?")))
    a("| Package | `%s` |" % s.get("package", "?"))
    a("| Version | %s (code %s) |" % (apk_dict.get("version_name"),
                                      apk_dict.get("version_code")))
    a("| Commit | %s |" % os.environ.get("APKTEST_COMMIT", "n/a"))
    a("| APK | `%s` (%.1f MB, sha256 %s...) |"
      % (os.path.basename(apk_dict.get("path", "")),
         (apk_dict.get("size") or 0) / 1e6, (apk_dict.get("sha256") or "")[:12]))
    a("| Android API | %s |" % s.get("device", {}).get("api_level", "?"))
    a("| Device | %s %s (%s) |" % (s.get("device", {}).get("brand", ""),
                                   s.get("device", {}).get("model", ""),
                                   s.get("device", {}).get("serial", "")))
    a("| Mode | %s |" % s.get("mode"))
    a("| **Summary** | **%s** |" % s.get("status"))
    a("")
    a("## Feature Discovery")
    a("")
    a("- Discovered: %s (screens: %s)" % (fd.get("discovered", 0), fd.get("screens", 0)))
    a("- Features: %s" % ", ".join(fd.get("features", [])) or "none")
    a("- Tested: %s — Passed: %s — Failed: %s" % (fd.get("tested", 0),
                                                  fd.get("passed", 0),
                                                  fd.get("failed", 0)))
    a("")
    a("## Flows")
    a("")
    a("| Flow | Status | Notes |")
    a("|---|---|---|")
    for f in flows:
        notes = "; ".join(f.get("notes", []))[:160]
        a("| %s | %s | %s |" % (f.get("flow"), f.get("status"),
                                notes.replace("|", "/")))
    a("")
    a("## Crashes: %s" % c.get("crashes", 0))
    a("")
    a("## ANR: %s" % c.get("anrs", 0))
    a("")
    for section in ("Lifecycle", "Permissions", "Network", "Persistence", "Visual",
                    "Random Exploration"):
        a("## %s" % section)
        a("")
        sec = [f for f in flows if section.split()[0].lower() in f.get("flow", "")]
        if sec:
            for f in sec:
                a("- %s: %s — %s" % (f["flow"], f["status"],
                                     "; ".join(f.get("notes", []))[:200]))
        else:
            a("- not exercised in this mode")
        a("")
    a("## Findings")
    a("")
    for f in s.get("findings", [])[:40]:
        a("- **[%s]** %s (%s): %s" % (f["severity"], f["kind"], f.get("flow", ""),
                                      f["detail"][:220]))
    if not s.get("findings"):
        a("- none")
    a("")
    a("## Auto Fixes")
    a("")
    if autofix_log:
        for p in autofix_log.get("proposals", []):
            a("- %s: %s (applied=%s) — %s" % (p.get("fixer"), p.get("desc"),
                                              p.get("applied"),
                                              (p.get("error") or "ok")[:120]))
    else:
        a("- none")
    a("")
    a("## Regression Tests")
    a("")
    a("- CI functional tests: `%s`" % ", ".join(s.get("regression", ["none"])))
    a("")
    a("## Remaining Problems")
    a("")
    if s.get("remaining_problems"):
        for p in s["remaining_problems"][:20]:
            a("- %s" % p[:250])
    else:
        a("- none")
    a("")
    a("## Final Recommendation")
    a("")
    a("**%s**" % s.get("recommendation"))
    a("")
    return "\n".join(lines)


def write_session(out_dir, summary, apk_dict, report_md):
    ensure = os.path.join(out_dir, "reports")
    os.makedirs(ensure, exist_ok=True)
    spath = os.path.join(ensure, "summary.json")
    with open(spath, "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "apk": apk_dict}, f, indent=2, default=str)
    rpath = os.path.join(out_dir, "release-test-report.md")
    with open(rpath, "w", encoding="utf-8") as f:
        f.write(report_md)
    return spath, rpath


# ---------------------------------------------------------------------------
def gate_merge(root, out_dir):
    """Merge summary.json files from all matrix runs -> gate.json + report."""
    os.makedirs(out_dir, exist_ok=True)
    summaries = []
    for p in sorted(glob.glob(os.path.join(root, "**", "summary.json"),
                              recursive=True)):
        try:
            with open(p, "r", encoding="utf-8") as f:
                summaries.append(json.load(f))
        except Exception:
            pass
    gate = {
        "runs": len(summaries),
        "status": "PASS" if summaries else "UNKNOWN",
        "gate": "RELEASE" if summaries else "DO_NOT_RELEASE",
        "runs_detail": [],
    }
    for s in summaries:
        gate["runs_detail"].append({
            "mode": s.get("summary", {}).get("mode"),
            "device": s.get("summary", {}).get("device"),
            "status": s.get("summary", {}).get("status"),
            "gate": s.get("summary", {}).get("gate"),
            "crashes": s.get("summary", {}).get("counts", {}).get("crashes"),
            "anrs": s.get("summary", {}).get("counts", {}).get("anrs"),
        })
        if s.get("summary", {}).get("gate") != "RELEASE":
            gate["gate"] = "DO_NOT_RELEASE"
            gate["status"] = "FAIL"
    if not summaries:
        gate["gate"] = "DO_NOT_RELEASE"
        gate["status"] = "FAIL"
        gate["reason"] = "no summaries found (test job crashed?)"
    with open(os.path.join(out_dir, "gate.json"), "w", encoding="utf-8") as f:
        json.dump(gate, f, indent=2)
    # merged human report
    md = ["# Universal APK Test — Release Gate", "",
          "Gate: **%s** (runs: %d)" % (gate["gate"], gate["runs"]), ""]
    for r in gate["runs_detail"]:
        md.append("- API %s: status=%s gate=%s crashes=%s anrs=%s"
                  % (r.get("device", {}).get("api_level"), r.get("status"),
                     r.get("gate"), r.get("crashes"), r.get("anrs")))
    # attach the richest report body if present
    reports = sorted(glob.glob(os.path.join(root, "**", "release-test-report.md"),
                               recursive=True))
    if reports:
        try:
            with open(reports[-1], "r", encoding="utf-8") as f:
                md.append("\n---\n\n" + f.read())
        except Exception:
            pass
    with open(os.path.join(out_dir, "release-test-report.md"), "w",
              encoding="utf-8") as f:
        f.write("\n".join(md))
    return gate


if __name__ == "__main__":
    import sys
    root = sys.argv[sys.argv.index("--root") + 1] if "--root" in sys.argv else "."
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "gate"
    g = gate_merge(root, out)
    print("GATE=%s" % g["gate"])
    sys.exit(0 if g["gate"] == "RELEASE" else 1)
