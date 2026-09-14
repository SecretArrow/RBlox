"""Live crash / ANR / freeze detection from logcat streams.

Streams main+system+crash and events buffers in background threads, matching
every line against a detector table. Ground truth for 'app died' remains
pidof checks performed by the flows; logcat provides the evidence.
"""
import os
import re
import subprocess
import threading
import time


class Event:
    __slots__ = ("kind", "severity", "ts", "line", "context", "package_match")

    def __init__(self, kind, severity, ts, line, context="", package_match=None):
        self.kind = kind
        self.severity = severity
        self.ts = ts
        self.line = line.strip()
        self.context = context
        self.package_match = package_match

    def to_dict(self):
        return {"kind": self.kind, "severity": self.severity, "ts": self.ts,
                "line": self.line, "context": self.context[-2000:],
                "package_match": self.package_match}


DETECTORS = [
    ("fatal_exception", re.compile(r"FATAL EXCEPTION"), "critical"),
    ("android_runtime", re.compile(r"AndroidRuntime:"), "critical"),
    ("native_fatal", re.compile(r"Fatal signal \d+ \((SIG(SEGV|ABRT|BUS|ILL|FPE|TRAP))\)"), "critical"),
    ("tombstone", re.compile(r"Process .* has died.*tombstone"), "critical"),
    ("anr", re.compile(r"ANR in |ANR key dispatch timed out|Input dispatching timed out"), "critical"),
    ("am_crash", re.compile(r"\bam_crash\b"), "critical"),
    ("am_anr", re.compile(r"\bam_anr\b"), "critical"),
    ("force_finish", re.compile(r"Force finishing activity"), "warning"),
    ("oom", re.compile(r"java\.lang\.OutOfMemoryError"), "critical"),
    ("died", re.compile(r"Process .+ \(pid \d+\) has died"), "warning"),
    ("godot_fatal", re.compile(r"FATAL:", re.I), "critical"),
    ("godot_error", re.compile(r"\bgodot.*\b(ERROR|SCRIPT ERROR)\b", re.I), "warning"),
    ("godot_script", re.compile(r"SCRIPT ERROR"), "warning"),
]


class CrashMonitor:
    """Background logcat watchers. poll() returns new app-relevant events."""

    def __init__(self, adb, package, out_dir):
        self.adb = adb
        self.package = package
        self.out_dir = out_dir
        self.events = []
        self._lock = threading.Lock()
        self._procs = []
        self._threads = []
        self._stop = threading.Event()
        os.makedirs(out_dir, exist_ok=True)

    # ------------------------------------------------------------------
    def start(self):
        for name, args in (
                ("main", ["logcat", "-v", "threadtime", "-b", "main,system,crash"]),
                ("events", ["logcat", "-v", "time", "-b", "events"])):
            fh = open(os.path.join(self.out_dir, "logcat-%s.log" % name), "ab")
            try:
                p = subprocess.Popen(["adb", "-s", self.adb.serial] + args,
                                     stdout=fh, stderr=subprocess.DEVNULL,
                                     stdin=subprocess.DEVNULL)
            except Exception:
                fh.close()
                continue
            self._procs.append(p)
            t = threading.Thread(target=self._reader, args=(p, fh, name == "events"),
                                 daemon=True)
            self._threads.append(t)
            t.start()

    def _reader(self, proc, fh, is_events):
        tail = []
        while not self._stop.is_set():
            line = proc.stdout.readline() if hasattr(proc.stdout, "readline") else b""
            if not line:
                if proc.poll() is not None:
                    break
                time.sleep(0.2)
                continue
            text = line.decode("utf-8", "replace").rstrip()
            tail.append(text)
            if len(tail) > 40:
                tail.pop(0)
            for kind, rx, sev in DETECTORS:
                if rx.search(text):
                    ctx = "\n".join(tail)
                    pm = self.package in text or self.package in ctx
                    # demote unrelated system crashes to warnings
                    if sev == "critical" and not pm and kind in (
                            "android_runtime", "died", "force_finish", "fatal_exception"):
                        sev = "warning"
                    ev = Event(kind, sev, time.time(), text, ctx, pm)
                    with self._lock:
                        self.events.append(ev)
                    break
        fh.close()

    # ------------------------------------------------------------------
    def poll(self, kinds=None, since=0):
        with self._lock:
            new = self.events[since:]
            return len(self.events), [e for e in new
                                      if kinds is None or e.kind in kinds]

    def all_events(self, severity=None):
        with self._lock:
            return [e for e in self.events
                    if severity is None or e.severity == severity]

    def has_critical(self, package_scoped=True, since=0):
        with self._lock:
            for e in self.events:
                if (e.ts >= since and e.severity == "critical"
                        and (not package_scoped or e.package_match)):
                    return e
        return None

    def crash_events(self):
        """Critical events that look like real app crashes/ANRs."""
        evs = self.all_events("critical")
        return [e for e in evs if e.package_match or e.kind in (
            "fatal_exception", "native_fatal", "anr", "am_crash", "am_anr", "oom")]

    def snapshot_tail(self, lines=400):
        try:
            return self.adb.logcat(buffer="crash", lines=lines)
        except Exception:
            return ""

    def stop(self):
        self._stop.set()
        for p in self._procs:
            try:
                p.terminate()
            except Exception:
                pass
        for t in self._threads:
            t.join(timeout=3)

    def event_dicts(self):
        with self._lock:
            return [e.to_dict() for e in self.events]


def extract_stack(log_text, needle="FATAL EXCEPTION"):
    """Return the crash section (needle + following ~70 lines) from a log."""
    idx = log_text.find(needle)
    if idx < 0:
        return ""
    return "\n".join(log_text[idx:].splitlines()[:70])
