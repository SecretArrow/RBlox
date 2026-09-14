"""APK static inspection: metadata, components, permissions, deep links.

Everything is derived dynamically from the APK itself — never hardcoded.
Primary source: binary AndroidManifest (axml.py). Optional cross-check via
aapt2 (badging + signature verification) when the Android SDK is present.
"""
import hashlib
import os
import re
import shutil
import subprocess
import zipfile

from . import axml

LAUNCHER_ACTION = "android.intent.action.MAIN"
LAUNCHER_CATEGORY = "android.intent.category.LAUNCHER"
VIEW_ACTION = "android.intent.action.VIEW"

COMPONENT_TAGS = ("activity", "activity-alias", "service", "receiver", "provider")


def _norm_component(package, name):
    if not name:
        return name
    if name.startswith("."):
        return package + name
    if "." not in name.split("/")[0]:
        return package + "." + name
    return name


class ApkInfo:
    """Complete static model of one APK file."""

    def __init__(self, path):
        self.path = os.path.abspath(path)
        self.size = os.path.getsize(self.path) if os.path.exists(self.path) else 0
        self.sha256 = None
        self.package = None
        self.version_name = None
        self.version_code = None
        self.min_sdk = None
        self.target_sdk = None
        self.label = None
        self.debuggable = False
        self.abis = []
        self.permissions = []
        self.activities = []          # [{name, exported, launchable, intent_filters}]
        self.services = []
        self.receivers = []
        self.providers = []
        self.deep_links = []
        self.exported = []
        self.launchable_activity = None
        self.signer = None
        self.issues = []

    # ------------------------------------------------------------------
    @classmethod
    def from_file(cls, path, use_aapt2=True):
        info = cls(path)
        info._hash()
        root, _ = axml.parse_apk_manifest(path)
        info._from_manifest(root)
        info._from_zip()
        if use_aapt2:
            info._from_aapt2()
        return info

    def _hash(self):
        h = hashlib.sha256()
        with open(self.path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        self.sha256 = h.hexdigest()

    def _from_manifest(self, root):
        self.package = root.get("package") or None
        self.version_name = root.get("android:versionName")
        vc = root.get("android:versionCode")
        try:
            self.version_code = int(vc)
        except (TypeError, ValueError):
            self.version_code = None
        sdk = root.find("uses-sdk")
        if sdk is not None:
            self.min_sdk = _to_int(sdk.get("android:minSdkVersion"))
            self.target_sdk = _to_int(sdk.get("android:targetSdkVersion"))
        for perm in root.findall("uses-permission"):
            name = perm.get("android:name")
            if name and name not in self.permissions:
                self.permissions.append(name)

        app = root.find("application")
        if app is None:
            self.issues.append("manifest has no <application> element")
            return
        self.label = app.get("android:label")
        self.debuggable = app.get("android:debuggable") == "true"
        for tag, bucket in (("activity", self.activities),
                            ("activity-alias", self.activities),
                            ("service", self.services),
                            ("receiver", self.receivers),
                            ("provider", self.providers)):
            for comp in app.findall(tag):
                name = _norm_component(self.package, comp.get("android:name"))
                if not name:
                    continue
                filters = []
                launchable = False
                for flt in comp.findall("intent-filter"):
                    actions = [a.get("android:name")
                               for a in flt.findall("action") if a.get("android:name")]
                    cats = [c.get("android:name")
                            for c in flt.findall("category") if c.get("android:name")]
                    data = []
                    for d in flt.findall("data"):
                        item = {k.split(":", 1)[1]: v for k, v in d.attrib.items()
                                if k.startswith("android:")}
                        if item:
                            data.append(item)
                    filters.append({"actions": actions, "categories": cats, "data": data})
                    if LAUNCHER_ACTION in actions and LAUNCHER_CATEGORY in cats:
                        launchable = True
                    for d in data:
                        if VIEW_ACTION in actions and d.get("scheme"):
                            link = d.get("scheme") + "://"
                            if d.get("host"):
                                link += d["host"]
                            if d.get("pathPrefix"):
                                link += d["pathPrefix"]
                            if link not in self.deep_links:
                                self.deep_links.append(link)
                exported = comp.get("android:exported")
                if exported is None and filters:
                    # Android 12+ requires explicit exported when filters exist
                    self.issues.append(
                        "component %s has intent-filter but no android:exported "
                        "(install fails on API 31+)" % name)
                entry = {"name": name, "exported": exported,
                         "intent_filters": filters}
                if tag in ("activity", "activity-alias"):
                    entry["launchable"] = launchable
                    if launchable and not self.launchable_activity:
                        self.launchable_activity = name
                bucket.append(entry)
                if exported == "true":
                    self.exported.append({"type": tag, "name": name,
                                          "permission": comp.get("android:permission")})

    def _from_zip(self):
        with zipfile.ZipFile(self.path) as z:
            names = z.namelist()
            abis = set()
            for n in names:
                if n.startswith("lib/") and "/" in n[4:]:
                    abis.add(n.split("/")[1])
            self.abis = sorted(abis)
            sig = [n for n in names if re.match(r"^META-INF/.*\.(RSA|DSA|EC)$", n)]
            if sig:
                self.signer = "v1-jar (" + ", ".join(sorted(sig)[:2]) + ")"

    def _from_aapt2(self):
        aapt2 = _find_aapt2()
        if not aapt2:
            return
        try:
            out = subprocess.run([aapt2, "dump", "badging", self.path],
                                 capture_output=True, text=True, timeout=60)
            for line in out.stdout.splitlines():
                if line.startswith("application-label:") and not self.label:
                    self.label = line.split(":", 1)[1].strip()
                elif line.startswith("sdkVersion:") and self.min_sdk is None:
                    self.min_sdk = _to_int(line.split(":", 1)[1].strip().strip("'"))
                elif line.startswith("targetSdkVersion:") and self.target_sdk is None:
                    self.target_sdk = _to_int(line.split(":", 1)[1].strip().strip("'"))
        except Exception:
            pass
        signer = _apksigner_certs(self.path)
        if signer:
            self.signer = signer

    # ------------------------------------------------------------------
    def runtime_permissions(self):
        """Requested permissions from the dangerous set (test targets)."""
        return [p for p in self.permissions if p in axml_known_dangerous()]

    def verify(self):
        """Verify APK identity/installability. Returns (ok, issues)."""
        issues = list(self.issues)
        if not self.package:
            issues.append("no package name in manifest")
        if not self.version_name and self.version_code is None:
            issues.append("no versionName/versionCode")
        if not self.abis:
            issues.append("no native libs and no ABI evidence (may be fine for pure-Java)")
        if self.min_sdk is None:
            issues.append("minSdkVersion unknown")
        if self.launchable_activity is None and not self.services:
            issues.append("no LAUNCHER activity found — app may not be startable")
        return (len(issues) == 0, issues)

    def all_components(self):
        return ({"kind": "activity", **a} for a in self.activities)

    def to_dict(self):
        return {
            "path": self.path, "size": self.size, "sha256": self.sha256,
            "package": self.package, "version_name": self.version_name,
            "version_code": self.version_code, "min_sdk": self.min_sdk,
            "target_sdk": self.target_sdk, "label": self.label,
            "debuggable": self.debuggable, "abis": self.abis,
            "permissions": self.permissions,
            "runtime_permissions": self.runtime_permissions(),
            "activities": self.activities, "services": self.services,
            "receivers": self.receivers, "providers": self.providers,
            "deep_links": self.deep_links, "exported": self.exported,
            "launchable_activity": self.launchable_activity,
            "signer": self.signer, "verify_issues": self.issues,
        }


def _to_int(v):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return None


def axml_known_dangerous():
    from .config import DANGEROUS_PERMS
    return DANGEROUS_PERMS


def _find_aapt2():
    for cand in (shutil.which("aapt2"),):
        if cand:
            return cand
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        bt = os.path.join(sdk, "build-tools")
        if os.path.isdir(bt):
            for ver in sorted(os.listdir(bt), reverse=True):
                p = os.path.join(bt, ver, "aapt2")
                if os.path.exists(p):
                    return p
    return None


def _apksigner_certs(apk):
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        return None
    bt = os.path.join(sdk, "build-tools")
    if not os.path.isdir(bt):
        return None
    for ver in sorted(os.listdir(bt), reverse=True):
        exe = os.path.join(bt, ver, "apksigner")
        if os.path.exists(exe):
            try:
                r = subprocess.run([exe, "verify", "--print-certs", apk],
                                   capture_output=True, text=True, timeout=60)
                if r.returncode == 0:
                    m = re.search(r"Signer #1 certificate DN: (.+)", r.stdout)
                    return "apksigner OK" + (" — " + m.group(1).strip() if m else "")
                return "apksigner FAILED: " + r.stderr.strip().splitlines()[0][:120]
            except Exception:
                return None
    return None


def pick_apk(paths, prefer_abi="x86_64"):
    """Choose the APK best suited for this emulator (or default preference).

    Order: exact ABI match -> universal -> arm64-v8a (API30+ x86_64 images
    translate ARM64) -> anything else with a warning.
    """
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        return None, None, "no APK candidates"
    infos = []
    for p in paths:
        try:
            infos.append(ApkInfo.from_file(p, use_aapt2=False))
        except Exception:
            infos.append(None)
    def has_abi(info, abi):
        return info and abi in info.abis
    # exact
    for info in infos:
        if has_abi(info, prefer_abi):
            return info.path, prefer_abi, "exact ABI match"
    for info in infos:
        if info and "universal" in os.path.basename(info.path).lower():
            return info.path, "universal", "universal APK"
    for info in infos:
        if has_abi(info, "universal") and info.abis:
            return info.path, "universal", "universal by lib/ contents"
    for info in infos:
        if has_abi(info, "arm64-v8a"):
            return info.path, "arm64-v8a", "arm64 via emulator ARM translation (API 30+)"
    return infos[0].path if infos[0] else paths[0], None, "fallback: first candidate"
