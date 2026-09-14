"""UI hierarchy model from uiautomator dumps.

Discovery priority per spec: resource-id > content-desc > semantics/role >
visible text > coordinates as last resort. Works for Android Views and for
Jetpack Compose (Compose exposes its semantics tree through accessibility,
which uiautomator dumps). Canvas/GL apps (games) dump an empty hierarchy —
that is handled as a first-class 'surface app' result, never an error.
"""
import hashlib
import re
import xml.etree.ElementTree as ET

INTERACTIVE_HINTS = ("button", "checkbox", "switch", "toggle", "radio",
                     "seekbar", "slider", "tab", "menu", "item", "card",
                     "fab", "chip", "link")
EDITABLE_CLASSES = ("EditText", "SearchView$SearchAutoComplete",
                    "AutoCompleteTextView", "TextInputEditText")
SCROLL_CLASSES = ("ScrollView", "ListView", "RecyclerView", "GridView",
                  "ViewPager", "NestedScrollView")
DIALOG_CLASSES = ("Dialog", "AlertDialog", "BottomSheet")


class Element:
    __slots__ = ("attrs", "x1", "y1", "x2", "y2")

    def __init__(self, attrs, bounds):
        self.attrs = attrs
        self.x1, self.y1, self.x2, self.y2 = bounds

    # convenience accessors -------------------------------------------------
    @property
    def rid(self):
        return self.attrs.get("resource-id") or ""

    @property
    def text(self):
        return (self.attrs.get("text") or "").strip()

    @property
    def desc(self):
        return (self.attrs.get("content-desc") or "").strip()

    @property
    def cls(self):
        return self.attrs.get("class") or ""

    def _flag(self, name):
        return (self.attrs.get(name) or "").lower() == "true"

    @property
    def clickable(self):
        return self._flag("clickable")

    @property
    def checkable(self):
        return self._flag("checkable")

    @property
    def long_clickable(self):
        return self._flag("long-clickable")

    @property
    def scrollable(self):
        return self._flag("scrollable")

    @property
    def enabled(self):
        return not self._flag("disabled") and self.attrs.get("enabled", "true") == "true"

    @property
    def center(self):
        return ((self.x1 + self.x2) // 2, (self.y1 + self.y2) // 2)

    @property
    def visible(self):
        return self.x2 > self.x1 and self.y2 > self.y1

    # roles -------------------------------------------------------------------
    def role(self):
        c = self.cls.lower()
        if "checkbox" in c:
            return "checkbox"
        if "switch" in c:
            return "switch"
        if "radiobutton" in c:
            return "radio"
        if "seekbar" in c or "slider" in c:
            return "slider"
        if any(k in c for k in EDITABLE_CLASSES):
            return "textfield"
        if "webview" in c:
            return "webview"
        if "spinner" in c:
            return "spinner"
        if "button" in c or "imagebutton" in c or "floatingactionbutton" in c:
            return "button"
        if "textview" in c and self.clickable:
            return "text-button"
        if self.checkable:
            return "toggle"
        if self.clickable or self.long_clickable:
            return "clickable"
        if self.scrollable:
            return "scrollable"
        return "static"

    def interactive(self):
        return self.role() != "static"

    def label(self):
        """Best human-identifiable label (id > desc > role+text)."""
        return self.rid.split("/")[-1] if self.rid else (self.desc or self.text
                                                         or self.role())

    def matches(self, needle):
        n = needle.lower()
        return (n in self.rid.lower() or n in self.desc.lower()
                or n in self.text.lower() or n in self.cls.lower())


_BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def parse(xml_text):
    """Parse a uiautomator XML dump -> (elements, meta dict)."""
    if not xml_text:
        return [], {"available": False, "reason": "no dump"}
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return [], {"available": False, "reason": "unparseable dump"}
    elements, metas = [], []
    for node in root.iter("node"):
        attrs = dict(node.attrib)
        m = _BOUNDS.match(attrs.get("bounds", ""))
        if not m:
            continue
        b = tuple(int(g) for g in m.groups())
        elements.append(Element(attrs, b))
        metas.append(attrs)
    meta = {"available": True, "count": len(elements),
            "packages": sorted({a.get("package", "") for a in metas}) - {""}}
    return elements, meta


def parse_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return parse(f.read())


def interactive(elements):
    return [e for e in elements if e.interactive() and e.visible and e.enabled]


def textfields(elements):
    return [e for e in elements if e.role() == "textfield" and e.visible]


def toggles(elements):
    return [e for e in elements
            if e.role() in ("checkbox", "switch", "toggle") and e.visible]


def scrollables(elements):
    return [e for e in elements if e.role() == "scrollable" or e.scrollable]


def dialogs(elements):
    return [e for e in elements if any(k in e.cls for k in DIALOG_CLASSES)]


def webviews(elements):
    return [e for e in elements if e.role() == "webview"]


def fingerprint(elements):
    """Stable screen fingerprint: ids+classes+texts, order-insensitive."""
    parts = sorted("%s|%s|%s|%s" % (e.rid, e.cls, e.text, e.desc)
                   for e in elements)
    return hashlib.sha1("\n".join(parts).encode("utf-8")).hexdigest()[:12]


def looks_blank(elements, meta, has_surface_view=False):
    """Blank-screen heuristic.

    An empty hierarchy on an app that owns a SurfaceView (game engine) is
    normal canvas rendering — NOT blank. True blank = no nodes at all AND
    nothing suggests a surface app.
    """
    if meta.get("available") and meta.get("count", 0) > 1:
        return False
    return not has_surface_view


def find(elements, rid=None, desc=None, text=None, cls=None):
    """Priority finder: id > desc > class > text (spec order)."""
    if rid:
        for e in elements:
            if e.rid.endswith(rid):
                return e
    if desc:
        for e in elements:
            if desc.lower() in e.desc.lower():
                return e
    if cls:
        for e in elements:
            if cls.lower() in e.cls.lower():
                return e
    if text:
        for e in elements:
            if text.lower() in e.text.lower():
                return e
    return None
