"""Unit tests: safety engine, fuzzer, analyzer, config, reporting."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from apktester import analyzer, config, fuzzer, reporting, safety  # noqa: E402


class FakeElement:
    def __init__(self, rid="", desc="", text=""):
        self.rid, self.desc, self.text = rid, desc, text


class TestSafety(unittest.TestCase):
    def test_forbidden_never_tapped(self):
        for label in ("Delete account", "Purchase item", "Checkout",
                      "Pay now", "Sign out", "Uninstall"):
            r = safety.classify(FakeElement(text=label))
            self.assertEqual(r.level, safety.FORBIDDEN, label)
            self.assertFalse(r.allow_tap)

    def test_destructive_goes_to_confirmation_probe(self):
        r = safety.classify(FakeElement(rid="btn_clear_cache", text="Clear cache"))
        self.assertEqual(r.level, safety.DESTRUCTIVE)
        self.assertTrue(r.needs_confirmation_probe)

    def test_safe_navigation(self):
        r = safety.classify(FakeElement(desc="Open settings"))
        self.assertEqual(r.level, safety.SAFE)

    def test_cancel_finder(self):
        class E(FakeElement):
            def __init__(self, text, clickable=True):
                super().__init__(text=text)
                self.clickable = clickable
        els = [E("Delete"), E("Cancel"), E("Are you sure?")]
        self.assertEqual(safety.find_cancel(els).text, "Cancel")
        confirm = safety.find_confirm(els)
        self.assertEqual(confirm.text, "Delete")


class TestFuzzer(unittest.TestCase):
    def test_corpus_bounded_and_tagged(self):
        vals = fuzzer.corpus(max_values=5)
        self.assertLessEqual(len(vals), 6)
        self.assertTrue(any(v["kind"] == "extra_long" for v in vals))
        for v in vals:
            self.assertIsInstance(v["adb_safe"], bool)

    def test_typing_marker(self):
        can, norm = fuzzer.typed({"kind": "x", "value": "a b", "adb_safe": True})
        self.assertTrue(can)
        self.assertEqual(norm, "a%sb")
        can2, _ = fuzzer.typed({"kind": "x", "value": "\u4f60", "adb_safe": False})
        self.assertFalse(can2)


class TestAnalyzer(unittest.TestCase):
    def test_java_npe_mapping(self):
        log = ("FATAL EXCEPTION: main\n"
               "Process: com.foo, PID 123\n"
               "java.lang.NullPointerException: Attempt to invoke virtual method "
               "'void com.foo.Bar.baz()' on a null object reference\n"
               "  at com.foo.Bar.baz(Bar.java:42)\n"
               "  at com.foo.MainActivity.onCreate(MainActivity.java:13)\n")
        rca = analyzer.analyze([], log, None, None)
        self.assertEqual(rca.kind, "java-npe")
        self.assertTrue(rca.frames)
        self.assertEqual(rca.frames[0].file, "Bar.java")

    def test_native_crash(self):
        log = ("Fatal signal 11 (SIGSEGV), code 1, fault addr 0x0 in tid 99\n"
               "#00 pc 0x0001234 /data/app/libarm64.so\n")
        rca = analyzer.analyze([], log, None, None)
        self.assertEqual(rca.kind, "native-crash")

    def test_install_exported(self):
        rca = analyzer.analyze([], "", "Install error: Targeting S+ (version 31 and "
                                       "above) requires that an explicit value for "
                                       "android:exported", None)
        self.assertEqual(rca.kind, "install-exported")
        self.assertTrue(rca.fixable)

    def test_godot_null_instance(self):
        log = ("E godot: SCRIPT ERROR: Invalid call. Nonexistent function 'x' "
               "in base 'null instance'.\n"
               "E godot:          at: _on_pressed (res://scripts/ui/menu.gd:88)\n")
        rca = analyzer.analyze([type("E", (), {"context": log, "kind": "godot_error",
                                               "severity": "warning"})()], "", None,
                               None)
        self.assertEqual(rca.kind, "godot-script-error")
        self.assertTrue(rca.fixable)
        self.assertEqual(rca.frames[0].file, "res://scripts/ui/menu.gd")


class TestConfig(unittest.TestCase):
    def test_modes_bounded(self):
        for m in config.MODES:
            c = config.TestConfig(mode=m)
            self.assertGreater(c.max_actions, 0)
            self.assertGreater(c.max_minutes, 0)
        smoke = config.TestConfig(mode="SMOKE")
        self.assertEqual(smoke.monkey_actions, 0)
        deep = config.TestConfig(mode="DEEP")
        self.assertGreater(deep.monkey_actions, 0)

    def test_unknown_mode_falls_back(self):
        c = config.TestConfig(mode="NOPE")
        self.assertEqual(c.mode, config.SMOKE)


class TestReporting(unittest.TestCase):
    def test_report_sections(self):
        class FakeCfg:
            mode = "SMOKE"
            strict = True
            def to_dict(self):
                return {"mode": "SMOKE"}
        summary = {
            "mode": "SMOKE", "status": "PASS", "gate": "RELEASE",
            "package": "com.x", "device": {"api_level": 30, "brand": "b",
                                           "model": "m", "serial": "s"},
            "feature_discovery": {"discovered": 3, "screens": 1,
                                  "features": ["ui-hierarchy"], "tested": 2,
                                  "passed": 2, "failed": 0},
            "counts": {"crashes": 0, "anrs": 0, "critical": 0, "major": 0,
                       "minor": 0, "warnings": 0},
            "findings": [], "flows": [{"flow": "launch", "status": "passed",
                                       "notes": ["ok"]}],
            "remaining_problems": [], "recommendation": "RELEASE",
        }
        apk = {"label": "X", "package": "com.x", "version_name": "1.0",
               "version_code": 1, "path": "/tmp/x.apk", "size": 1000,
               "sha256": "ab" * 10}
        md = reporting.render_report(summary, apk)
        for needle in ("Release Test Report", "Feature Discovery", "Crashes",
                       "ANR", "Lifecycle", "Permissions", "Network",
                       "Persistence", "Visual", "Random Exploration",
                       "Auto Fixes", "Regression Tests", "Remaining Problems",
                       "Final Recommendation", "RELEASE"):
            self.assertIn(needle, md)


if __name__ == "__main__":
    unittest.main()
