"""Unit tests for the AXML parser via a hand-built binary manifest."""
import os
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from apktester import axml  # noqa: E402


def build_manifest():
    root = ET.Element("manifest", {
        "package": "com.example.anyapp",
        "android:versionCode": "7",
        "android:versionName": "1.2.3",
    })
    ET.SubElement(root, "uses-permission",
                  {"android:name": "android.permission.INTERNET"})
    ET.SubElement(root, "uses-sdk",
                  {"android:minSdkVersion": "24", "android:targetSdkVersion": "34"})
    app = ET.SubElement(root, "application",
                        {"android:label": "AnyApp", "android:debuggable": "false"})
    act = ET.SubElement(app, "activity", {
        "android:name": ".MainActivity",
        "android:exported": "true",
    })
    flt = ET.SubElement(act, "intent-filter")
    ET.SubElement(flt, "action", {"android:name": "android.intent.action.MAIN"})
    ET.SubElement(flt, "category",
                  {"android:name": "android.intent.category.LAUNCHER"})
    ET.SubElement(app, "service", {"android:name": "com.example.anyapp.Svc",
                                   "android:exported": "false"})
    return root


class TestAxml(unittest.TestCase):
    def test_roundtrip(self):
        src = build_manifest()
        blob = axml.write_axml(src)
        parsed, meta = axml.parse(blob)
        self.assertEqual(parsed.tag, "manifest")
        self.assertEqual(parsed.get("package"), "com.example.anyapp")
        self.assertEqual(parsed.get("android:versionName"), "1.2.3")
        self.assertEqual(parsed.get("android:versionCode"), "7")
        perms = parsed.findall("uses-permission")
        self.assertEqual(perms[0].get("android:name"), "android.permission.INTERNET")
        sdk = parsed.find("uses-sdk")
        self.assertEqual(sdk.get("android:minSdkVersion"), "24")
        self.assertEqual(sdk.get("android:targetSdkVersion"), "34")
        acts = parsed.findall("application/activity")
        self.assertEqual(acts[0].get("android:name"), ".MainActivity")
        self.assertEqual(acts[0].get("android:exported"), "true")
        self.assertEqual(len(acts[0].findall("intent-filter/action")), 1)
        self.assertEqual(parsed.find("application/service").get("android:exported"),
                         "false")

    def test_rejects_non_axml(self):
        with self.assertRaises(ValueError):
            axml.parse(b"\x00\x00")

    def test_string_pool_utf16(self):
        src = ET.Element("manifest", {"package": "caf\u00e9 \u4f60\u597d"})
        parsed, _ = axml.parse(axml.write_axml(src))
        self.assertEqual(parsed.get("package"), "caf\u00e9 \u4f60\u597d")


if __name__ == "__main__":
    unittest.main()
