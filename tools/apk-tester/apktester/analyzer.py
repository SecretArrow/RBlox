"""Source-level root cause analysis (spec 20).

Correlates runtime failures (stack traces, engine error logs, install
failures) with source files in the repository. Produces a structured
root-cause-analysis.json consumed by the fixer layer. Honest by design: when
nothing can be attributed, it says so instead of guessing a patch location.
"""
import json
import os
import re


class Frame:
    __slots__ = ("file", "line", "symbol", "kind", "repo_path")

    def __init__(self, file, line, symbol, kind, repo_path=None):
        self.file = file
        self.line = line
        self.symbol = symbol
        self.kind = kind
        self.repo_path = repo_path

    def to_dict(self):
        return {"file": self.file, "line": self.line, "symbol": self.symbol,
                "kind": self.kind, "repo_path": self.repo_path}


JAVA_FRAME = re.compile(
    r"\bat ([\w$.]+)\.([\w$<>]+)\(([\w$.]+\.(?:java|kt|kts)):?(\d+)?\)")
NATIVE_FRAME = re.compile(r"#\d+ pc \d+ (\S+)")
GODOT_AT = re.compile(r"at:\s*([\w<>.]+)\s*\((res://[^)]+?\.gd):(\d+)\)")
GODOT_SCRIPT_ERR = re.compile(r"SCRIPT ERROR:\s*(.+)", )

STRATEGIES = {
    "null-instance": "godot-null-guard",
    "java-npe": "report-only",
    "native": "report-only",
    "install-exported": "manifest-exported",
    "missing-permission": "manifest-permission",
    "unknown": "manual",
}


class RCA:
    def __init__(self):
        self.kind = "unknown"
        self.exception = None
        self.message = ""
        self.frames = []
        self.strategy = STRATEGIES["unknown"]
        self.evidence = []
        self.confidence = 0.0
        self.fixable = False

    def to_dict(self):
        return {"kind": self.kind, "exception": self.exception,
                "message": self.message[:400],
                "frames": [f.to_dict() for f in self.frames],
                "strategy": self.strategy, "evidence": self.evidence,
                "confidence": self.confidence, "fixable": self.fixable}


def _map_repo(repo_root, path):
    """Map a source path (java path, res://, or filename) into the repo."""
    if not repo_root:
        return None
    cands = []
    if path.startswith("res://"):
        cands.append(os.path.join(repo_root, path[len("res://"):]))
    base = os.path.basename(path.replace("res://", ""))
    if base:
        for root, _dirs, files in os.walk(repo_root):
            if base in files and ".git" not in root:
                cands.append(os.path.join(root, base))
                if len(cands) > 4:
                    break
    for c in cands:
        if os.path.exists(c):
            return c
    return None


def analyze(events, log_text, install_error, repo_root):
    """Build the best RCA from available evidence.

    events     : monitor.Event list (crash/anr/godot errors)
    log_text   : logcat crash buffer dump (str)
    install_error: adb install stderr/stdout when install failed (str)
    repo_root  : checkout of the app source (or None)
    """
    rca = RCA()
    # --- install failures (manifest/gradle class) -------------------------
    if install_error:
        msg = install_error[:500]
        rca.evidence.append("install: %s" % msg)
        if "exported" in msg.lower() or "targeting s+" in msg.lower():
            rca.kind = "install-exported"
            rca.strategy = STRATEGIES["install-exported"]
            rca.fixable = True
            rca.confidence = 0.9
            return rca
        if "install_failed_update_incompatible" in msg.lower():
            rca.kind = "signature-conflict"
            rca.message = msg
            return rca
    # --- crash stack --------------------------------------------------------
    stack = log_text or ""
    if not stack and events:
        stack = "\n".join(e.context for e in events if e.context)
    if "FATAL EXCEPTION" in stack or "AndroidRuntime" in stack:
        rca.kind = "java-crash"
        m = re.search(r"([\w$.]+(?:Exception|Error))[:\s]?([^\n]*)", stack)
        if m:
            rca.exception = m.group(1)
            rca.message = m.group(2).strip()[:200]
        for fm in JAVA_FRAME.finditer(stack):
            f = Frame(fm.group(3), int(fm.group(4) or 0), "%s.%s" % (fm.group(1), fm.group(2)),
                      "java")
            f.repo_path = _map_repo(repo_root, f.file) if repo_root else None
            rca.frames.append(f)
            if len(rca.frames) >= 12:
                break
        if rca.exception and "NullPointer" in rca.exception:
            rca.strategy = STRATEGIES["java-npe"]
            rca.kind = "java-npe"
            rca.confidence = 0.6
        if rca.frames and rca.frames[0].repo_path:
            rca.confidence = max(rca.confidence, 0.7)
        if "SecurityException" in (rca.exception or ""):
            rca.kind = "missing-permission"
            rca.strategy = STRATEGIES["missing-permission"]
            rca.fixable = True
            rca.confidence = 0.85
            perm = re.search(r"android\.permission\.[A-Z_]+", stack)
            rca.message = perm.group(0) if perm else rca.message
    elif "Fatal signal" in stack:
        rca.kind = "native-crash"
        rca.message = stack.splitlines()[0][:200]
        for fm in NATIVE_FRAME.finditer(stack):
            f = Frame(fm.group(1), 0, "", "native")
            f.repo_path = _map_repo(repo_root, os.path.basename(f.file)) if repo_root else None
            rca.frames.append(f)
            if len(rca.frames) >= 8:
                break
        rca.confidence = 0.5
    elif "ANR" in stack:
        rca.kind = "anr"
        rca.message = stack.splitlines()[0][:200]
        rca.confidence = 0.6
    # --- Godot script errors (first-class: the engine prints file:line) -----
    godot_at = None
    for src in (stack,):
        for m in GODOT_AT.finditer(src):
            godot_at = m
    if godot_at is None and events:
        for e in events:
            m = GODOT_AT.search(e.context or "")
            if m:
                godot_at = m
                break
    if godot_at is not None and not rca.frames:
        f = Frame(godot_at.group(2), int(godot_at.group(3)), godot_at.group(1), "godot")
        f.repo_path = _map_repo(repo_root, f.file) if repo_root else None
        rca.frames.append(f)
        rca.kind = rca.kind if rca.kind != "unknown" else "godot-script-error"
        if rca.kind == "godot-script-error":
            ctx_line = ""
            for e in events:
                if "SCRIPT ERROR" in (e.context or ""):
                    m = GODOT_SCRIPT_ERR.search(e.context)
                    if m:
                        ctx_line = m.group(1)
                        break
            rca.message = ctx_line or "SCRIPT ERROR near %s:%s" % (f.file, f.line)
            if re.search(r"null instance|previously freed", rca.message, re.I):
                rca.strategy = STRATEGIES["null-instance"]
                rca.fixable = True
                rca.confidence = 0.8
    rca.evidence.append("logcat-scan: %d chars analysed" % len(stack))
    return rca


def save(rca, out_dir):
    path = os.path.join(out_dir, "reports", "root-cause-analysis.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(rca.to_dict(), fh, indent=2)
    return path
