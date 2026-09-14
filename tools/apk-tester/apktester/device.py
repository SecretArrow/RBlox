"""ADB device wrapper — every call bounded by a timeout, never hangs.

Generic across ANY app: launch resolution is derived from the package's own
launcher activity (or monkey), never hardcoded.
"""
import re
import subprocess
import time


class DeviceError(Exception):
    pass


class Adb:
    def __init__(self, serial=None):
        self.serial = serial or _auto_serial()
        if not self.serial:
            raise DeviceError("no Android device/emulator attached (adb devices empty)")

    # -- low level -------------------------------------------------------
    def _cmd(self, args, timeout=30, binary=False, check=True):
        cmd = ["adb"]
        if self.serial:
            cmd += ["-s", self.serial]
        cmd += args
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise DeviceError("adb timeout: %s" % " ".join(args))
        if check and r.returncode != 0:
            raise DeviceError("adb failed (%s): %s" % (
                " ".join(args), r.stderr.decode("utf-8", "replace").strip()[:200]))
        return r.stdout if binary else r.stdout.decode("utf-8", "replace")

    def shell(self, cmd, timeout=30):
        return self._cmd(["shell", cmd], timeout=timeout)

    def root(self):
        try:
            self._cmd(["root"], timeout=15)
            time.sleep(2)
            self._cmd(["wait-for-device"], timeout=60)
            uid = self.shell("id -u", timeout=15).strip()
            return "uid=0" in uid
        except DeviceError:
            return False

    # -- install / uninstall ----------------------------------------------
    def install(self, apk, timeout=300, replace=True):
        args = ["install"]
        if replace:
            args.append("-r")
        args += ["-t", apk]
        out = self._cmd(args, timeout=timeout, check=False)
        ok = "Success" in out
        return ok, out.strip()

    def uninstall(self, package, timeout=120):
        out = self._cmd(["uninstall", package], timeout=timeout, check=False)
        return "Success" in out

    def is_installed(self, package):
        out = self.shell("pm path %s" % package, timeout=20)
        return bool(out.strip().startswith("package:"))

    # -- launch ------------------------------------------------------------
    def resolve_launcher(self, package):
        """Ask the system which activity is the launcher — no hardcoding."""
        out = self.shell(
            "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER %s"
            % package, timeout=25).strip()
        for line in out.splitlines():
            line = line.strip()
            if "/" in line and package in line:
                return line.split()[-1]
        return None

    def launch(self, package, wait_timeout=150):
        """Launch via monkey (proven-stable), then wait until foreground.

        Returns dict(package, component, pid, resumed, elapsed).
        """
        t0 = time.time()
        comp = self.resolve_launcher(package)
        self.shell("monkey -p %s -c android.intent.category.LAUNCHER 1" % package,
                   timeout=45)
        resumed = self.wait_foreground(package, timeout=wait_timeout)
        pid = self.pidof(package)
        return {"package": package, "component": comp, "pid": pid,
                "resumed": resumed, "elapsed": round(time.time() - t0, 1)}

    def start_view(self, uri, timeout=30):
        out = self.shell("am start -a android.intent.action.VIEW -d %s" % uri,
                         timeout=timeout)
        return "Error" not in out.splitlines()[0] if out else False

    def start_component(self, component, timeout=45):
        out = self.shell("am start -n %s" % component, timeout=timeout)
        return "Error" not in out.splitlines()[0] if out else False

    def wait_foreground(self, package, timeout=150, poll=2.5):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                out = self.shell("dumpsys activity activities", timeout=20)
                m = re.search(r"ResumedActivity[^\n]*", out)
                if m and package in m.group(0):
                    return True
            except DeviceError:
                pass
            time.sleep(poll)
        return False

    def current_focus(self):
        out = self.shell("dumpsys window windows", timeout=20)
        m = re.search(r"mCurrentFocus=Window\{[^}]*\s(\S+)\}", out)
        return m.group(1) if m else None

    # -- process -----------------------------------------------------------
    def pidof(self, package):
        try:
            out = self.shell("pidof %s" % package, timeout=15)
        except DeviceError:
            return None
        pid = out.strip().split()[0] if out.strip() else None
        return pid or None

    def force_stop(self, package):
        self.shell("am force-stop %s" % package, timeout=20)

    def kill_background(self, package):
        self.shell("am kill %s" % package, timeout=20)

    # -- media / input -----------------------------------------------------
    def screencap(self, path, timeout=30):
        data = self._cmd(["exec-out", "screencap", "-p"], timeout=timeout,
                         binary=True, check=False)
        if len(data) < 100:
            return False
        with open(path, "wb") as f:
            f.write(data)
        return True

    def screen_size(self):
        out = self.shell("wm size", timeout=15)
        m = re.search(r"(\d+)x(\d+)", out)
        return (int(m.group(1)), int(m.group(2))) if m else (1080, 1920)

    def tap(self, x, y):
        self.shell("input tap %d %d" % (int(x), int(y)), timeout=20)

    def swipe(self, x1, y1, x2, y2, ms=300):
        self.shell("input swipe %d %d %d %d %d" % (x1, y1, x2, y2, ms), timeout=25)

    def key(self, code):
        self.shell("input keyevent %d" % code, timeout=20)

    def back(self):
        self.key(4)

    def home(self):
        self.key(3)

    def wake(self):
        self.key(224)

    def dismiss_keyguard(self):
        self.shell("wm dismiss-keyguard", timeout=15)

    def type_text(self, text):
        """Type ASCII-safe text (adb input limitation); returns bool."""
        safe = re.match(r"^[A-Za-z0-9@#%_\-\.+/ ]*$", text or "")
        if not safe:
            return False
        arg = text.replace(" ", "%s")
        if not arg:
            return True
        self.shell("input text '%s'" % arg, timeout=25)
        return True

    # -- UI dump -----------------------------------------------------------
    def uidump(self, timeout=20):
        """Return the current UI hierarchy XML (None if unavailable).

        Note: canvas/GL apps (games) may never become 'idle'; uiautomator dump
        then fails/times out — we treat None as 'no view hierarchy' which is
        itself a discovery result (surface app), not an error.
        """
        try:
            out = self.shell("uiautomator dump /sdcard/rbx_uidump.xml",
                             timeout=timeout)
            if "dumped" not in (out or "").lower() and "dump" not in (out or "").lower():
                return None
            data = self._cmd(["exec-out", "cat", "/sdcard/rbx_uidump.xml"],
                             timeout=15, binary=True, check=False)
            xml = data.decode("utf-8", "replace")
            return xml if "<hierarchy" in xml else None
        except DeviceError:
            return None

    # -- properties / state --------------------------------------------------
    def prop(self, name, timeout=15):
        try:
            return self.shell("getprop %s" % name, timeout=timeout).strip()
        except DeviceError:
            return ""

    def api_level(self):
        v = self.prop("ro.build.version.sdk")
        return int(v) if v.isdigit() else 0

    def airplane(self, on):
        """Toggle airplane mode. Returns True on success."""
        for cmd in ("cmd connectivity airplane-mode %s" % ("enable" if on else "disable"),
                    "svc wifi %s" % ("disable" if on else "enable"),
                    "svc data %s" % ("disable" if on else "enable")):
            try:
                self.shell(cmd, timeout=25)
                time.sleep(2)
                return True
            except DeviceError:
                continue
        return False

    def grant(self, package, perm):
        return "granted" in self.shell(
            "pm grant %s %s" % (package, perm), timeout=20).lower() or True

    def revoke(self, package, perm):
        try:
            self.shell("pm revoke %s %s" % (package, perm), timeout=20)
            return True
        except DeviceError:
            return False

    def dumpsys(self, section, timeout=25):
        return self.shell("dumpsys %s" % section, timeout=timeout)

    def logcat(self, buffer="crash", lines=800, timeout=30):
        return self.shell("logcat -d -b %s -v time" % buffer, timeout=timeout)

    def clear_logcat(self):
        try:
            self.shell("logcat -c", timeout=15)
            self.shell("logcat -b events -c", timeout=15)
            self.shell("logcat -b crash -c", timeout=15)
        except DeviceError:
            pass

    def pull(self, remote, local, timeout=60):
        try:
            self._cmd(["pull", remote, local], timeout=timeout, check=False)
            import os
            return os.path.exists(local)
        except DeviceError:
            return False

    def wait_boot(self, timeout=600):
        deadline = time.time() + timeout
        self._cmd(["wait-for-device"], timeout=timeout)
        while time.time() < deadline:
            if self.prop("sys.boot_completed") == "1":
                # package manager ready?
                if self.is_installed("android"):
                    return True
            time.sleep(5)
        raise DeviceError("device boot not completed within %ss" % timeout)

    def info(self):
        return {"serial": self.serial, "model": self.prop("ro.product.model"),
                "brand": self.prop("ro.product.brand"),
                "android_release": self.prop("ro.build.version.release"),
                "api_level": self.api_level(),
                "abi": self.prop("ro.product.cpu.abi"),
                "screen": "%sx%s" % self.screen_size()}


def _auto_serial():
    try:
        r = subprocess.run(["adb", "devices"], capture_output=True, timeout=20)
        for line in r.stdout.decode("utf-8", "replace").splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                return parts[0]
    except Exception:
        pass
    return None
