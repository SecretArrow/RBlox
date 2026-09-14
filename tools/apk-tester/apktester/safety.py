"""Safe interaction engine — decides WHAT may be tapped and HOW FAR.

Before any action the engine classifies risk. Destructive flows are opened
and verified but never executed irreversibly: we test the confirmation UI and
the CANCEL path, never the destructive confirm. Real purchases / external
messages are never triggered (spec 7).
"""
import re

SAFE = "safe"
REVIEW = "review"
DESTRUCTIVE = "destructive"
FORBIDDEN = "forbidden"

# Highest risk: never tapped at all — presence is verified instead.
FORBIDDEN_RE = re.compile(
    r"\b(purchase|buy|checkout|pay|payment|subscribe|order now|upgrade now|"
    r"delete account|remove account|close account|sign ?out|log ?out|"
    r"uninstall|reset (all|device|phone)|factory reset|transfer|withdraw|"
    r"send (money|payment|sms|email)|share .*(external|social))\b", re.I)

# Destructive: tapping is allowed ONLY if a confirmation UI appears and we
# test the cancel path.
DESTRUCTIVE_RE = re.compile(
    r"\b(delete|remove|erase|clear|reset|discard|wipe|empty|"
    r"logout|sign ?out|revoke|unlink|block|report)\b", re.I)

CONFIRMATION_RE = re.compile(
    r"\b(confirm|are you sure|sure\?|cancel|keep|no,? keep|yes,? delete|"
    r"cannot be undone|permanently)\b", re.I)

CANCEL_RE = re.compile(r"^(cancel|no|keep|dismiss|don'?t|not now|no thanks|"
                       r"keep it|keep editing)\b", re.I)

CONFIRM_RE = re.compile(r"^(ok|okay|yes|confirm|delete|remove|proceed|continue|"
                        r"accept|allow)\b", re.I)

# Navigation/feature discovery keywords (generic, category-agnostic)
NAV_HINT_RE = re.compile(
    r"\b(menu|settings?|preferences?|profile|account|home|back|search|"
    r"filter|sort|refresh|retry|reload|more|help|about|open|edit|add|"
    r"create|new|close|next|done|start|play|continue|explore|browse|"
    r"library|inbox|notifications?|drawer|tabs?)\b", re.I)


class Risk:
    __slots__ = ("level", "reason", "allow_tap", "needs_confirmation_probe")

    def __init__(self, level, reason, allow_tap=True, needs_confirmation_probe=False):
        self.level = level
        self.reason = reason
        self.allow_tap = allow_tap
        self.needs_confirmation_probe = needs_confirmation_probe


def classify(element_or_label):
    """Classify one interaction target. Never raises."""
    if element_or_label is None:
        return Risk(SAFE, "no target")
    label = " ".join(filter(None, [
        getattr(element_or_label, "rid", ""),
        getattr(element_or_label, "desc", ""),
        getattr(element_or_label, "text", ""),
    ])) if not isinstance(element_or_label, str) else element_or_label

    if FORBIDDEN_RE.search(label):
        return Risk(FORBIDDEN, "potentially irreversible/external: %r" % label[:80],
                    allow_tap=False)
    if DESTRUCTIVE_RE.search(label):
        return Risk(DESTRUCTIVE,
                    "destructive semantics: %r — only cancel-path will be tested"
                    % label[:80], allow_tap=True, needs_confirmation_probe=True)
    return Risk(SAFE, "ordinary navigation/control")


def is_confirmation_dialog(elements):
    """Does the current screen look like a confirmation dialog?"""
    joined = " ".join((e.text + " " + e.desc) for e in elements)
    return bool(CONFIRMATION_RE.search(joined))


def find_cancel(elements):
    """Find the safest (cancel/close) control inside a dialog."""
    for e in elements:
        if e.text and CANCEL_RE.match(e.text.strip()):
            return e
    for e in elements:
        if e.desc and CANCEL_RE.match(e.desc.strip()):
            return e
    # neutral fallback: anything that is NOT the confirm verb
    for e in elements:
        if e.clickable and e.text and not CONFIRM_RE.match(e.text.strip()):
            return e
    return None


def find_confirm(elements):
    for e in elements:
        if e.clickable and e.text and CONFIRM_RE.match(e.text.strip()):
            return e
    return None


def nav_priority(element):
    """Sort key: likely navigation targets first during discovery."""
    label = " ".join(filter(None, [element.rid, element.desc, element.text]))
    score = 0
    if NAV_HINT_RE.search(label):
        score -= 10
    if element.role() in ("button", "text-button"):
        score -= 5
    if element.role() in ("checkbox", "switch", "toggle", "slider"):
        score += 4
    return score
