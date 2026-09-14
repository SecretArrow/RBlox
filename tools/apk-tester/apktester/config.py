"""Central configuration: test modes, budgets, limits.

Every limit is overridable via CLI flags or APKTEST_* environment variables so
CI callers can tune behaviour without code changes. All exploration is bounded
by design: the runner must never wait forever (spec: TEST BUDGET).
"""
import os

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
SMOKE = "SMOKE"
STANDARD = "STANDARD"
DEEP = "DEEP"
RELEASE = "RELEASE"
MODES = (SMOKE, STANDARD, DEEP, RELEASE)

# Per-mode budgets. max_* are hard ceilings; the runner degrades gracefully
# (finishes the current flow, marks the session partial) when a ceiling hits.
MODE_BUDGETS = {
    SMOKE: dict(max_minutes=8, max_actions=40, monkey_actions=0,
                max_screen_depth=2, fuzz_values=4),
    STANDARD: dict(max_minutes=20, max_actions=150, monkey_actions=120,
                   max_screen_depth=3, fuzz_values=6),
    DEEP: dict(max_minutes=35, max_actions=320, monkey_actions=300,
               max_screen_depth=4, fuzz_values=10),
    RELEASE: dict(max_minutes=45, max_actions=400, monkey_actions=400,
                  max_screen_depth=4, fuzz_values=12),
}

# Repair loop ceiling (spec: MAX_REPAIR_ATTEMPTS, never loop indefinitely)
MAX_REPAIR_ATTEMPTS = 5
MAX_RETRIES = 2

# Timeouts (seconds)
ACTION_TIMEOUT = 30
INSTALL_TIMEOUT = 300
BOOT_TIMEOUT = 600
LAUNCH_TIMEOUT = 150
UIDUMP_TIMEOUT = 20
SCREENSHOT_TIMEOUT = 20

# Dangerous runtime permissions (never granted blindly; deny-path tested first)
DANGEROUS_PERMS = {
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.READ_CONTACTS", "android.permission.WRITE_CONTACTS",
    "android.permission.CALL_PHONE",
    "android.permission.SEND_SMS", "android.permission.READ_SMS",
    "android.permission.RECEIVE_SMS",
    "android.permission.READ_PHONE_STATE", "android.permission.CALL_PHONE",
    "android.permission.READ_CALENDAR", "android.permission.WRITE_CALENDAR",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_IMAGES", "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.BODY_SENSORS",
    "android.permission.ACTIVITY_RECOGNITION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.BLUETOOTH_SCAN", "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BLUETOOTH_ADVERTISE",
}


def _env_int(name, default):
    try:
        return int(os.environ.get(name, "") or default)
    except (TypeError, ValueError):
        return default


class TestConfig:
    """Fully resolved test configuration for one runner session."""

    def __init__(self, mode=SMOKE, seed=42, out_dir="artifacts",
                 max_repair_attempts=MAX_REPAIR_ATTEMPTS, strict=None,
                 overrides=None):
        self.mode = mode if mode in MODES else SMOKE
        b = dict(MODE_BUDGETS[self.mode])
        self.seed = int(seed)
        self.out_dir = out_dir
        self.max_repair_attempts = int(max_repair_attempts)
        # strict=True: any warning-class finding fails the gate (RELEASE mode
        # defaults to strict).
        self.strict = (self.mode == RELEASE) if strict is None else bool(strict)
        b.update(overrides or {})
        # Environment overrides (APKTEST_MAX_ACTIONS etc.)
        b["max_minutes"] = _env_int("APKTEST_MAX_MINUTES", b["max_minutes"])
        b["max_actions"] = _env_int("APKTEST_MAX_ACTIONS", b["max_actions"])
        b["monkey_actions"] = _env_int("APKTEST_MONKEY_ACTIONS", b["monkey_actions"])
        b["max_screen_depth"] = _env_int("APKTEST_MAX_SCREEN_DEPTH", b["max_screen_depth"])
        b["fuzz_values"] = _env_int("APKTEST_FUZZ_VALUES", b["fuzz_values"])
        self.max_minutes = b["max_minutes"]
        self.max_actions = b["max_actions"]
        self.monkey_actions = b["monkey_actions"]
        self.max_screen_depth = b["max_screen_depth"]
        self.fuzz_values = b["fuzz_values"]
        self.max_retries = MAX_RETRIES

    @property
    def max_test_seconds(self):
        return self.max_minutes * 60

    def to_dict(self):
        return {
            "mode": self.mode, "seed": self.seed, "max_minutes": self.max_minutes,
            "max_actions": self.max_actions, "monkey_actions": self.monkey_actions,
            "max_screen_depth": self.max_screen_depth,
            "fuzz_values": self.fuzz_values,
            "max_repair_attempts": self.max_repair_attempts,
            "strict": self.strict,
        }
