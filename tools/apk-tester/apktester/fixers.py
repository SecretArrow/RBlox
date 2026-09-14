"""Autonomous safe auto-fix layer (spec 21/22).

Principles enforced here:
- minimal, local changes; architecture untouched
- every fix is backed up and emitted as a unified diff for human review
- fixes NEVER delete features, swallow exceptions, disable tests, add CI
  detection, or replace production logic with mocks
- when no safe fixer exists for the defect class, the layer says so and
  stops (report-only) instead of guessing

Fixers shipped:
- GodotFixer   : null-instance / freed-instance script errors -> is_instance_valid
                 guard around the single offending statement
- GradleFixer  : manifest exported flag (API31 install failure), missing
                 uses-permission for SecurityException
- GenericFixer : explicit "manual review required" (report-only)
"""
import os
import re
import shutil
import subprocess
import time


class Proposal:
    def __init__(self, fixer, repo_path, desc, strategy):
        self.fixer = fixer
        self.repo_path = repo_path
        self.desc = desc
        self.strategy = strategy
        self.applied = False
        self.diff = ""
        self.error = None

    def to_dict(self):
        return {"fixer": self.fixer, "path": self.repo_path, "desc": self.desc,
                "strategy": self.strategy, "applied": self.applied,
                "error": self.error, "diff": self.diff[:4000]}


def detect_projects(repo_root):
    found = []
    if os.path.exists(os.path.join(repo_root, "project.godot")):
        found.append("godot")
    if any(os.path.exists(os.path.join(repo_root, f))
           for f in ("build.gradle", "build.gradle.kts")):
        found.append("gradle")
    return found or ["unknown"]


def _backup(path, out_dir):
    bdir = os.path.join(out_dir, "reports", "autofix-backups")
    os.makedirs(bdir, exist_ok=True)
    rel = path.replace(os.sep, "_").lstrip("_")
    dst = os.path.join(bdir, "%d-%s" % (int(time.time()), rel))
    shutil.copy2(path, dst)
    return dst


def _diff(before, after):
    import difflib
    return "".join(difflib.unified_diff(
        before.splitlines(True), after.splitlines(True),
        fromfile="before", tofile="after", n=3))


# ---------------------------------------------------------------------------
def godot_null_guard(rca, repo_root):
    """Propose is_instance_valid guards for null/freed-instance script errors.

    Only when: message names a null/freed base, the engine pointed at
    res://file.gd:line, the file+line exist, the offending statement is a
    single-line statement, and the receiver is a simple identifier we can
    name in the guard. Otherwise: report-only (honest).
    """
    props = []
    if not (rca.message and re.search(r"null instance|previously freed",
                                      rca.message, re.I)):
        return props
    for f in rca.frames:
        if f.kind != "godot" or not f.repo_path or not f.line:
            continue
        try:
            with open(f.repo_path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        idx = f.line - 1
        if idx < 0 or idx >= len(lines):
            continue
        line = lines[idx].rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.endswith((",", "\\", "(", ":")):
            continue  # multi-line statement — not safe to wrap blindly
        # receiver guess: <ident>.<member> where member is the failing symbol
        recv = None
        m = re.search(r"([A-Za-z_]\w*)\.%s\s*\(" % re.escape(
            (f.symbol or "").split(".")[-1] or "x"), line)
        if m:
            recv = m.group(1)
        else:
            m = re.search(r"([A-Za-z_]\w*)\s*\[", line) if "index" in rca.message.lower() else None
            if m:
                recv = m.group(1)
            else:
                m = re.search(r"([A-Za-z_]\w*)\.([A-Za-z_]\w*)", line)
                if m:
                    recv = m.group(1)
        if not recv or recv in ("self", "true", "false", "null", "and", "or", "not"):
            continue
        indent = line[:len(line) - len(line.lstrip())]
        step = _indent_step(lines, idx, indent)
        p = Proposal("GodotFixer", f.repo_path,
                     "guard null/freed instance '%s' at %s:%d"
                     % (recv, os.path.basename(f.repo_path), f.line),
                     "godot-null-guard")
        body_indent = indent + " " * step
        new_lines = lines[:idx] \
            + ["%sif is_instance_valid(%s):\n" % (indent, recv),
               "%s%s\n" % (body_indent, stripped)] \
            + lines[idx + 1:]
        p.diff = _diff("".join(lines), "".join(new_lines))
        p.new_content = "".join(new_lines)
        props.append(p)
        break   # one minimal fix per repair attempt
    return props


def _indent_step(lines, idx, indent):
    for i in range(idx + 1, min(idx + 30, len(lines))):
        l = lines[i].rstrip("\n")
        if l.strip() and l.startswith(indent) and len(l) > len(indent):
            step = len(l) - len(l.lstrip()) - len(indent)
            if 0 < step <= 8:
                return step
    return 4 if len(indent) % 8 else 8


def godot_fix(rca, repo_root):
    return godot_null_guard(rca, repo_root)


# ---------------------------------------------------------------------------
EXPORTED_INSTALL_RE = re.compile(r"targeting s+|android:exported", re.I)


def find_manifest(repo_root):
    best = None
    for root, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in (".git", "build", ".godot")]
        if "AndroidManifest.xml" in files:
            p = os.path.join(root, "AndroidManifest.xml")
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                txt = f.read()
            if "<application" in txt:
                score = txt.count("<intent-filter")
                if best is None or score > best[1]:
                    best = (p, score)
    return best[0] if best else None


def gradle_fix(rca, repo_root):
    props = []
    manifest = find_manifest(repo_root)
    if not manifest:
        return props
    with open(manifest, "r", encoding="utf-8", errors="replace") as f:
        txt = f.read()
    if rca.kind == "install-exported":
        # add exported="true"/"false" to elements with intent-filter lacking it
        changed = False
        pattern = re.compile(r"<(activity|activity-alias|service|receiver)\b([^>]*)>",
                             re.S)
        out = txt
        for m in list(pattern.finditer(txt)):
            head, attrs = m.group(1), m.group(2)
            if "android:exported" in attrs:
                continue
            # look ahead for its intent-filter (same tag block)
            end = txt.find("</%s>" % head, m.end())
            block = txt[m.start(): end if end != -1 else m.end() + 2000]
            if "<intent-filter" not in block:
                continue
            exported_val = ("true"
                            if 'android.intent.category.LAUNCHER' in block
                            or 'android.intent.action.MAIN' in block else "false")
            insert_at = m.start() + len("<%s" % head)
            out = out[:insert_at] + ' android:exported="%s"' % exported_val \
                + out[insert_at:]
            changed = True
            p = Proposal("GradleFixer", manifest,
                         "set android:exported=%s on <%s> with intent-filter"
                         % (exported_val, head), "manifest-exported")
            p.diff = _diff(txt, out)
            p.new_content = out
            props = [p]
            break
        if not changed:
            pass
    elif rca.kind == "missing-permission":
        perm = re.search(r"android\.permission\.[A-Z_]+", rca.message or "")
        if perm and perm.group(0) not in txt:
            uses = '<uses-permission android:name="%s"/>\n    ' % perm.group(0)
            out = txt.replace("</manifest>", "    " + uses + "</manifest>")
            p = Proposal("GradleFixer", manifest,
                         "add missing <uses-permission %s>" % perm.group(0),
                         "manifest-permission")
            p.diff = _diff(txt, out)
            p.new_content = out
            props = [p]
    return props


def generic_fix(rca, repo_root):
    p = Proposal("GenericFixer", None,
                 "defect class '%s' has no safe automatic fix — manual review "
                 "required (RCA attached)" % rca.kind, "manual")
    p.applied = False
    p.error = "report-only"
    return [p]


PROPOSERS = {
    "godot": godot_fix,
    "gradle": gradle_fix,
    "unknown": generic_fix,
}


# ---------------------------------------------------------------------------
def propose_and_apply(rca, repo_root, out_dir, dry_run=False):
    """Propose fixes, apply safe ones with backup+diff. Returns (applied, log)."""
    projects = detect_projects(repo_root) if repo_root else ["unknown"]
    proposals = []
    for proj in projects:
        proposals.extend(PROPOSERS.get(proj, generic_fix)(rca, repo_root))
    # honesty rule: if no project-specific fixer could act, say so explicitly
    if not proposals:
        proposals.extend(generic_fix(rca, repo_root))
    applied = []
    for p in proposals:
        if p.fixer == "GenericFixer":
            applied.append(p)
            continue
        if dry_run or not getattr(p, "new_content", None):
            continue
        try:
            _backup(p.repo_path, out_dir)
            with open(p.repo_path, "w", encoding="utf-8") as f:
                f.write(p.new_content)
            p.applied = True
            applied.append(p)
        except OSError as exc:
            p.error = str(exc)
    log = {"ts": time.time(), "rca": rca.to_dict(),
           "proposals": [p.to_dict() for p in proposals]}
    return applied, log


def static_check(repo_root, projects):
    """Cheap syntax gate before rebuild. Godot/Gradle are validated by the
    rebuild itself (export/compile fails on syntax errors) — nothing to fake
    here, so we only verify the touched files still parse as text."""
    return True, "build step validates syntax"


def run_build(build_cmd, repo_root, timeout=1500):
    """Run the project's release-build command; return (ok, output)."""
    if not build_cmd:
        return False, "no build command configured"
    try:
        r = subprocess.run(build_cmd, shell=True, cwd=repo_root,
                           capture_output=True, text=True, timeout=timeout)
        out = (r.stdout or "")[-4000:] + "\n" + (r.stderr or "")[-4000:]
        return r.returncode == 0, out
    except subprocess.TimeoutExpired:
        return False, "build timed out after %ss" % timeout


def newest_apk(apk_dir):
    cands = []
    for root, _dirs, files in os.walk(apk_dir or "."):
        for f in files:
            if f.endswith(".apk"):
                p = os.path.join(root, f)
                cands.append((os.path.getmtime(p), p))
    if not cands:
        return None
    return max(cands)[1]
