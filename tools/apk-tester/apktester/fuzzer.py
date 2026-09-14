"""Safe input fuzzing corpus (spec 8).

Values are bounded (no DoS), representative of real crash classes, and
annotated with whether adb can physically type them (adb `input text` only
accepts a conservative ASCII subset — unicode/emoji entries are still
recorded but marked skipped-with-reason when the device cannot inject them).
"""
import re

ADB_SAFE_RE = re.compile(r"^[A-Za-z0-9@#%_\-\.+/ ]*$")


def _entry(kind, value, note=""):
    return {"kind": kind, "value": value, "adb_safe": bool(ADB_SAFE_RE.match(value)),
            "note": note}


def corpus(max_values=10, long_len=256, extra_long_len=5000):
    values = [
        _entry("empty", ""),
        _entry("short", "a"),
        _entry("word", "hello world"),
        _entry("number", "123"),
        _entry("negative", "-1"),
        _entry("decimal", "3.14"),
        _entry("zero", "0"),
        _entry("whitespace", "   "),
        _entry("specials", "!@#$%^&*()_+-=[]{};':\",./<>?|\\`~"),
        _entry("unicode", "caf\u00e9 na\u00efve \u4f60\u597d\u4e16\u754c",
               "may be skipped: adb input cannot inject non-ASCII"),
        _entry("emoji", "\U0001F600\U0001F680",
               "may be skipped: adb input cannot inject non-ASCII"),
        _entry("long", "A" * long_len),
        _entry("html", "<script>alert(1)</script>"),
        _entry("path", "../../etc/passwd"),
        _entry("format", "%s%d%n"),
        _entry("sql", "' OR '1'='1"),
        _entry("extra_long", "B" * extra_long_len, "single deep boundary probe"),
    ]
    return values[:max(1, max_values)] + (values[-1:] if max_values < len(values) else [])


def typed(entry):
    """Return (can_type, normalized)."""
    if entry["adb_safe"]:
        return True, entry["value"].replace(" ", "%s")
    return False, entry["value"]
